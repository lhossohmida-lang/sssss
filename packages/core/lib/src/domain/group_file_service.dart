import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import '../data/remote/upload_worker.dart';
import 'catalog_service.dart';

/// ملف مرفوع لمجموعة (درس PDF أو تمارين) مع حالة رفعه.
class GroupFileItem {
  const GroupFileItem({required this.file, required this.uploaded});

  final GroupFileRow file;

  /// هل وصل الملف إلى الخادم (له رابط)؟ وإلا فهو في طابور الرفع.
  final bool uploaded;

  String get id => file.id;
  String get title => file.title;
  String get fileName => file.fileName;
  int get sizeBytes => file.sizeBytes;

  /// امتداد الملف بأحرف صغيرة بلا نقطة.
  String get extension => GroupFileService.extensionOf(file.fileName);

  bool get isPdf => extension == 'pdf';
  bool get isImage => GroupFileService.imageExtensions.contains(extension);
}

/// ملفات المجموعات: يرفعها أستاذ المجموعة (دروس وتمارين PDF أو صور)
/// فتُحفظ نسخة منها على الجهاز ويُسجَّل صفها فتظهر فوراً، وتوضع في طابور
/// الرفع فيُكتب رابطها على الخادم عند اكتماله وتصل إلى التلاميذ وأوليائهم.
class GroupFileService {
  GroupFileService(
    this.db,
    this.writer, {
    required this.directory,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final AppDatabase db;
  final SyncWriter writer;

  /// مجلد الملفات على الجهاز.
  final Directory directory;
  final int Function() _clock;

  static const String fieldTitle = 'title';
  static const String fieldFile = 'file';
  static const String fieldGroup = 'group';

  /// حد حجم الملف: حد مخزن `files` على الخادم (10 ميغابايت).
  static const int maxBytes = 10 * 1024 * 1024;

  /// مخزن الملفات على الخادم.
  static const String bucket = 'files';

  static const Set<String> imageExtensions = {'png', 'jpg', 'jpeg'};

  /// الامتدادات المقبولة: PDF وصور، وهي ما يُعرض داخل التطبيق دون برنامج آخر.
  static const Set<String> allowedExtensions = {'pdf', 'png', 'jpg', 'jpeg'};

  /// امتداد [fileName] بأحرف صغيرة بلا نقطة (فارغ إن لم يوجد).
  static String extensionOf(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    return ext.isEmpty ? '' : ext.substring(1);
  }

  /// ملفات المجموعة الأحدث أولاً، ولحظياً.
  Stream<List<GroupFileItem>> watchFiles(String groupId) {
    return db
        .customSelect('SELECT 1', readsFrom: {db.groupFiles})
        .watch()
        .asyncMap((_) => files(groupId));
  }

  Future<List<GroupFileItem>> files(String groupId) async {
    final rows =
        await (db.select(db.groupFiles)
              ..where((f) => f.groupId.equals(groupId) & f.deletedAt.isNull())
              ..orderBy([
                (f) => OrderingTerm.desc(f.createdAt),
                (f) => OrderingTerm.desc(f.id),
              ]))
            .get();
    return [
      for (final row in rows)
        GroupFileItem(
          file: row,
          uploaded: row.fileUrl != null && row.fileUrl!.isNotEmpty,
        ),
    ];
  }

  /// يضيف ملفاً إلى مجموعة الأستاذ [teacherId]: يتحقق ثم ينسخ [bytes] إلى
  /// مجلد الجهاز ويسجّل الصف ويضع الملف في طابور الرفع. يعيد الصف.
  ///
  /// يرمي [ValidationException] لعنوان فارغ أو امتداد غير مقبول أو ملف
  /// فارغ أو أكبر من [maxBytes] أو مجموعة ليست للأستاذ.
  Future<GroupFileRow> add({
    required String groupId,
    required String teacherId,
    required String title,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final errors = <String, String>{};
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) errors[fieldTitle] = 'أدخل عنوان الملف';
    final ext = extensionOf(fileName);
    if (!allowedExtensions.contains(ext)) {
      errors[fieldFile] = 'نوع الملف غير مقبول؛ المقبول: PDF أو صورة';
    } else if (bytes.isEmpty) {
      errors[fieldFile] = 'الملف فارغ';
    } else if (bytes.length > maxBytes) {
      errors[fieldFile] = 'الملف أكبر من 10 ميغابايت';
    }
    if (errors.isNotEmpty) throw ValidationException(errors);
    await _checkOwner(groupId, teacherId);

    final id = writer.newId();
    await directory.create(recursive: true);
    // اسم الملف على الجهاز معرّف الصف وحده فلا تتصادم أسماء الملفات.
    final local = File(p.join(directory.path, '$id.$ext'));
    await local.writeAsBytes(bytes, flush: true);
    try {
      return await db.transaction(() async {
        final now = writer.now();
        final row = GroupFileRow(
          id: id,
          createdAt: now,
          updatedAt: now,
          groupId: groupId,
          title: cleanTitle,
          fileName: p.basename(fileName),
          sizeBytes: bytes.length,
          localPath: local.path,
          uploadedBy: teacherId,
        );
        await writer.save(db.groupFiles, row, key: {'id': id});
        await UploadQueueWriter(db, writer, clock: _clock).enqueue(
          kind: 'group_file',
          bucket: bucket,
          localPath: local.path,
          remotePath: 'groups/$groupId/$id.$ext',
          dedupeKey: 'group_file:$id',
          targetTable: 'group_files',
          targetRowId: id,
          targetColumn: 'file_url',
        );
        return row;
      });
    } on Object {
      await _deleteLocal(local.path);
      rethrow;
    }
  }

  /// يعيد تسمية عنوان ملف لأستاذ المجموعة.
  Future<void> rename(
    String id, {
    required String title,
    required String teacherId,
  }) async {
    final clean = title.trim();
    if (clean.isEmpty) {
      throw ValidationException.field(fieldTitle, 'أدخل عنوان الملف');
    }
    final row = await _find(id);
    await _checkOwner(row.groupId, teacherId);
    await writer.patch(
      db.groupFiles,
      key: {'id': id},
      values: {'title': clean},
    );
  }

  /// يحذف ملفاً (حذف ناعم) لأستاذ المجموعة، ويزيل نسخته المحلية.
  Future<void> remove(String id, {required String teacherId}) async {
    final row = await _find(id);
    await _checkOwner(row.groupId, teacherId);
    await writer.softDelete(db.groupFiles, key: {'id': id});
    // رفع لم يبدأ لملف محذوف لا طائل منه.
    await db.customUpdate(
      "UPDATE upload_queue SET status = 'failed', "
      "last_error = 'حُذف الملف قبل رفعه' "
      "WHERE dedupe_key = 'group_file:$id' AND status = 'pending'",
      updates: {db.uploadQueue},
    );
    final path = row.localPath;
    if (path != null) await _deleteLocal(path);
  }

  /// بيانات الملف من نسخته المحلية؛ `null` إن لم توجد على هذا الجهاز.
  Future<Uint8List?> readLocal(GroupFileRow row) async {
    final path = row.localPath;
    if (path == null) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  Future<GroupFileRow> _find(String id) async {
    final row = await (db.select(
      db.groupFiles,
    )..where((f) => f.id.equals(id) & f.deletedAt.isNull())).getSingleOrNull();
    if (row == null) {
      throw ValidationException.field(fieldFile, 'هذا الملف غير موجود');
    }
    return row;
  }

  Future<void> _checkOwner(String groupId, String teacherId) async {
    final group =
        await (db.select(db.groups)
              ..where((g) => g.id.equals(groupId) & g.deletedAt.isNull()))
            .getSingleOrNull();
    if (group == null || group.teacherId != teacherId) {
      throw ValidationException.field(
        fieldGroup,
        'هذه المجموعة ليست من مجموعاتك',
      );
    }
  }

  Future<void> _deleteLocal(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // ملف عالق لا يمنع بقية العملية.
    }
  }
}
