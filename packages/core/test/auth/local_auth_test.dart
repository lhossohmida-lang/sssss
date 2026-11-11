import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

/// تكرارات قليلة في الاختبارات حتى لا يطول الاشتقاق.
const int fastIterations = 50;

void main() {
  group('AppConfig', () {
    test('غير مهيّأ افتراضياً', () {
      expect(const AppConfig().isConfigured, isFalse);
      expect(AppConfig.fromEnvironment().isConfigured, isFalse);
    });

    test('يتطلب https ومفتاحاً', () {
      expect(
        const AppConfig(
          supabaseUrl: 'https://xyz.supabase.co',
          supabaseAnonKey: 'key',
        ).isConfigured,
        isTrue,
      );
      expect(
        const AppConfig(
          supabaseUrl: 'http://xyz.supabase.co',
          supabaseAnonKey: 'key',
        ).isConfigured,
        isFalse,
      );
      expect(
        const AppConfig(supabaseUrl: 'https://xyz.supabase.co').isConfigured,
        isFalse,
      );
      expect(
        const AppConfig(supabaseUrl: 'xyz', supabaseAnonKey: 'k').isConfigured,
        isFalse,
      );
    });
  });

  group('PasswordHasher', () {
    test('تطابق كلمة السر الصحيحة فقط', () async {
      final digest = await PasswordHasher.create(
        'secret-pass',
        iterations: fastIterations,
        random: Random(1),
      );
      expect(digest.iterations, fastIterations);
      expect(await PasswordHasher.verify('secret-pass', digest), isTrue);
      expect(await PasswordHasher.verify('secret-pasS', digest), isFalse);
      expect(await PasswordHasher.verify('', digest), isFalse);
    });

    test('الملح يختلف فتختلف البصمة لنفس كلمة السر', () async {
      final a = await PasswordHasher.create('same-pass', iterations: 10);
      final b = await PasswordHasher.create('same-pass', iterations: 10);
      expect(a.salt, isNot(b.salt));
      expect(a.hash, isNot(b.hash));
    });

    test('بصمة تالفة أو تكرارات غير صالحة ترفض', () async {
      expect(
        await PasswordHasher.verify(
          'x',
          const PasswordDigest(salt: '***', hash: '***', iterations: 10),
        ),
        isFalse,
      );
      final good = await PasswordHasher.create('x', iterations: 10);
      expect(
        await PasswordHasher.verify(
          'x',
          PasswordDigest(salt: good.salt, hash: good.hash, iterations: 0),
        ),
        isFalse,
      );
    });

    test('متجهات PBKDF2-HMAC-SHA256 المعروفة', () {
      String hex(List<int> bytes) =>
          bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final salt = utf8.encode('salt');
      expect(
        hex(PasswordHasher.derive('password', Uint8List.fromList(salt), 1)),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
      expect(
        hex(PasswordHasher.derive('password', Uint8List.fromList(salt), 2)),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });
  });

  group('LocalAuthGateway', () {
    late TestEnv env;
    late LocalAuthGateway gateway;

    setUp(() async {
      env = TestEnv();
      gateway = await LocalAuthGateway.open(env.db, iterations: fastIterations);
    });
    tearDown(() => env.close());

    test('جهاز جديد: لا حسابات ولا جلسة', () async {
      expect(await gateway.hasNoAccounts(), isTrue);
      expect(gateway.currentIdentity, isNull);
    });

    test('إنشاء صاحب المدرسة ثم الدخول بكلمة سره', () async {
      final created = await gateway.createFirstOwner(
        email: ' Owner@School.com ',
        displayName: ' المدير ',
        password: 'owner-pass-1',
      );
      expect(created.email, 'owner@school.com');
      expect(await gateway.hasNoAccounts(), isFalse);

      final row = await (env.db.select(
        env.db.userAccounts,
      )..where((t) => t.id.equals(created.id))).getSingle();
      expect(row.role, 'owner');
      expect(row.displayName, 'المدير');
      expect(row.mustChangePassword, isFalse);

      final identity = await gateway.signIn(
        email: 'owner@school.com',
        password: 'owner-pass-1',
      );
      expect(identity, created);
      expect(gateway.currentIdentity, created);
    });

    test('كتابة الحساب تمر عبر سجل العمليات وطابور المزامنة', () async {
      final created = await gateway.createFirstOwner(
        email: 'owner@school.com',
        displayName: 'المدير',
        password: 'owner-pass-1',
      );
      final outbox = await env.db.select(env.db.outbox).get();
      expect(outbox.any((o) => o.targetTable == 'user_accounts'), isTrue);
      final audit = await env.db.select(env.db.auditLog).get();
      expect(audit.single.userId, created.id);
    });

    test('لا تُخزَّن كلمة السر نصاً، بل بصمة', () async {
      await gateway.createFirstOwner(
        email: 'owner@school.com',
        displayName: 'م',
        password: 'owner-pass-1',
      );
      final creds = await env.db.select(env.db.localCredentials).getSingle();
      expect(creds.hash, isNot(contains('owner-pass-1')));
      expect(creds.salt, isNotEmpty);
      expect(creds.iterations, fastIterations);
    });

    test('كلمة سر خاطئة أو بريد مجهول: رفض موحّد', () async {
      await gateway.createFirstOwner(
        email: 'owner@school.com',
        displayName: 'م',
        password: 'owner-pass-1',
      );
      for (final attempt in [
        ('owner@school.com', 'wrong-pass-1'),
        ('nobody@school.com', 'owner-pass-1'),
      ]) {
        await expectLater(
          gateway.signIn(email: attempt.$1, password: attempt.$2),
          throwsA(
            isA<AuthFailureException>().having(
              (e) => e.failure,
              'failure',
              AuthFailure.invalidCredentials,
            ),
          ),
        );
      }
      expect(gateway.currentIdentity, isNull);
    });

    test('حساب ثانٍ مرفوض بعد الإعداد الأول', () async {
      await gateway.createFirstOwner(
        email: 'a@school.com',
        displayName: 'م',
        password: 'owner-pass-1',
      );
      await expectLater(
        gateway.createFirstOwner(
          email: 'b@school.com',
          displayName: 'م',
          password: 'owner-pass-2',
        ),
        throwsA(isA<AuthFailureException>()),
      );
    });

    test('بيانات إنشاء غير صالحة تُرفض دون كتابة', () async {
      for (final args in [
        ('bad', 'م', 'owner-pass-1'),
        ('a@school.com', '  ', 'owner-pass-1'),
        ('a@school.com', 'م', 'short'),
      ]) {
        await expectLater(
          gateway.createFirstOwner(
            email: args.$1,
            displayName: args.$2,
            password: args.$3,
          ),
          throwsA(isA<AuthFailureException>()),
        );
      }
      expect(await gateway.hasNoAccounts(), isTrue);
    });

    test('تغيير كلمة السر ثم الدخول بالجديدة فقط', () async {
      await gateway.createFirstOwner(
        email: 'owner@school.com',
        displayName: 'م',
        password: 'owner-pass-1',
      );
      await gateway.signIn(email: 'owner@school.com', password: 'owner-pass-1');
      await gateway.changePassword(newPassword: 'brand-new-pass');
      await gateway.signOut();
      expect(gateway.currentIdentity, isNull);
      await expectLater(
        gateway.signIn(email: 'owner@school.com', password: 'owner-pass-1'),
        throwsA(isA<AuthFailureException>()),
      );
      await gateway.signIn(
        email: 'owner@school.com',
        password: 'brand-new-pass',
      );
    });

    test('تغيير كلمة السر دون دخول يُرفض', () async {
      await expectLater(
        gateway.changePassword(newPassword: 'brand-new-pass'),
        throwsA(
          isA<AuthFailureException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.notSignedIn,
          ),
        ),
      );
    });

    test('الحساب المحذوف ناعماً لا يدخل', () async {
      final created = await gateway.createFirstOwner(
        email: 'owner@school.com',
        displayName: 'م',
        password: 'owner-pass-1',
      );
      await env.db.customStatement(
        "UPDATE user_accounts SET deleted_at = 9 WHERE id = '${created.id}'",
      );
      await expectLater(
        gateway.signIn(email: 'owner@school.com', password: 'owner-pass-1'),
        throwsA(isA<AuthFailureException>()),
      );
    });

    test('تُستعاد هوية الجلسة المحفوظة عند فتح البوابة من جديد', () async {
      final auth = AuthService(
        gateway: gateway,
        store: DatabaseSessionStore(env.db),
        directories: [LocalAccountDirectory(env.db)],
        writer: () => env.writer,
      );
      await gateway.createFirstOwner(
        email: 'owner@school.com',
        displayName: 'المدير',
        password: 'owner-pass-1',
      );
      await auth.signIn(email: 'owner@school.com', password: 'owner-pass-1');
      await auth.dispose();

      final reopened = await LocalAuthGateway.open(
        env.db,
        iterations: fastIterations,
      );
      expect(reopened.currentIdentity?.email, 'owner@school.com');
    });
  });

  group('UnconfiguredAuthGateway', () {
    test('يرفض الدخول برسالة واضحة ولا جلسة له', () async {
      const gateway = UnconfiguredAuthGateway();
      expect(gateway.currentIdentity, isNull);
      await expectLater(
        gateway.signIn(email: 'a@b.com', password: 'x'),
        throwsA(
          isA<AuthFailureException>().having(
            (e) => e.message,
            'message',
            UnconfiguredAuthGateway.message,
          ),
        ),
      );
      await gateway.signOut();
    });
  });
}
