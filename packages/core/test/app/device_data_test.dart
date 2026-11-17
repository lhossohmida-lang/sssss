import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:school_core/school_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fixtures.dart';

void main() {
  late Directory support;

  setUp(() {
    support = Directory.systemTemp.createTempSync('school_device_data_');
  });
  tearDown(() {
    if (support.existsSync()) support.deleteSync(recursive: true);
  });

  File file(String relative, [String content = 'x']) {
    final f = File(p.join(support.path, relative));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
    return f;
  }

  DeviceDataWiper wiper(AppIdentity app) =>
      DeviceDataWiper(app, supportDirectory: () async => support);

  bool exists(String relative) =>
      FileSystemEntity.typeSync(p.join(support.path, relative)) !=
      FileSystemEntityType.notFound;

  group('مسح بيانات الجهاز', () {
    test(
      'يمسح كل ما يخصّ التطبيق: قواعد كل المدارس وصورها وربطها وتحديثاتها',
      () async {
        final mine = [
          'school_admin.sqlite',
          'school_admin.sqlite-wal',
          'school_admin.sqlite-shm',
          'school_admin_abc123.sqlite',
          'school_admin_abc123.sqlite-journal',
          'photos_admin/a.jpg',
          'photos_admin_abc123/group_files/x.pdf',
          'pairing_admin.json',
          'updates/school-admin-setup.exe',
          'drive_uploads/backup.zip',
        ];
        for (final name in mine) {
          file(name);
        }

        final report = await wiper(AppIdentity.admin).wipe();

        for (final name in mine) {
          expect(exists(name), isFalse, reason: name);
        }
        expect(report.files, mine.length);
        expect(report.directories, 4, reason: 'صورتان وتحديثات ورفع Drive');
        expect(report.complete, isTrue);
        expect(report.nothingFound, isFalse);
      },
    );

    test('لا يمسّ بيانات تطبيق آخر ولا ملفات لا تخصّه', () async {
      final keep = [
        'school_teacher.sqlite',
        'school_teacher_abc123.sqlite',
        'photos_teacher/a.jpg',
        'pairing_teacher.json',
        'school_administrator.sqlite',
        'photos_administrator/a.jpg',
        'PersistedInstallation.abc.json',
        'shared_preferences.json',
        'notes/school_admin.sqlite',
      ];
      for (final name in keep) {
        file(name);
      }
      file('school_admin.sqlite');

      await wiper(AppIdentity.admin).wipe();

      expect(exists('school_admin.sqlite'), isFalse);
      for (final name in keep) {
        expect(exists(name), isTrue, reason: name);
      }
    });

    test('تطبيق الأستاذ يمسح ملفاته هو فقط', () async {
      file('school_teacher_k1.sqlite');
      file('photos_teacher_k1/x.png');
      file('pairing_teacher.json');
      file('school_admin.sqlite');

      final report = await wiper(AppIdentity.teacher).wipe();

      expect(report.files, 3);
      expect(exists('school_admin.sqlite'), isTrue);
    });

    test('تكراره لا يضر، وغياب المجلد لا يرمي', () async {
      file('school_admin.sqlite');
      final first = await wiper(AppIdentity.admin).wipe();
      expect(first.files, 1);
      final second = await wiper(AppIdentity.admin).wipe();
      expect(second.nothingFound, isTrue);

      support.deleteSync(recursive: true);
      final missing = await wiper(AppIdentity.admin).wipe();
      expect(missing.nothingFound, isTrue);
      expect(missing.complete, isTrue);
    });
  });

  group('جلسات الدخول المحفوظة', () {
    test('تُمسح مفاتيح الجلسة فقط وتبقى بقية التفضيلات', () async {
      SharedPreferences.setMockInitialValues({
        'sb-abcdefghijklmnopqrst-auth-token': '{"access_token":"x"}',
        'sb-abcdefghijklmnopqrst-auth-token-code-verifier': 'v',
        'theme': 'dark',
        'other': 1,
      });

      await DeviceDataWiper.clearAuthSessions();

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), {'theme', 'other'});
    });

    test('بلا جلسات لا شيء يحدث', () async {
      SharedPreferences.setMockInitialValues({});
      await DeviceDataWiper.clearAuthSessions();
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    });
  });

  group('التغييرات غير المرسلة', () {
    test('تُعدّ عمليات طابور الإرسال', () async {
      final env = TestEnv();
      addTearDown(env.close);
      expect(await countUnsyncedChanges(env.db), 0);

      await env.writer.save(
        env.db.subjects,
        SubjectsCompanion.insert(
          id: 's1',
          createdAt: 1,
          updatedAt: 1,
          name: 'فيزياء',
          monthlyPrice: const Value(2500),
        ),
        key: {'id': 's1'},
      );
      expect(await countUnsyncedChanges(env.db), greaterThan(0));
    });
  });
}
