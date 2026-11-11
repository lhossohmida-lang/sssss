import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fake_auth.dart';
import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late FakeAuthGateway gateway;
  late AuthService service;

  Future<void> addAccount(
    String id,
    String email,
    UserRole role, {
    String? entityId,
    bool mustChange = true,
    String name = '',
  }) => env.db
      .into(env.db.userAccounts)
      .insert(
        UserAccountsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          email: email,
          role: role.code,
          entityId: Value(entityId),
          displayName: Value(name),
          mustChangePassword: Value(mustChange),
        ),
      );

  Future<void> addWorker(String id, String permissions) => env.db
      .into(env.db.workers)
      .insert(
        WorkersCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          name: 'عامل',
          phone: '0550000001',
          email: 'w@school.local',
          qrCode: 'W-$id',
          permissions: Value(permissions),
        ),
      );

  AuthService build({AppIdentity? app}) => AuthService(
    gateway: gateway,
    store: DatabaseSessionStore(env.db, clock: () => 5000),
    directories: [LocalAccountDirectory(env.db)],
    writer: () => env.writer,
    app: app,
  );

  setUp(() async {
    env = TestEnv();
    gateway = FakeAuthGateway({
      'owner@school.local': (id: 'u-owner', password: 'ownerpass1'),
      'w@school.local': (id: 'u-worker', password: 'workerpass'),
      't@school.local': (id: 'u-teacher', password: 'teacherpass'),
      'ghost@school.local': (id: 'u-ghost', password: 'ghostpass1'),
    });
    await addAccount(
      'u-owner',
      'owner@school.local',
      UserRole.owner,
      mustChange: false,
      name: 'المدير',
    );
    await addWorker('w1', '{"students":["view","add"],"scanner":["use"]}');
    await addAccount(
      'u-worker',
      'w@school.local',
      UserRole.worker,
      entityId: 'w1',
      name: 'عامل الاستقبال',
    );
    await addAccount(
      'u-teacher',
      't@school.local',
      UserRole.teacher,
      entityId: 't1',
    );
    service = build();
  });

  tearDown(() async {
    await service.dispose();
    await env.close();
  });

  group('تسجيل الدخول', () {
    test(
      'صاحب المدرسة: يملك كل الصلاحيات ولا يُجبر على تغيير كلمة السر',
      () async {
        final session = await service.signIn(
          email: 'owner@school.local',
          password: 'ownerpass1',
        );
        expect(session.role, UserRole.owner);
        expect(session.displayName, 'المدير');
        expect(session.entityId, isNull);
        expect(session.mustChangePassword, isFalse);
        expect(
          session.can(PermissionModule.settings, PermissionAction.edit),
          isTrue,
        );
        expect(service.current, session);
        expect(service.isReady, isTrue);
      },
    );

    test('العامل: صلاحياته من جدول العمال', () async {
      final session = await service.signIn(
        email: 'w@school.local',
        password: 'workerpass',
      );
      expect(session.role, UserRole.worker);
      expect(session.entityId, 'w1');
      expect(
        session.can(PermissionModule.students, PermissionAction.add),
        isTrue,
      );
      expect(
        session.can(PermissionModule.scanner, PermissionAction.use),
        isTrue,
      );
      expect(
        session.can(PermissionModule.students, PermissionAction.delete),
        isFalse,
      );
      expect(
        session.can(PermissionModule.payments, PermissionAction.view),
        isFalse,
      );
      expect(session.mustChangePassword, isTrue);
      expect(service.isReady, isFalse);
    });

    test('البريد يُوحَّد (مسافات وحروف كبيرة)', () async {
      final session = await service.signIn(
        email: '  OWNER@school.local ',
        password: 'ownerpass1',
      );
      expect(session.accountId, 'u-owner');
    });

    test('كلمة سر خاطئة أو بريد مجهول يُرفضان ولا تُحفظ جلسة', () async {
      for (final attempt in [
        ('owner@school.local', 'wrong-pass'),
        ('nobody@school.local', 'ownerpass1'),
      ]) {
        await expectLater(
          service.signIn(email: attempt.$1, password: attempt.$2),
          throwsA(
            isA<AuthFailureException>().having(
              (e) => e.failure,
              'failure',
              AuthFailure.invalidCredentials,
            ),
          ),
        );
      }
      expect(service.current, isNull);
      expect(await DatabaseSessionStore(env.db).read(), isNull);
    });

    test('بريد غير صالح وكلمة سر فارغة يُرفضان قبل الاتصال', () async {
      await expectLater(
        service.signIn(email: 'abc', password: 'x'),
        throwsA(
          isA<AuthFailureException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.invalidEmail,
          ),
        ),
      );
      await expectLater(
        service.signIn(email: 'owner@school.local', password: ''),
        throwsA(
          isA<AuthFailureException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.invalidCredentials,
          ),
        ),
      );
    });

    test('عطل الشبكة يُصنَّف مؤقتاً برسالة عربية', () async {
      gateway.offline = true;
      await expectLater(
        service.signIn(email: 'owner@school.local', password: 'ownerpass1'),
        throwsA(
          isA<AuthFailureException>()
              .having((e) => e.transient, 'transient', isTrue)
              .having((e) => e.message, 'message', 'لا يوجد اتصال بالإنترنت'),
        ),
      );
    });

    test('حساب بلا سجل في النظام يُرفض ويُخرَج من الخادم', () async {
      await expectLater(
        service.signIn(email: 'ghost@school.local', password: 'ghostpass1'),
        throwsA(
          isA<AuthFailureException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.noAccount,
          ),
        ),
      );
      expect(gateway.currentIdentity, isNull);
      expect(gateway.signOuts, 1);
    });

    test('حساب محذوف حذفاً ناعماً لا يدخل', () async {
      await env.db.customStatement(
        "UPDATE user_accounts SET deleted_at = 9 WHERE id = 'u-owner'",
      );
      await expectLater(
        service.signIn(email: 'owner@school.local', password: 'ownerpass1'),
        throwsA(
          isA<AuthFailureException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.noAccount,
          ),
        ),
      );
    });

    test('عامل محذوف حذفاً ناعماً يدخل بلا صلاحيات', () async {
      await env.db.customStatement(
        "UPDATE workers SET deleted_at = 9 WHERE id = 'w1'",
      );
      final session = await service.signIn(
        email: 'w@school.local',
        password: 'workerpass',
      );
      expect(session.account.permissions.isEmpty, isTrue);
      expect(
        session.can(PermissionModule.students, PermissionAction.view),
        isFalse,
      );
    });
  });

  group('حصر الدخول بتطبيق الدور', () {
    test('الأستاذ لا يدخل تطبيق الإدارة', () async {
      service = build(app: AppIdentity.admin);
      await expectLater(
        service.signIn(email: 't@school.local', password: 'teacherpass'),
        throwsA(
          isA<AuthFailureException>()
              .having((e) => e.failure, 'failure', AuthFailure.wrongApp)
              .having((e) => e.message, 'message', contains('الإدارة')),
        ),
      );
      expect(service.current, isNull);
      expect(gateway.currentIdentity, isNull);
      expect(await DatabaseSessionStore(env.db).read(), isNull);
    });

    test(
      'العامل وصاحب المدرسة يدخلان تطبيق الإدارة، والأستاذ تطبيقه',
      () async {
        service = build(app: AppIdentity.admin);
        await service.signIn(email: 'w@school.local', password: 'workerpass');
        await service.signOut();
        await service.signIn(
          email: 'owner@school.local',
          password: 'ownerpass1',
        );
        await service.signOut();
        service = build(app: AppIdentity.teacher);
        final teacher = await service.signIn(
          email: 't@school.local',
          password: 'teacherpass',
        );
        expect(teacher.role, UserRole.teacher);
      },
    );
  });

  group('حفظ الجلسة', () {
    test('تُحفظ بعد الدخول وتُستعاد في التشغيل التالي دون كلمة سر', () async {
      await service.signIn(email: 'w@school.local', password: 'workerpass');
      final saved = gateway.currentIdentity;

      final next = build();
      gateway.restoreIdentity(saved);
      final restored = await next.restore();
      expect(restored, isNotNull);
      expect(restored!.accountId, 'u-worker');
      expect(
        restored.can(PermissionModule.scanner, PermissionAction.use),
        isTrue,
      );
      expect(next.current, restored);
      await next.dispose();
    });

    test('تُستعاد صلاحيات العامل الجديدة بعد المزامنة', () async {
      await service.signIn(email: 'w@school.local', password: 'workerpass');
      await env.db.customStatement(
        '''UPDATE workers SET permissions = '{"payments":["view"]}' WHERE id = 'w1' ''',
      );
      final next = build();
      final restored = await next.restore();
      expect(
        restored!.can(PermissionModule.payments, PermissionAction.view),
        isTrue,
      );
      expect(
        restored.can(PermissionModule.scanner, PermissionAction.use),
        isFalse,
      );
      // وتُحفظ المحدَّثة.
      final stored = await DatabaseSessionStore(env.db).read();
      expect(
        stored!.can(PermissionModule.payments, PermissionAction.view),
        isTrue,
      );
      await next.dispose();
    });

    test(
      'تُستعاد دون إنترنت من النسخة المحفوظة إن لم يوجد الحساب محلياً',
      () async {
        await service.signIn(email: 'w@school.local', password: 'workerpass');
        await env.db.customStatement('DELETE FROM user_accounts');
        final next = build();
        final restored = await next.restore();
        expect(restored, isNotNull);
        expect(restored!.accountId, 'u-worker');
        expect(
          restored.can(PermissionModule.students, PermissionAction.view),
          isTrue,
        );
        await next.dispose();
      },
    );

    test('جلسة الخادم المنتهية تمحو الجلسة المحفوظة', () async {
      await service.signIn(email: 'owner@school.local', password: 'ownerpass1');
      gateway.restoreIdentity(null);
      final next = build();
      expect(await next.restore(), isNull);
      expect(await DatabaseSessionStore(env.db).read(), isNull);
      await next.dispose();
    });

    test('بلا جلسة محفوظة لا يُستعاد شيء', () async {
      expect(await service.restore(), isNull);
      expect(service.current, isNull);
      expect(service.isReady, isFalse);
    });

    test('الخروج يمحو الجلسة ويُعلم المستمعين', () async {
      final events = <AuthSession?>[];
      final subscription = service.changes.listen(events.add);
      await service.signIn(email: 'owner@school.local', password: 'ownerpass1');
      await service.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(service.current, isNull);
      expect(gateway.currentIdentity, isNull);
      expect(await DatabaseSessionStore(env.db).read(), isNull);
      expect(events.map((s) => s?.accountId), ['u-owner', null]);
      await subscription.cancel();
    });

    test('صف الجلسة تالف الدور يُمحى ولا يُدخل أحداً', () async {
      final store = DatabaseSessionStore(env.db);
      await env.db.customStatement(
        'INSERT INTO device_session (id, account_id, email, role, saved_at) '
        "VALUES (1, 'x', 'x@y.com', 'admin-god', 1)",
      );
      expect(await store.read(), isNull);
      final rows = await env.db.select(env.db.deviceSession).get();
      expect(rows, isEmpty);
    });
  });

  group('تغيير كلمة السر عند أول دخول', () {
    test('يرفع العلامة محلياً ويضعها في طابور المزامنة ويسجّلها', () async {
      await service.signIn(email: 'w@school.local', password: 'workerpass');
      expect(service.isReady, isFalse);

      final updated = await service.changePassword(newPassword: 'NewPass123');
      expect(updated.mustChangePassword, isFalse);
      expect(service.isReady, isTrue);
      expect(gateway.lastPasswordSet, 'NewPass123');

      final row = await (env.db.select(
        env.db.userAccounts,
      )..where((t) => t.id.equals('u-worker'))).getSingle();
      expect(row.mustChangePassword, isFalse);
      expect(row.entityId, 'w1');
      expect(row.role, 'worker');
      expect(row.displayName, 'عامل الاستقبال');

      final queued = await env.db.select(env.db.outbox).get();
      expect(
        queued.where(
          (o) => o.targetTable == 'user_accounts' && o.rowId == 'u-worker',
        ),
        hasLength(1),
      );
      final audit = await env.db.select(env.db.auditLog).get();
      expect(audit.where((a) => a.entity == 'user_accounts'), hasLength(1));

      // الجلسة المحفوظة تتبع الحالة الجديدة.
      final stored = await DatabaseSessionStore(env.db).read();
      expect(stored!.mustChangePassword, isFalse);
    });

    test('كلمة السر الجديدة تدخل بها في المرة التالية فقط', () async {
      await service.signIn(email: 'w@school.local', password: 'workerpass');
      await service.changePassword(newPassword: 'NewPass123');
      await service.signOut();
      await expectLater(
        service.signIn(email: 'w@school.local', password: 'workerpass'),
        throwsA(isA<AuthFailureException>()),
      );
      final session = await service.signIn(
        email: 'w@school.local',
        password: 'NewPass123',
      );
      expect(session.mustChangePassword, isFalse);
    });

    test('كلمة سر قصيرة تُرفض ولا تُغيَّر', () async {
      await service.signIn(email: 'w@school.local', password: 'workerpass');
      await expectLater(
        service.changePassword(newPassword: 'short'),
        throwsA(
          isA<AuthFailureException>()
              .having((e) => e.failure, 'failure', AuthFailure.weakPassword)
              .having((e) => e.message, 'message', contains('8')),
        ),
      );
      expect(gateway.lastPasswordSet, isNull);
      expect(service.current!.mustChangePassword, isTrue);
    });

    test('دون تسجيل دخول يُرفض', () async {
      await expectLater(
        service.changePassword(newPassword: 'NewPass123'),
        throwsA(
          isA<AuthFailureException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.notSignedIn,
          ),
        ),
      );
    });

    test('فشل الشبكة لا يرفع العلامة', () async {
      await service.signIn(email: 'w@school.local', password: 'workerpass');
      gateway.offline = true;
      await expectLater(
        service.changePassword(newPassword: 'NewPass123'),
        throwsA(isA<AuthFailureException>()),
      );
      expect(service.current!.mustChangePassword, isTrue);
      final row = await (env.db.select(
        env.db.userAccounts,
      )..where((t) => t.id.equals('u-worker'))).getSingle();
      expect(row.mustChangePassword, isTrue);
    });

    test('من غيّرها من قبل يغيّرها ثانية دون كتابة جديدة', () async {
      await service.signIn(email: 'owner@school.local', password: 'ownerpass1');
      await service.changePassword(newPassword: 'AnotherPass9');
      expect(gateway.lastPasswordSet, 'AnotherPass9');
      expect(await env.db.select(env.db.outbox).get(), isEmpty);
    });
  });

  group('تحديث الجلسة بعد المزامنة', () {
    test('تغيّر صلاحيات العامل يصل إلى الجلسة ويُبث', () async {
      await service.signIn(email: 'w@school.local', password: 'workerpass');
      final events = <AuthSession?>[];
      final subscription = service.changes.listen(events.add);

      await env.db.customStatement(
        '''UPDATE workers SET permissions = '{"payments":["add"]}' WHERE id = 'w1' ''',
      );
      final updated = await service.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(
        updated!.can(PermissionModule.payments, PermissionAction.add),
        isTrue,
      );
      expect(
        updated.can(PermissionModule.students, PermissionAction.view),
        isFalse,
      );
      expect(events, hasLength(1));

      // لا تغيير: لا بث جديد.
      await service.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      await subscription.cancel();
    });

    test('بلا جلسة يعيد null', () async {
      expect(await service.refresh(), isNull);
    });
  });

  group('RemoteAccountDirectory', () {
    test('يقرأ الحساب وصلاحيات العامل من الخادم', () async {
      final calls = <String>[];
      final directory = RemoteAccountDirectory((table, column, value) async {
        calls.add('$table.$column=$value');
        if (table == 'user_accounts') {
          return [
            {
              'id': 'u-worker',
              'email': 'w@school.local',
              'role': 'worker',
              'entity_id': 'w1',
              'display_name': 'عامل',
              'must_change_password': true,
            },
          ];
        }
        return [
          {'id': 'w1', 'permissions': '{"groups":["view"]}'},
        ];
      });
      final record = await directory.find('u-worker');
      expect(record!.role, UserRole.worker);
      expect(record.mustChangePassword, isTrue);
      expect(
        record.permissions.can(PermissionModule.groups, PermissionAction.view),
        isTrue,
      );
      expect(calls, ['user_accounts.id=u-worker', 'workers.id=w1']);
    });

    test('حساب غير موجود أو بدور مجهول يعيد null', () async {
      expect(
        await RemoteAccountDirectory((_, _, _) async => []).find('x'),
        isNull,
      );
      final unknownRole = RemoteAccountDirectory(
        (_, _, _) async => [
          {'id': 'x', 'email': 'a@b.com', 'role': 'superuser'},
        ],
      );
      expect(await unknownRole.find('x'), isNull);
    });

    test('أول دخول على جهاز فارغ يعتمد على الخادم', () async {
      final fresh = TestEnv();
      addTearDown(fresh.close);
      final remote = RemoteAccountDirectory((table, column, value) async {
        if (table == 'user_accounts') {
          return [
            {
              'id': 'u-owner',
              'email': 'owner@school.local',
              'role': 'owner',
              'entity_id': null,
              'display_name': 'المدير',
              'must_change_password': false,
            },
          ];
        }
        return [];
      });
      final auth = AuthService(
        gateway: gateway,
        store: DatabaseSessionStore(fresh.db),
        directories: [LocalAccountDirectory(fresh.db), remote],
        writer: () => fresh.writer,
      );
      final session = await auth.signIn(
        email: 'owner@school.local',
        password: 'ownerpass1',
      );
      expect(session.role, UserRole.owner);
      expect(session.displayName, 'المدير');
      await auth.dispose();
    });
  });

  test('صاحب العملية في السجل هو المستخدم المسجَّل', () async {
    final session = await service.signIn(
      email: 'w@school.local',
      password: 'workerpass',
    );
    expect(session.actor.userId, 'u-worker');
    expect(session.actor.userName, 'عامل الاستقبال');
    final teacher = await build().signIn(
      email: 't@school.local',
      password: 'teacherpass',
    );
    expect(teacher.actor.userName, 't@school.local');
  });
}
