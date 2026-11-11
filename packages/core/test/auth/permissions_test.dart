import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

void main() {
  group('WorkerPermissions', () {
    test('الافتراضي بلا صلاحيات', () {
      expect(WorkerPermissions.none.isEmpty, isTrue);
      expect(WorkerPermissions.none.encode(), '{}');
      expect(
        WorkerPermissions.none.can(
          PermissionModule.students,
          PermissionAction.view,
        ),
        isFalse,
      );
    });

    test('الترميز والفك دورة كاملة وبترتيب ثابت', () {
      final permissions = WorkerPermissions.none
          .withAction(
            PermissionModule.payments,
            PermissionAction.edit,
            allowed: true,
          )
          .withAction(
            PermissionModule.students,
            PermissionAction.add,
            allowed: true,
          )
          .withAction(
            PermissionModule.students,
            PermissionAction.view,
            allowed: true,
          )
          .withAction(
            PermissionModule.scanner,
            PermissionAction.use,
            allowed: true,
          );
      const expected =
          '{"students":["view","add"],"payments":["edit"],"scanner":["use"]}';
      expect(permissions.encode(), expected);
      expect(WorkerPermissions.decode(expected), permissions);
      expect(WorkerPermissions.decode(expected).encode(), expected);
    });

    test('تعطيل آخر فعل يحذف الوحدة', () {
      final on = WorkerPermissions.none.withAction(
        PermissionModule.rooms,
        PermissionAction.view,
        allowed: true,
      );
      final off = on.withAction(
        PermissionModule.rooms,
        PermissionAction.view,
        allowed: false,
      );
      expect(off.isEmpty, isTrue);
      expect(off.encode(), '{}');
      expect(off, WorkerPermissions.none);
    });

    test('withModule يفعّل كل أفعال الوحدة أو يعطّلها', () {
      final all = WorkerPermissions.none.withModule(
        PermissionModule.students,
        allowed: true,
      );
      expect(all.actionsOf(PermissionModule.students), [
        PermissionAction.view,
        PermissionAction.add,
        PermissionAction.edit,
        PermissionAction.delete,
      ]);
      final none = all.withModule(PermissionModule.students, allowed: false);
      expect(none.isEmpty, isTrue);
    });

    test('فعل لا يخص الوحدة يُرفض', () {
      expect(
        () => WorkerPermissions.none.withAction(
          PermissionModule.audit,
          PermissionAction.delete,
          allowed: true,
        ),
        throwsArgumentError,
      );
    });

    test('الحقل التالف أو الفارغ يعني بلا صلاحيات ولا يرمي', () {
      for (final bad in [null, '', '   ', 'not json', '[]', '"x"', '{"a":1}']) {
        expect(
          WorkerPermissions.decode(bad),
          WorkerPermissions.none,
          reason: '$bad',
        );
      }
    });

    test('الوحدات والأفعال المجهولة تُتجاهل والباقي يُقرأ', () {
      final permissions = WorkerPermissions.decode(
        '{"students":["view","fly","add"],"ghost":["view"],'
        '"audit":["view","delete"],"rooms":"view","payments":[1,"edit"]}',
      );
      expect(
        permissions.encode(),
        '{"students":["view","add"],"payments":["edit"],"audit":["view"]}',
      );
    });

    test('المساواة لا تتأثر بترتيب المفاتيح في JSON', () {
      expect(
        WorkerPermissions.decode('{"rooms":["view"],"students":["add"]}'),
        WorkerPermissions.decode('{"students":["add"],"rooms":["view"]}'),
      );
      expect(
        WorkerPermissions.decode('{"rooms":["view"]}'),
        isNot(WorkerPermissions.decode('{"rooms":["edit"]}')),
      );
    });

    test('كل رموز الوحدات والأفعال فريدة وتُقرأ من رمزها', () {
      final modules = PermissionModule.values.map((m) => m.code).toSet();
      expect(modules.length, PermissionModule.values.length);
      for (final module in PermissionModule.values) {
        expect(PermissionModule.fromCode(module.code), module);
        expect(module.actions, isNotEmpty);
      }
      for (final action in PermissionAction.values) {
        expect(PermissionAction.fromCode(action.code), action);
      }
      expect(() => PermissionModule.fromCode('x'), throwsArgumentError);
      expect(() => PermissionAction.fromCode('x'), throwsArgumentError);
    });

    test('رموز الصلاحيات التي يفحصها الخادم كلها موجودة', () {
      // مأخوذة من app.can(...) في supabase/migrations/0002_rls.sql.
      const used = {
        'attendance': ['add', 'edit', 'view'],
        'audit': ['view'],
        'chat': ['delete', 'edit', 'view'],
        'groups': ['add', 'edit', 'view'],
        'payments': ['add', 'delete', 'edit', 'view'],
        'receive_money': ['use'],
        'requests': ['edit', 'view'],
        'scanner': ['use'],
        'sms': ['edit', 'use', 'view'],
        'students': ['add', 'edit', 'view'],
        'teachers': ['add', 'edit', 'view'],
        'workers': ['edit', 'view'],
      };
      used.forEach((module, actions) {
        final parsed = PermissionModule.tryFromCode(module);
        expect(parsed, isNotNull, reason: module);
        for (final action in actions) {
          expect(
            parsed!.actions.map((a) => a.code),
            contains(action),
            reason: '$module/$action',
          );
        }
      });
    });
  });

  group('AccessPolicy', () {
    final worker = WorkerPermissions.none.withAction(
      PermissionModule.payments,
      PermissionAction.view,
      allowed: true,
    );

    test('صاحب المدرسة يملك كل شيء', () {
      const policy = AccessPolicy(role: UserRole.owner);
      for (final module in PermissionModule.values) {
        for (final action in module.actions) {
          expect(policy.can(module, action), isTrue);
        }
      }
      expect(policy.isOwner, isTrue);
      expect(policy.isStaff, isTrue);
    });

    test('العامل حسب صلاحياته فقط', () {
      final policy = AccessPolicy(role: UserRole.worker, permissions: worker);
      expect(
        policy.can(PermissionModule.payments, PermissionAction.view),
        isTrue,
      );
      expect(
        policy.can(PermissionModule.payments, PermissionAction.edit),
        isFalse,
      );
      expect(
        policy.can(PermissionModule.students, PermissionAction.view),
        isFalse,
      );
      expect(policy.canAnyOf(PermissionModule.payments), isTrue);
      expect(policy.canAnyOf(PermissionModule.students), isFalse);
      expect(policy.isOwner, isFalse);
      expect(policy.isStaff, isTrue);
    });

    test('الأستاذ والوليّ بلا صلاحيات إدارية حتى لو حُمّلت عليهما', () {
      for (final role in [UserRole.teacher, UserRole.parent]) {
        final policy = AccessPolicy(role: role, permissions: worker);
        expect(
          policy.can(PermissionModule.payments, PermissionAction.view),
          isFalse,
        );
        expect(policy.isStaff, isFalse);
      }
    });

    test('كل دور يدخل من تطبيقه فقط', () {
      bool allows(UserRole role, AppIdentity app) =>
          AccessPolicy(role: role).allowsApp(app);
      expect(allows(UserRole.owner, AppIdentity.admin), isTrue);
      expect(allows(UserRole.worker, AppIdentity.admin), isTrue);
      expect(allows(UserRole.teacher, AppIdentity.admin), isFalse);
      expect(allows(UserRole.teacher, AppIdentity.teacher), isTrue);
      expect(allows(UserRole.parent, AppIdentity.student), isTrue);
      expect(allows(UserRole.parent, AppIdentity.teacher), isFalse);
      expect(allows(UserRole.owner, AppIdentity.student), isFalse);
    });
  });
}
