import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';

import '../support/fake_remote.dart';
import '../support/fixtures.dart';

/// منسّق مزامنة يسجّل بدايته وإيقافه.
class RecordingCoordinator extends SyncCoordinator {
  RecordingCoordinator(AppDatabase db, this.log, this.accountId)
    : super(
        db,
        SyncEngine(db, FakeRemote(), tables: const []),
        interval: const Duration(hours: 1),
      );

  final List<String> log;
  final String accountId;

  @override
  void start() {
    log.add('start:$accountId');
    super.start();
  }

  @override
  Future<void> stop() {
    log.add('stop:$accountId');
    return super.stop();
  }
}

void main() {
  late TestEnv env;
  late FakeAuthGateway gateway;

  Future<void> account(String id, String email, UserRole role) => env.db
      .into(env.db.userAccounts)
      .insert(
        UserAccountsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          email: email,
          role: role.code,
          mustChangePassword: const Value(false),
        ),
      );

  setUp(() async {
    env = TestEnv();
    gateway = FakeAuthGateway({
      'a@school.local': (id: 'u-a', password: 'password-a'),
      'b@school.local': (id: 'u-b', password: 'password-b'),
    });
    await account('u-a', 'a@school.local', UserRole.owner);
    await account('u-b', 'b@school.local', UserRole.teacher);
  });

  tearDown(() => env.close());

  group('AppRuntime', () {
    test('إعدادات الخادم غائبة: تطبيق الإدارة بالوضع المحلي', () async {
      final runtime = await AppRuntime.start(
        app: AppIdentity.admin,
        database: env.db,
      );
      expect(runtime.isLocalMode, isTrue);
      expect(runtime.sync, isNull);
      expect(runtime.auth.current, isNull);
      // لا نغلق env.db هنا: يُغلق في tearDown.
      await runtime.auth.dispose();
    });

    test('إعدادات الخادم غائبة: الأستاذ والوليّ لا يدخلان', () async {
      for (final app in [AppIdentity.teacher, AppIdentity.student]) {
        final runtime = await AppRuntime.start(app: app, database: env.db);
        expect(runtime.isLocalMode, isFalse);
        await expectLater(
          runtime.auth.signIn(email: 'a@school.local', password: 'x-password'),
          throwsA(
            isA<AuthFailureException>().having(
              (e) => e.message,
              'message',
              UnconfiguredAuthGateway.message,
            ),
          ),
        );
        await runtime.auth.dispose();
      }
    });

    test('يستعيد الجلسة المحفوظة عند التشغيل', () async {
      gateway.restoreIdentity(
        const AuthIdentity(id: 'u-a', email: 'a@school.local'),
      );
      await DatabaseSessionStore(env.db).write(
        AuthSession(
          const AccountRecord(
            id: 'u-a',
            email: 'a@school.local',
            role: UserRole.owner,
            mustChangePassword: false,
          ),
        ),
      );
      final runtime = await AppRuntime.start(
        app: AppIdentity.admin,
        database: env.db,
        gateway: gateway,
      );
      expect(runtime.auth.current?.accountId, 'u-a');
      expect(runtime.auth.isReady, isTrue);
      await runtime.auth.dispose();
    });

    test('الكتابة تُنسب إلى المستخدم المسجَّل وتُرفض قبل الدخول', () async {
      final runtime = await AppRuntime.start(
        app: AppIdentity.admin,
        database: env.db,
        gateway: gateway,
      );
      Future<void> save() => runtime.writer.save(
        env.db.rooms,
        RoomsCompanion.insert(
          id: 'r1',
          createdAt: 0,
          updatedAt: 0,
          name: 'قاعة',
        ),
        key: {'id': 'r1'},
      );
      await expectLater(save(), throwsA(isA<StateError>()));
      await runtime.auth.signIn(
        email: 'a@school.local',
        password: 'password-a',
      );
      await save();
      final audit = await env.db.select(env.db.auditLog).get();
      expect(audit.single.userId, 'u-a');
      await runtime.auth.dispose();
    });

    test('المزامنة تبدأ بعد الدخول وتتوقف عند الخروج', () async {
      final log = <String>[];
      final runtime = await AppRuntime.start(
        app: AppIdentity.admin,
        database: env.db,
        gateway: gateway,
        syncFactory: (session) =>
            RecordingCoordinator(env.db, log, session.accountId),
      );
      expect(runtime.sync, isNull);
      await runtime.auth.signIn(
        email: 'a@school.local',
        password: 'password-a',
      );
      await Future<void>.delayed(Duration.zero);
      expect(log, ['start:u-a']);
      expect(runtime.sync, isNotNull);
      await runtime.auth.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(log, ['start:u-a', 'stop:u-a']);
      expect(runtime.sync, isNull);
      await runtime.auth.dispose();
    });
  });

  group('DefaultsSeeder', () {
    Future<int> levelCount(AppDatabase db) async =>
        (await db.select(db.levels).get()).length;

    Future<void> until(Future<bool> Function() condition) async {
      for (var i = 0; i < 200; i++) {
        if (await condition()) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        await condition(),
        isTrue,
        reason: 'لم يتحقق الشرط في الوقت المحدد',
      );
    }

    test('الوضع المحلي: المستويات تُضاف فور دخول صاحب المدرسة', () async {
      final runtime = await startTestRuntime(localMode: true);
      addTearDown(runtime.auth.dispose);
      expect(await levelCount(runtime.db), 0);
      await runtime.localGateway!.createFirstOwner(
        email: 'owner@school.com',
        displayName: 'المدير',
        password: 'owner-pass-1',
      );
      await runtime.auth.signIn(
        email: 'owner@school.com',
        password: 'owner-pass-1',
      );
      await until(() async => await levelCount(runtime.db) == 12);
    });

    test('مع الخادم: لا إضافة قبل أول مزامنة ناجحة ثم تُضاف', () async {
      final remote = FakeRemote()..offline = true;
      late SyncCoordinator coordinator;
      final runtime = await startTestRuntime(
        gateway: gateway,
        syncFactory: (session) => coordinator = SyncCoordinator(
          env.db,
          SyncEngine(env.db, remote, tables: SyncProfile.forRole(session.role)),
          debounce: const Duration(milliseconds: 5),
          interval: const Duration(hours: 1),
        ),
        database: env.db,
      );
      addTearDown(runtime.dispose);
      await runtime.auth.signIn(
        email: 'a@school.local',
        password: 'password-a',
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(await levelCount(env.db), 0, reason: 'الخادم غير متاح بعد');
      remote.offline = false;
      await coordinator.syncNow();
      await until(() async => await levelCount(env.db) == 12);
    });

    test('غير صاحب المدرسة لا تُضاف له مستويات', () async {
      final runtime = await startTestRuntime(
        accounts: const [
          TestAccount(
            id: 'u-w',
            email: 'w@school.local',
            password: 'password-w',
            role: UserRole.worker,
            entityId: 'w1',
          ),
        ],
        database: env.db,
      );
      addTearDown(runtime.auth.dispose);
      await runtime.auth.signIn(
        email: 'w@school.local',
        password: 'password-w',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await levelCount(env.db), 0);
    });
  });

  group('SyncLifecycle', () {
    late AuthService auth;
    late List<String> log;
    late SyncLifecycle lifecycle;

    setUp(() async {
      log = [];
      auth = AuthService(
        gateway: gateway,
        store: DatabaseSessionStore(env.db),
        directories: [LocalAccountDirectory(env.db)],
        writer: () => env.writer,
      );
      lifecycle = SyncLifecycle(
        auth,
        (s) => RecordingCoordinator(env.db, log, s.accountId),
      );
    });

    tearDown(() async {
      await lifecycle.dispose();
      await auth.dispose();
    });

    test('تغيّر الصلاحيات أو الاسم لا يعيد المزامنة', () async {
      await auth.signIn(email: 'a@school.local', password: 'password-a');
      await env.db.customStatement(
        "UPDATE user_accounts SET display_name = 'جديد' WHERE id = 'u-a'",
      );
      await auth.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(log, ['start:u-a']);
    });

    test('تبديل الحساب يوقف مزامنة الأول ويبدأ الثاني', () async {
      await auth.signIn(email: 'a@school.local', password: 'password-a');
      await auth.signIn(email: 'b@school.local', password: 'password-b');
      await Future<void>.delayed(Duration.zero);
      expect(log, ['start:u-a', 'stop:u-a', 'start:u-b']);
    });

    test('dispose يوقف المنسّق الحالي', () async {
      await auth.signIn(email: 'a@school.local', password: 'password-a');
      await Future<void>.delayed(Duration.zero);
      await lifecycle.dispose();
      expect(log, ['start:u-a', 'stop:u-a']);
      expect(lifecycle.coordinator, isNull);
    });
  });
}
