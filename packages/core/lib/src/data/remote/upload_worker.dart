import 'dart:io';

import 'package:drift/drift.dart';

import '../local/app_database.dart';
import '../local/sync_writer.dart';
import 'file_store.dart';
import 'remote_store.dart';

/// يضيف الملفات إلى طابور الرفع. منفصل عن [UploadWorker] ليستعمله من يريد
/// الإضافة فقط (حفظ صورة) دون أن يحتاج مخزن ملفات الخادم، فيعمل أيضاً في
/// الوضع المحلي وتُرفع الملفات لاحقاً حين يُهيَّأ الخادم.
class UploadQueueWriter {
  UploadQueueWriter(this.db, this.writer, {int Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final AppDatabase db;
  final SyncWriter writer;
  final int Function() _clock;

  /// يضيف ملفاً إلى طابور الرفع. نفس [dedupeKey] لا يدخل مرتين.
  ///
  /// يعيد `false` إن كان الملف في الطابور من قبل.
  Future<bool> enqueue({
    required String kind,
    required String bucket,
    required String localPath,
    required String remotePath,
    required String dedupeKey,
    String? targetTable,
    String? targetRowId,
    String? targetColumn,
  }) async {
    final existing = await (db.select(
      db.uploadQueue,
    )..where((u) => u.dedupeKey.equals(dedupeKey))).getSingleOrNull();
    if (existing != null) return false;
    await db
        .into(db.uploadQueue)
        .insert(
          UploadQueueCompanion.insert(
            id: writer.newId(),
            kind: kind,
            bucket: Value(bucket),
            localPath: localPath,
            remotePath: remotePath,
            dedupeKey: dedupeKey,
            targetTable: Value(targetTable),
            targetRowId: Value(targetRowId),
            targetColumn: Value(targetColumn),
            createdAt: _clock(),
          ),
        );
    return true;
  }
}

/// يرفع الملفات المنتظرة في `upload_queue` إلى مخزن الخادم في الخلفية.
///
/// الملف يُعرض فوراً من مساره المحلي؛ وعند اكتمال الرفع يُكتب مساره على
/// الخادم في السجل المعني (مثل `students.photo_url`) فيتزامن مع كل الأجهزة.
class UploadWorker {
  UploadWorker(
    this.db,
    this.writer,
    this.files, {
    int Function()? clock,
    this.maxAttempts = 8,
  }) : _clock = clock ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final AppDatabase db;
  final SyncWriter writer;
  final FileStore files;
  final int Function() _clock;

  /// بعد هذا العدد من المحاولات يُعلَّم الرفع فاشلاً ويتوقف.
  final int maxAttempts;

  static const String statusPending = 'pending';
  static const String statusDone = 'done';
  static const String statusFailed = 'failed';

  /// يضيف ملفاً إلى طابور الرفع. نفس [dedupeKey] لا يدخل مرتين.
  ///
  /// يعيد `false` إن كان الملف في الطابور من قبل.
  Future<bool> enqueue({
    required String kind,
    required String bucket,
    required String localPath,
    required String remotePath,
    required String dedupeKey,
    String? targetTable,
    String? targetRowId,
    String? targetColumn,
  }) => UploadQueueWriter(db, writer, clock: _clock).enqueue(
    kind: kind,
    bucket: bucket,
    localPath: localPath,
    remotePath: remotePath,
    dedupeKey: dedupeKey,
    targetTable: targetTable,
    targetRowId: targetRowId,
    targetColumn: targetColumn,
  );

  /// يرفع كل ما حان وقته. يعيد عدد الملفات المرفوعة بنجاح.
  ///
  /// العطل المؤقت يوقف الجولة ويؤجل الملف؛ الرفض النهائي أو الملف المفقود
  /// يعلّمه فاشلاً ويكمل الباقي.
  Future<int> processPending({Set<String>? buckets}) async {
    var uploaded = 0;
    final now = _clock();
    final query = db.select(db.uploadQueue)
      ..where(
        (u) =>
            u.status.equals(statusPending) &
            u.nextAttemptAt.isSmallerOrEqualValue(now),
      )
      ..orderBy([(u) => OrderingTerm(expression: u.createdAt)]);
    for (final item in await query.get()) {
      if (buckets != null && !buckets.contains(item.bucket)) continue;
      if (!File(item.localPath).existsSync()) {
        await _fail(item, 'الملف المحلي غير موجود');
        continue;
      }
      try {
        final stored = await files.upload(
          bucket: item.bucket,
          remotePath: item.remotePath,
          localPath: item.localPath,
        );
        await db.transaction(() async {
          await (db.update(
            db.uploadQueue,
          )..where((u) => u.id.equals(item.id))).write(
            UploadQueueCompanion(
              status: const Value(statusDone),
              doneAt: Value(_clock()),
              lastError: const Value(null),
            ),
          );
          await _writeTarget(item, stored);
        });
        uploaded++;
      } on RemoteException catch (e) {
        if (e.permanent) {
          await _fail(item, e.message);
          continue;
        }
        final attempts = item.attempts + 1;
        if (attempts >= maxAttempts) {
          await _fail(item, e.message, attempts: attempts);
          continue;
        }
        final shift = attempts > 8 ? 8 : attempts;
        await (db.update(
          db.uploadQueue,
        )..where((u) => u.id.equals(item.id))).write(
          UploadQueueCompanion(
            attempts: Value(attempts),
            lastError: Value(e.message),
            nextAttemptAt: Value(_clock() + 5000 * (1 << (shift - 1))),
          ),
        );
        break;
      }
    }
    return uploaded;
  }

  /// يعيد الملفات الفاشلة إلى الانتظار (زر «إعادة المحاولة»).
  Future<void> retryFailed({Set<String>? buckets}) async {
    final query = db.update(db.uploadQueue)
      ..where((u) {
        final failed = u.status.equals(statusFailed);
        return buckets == null ? failed : failed & u.bucket.isIn(buckets);
      });
    await query.write(
      const UploadQueueCompanion(
        status: Value(statusPending),
        attempts: Value(0),
        nextAttemptAt: Value(0),
      ),
    );
  }

  Future<void> _writeTarget(UploadQueueRow item, String stored) async {
    final tableName = item.targetTable;
    final rowId = item.targetRowId;
    final column = item.targetColumn;
    if (tableName == null || rowId == null || column == null) return;
    final table = db.allTables.firstWhere(
      (t) => t.actualTableName == tableName,
    );
    // مفتاح الجدول الأساسي: `id` غالباً، و`key` لجدول الإعدادات.
    final keyColumn = table.$primaryKey.length == 1
        ? table.$primaryKey.single.name
        : 'id';
    await writer.patch(
      table,
      key: {keyColumn: rowId},
      values: {column: stored},
    );
  }

  Future<void> _fail(UploadQueueRow item, String message, {int? attempts}) =>
      (db.update(db.uploadQueue)..where((u) => u.id.equals(item.id))).write(
        UploadQueueCompanion(
          status: const Value(statusFailed),
          attempts: Value(attempts ?? item.attempts + 1),
          lastError: Value(message),
        ),
      );
}
