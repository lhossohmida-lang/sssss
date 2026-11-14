import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// ينشئ لقطة SQLite متسقة أو يستعيدها مع التحقق من المخطط وسلامة الصفحات.
///
/// يستخدم SQLite Backup API كي يشمل معاملات WAL المكتملة من دون نسخ ملفات
/// القاعدة النشطة مباشرة أو تعطيل الكتابة في التطبيق.
class DatabaseBackupService {
  DatabaseBackupService({required this.databaseFile, this.schemaVersion = 3});

  final File databaseFile;
  final int schemaVersion;

  /// يكتب لقطة قابلة للنقل إلى [destination] ويزيل الوجهة الجزئية عند الفشل.
  Future<void> createSnapshot(File destination) async {
    if (!await databaseFile.exists()) {
      throw const FileSystemException('ملف قاعدة البيانات غير موجود');
    }
    await destination.parent.create(recursive: true);
    if (await destination.exists()) await destination.delete();

    Database? source;
    Database? target;
    try {
      source = sqlite3.open(databaseFile.path, mode: OpenMode.readOnly);
      target = sqlite3.open(destination.path);
      await source.backup(target, nPage: 128).drain<void>();
      _verify(target);
      _clearIfPresent(target, 'device_session');
      _clearIfPresent(target, 'device_info');
    } on Object {
      target?.close();
      target = null;
      source?.close();
      source = null;
      if (await destination.exists()) await destination.delete();
      rethrow;
    } finally {
      target?.close();
      source?.close();
    }
  }

  /// يستبدل محتوى القاعدة الحالية فقط بعد فحص اللقطة كاملة.
  ///
  /// تبقى واجهات التطبيق عاملة على اتصال Drift نفسه؛ على نجاح الاستعادة يجب
  /// إغلاق التطبيق وإعادة فتحه كي تُستعاد الجلسة والصلاحيات من البيانات الجديدة.
  Future<void> restoreFrom(File backup) async {
    if (!await backup.exists()) {
      throw const FileSystemException('ملف النسخة الاحتياطية غير موجود');
    }
    Database? source;
    Database? target;
    try {
      source = sqlite3.open(backup.path, mode: OpenMode.readOnly);
      _verify(source);
      if (!await databaseFile.parent.exists()) {
        await databaseFile.parent.create(recursive: true);
      }
      target = sqlite3.open(databaseFile.path);
      final deviceInfo = _readDeviceInfo(target);
      await source.backup(target, nPage: 128).drain<void>();
      _verify(target);
      _clearIfPresent(target, 'device_session');
      _clearIfPresent(target, 'device_info');
      if (deviceInfo.isNotEmpty && _tableExists(target, 'device_info')) {
        final insert = target.prepare(
          'INSERT OR REPLACE INTO device_info (key, value) VALUES (?, ?)',
        );
        try {
          for (final entry in deviceInfo) {
            insert.execute([entry.key, entry.value]);
          }
        } finally {
          insert.close();
        }
      }
    } finally {
      target?.close();
      source?.close();
    }
  }

  void _verify(Database database) {
    final version = database.select('PRAGMA user_version').single.values.first;
    if (version != schemaVersion) {
      throw FormatException(
        'إصدار مخطط النسخة ($version) لا يطابق التطبيق ($schemaVersion)',
      );
    }
    final integrity = database
        .select('PRAGMA integrity_check')
        .single
        .values
        .first;
    if (integrity != 'ok') {
      throw const FormatException('ملف النسخة الاحتياطية تالف');
    }
    final tables = database.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'settings'",
    );
    if (tables.isEmpty) {
      throw const FormatException('الملف ليس قاعدة تطبيق المدرسة');
    }
  }

  List<({String key, String value})> _readDeviceInfo(Database database) {
    if (!_tableExists(database, 'device_info')) return const [];
    return [
      for (final row in database.select('SELECT key, value FROM device_info'))
        (key: row['key'] as String, value: row['value'] as String),
    ];
  }

  void _clearIfPresent(Database database, String table) {
    if (_tableExists(database, table)) database.execute('DELETE FROM $table');
  }

  bool _tableExists(Database database, String name) => database.select(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
    [name],
  ).isNotEmpty;
}
