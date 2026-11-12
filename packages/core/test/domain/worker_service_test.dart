import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late FakeAccountProvisioner provisioner;
  late AccountService accounts;
  late WorkerService service;

  final weekdays = WorkerSchedule.fromJson(
    '{"6":"full","7":"full","1":"half"}',
  );

  setUp(() {
    env = TestEnv();
    provisioner = FakeAccountProvisioner();
    accounts = AccountService(env.db, env.writer, provisioner);
    service = WorkerService(env.db, env.writer, accounts);
  });
  tearDown(() => env.close());

  Future<WorkerCreated> addDefault({String phone = '0660123456'}) =>
      service.add(
        name: 'سمير',
        phone: phone,
        fullDayWage: 1500,
        halfDayWage: 800,
        schedule: weekdays,
      );

  group('إضافة', () {
    test('عامل بحسابه ورمزه وأجرَيه وبرنامجه وصلاحياته الفارغة', () async {
      final created = await addDefault();
      final worker = created.worker;
      expect(worker.name, 'سمير');
      expect(worker.phone, '0660123456');
      expect(worker.email, '0660123456@school.local');
      expect(worker.qrCode, startsWith('W-'));
      expect(worker.fullDayWage, 1500);
      expect(worker.halfDayWage, 800);
      expect(worker.expectedStartMinutes, 480);
      expect(worker.expectedEndMinutes, 1020);
      expect(worker.authUserId, created.account.accountId);
      expect(
        WorkerSchedule.fromJson(worker.weeklySchedule).kindOn(6),
        WorkDayKind.full,
      );
      expect(
        WorkerSchedule.fromJson(worker.weeklySchedule).kindOn(1),
        WorkDayKind.half,
      );
      expect(
        WorkerSchedule.fromJson(worker.weeklySchedule).kindOn(3),
        WorkDayKind.off,
      );
      expect(WorkerPermissions.decode(worker.permissions).isEmpty, isTrue);
    });

    test('الحساب بدور عامل مع كلمة سر مؤقتة ورسالة بياناته', () async {
      final created = await addDefault();
      expect(
        provisioner.created[created.account.accountId]?.role,
        UserRole.worker,
      );
      expect(created.account.password.length, 8);
      final account = await (env.db.select(
        env.db.userAccounts,
      )..where((a) => a.id.equals(created.account.accountId))).getSingle();
      expect(account.role, 'worker');
      expect(account.entityId, created.worker.id);
      expect(account.displayName, 'سمير');
      expect(await env.db.select(env.db.smsQueue).get(), hasLength(1));
    });

    test('بصلاحيات أولية', () async {
      final perms = const WorkerPermissions({})
          .withModule(PermissionModule.scanner, allowed: true);
      final created = await service.add(
        name: 'نور',
        phone: '0770123456',
        fullDayWage: 1000,
        halfDayWage: 500,
        schedule: weekdays,
        permissions: perms,
      );
      expect(
        WorkerPermissions.decode(created.worker.permissions)
            .can(PermissionModule.scanner, PermissionAction.use),
        isTrue,
      );
    });

    test('بيانات ناقصة أو غير صالحة: أخطاء بالحقول ولا شيء يُكتب', () async {
      await expectLater(
        service.add(
          name: ' ',
          phone: '123',
          fullDayWage: -10,
          halfDayWage: 15,
          schedule: const WorkerSchedule({}),
          startMinutes: 600,
          endMinutes: 600,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys.toSet(),
            'حقول',
            containsAll([
              WorkerService.fieldName,
              WorkerService.fieldPhone,
              WorkerService.fieldFullWage,
              WorkerService.fieldHours,
              WorkerService.fieldSchedule,
            ]),
          ),
        ),
      );
      expect(await env.db.select(env.db.workers).get(), isEmpty);
      expect(provisioner.created, isEmpty);
    });

    test('أجر النصف لا يزيد عن الكامل ويكون من مضاعفات 10', () {
      final errors = WorkerService.validate(
        name: 'س',
        fullDayWage: 1000,
        halfDayWage: 1500,
        startMinutes: 480,
        endMinutes: 1020,
        schedule: weekdays,
      );
      expect(errors[WorkerService.fieldHalfWage], contains('لا يزيد'));
      final odd = WorkerService.validate(
        name: 'س',
        fullDayWage: 1005,
        halfDayWage: 500,
        startMinutes: 480,
        endMinutes: 1020,
        schedule: weekdays,
      );
      expect(odd[WorkerService.fieldFullWage], contains('10'));
      expect(
        WorkerService.validate(
          name: 'س',
          fullDayWage: 1000,
          halfDayWage: 500,
          startMinutes: 480,
          endMinutes: 1020,
          schedule: weekdays,
        ),
        isEmpty,
      );
    });

    test('هاتف مستعمل في حساب آخر مرفوض', () async {
      await addDefault();
      await expectLater(
        addDefault(),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors[WorkerService.fieldPhone],
            'phone',
            contains('مستعمل'),
          ),
        ),
      );
      expect(await env.db.select(env.db.workers).get(), hasLength(1));
    });
  });

  group('قراءة وتعديل', () {
    test('القائمة مرتبة بالاسم بأيام العمل وصلاحياتها', () async {
      await service.add(
        name: 'ياسين',
        phone: '0660000002',
        fullDayWage: 1000,
        halfDayWage: 500,
        schedule: weekdays,
      );
      await service.add(
        name: 'أمين',
        phone: '0660000001',
        fullDayWage: 1000,
        halfDayWage: 500,
        schedule: WorkerSchedule.fromJson('{"6":"full"}'),
      );
      final items = await service.watchAll().first;
      expect(items.map((i) => i.name), ['أمين', 'ياسين']);
      expect(items.first.workDays, 1);
      expect(items.last.workDays, 3);
    });

    test('التعديل: الاسم والأجران والبرنامج والساعات واسم الحساب', () async {
      final created = await addDefault();
      final changed = await service.update(
        created.worker.id,
        name: 'سمير بن علي',
        phone: '0661111111',
        fullDayWage: 2000,
        halfDayWage: 1000,
        schedule: WorkerSchedule.fromJson('{"2":"full"}'),
        startMinutes: 540,
        endMinutes: 1080,
      );
      expect(changed, isTrue);
      final row = await (env.db.select(
        env.db.workers,
      )..where((w) => w.id.equals(created.worker.id))).getSingle();
      expect(row.name, 'سمير بن علي');
      expect(row.phone, '0661111111');
      expect(row.email, '0660123456@school.local', reason: 'بريد الدخول ثابت');
      expect(row.fullDayWage, 2000);
      expect(row.halfDayWage, 1000);
      expect(row.expectedStartMinutes, 540);
      expect(row.expectedEndMinutes, 1080);
      expect(
        WorkerSchedule.fromJson(row.weeklySchedule).kindOn(2),
        WorkDayKind.full,
      );
      final account = await (env.db.select(
        env.db.userAccounts,
      )..where((a) => a.id.equals(created.account.accountId))).getSingle();
      expect(account.displayName, 'سمير بن علي');
    });

    test('تعديل بيانات غير صالحة أو عامل مجهول', () async {
      final created = await addDefault();
      await expectLater(
        service.update(
          created.worker.id,
          name: '',
          phone: '0661111111',
          fullDayWage: 1000,
          halfDayWage: 500,
          schedule: weekdays,
          startMinutes: 480,
          endMinutes: 1020,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        await service.update(
          'nope',
          name: 'س',
          phone: '0661111111',
          fullDayWage: 1000,
          halfDayWage: 500,
          schedule: weekdays,
          startMinutes: 480,
          endMinutes: 1020,
        ),
        isFalse,
      );
    });
  });

  group('الصلاحيات والحذف', () {
    test(
      'ضبط الصلاحيات يُخزَّن بنفس صيغة الخادم ويُسجَّل في العمليات',
      () async {
        final created = await addDefault();
        final perms = const WorkerPermissions({})
            .withAction(
              PermissionModule.students,
              PermissionAction.view,
              allowed: true,
            )
            .withAction(
              PermissionModule.students,
              PermissionAction.add,
              allowed: true,
            )
            .withModule(PermissionModule.scanner, allowed: true);
        expect(await service.setPermissions(created.worker.id, perms), isTrue);
        final row = await (env.db.select(
          env.db.workers,
        )..where((w) => w.id.equals(created.worker.id))).getSingle();
        expect(
          row.permissions,
          '{"students":["view","add"],"scanner":["use"]}',
        );
        final audit = await env.db.select(env.db.auditLog).get();
        expect(audit.where((a) => a.action == 'set_permissions'), hasLength(1));
        expect(await service.setPermissions('nope', perms), isFalse);
      },
    );

    test('الصلاحيات تظهر في جلسة العامل عبر دليل الحسابات', () async {
      final created = await addDefault();
      await service.setPermissions(
        created.worker.id,
        const WorkerPermissions({})
            .withModule(PermissionModule.scanner, allowed: true),
      );
      final record = await LocalAccountDirectory(env.db)
          .find(created.account.accountId);
      expect(
        record!.permissions.can(PermissionModule.scanner, PermissionAction.use),
        isTrue,
      );
    });

    test('الحذف ناعم ويعطّل الحساب، ويحتفظ بالسجل', () async {
      final created = await addDefault();
      expect(await service.remove(created.worker.id), isTrue);
      expect(await service.remove(created.worker.id), isFalse);
      expect(await service.watchAll().first, isEmpty);
      final row = await (env.db.select(
        env.db.workers,
      )..where((w) => w.id.equals(created.worker.id))).getSingle();
      expect(row.deletedAt, isNotNull);
      final account = await (env.db.select(
        env.db.userAccounts,
      )..where((a) => a.id.equals(created.account.accountId))).getSingle();
      expect(account.deletedAt, isNotNull, reason: 'الحساب معطَّل');
    });

    test('إعادة كلمة السر ترسلها، وعامل بلا حساب مرفوض', () async {
      final created = await addDefault();
      final reset = await service.resetPassword(created.worker.id);
      expect(reset.password.length, 8);
      await expectLater(
        service.resetPassword('nope'),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
