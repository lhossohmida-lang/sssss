import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

AppPage page(String path, {PermissionModule? requires}) => AppPage(
  path: path,
  requires: requires,
  builder: (_, _) => const SizedBox(),
);

void main() {
  group('AppPage.matches', () {
    test('مسار ثابت', () {
      expect(page('/settings').matches('/settings'), isTrue);
      expect(page('/settings').matches('/settings/x'), isFalse);
      expect(page('/settings').matches('/setting'), isFalse);
    });

    test('معاملات المسار والاستعلام', () {
      final p = page('/students/:id');
      expect(p.matches('/students/42'), isTrue);
      expect(p.matches('/students/42?tab=1'), isTrue);
      expect(p.matches('/students'), isFalse);
      expect(p.matches('/groups/42'), isFalse);
      expect(page('/students/:id/edit').matches('/students/7/edit'), isTrue);
    });
  });

  group('AppPage.visibleTo', () {
    final worker = AccessPolicy(
      role: UserRole.worker,
      permissions: WorkerPermissions.none.withAction(
        PermissionModule.settings,
        PermissionAction.view,
        allowed: true,
      ),
    );
    const owner = AccessPolicy(role: UserRole.owner);
    const teacher = AccessPolicy(role: UserRole.teacher);

    test('بلا شرط: لكل مستخدم', () {
      expect(page('/x').visibleTo(teacher), isTrue);
    });

    test('بشرط وحدة: حسب الصلاحية', () {
      final p = page('/settings', requires: PermissionModule.settings);
      expect(p.visibleTo(owner), isTrue);
      expect(p.visibleTo(worker), isTrue);
      expect(p.visibleTo(teacher), isFalse);
      expect(
        page(
          '/payments',
          requires: PermissionModule.payments,
        ).visibleTo(worker),
        isFalse,
      );
    });

    test('ownerOnly لا يتجاوزه عامل حتى لو كانت لديه صلاحية الوحدة', () {
      final drive = AppPage(
        path: '/drive',
        builder: (_, _) => const SizedBox(),
        requires: PermissionModule.settings,
        ownerOnly: true,
      );
      expect(drive.visibleTo(worker), isFalse);
      expect(drive.visibleTo(owner), isTrue);
    });
  });

  group('AppPage بفعل محدد', () {
    test('صلاحية العرض لا تكفي لصفحة تشترط الإضافة', () {
      final page = AppPage(
        path: '/students/new',
        requires: PermissionModule.students,
        action: PermissionAction.add,
        builder: (_, _) => const SizedBox(),
      );
      AccessPolicy worker(PermissionAction action) => AccessPolicy(
        role: UserRole.worker,
        permissions: WorkerPermissions.none.withAction(
          PermissionModule.students,
          action,
          allowed: true,
        ),
      );
      expect(page.visibleTo(worker(PermissionAction.view)), isFalse);
      expect(page.visibleTo(worker(PermissionAction.add)), isTrue);
      expect(page.visibleTo(const AccessPolicy(role: UserRole.owner)), isTrue);
    });
  });

  group('AppTab.visibleTo', () {
    AppTab tab({PermissionModule? requires, Set<UserRole>? roles}) => AppTab(
      path: '/t',
      destination: const ClayDestination(label: 'ت', icon: ClayIcons.home),
      builder: (_) => const SizedBox(),
      requires: requires,
      roles: roles,
    );

    test('الأدوار والصلاحيات', () {
      const owner = AccessPolicy(role: UserRole.owner);
      const teacher = AccessPolicy(role: UserRole.teacher);
      expect(tab().visibleTo(teacher), isTrue);
      expect(tab(roles: {UserRole.owner}).visibleTo(teacher), isFalse);
      expect(tab(roles: {UserRole.owner}).visibleTo(owner), isTrue);
      expect(
        tab(requires: PermissionModule.students).visibleTo(teacher),
        isFalse,
      );
      expect(tab(requires: PermissionModule.students).visibleTo(owner), isTrue);
    });
  });
}
