import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import '../data/remote/upload_worker.dart';

/// نوع ملف Google Drive والمجلد الذي يحفظ تحته.
enum DriveUploadKind {
  file('drive_file', 'ملفات'),
  attendanceExcel('attendance_excel', 'Excel/الحضور'),
  backup('backup', 'النسخ الاحتياطية');

  const DriveUploadKind(this.code, this.folder);

  final String code;
  final String folder;
}

/// يثبّت الملفات المحلية في مجلد دائم ويضيفها إلى طابور Drive.
///
/// لا يحتاج إلى اتصال أو جلسة Google؛ تُرفع العناصر لاحقاً من أي جهاز إدارة
/// سجّل الدخول بحساب المالك. أسماء الملفات ومسارات الفئات ثابتة بين الأجهزة؛
/// ومفتاح المحتوى يمنع تكرار الصف نفسه على الجهاز. يمنع DriveFileStore
/// التكرار بين الأجهزة بالمسار المنطقي نفسه.
class DriveQueueService {
  DriveQueueService(
    this.db,
    this.writer, {
    required this.stagingDirectory,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase db;
  final SyncWriter writer;
  final Directory stagingDirectory;
  final int Function() _clock;

  static const String bucket = 'drive';

  /// يضيف مساراً من منتقي الملفات؛ الملف يُنسخ قبل حفظه في الطابور كيلا
  /// يعتمد الرفع على بقاء ملف المصدر أو صلاحية URI مؤقتة على Android.
  Future<bool> enqueueFile({
    required String sourcePath,
    required String fileName,
    required DriveUploadKind kind,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FileSystemException('الملف غير موجود');
    }
    final temporary = _temporaryFile();
    await source.copy(temporary.path);
    return _enqueueStaged(temporary, fileName: fileName, kind: kind);
  }

  /// يضيف تدفق منتقي الملفات مع كتابة تدريجية إلى القرص، دون تحميل الملف
  /// كاملاً في الذاكرة.
  Future<bool> enqueueStream({
    required Stream<List<int>> bytes,
    required String fileName,
    required DriveUploadKind kind,
  }) async {
    final temporary = _temporaryFile();
    final sink = temporary.openWrite();
    try {
      await sink.addStream(bytes);
      await sink.flush();
      await sink.close();
    } on Object {
      await sink.close();
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    return _enqueueStaged(temporary, fileName: fileName, kind: kind);
  }

  /// طابور Drive الأحدث أولاً (لواجهة الإدارة).
  Stream<List<UploadQueueRow>> watchQueue() =>
      (db.select(db.uploadQueue)
            ..where((u) => u.bucket.equals(bucket))
            ..orderBy([
              (u) => OrderingTerm(
                expression: u.createdAt,
                mode: OrderingMode.desc,
              ),
            ])
            ..limit(200))
          .watch();

  /// يعيد العناصر الفاشلة في مخزن Drive فقط إلى الانتظار.
  Future<int> retryFailed() async =>
      (db.update(db.uploadQueue)
            ..where((u) => u.bucket.equals(bucket) & u.status.equals('failed')))
          .write(
            const UploadQueueCompanion(
              status: Value(UploadWorker.statusPending),
              attempts: Value(0),
              nextAttemptAt: Value(0),
              lastError: Value(null),
            ),
          );

  File _temporaryFile() {
    stagingDirectory.createSync(recursive: true);
    return File(p.join(stagingDirectory.path, '${writer.newId()}.part'));
  }

  Future<bool> _enqueueStaged(
    File temporary, {
    required String fileName,
    required DriveUploadKind kind,
  }) async {
    try {
      final safeName = _safeFileName(fileName);
      if (safeName.isEmpty) throw const FormatException('اسم الملف غير صالح');
      final digest = await sha256.bind(temporary.openRead()).first;
      final remotePath = '${kind.folder}/$safeName';
      final dedupeKey =
          'drive:${sha256.convert(utf8.encode('$remotePath|$digest'))}';
      final extension = p.extension(safeName);
      final local = File(
        p.join(
          stagingDirectory.path,
          '${sha256.convert(utf8.encode(dedupeKey))}$extension',
        ),
      );

      if (!await local.exists()) await temporary.rename(local.path);
      return await UploadQueueWriter(db, writer, clock: _clock).enqueue(
        kind: kind.code,
        bucket: bucket,
        localPath: local.path,
        remotePath: remotePath,
        dedupeKey: dedupeKey,
      );
    } on Object {
      // لا نحذف الملف الثابت: قد تكون معاملة جهاز آخر محلياً قد أضافته بالفعل.
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  String _safeFileName(String value) {
    final name = p
        .basename(value.trim())
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    return name.replaceAll(RegExp(r'^\.+'), '').trim();
  }
}
