import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('school_backup_test');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('ينشئ لقطة سليمة ويستعيد بياناتها إلى قاعدة قائمة', () async {
    final source = File('${directory.path}/source.sqlite');
    final snapshot = File('${directory.path}/backup.sqlite');
    final destination = File('${directory.path}/destination.sqlite');
    _createDatabase(source, 'من النسخة');
    _createDatabase(destination, 'البيانات الحالية');
    _setDeviceInfo(source, 'device-a');
    _setDeviceInfo(destination, 'device-b');

    final sourceBackup = DatabaseBackupService(databaseFile: source);
    await sourceBackup.createSnapshot(snapshot);
    _expectValue(snapshot, 'من النسخة');
    _expectDeviceInfo(snapshot, expectEmpty: true);
    _expectSession(snapshot, expectEmpty: true);

    await DatabaseBackupService(databaseFile: destination)
        .restoreFrom(snapshot);

    _expectValue(destination, 'من النسخة');
    _expectDeviceInfo(destination, value: 'device-b');
    _expectSession(destination, expectEmpty: true);
  });

  test('يرفض مخططاً غير مطابق قبل تغيير قاعدة الوجهة', () async {
    final invalid = File('${directory.path}/wrong-version.sqlite');
    final destination = File('${directory.path}/destination.sqlite');
    _createDatabase(invalid, 'نسخة قديمة', version: 2);
    _createDatabase(destination, 'البيانات الحالية');

    await expectLater(
      DatabaseBackupService(databaseFile: destination).restoreFrom(invalid),
      throwsA(isA<FormatException>()),
    );
    _expectValue(destination, 'البيانات الحالية');
  });

  test('يحذف لقطة غير مكتملة إن فشل التحقق من مخطط المصدر', () async {
    final invalid = File('${directory.path}/wrong-version.sqlite');
    final snapshot = File('${directory.path}/backup.sqlite');
    _createDatabase(invalid, 'نسخة قديمة', version: 2);

    await expectLater(
      DatabaseBackupService(databaseFile: invalid).createSnapshot(snapshot),
      throwsA(isA<FormatException>()),
    );
    expect(snapshot.existsSync(), isFalse);
  });

  test('ينسخ ويستعيد القاعدة الفعلية المفتوحة بوضع WAL', () async {
    final databaseFile = File('${directory.path}/school_admin.sqlite');
    final snapshot = File('${directory.path}/school_backup.sqlite');
    final database = openAppDatabase(databaseFile);
    try {
      await database.customSelect('SELECT 1').getSingle();
      await database
          .into(database.settings)
          .insert(
            SettingsCompanion.insert(
              key: 'school_name',
              value: 'نسخة المصدر',
              updatedAt: 1,
            ),
          );
      await database.customStatement(
        'INSERT INTO device_info (key, value) VALUES '
        '(\'receipt_device\', \'local-device\')',
      );
      await database.customStatement(
        'INSERT INTO device_session (id, account_id, email, role, display_name, '
        'must_change_password, permissions, saved_at) VALUES '
        '(1, \'owner\', \'owner@school.dz\', \'owner\', \'Owner\', 0, \'{}\', 1)',
      );

      await DatabaseBackupService(
        databaseFile: databaseFile,
        schemaVersion: database.schemaVersion,
      ).createSnapshot(snapshot);
      await database.customStatement(
        'UPDATE settings SET value = \'بيانات أحدث من النسخة\', updated_at = 3 '
        'WHERE key = \'school_name\'',
      );
      await DatabaseBackupService(
        databaseFile: databaseFile,
        schemaVersion: database.schemaVersion,
      ).restoreFrom(snapshot);

      final restored = await database.select(database.settings).getSingle();
      final deviceInfo = await database.select(database.deviceInfo).get();
      final session = await database.select(database.deviceSession).get();
      expect(restored.value, 'نسخة المصدر');
      expect(deviceInfo.single.value, 'local-device');
      expect(session, isEmpty);
    } finally {
      await database.close();
    }
  });
}

void _createDatabase(File file, String value, {int version = 3}) {
  final database = sqlite3.open(file.path);
  database.execute('PRAGMA user_version = $version');
  database.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
  database.execute(
    'CREATE TABLE device_info (key TEXT PRIMARY KEY, value TEXT)',
  );
  database.execute('CREATE TABLE device_session (id INTEGER PRIMARY KEY)');
  database.execute('INSERT INTO settings (key, value) VALUES (?, ?)', [
    'message',
    value,
  ]);
  database.close();
}

void _expectValue(File file, String expected) {
  final database = sqlite3.open(file.path, mode: OpenMode.readOnly);
  final value = database
      .select("SELECT value FROM settings WHERE key = 'message'")
      .single
      .values
      .first;
  database.close();
  expect(value, expected);
}

void _setDeviceInfo(File file, String deviceId) {
  final database = sqlite3.open(file.path);
  database.execute('INSERT INTO device_info (key, value) VALUES (?, ?)', [
    'receipt_device',
    deviceId,
  ]);
  database.execute('INSERT INTO device_session (id) VALUES (1)');
  database.close();
}

void _expectDeviceInfo(File file, {String? value, bool expectEmpty = false}) {
  final database = sqlite3.open(file.path, mode: OpenMode.readOnly);
  final rows = database.select('SELECT value FROM device_info');
  database.close();
  if (expectEmpty) {
    expect(rows, isEmpty);
  } else {
    expect(rows.single['value'], value);
  }
}

void _expectSession(File file, {required bool expectEmpty}) {
  final database = sqlite3.open(file.path, mode: OpenMode.readOnly);
  final rows = database.select('SELECT id FROM device_session');
  database.close();
  expect(rows, expectEmpty ? isEmpty : hasLength(1));
}
