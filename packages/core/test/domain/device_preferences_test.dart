import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  group('GoogleAccountEmail', () {
    test('يُنظَّف بالأحرف الصغيرة ودون مسافات', () {
      expect(
        GoogleAccountEmail.normalize('  Owner.Name+drive@Gmail.COM '),
        'owner.name+drive@gmail.com',
      );
      expect(
        GoogleAccountEmail.normalize('director@school.example.dz'),
        'director@school.example.dz',
      );
    });

    test('الفارغ أو الفراغ يعني بلا بريد', () {
      expect(GoogleAccountEmail.normalize(null), isNull);
      expect(GoogleAccountEmail.normalize(''), isNull);
      expect(GoogleAccountEmail.normalize('   '), isNull);
    });

    test('الشكل الخاطئ يرمي FormatException برسالة عربية', () {
      for (final bad in [
        'no-at-sign',
        'two@@gmail.com',
        'a@b',
        'a b@gmail.com',
        '@gmail.com',
        'name@.com',
        'name@gmail',
        '${'x' * 250}@gmail.com',
      ]) {
        expect(
          () => GoogleAccountEmail.normalize(bad),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('بريد'),
            ),
          ),
          reason: bad,
        );
      }
    });
  });

  group('DevicePreferences', () {
    late TestEnv env;
    late DevicePreferences prefs;

    setUp(() {
      env = TestEnv();
      prefs = DevicePreferences(env.db);
    });
    tearDown(() => env.close());

    test('لا قيمة قبل الحفظ', () async {
      expect(await prefs.driveOwnerEmail(), isNull);
      expect(await prefs.read('anything'), isNull);
    });

    test('يحفظ القيمة ويستبدلها ويحذفها بالفارغ', () async {
      await prefs.write('k', ' one ');
      expect(await prefs.read('k'), 'one');
      await prefs.write('k', 'two');
      expect(await prefs.read('k'), 'two');
      await prefs.write('k', '  ');
      expect(await prefs.read('k'), isNull);
      expect(await env.db.select(env.db.deviceInfo).get(), isEmpty);
    });

    test('بريد المالك ينظَّف ويُحفظ، والمسح يزيله', () async {
      expect(
        await prefs.saveDriveOwnerEmail(' Owner@Gmail.com '),
        'owner@gmail.com',
      );
      expect(await prefs.driveOwnerEmail(), 'owner@gmail.com');
      expect(await prefs.saveDriveOwnerEmail(''), isNull);
      expect(await prefs.driveOwnerEmail(), isNull);
    });

    test('بريد غير صالح لا يغيّر المحفوظ', () async {
      await prefs.saveDriveOwnerEmail('owner@gmail.com');
      await expectLater(
        prefs.saveDriveOwnerEmail('not-an-email'),
        throwsFormatException,
      );
      expect(await prefs.driveOwnerEmail(), 'owner@gmail.com');
    });

    test('لا يُكتب في جدول الإعدادات المتزامن ولا طابور المزامنة', () async {
      await prefs.saveDriveOwnerEmail('owner@gmail.com');
      expect(await env.db.select(env.db.settings).get(), isEmpty);
      expect(await env.db.select(env.db.outbox).get(), isEmpty);
    });

    test('معرّف الجهاز عشوائي يُنشأ مرة ويبقى، ولا يُزامَن', () async {
      final first = await prefs.deviceId();
      expect(first, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(await prefs.deviceId(), first);
      // نسخة جديدة على القاعدة نفسها تقرأ المحفوظ ولا تنشئ آخر.
      expect(await DevicePreferences(env.db).deviceId(), first);
      expect(await prefs.read(DevicePreferences.deviceIdKey), first);
      expect(await env.db.select(env.db.settings).get(), isEmpty);
      expect(await env.db.select(env.db.outbox).get(), isEmpty);
    });

    test('علامة طلب إذن الرسائل تُحفظ محلياً', () async {
      expect(await prefs.read(DevicePreferences.smsPermissionAskedKey), isNull);
      await prefs.write(DevicePreferences.smsPermissionAskedKey, '1');
      expect(await prefs.read(DevicePreferences.smsPermissionAskedKey), '1');
    });

    test('watch يعيد القيمة الحالية ثم كل تغيير', () async {
      final seen = <String?>[];
      final subscription = prefs
          .watch(DevicePreferences.driveOwnerEmailKey)
          .listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await prefs.saveDriveOwnerEmail('a@gmail.com');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await prefs.saveDriveOwnerEmail('');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await subscription.cancel();
      expect(seen, [null, 'a@gmail.com', null]);
    });
  });
}
