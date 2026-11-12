import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import '../data/remote/file_store.dart';
import '../data/remote/remote_store.dart';
import '../data/remote/upload_worker.dart';
import 'photo_processor.dart';
import 'setting_keys.dart';

/// شعار المدرسة: يُضغط (أطول ضلع 400)، يُحفظ على الجهاز فيُعرض فوراً،
/// ويُرفع في الخلفية فيصل الأجهزة الأخرى، وتجلبه هي من الخادم عند الحاجة.
class LogoService {
  LogoService(
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

  /// مخزن ملفات الخادم لجلب شعار رفعه جهاز آخر؛ `null` دون خادم.
  final FileStore? files;
  final int Function() _clock;

  /// أطول ضلع للشعار بالبكسل (يكفي للبطاقة والوصل المطبوعين).
  static const int maxSide = 400;

  /// يضغط [bytes] ويجعلها شعار المدرسة، ويعيد مسار الملف المحلي.
  /// يرمي [FormatException] إن لم تكن صورة صالحة.
  Future<String> set(Uint8List bytes) async {
    final jpeg = await PhotoProcessor.compress(
      bytes,
      maxSide: maxSide,
      quality: 85,
    );
    await directory.create(recursive: true);
    final stamp = _clock();
    final file = File(p.join(directory.path, 'logo-$stamp.jpg'));
    await file.writeAsBytes(jpeg, flush: true);

    final old = await _setting(SettingKeys.schoolLogoLocal);
    await _write(SettingKeys.schoolLogoLocal, file.path);
    // صف الرابط يجب أن يوجد ليكتب فيه الرفع نتيجته (التحديث لا يُنشئ صفاً).
    if (await _setting(SettingKeys.schoolLogo) == null) {
      await _write(SettingKeys.schoolLogo, '');
    }
    await UploadQueueWriter(db, writer, clock: _clock).enqueue(
      kind: 'photo',
      bucket: 'photos',
      localPath: file.path,
      remotePath: 'school/logo-$stamp.jpg',
      dedupeKey: 'logo:$stamp',
      targetTable: 'settings',
      targetRowId: SettingKeys.schoolLogo,
      targetColumn: 'value',
    );
    if (old != null && old.isNotEmpty && old != file.path) await _delete(old);
    return file.path;
  }

  /// يزيل الشعار.
  Future<void> clear() async {
    final old = await _setting(SettingKeys.schoolLogoLocal);
    await _write(SettingKeys.schoolLogoLocal, '');
    await _write(SettingKeys.schoolLogo, '');
    if (old != null && old.isNotEmpty) await _delete(old);
  }

  /// ملف الشعار على هذا الجهاز: المحلي إن وُجد، وإلا يُجلب من الخادم (إن
  /// وُجد رابطه ومخزن الملفات) ويُحفظ للمرات القادمة. `null` إن لم يوجد.
  Future<File?> resolve() async {
    final local = await _setting(SettingKeys.schoolLogoLocal);
    if (local != null && local.isNotEmpty && File(local).existsSync()) {
      return File(local);
    }
    final remote = await _setting(SettingKeys.schoolLogo);
    final store = files;
    if (remote == null || remote.isEmpty || store == null) return null;
    final slash = remote.indexOf('/');
    if (slash < 0) return null;
    try {
      final bytes = await store.download(
        bucket: remote.substring(0, slash),
        remotePath: remote.substring(slash + 1),
      );
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, 'logo-remote.jpg'));
      await file.writeAsBytes(bytes, flush: true);
      await _write(SettingKeys.schoolLogoLocal, file.path);
      return file;
    } on RemoteException {
      return null;
    }
  }

  Future<String?> _setting(String key) async {
    final row = await (db.select(
      db.settings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _write(String key, String value) => writer.save(
    db.settings,
    SettingsCompanion.insert(key: key, value: value, updatedAt: writer.now()),
    key: {'key': key},
  );

  Future<void> _delete(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // ملف قديم عالق لا يمنع حفظ الشعار الجديد.
    }
  }
}
