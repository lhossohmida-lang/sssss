import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Table, TableInfo, Variable;
import 'package:path/path.dart' as p;

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import '../data/remote/file_store.dart';
import '../data/remote/remote_store.dart';
import '../data/remote/upload_worker.dart';
import 'photo_processor.dart';

/// من له صورة: الجدول وأعمدة المسار المحلي والرابط البعيد.
enum PhotoOwner {
  student('students', 'photo_local_path', 'photo_url', 'students'),
  teacher('teachers', 'photo_local_path', 'photo_url', 'teachers'),
  expenseInvoice(
    'expenses',
    'invoice_photo_local_path',
    'invoice_photo_url',
    'expenses',
  );

  const PhotoOwner(
    this.table,
    this.localColumn,
    this.remoteColumn,
    this.remoteFolder,
  );

  final String table;
  final String localColumn;
  final String remoteColumn;

  /// المجلد في مخزن الصور على الخادم.
  final String remoteFolder;
}

/// حفظ صور التلاميذ والأساتذة وفواتير المصاريف: ضغط في isolate، حفظ في مجلد
/// الجهاز، تسجيل المسار المحلي في السجل، ثم وضع الملف في طابور الرفع.
class PhotoService {
  PhotoService(
    this.db,
    this.writer, {
    required this.directory,
    this.files,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final AppDatabase db;
  final SyncWriter writer;

  /// مجلد الصور على الجهاز.
  final Directory directory;

  /// مخزن الملفات لجلب صورة رفعها جهاز آخر؛ `null` دون خادم.
  final FileStore? files;

  final int Function() _clock;

  /// يضغط [bytes] ويربطها بصاحب [id]، ويعيد مسار الملف المحلي.
  ///
  /// كل صورة جديدة باسم ملف جديد، فلا تُخدع ذاكرة الصور المؤقتة بالمسار
  /// القديم. تُحذف الصورة القديمة بعد نجاح التبديل. يرمي [FormatException]
  /// إن لم تكن البيانات صورة صالحة، و[StateError] إن لم يوجد السجل.
  Future<String> attach(PhotoOwner owner, String id, Uint8List bytes) async {
    final invoice = owner == PhotoOwner.expenseInvoice;
    final jpeg = await PhotoProcessor.compress(
      bytes,
      maxSide: invoice ? 1800 : PhotoProcessor.maxSide,
      quality: invoice ? 88 : PhotoProcessor.quality,
    );
    await directory.create(recursive: true);
    final stamp = _clock();
    final file = File(p.join(directory.path, '${owner.name}-$id-$stamp.jpg'));
    await file.writeAsBytes(jpeg, flush: true);

    final old = await _currentPath(owner, id);
    final updated = await writer.patch(
      _table(owner),
      key: {'id': id},
      values: {owner.localColumn: file.path},
    );
    if (!updated) {
      await _delete(file.path);
      throw StateError('السجل غير موجود: ${owner.table}/$id');
    }
    await UploadQueueWriter(db, writer, clock: _clock).enqueue(
      kind: 'photo',
      bucket: 'photos',
      localPath: file.path,
      remotePath: '${owner.remoteFolder}/$id-$stamp.jpg',
      dedupeKey: 'photo:${owner.table}:$id:$stamp',
      targetTable: owner.table,
      targetRowId: id,
      targetColumn: owner.remoteColumn,
    );
    if (old != null && old != file.path) await _delete(old);
    return file.path;
  }

  /// يزيل صورة صاحب [id]: يمسح المسار المحلي والرابط ويحذف الملف.
  Future<void> remove(PhotoOwner owner, String id) async {
    final old = await _currentPath(owner, id);
    await writer.patch(
      _table(owner),
      key: {'id': id},
      values: {owner.localColumn: null, owner.remoteColumn: null},
    );
    if (old != null) await _delete(old);
  }

  /// يعيد الصورة المحلية، أو يجلبها من مخزن الصور إن رفعها جهاز آخر.
  /// تحفظ النسخة البعيدة محلياً باسم يتضمن مسارها ليُحدَّث cache عند تبديلها.
  Future<File?> resolve(PhotoOwner owner, String id) async {
    final row = await db
        .customSelect(
          'SELECT ${owner.localColumn} AS local_path, '
          '${owner.remoteColumn} AS remote_path FROM ${owner.table} '
          'WHERE id = ?',
          variables: [Variable<String>(id)],
          readsFrom: {db.students, db.teachers, db.expenses},
        )
        .getSingleOrNull();
    if (row == null) return null;

    final localPath = row.read<String?>('local_path');
    if (localPath != null && localPath.isNotEmpty) {
      final local = File(localPath);
      if (local.existsSync()) return local;
    }

    final remote = row.read<String?>('remote_path');
    final store = files;
    if (remote == null || remote.isEmpty || store == null) return null;
    final slash = remote.indexOf('/');
    if (slash <= 0) return null;
    final bucket = remote.substring(0, slash);
    final remotePath = remote.substring(slash + 1);
    if (bucket != 'photos' ||
        !remotePath.startsWith('${owner.remoteFolder}/')) {
      return null;
    }

    final cacheKey = remotePath.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File(
      p.join(directory.path, '${owner.name}-$id-$cacheKey.jpg'),
    );
    if (file.existsSync()) return file;
    try {
      final bytes = await store.download(
        bucket: bucket,
        remotePath: remotePath,
      );
      await directory.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } on RemoteException {
      return null;
    }
  }

  TableInfo<Table, Object?> _table(PhotoOwner owner) => switch (owner) {
    PhotoOwner.student => db.students,
    PhotoOwner.teacher => db.teachers,
    PhotoOwner.expenseInvoice => db.expenses,
  };

  Future<String?> _currentPath(PhotoOwner owner, String id) async {
    final row = await db
        .customSelect(
          'SELECT ${owner.localColumn} AS path FROM ${owner.table} '
          'WHERE id = ?',
          variables: [Variable<String>(id)],
          readsFrom: {db.students, db.teachers, db.expenses},
        )
        .getSingleOrNull();
    return row?.read<String?>('path');
  }

  Future<void> _delete(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // ملف قديم عالق لا يمنع حفظ الصورة الجديدة.
    }
  }
}
