import 'package:admin/admin_tabs.dart';
import 'package:admin/screens/more_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

AccessPolicy worker(WorkerPermissions permissions) =>
    AccessPolicy(role: UserRole.worker, permissions: permissions);

/// صلاحية واحدة على وحدة: الفعل المشترط أو «العرض» أو أول فعل للوحدة.
PermissionAction neededOf(AppPage page) =>
    page.anyActions?.first ??
    page.action ??
    (page.requires!.actions.contains(PermissionAction.view)
        ? PermissionAction.view
        : page.requires!.actions.first);

/// مسار نموذجي للصفحة بمعرّف وهمي.
String sample(AppPage page) => page.path.replaceAll(':id', 'abc');

void main() {
  const owner = AccessPolicy(role: UserRole.owner);
  const teacher = AccessPolicy(role: UserRole.teacher);
  const parent = AccessPolicy(role: UserRole.parent);
  final nobody = worker(WorkerPermissions.none);

  group('صفحات الإدارة', () {
    test('لا صفحة بلا شرط صلاحية', () {
      for (final page in adminPages) {
        expect(page.requires, isNotNull, reason: page.path);
      }
    });

    test('المسارات فريدة', () {
      final paths = adminPages.map((p) => p.path).toList();
      expect(paths.toSet(), hasLength(paths.length));
    });

    test('لا مسار ثابت تحجبه صفحة بمعامل قبله', () {
      for (var i = 0; i < adminPages.length; i++) {
        final page = adminPages[i];
        if (page.path.contains(':')) continue;
        final first = adminPages.firstWhere((p) => p.matches(page.path));
        expect(
          first.path,
          page.path,
          reason: '${page.path} يحجبه ${first.path}',
        );
      }
    });

    for (final page in adminPages) {
      test('${page.path}: المالك أو من فعّل كل صلاحياتها', () {
        final module = page.requires!;
        final action = neededOf(page);
        var permissions = WorkerPermissions.none.withAction(
          module,
          action,
          allowed: true,
        );
        for (final requirement in page.requiredPermissions.entries) {
          permissions = permissions.withAction(
            requirement.key,
            requirement.value,
            allowed: true,
          );
        }
        final granted = worker(permissions);
        final other = PermissionModule.values.firstWhere((m) => m != module);
        final foreign = worker(
          WorkerPermissions.none.withModule(other, allowed: true),
        );

        expect(page.visibleTo(owner), isTrue, reason: 'المالك');
        if (page.ownerOnly) {
          expect(page.visibleTo(granted), isFalse, reason: 'المالك فقط');
        } else {
          expect(page.visibleTo(granted), isTrue, reason: 'عامل بصلاحيتها');
          expect(page.visibleTo(nobody), isFalse, reason: 'عامل بلا صلاحيات');
          expect(page.visibleTo(foreign), isFalse, reason: 'صلاحية وحدة أخرى');
          expect(page.visibleTo(teacher), isFalse, reason: 'الأستاذ');
          expect(page.visibleTo(parent), isFalse, reason: 'الوليّ');
        }
      });
    }

    test('صفحات الإضافة والتعديل لا يكفي لها العرض فقط', () {
      var checked = 0;
      for (final page in adminPages) {
        final action = page.action;
        if (action == null || action == PermissionAction.view) continue;
        if (!page.requires!.actions.contains(PermissionAction.view)) continue;
        final viewOnly = worker(
          WorkerPermissions.none.withAction(
            page.requires!,
            PermissionAction.view,
            allowed: true,
          ),
        );
        expect(
          page.visibleTo(viewOnly),
          isFalse,
          reason: '${page.path} تشترط ${action.code}',
        );
        checked++;
      }
      expect(checked, greaterThan(0));
    });
  });

  group('تبويبات الإدارة وقائمة المزيد', () {
    test('تبويب بشرط يختفي عن عامل بلا صلاحيات ويظهر بها', () {
      for (final tab in adminTabs) {
        final module = tab.requires;
        if (module == null) {
          expect(tab.visibleTo(nobody), isTrue, reason: tab.path);
          continue;
        }
        expect(tab.visibleTo(nobody), isFalse, reason: tab.path);
        expect(
          tab.visibleTo(
            worker(WorkerPermissions.none.withModule(module, allowed: true)),
          ),
          isTrue,
          reason: tab.path,
        );
        expect(tab.visibleTo(owner), isTrue, reason: tab.path);
      }
    });

    test('كل قسم في «المزيد» له صفحة بالشرط نفسه', () {
      for (final entry in moreEntries) {
        final page = adminPages.where((p) => p.path == entry.path).firstOrNull;
        expect(page, isNotNull, reason: '${entry.label} بلا صفحة');
        expect(entry.requires, isNotNull, reason: entry.label);
        expect(page!.requires, entry.requires, reason: entry.label);
        expect(page.ownerOnly, entry.ownerOnly, reason: entry.label);
        expect(
          page.requiredPermissions,
          entry.requiredPermissions,
          reason: entry.label,
        );
      }
    });

    test('أقسام «المزيد» بلا تكرار في المسار', () {
      final paths = moreEntries.map((e) => e.path).toList();
      expect(paths.toSet(), hasLength(paths.length));
    });

    test('Google Drive لا يظهر لعامل حتى إن فُعّلت له الإعدادات', () {
      final drive = moreEntries.singleWhere((entry) => entry.path == '/drive');
      expect(drive.ownerOnly, isTrue);
      expect(drive.requires, PermissionModule.settings);
    });
  });

  group('التنقل الفعلي', () {
    const reader = TestAccount(
      id: 'u-reader',
      email: 'reader@school.local',
      password: 'reader-pass-1',
      role: UserRole.worker,
      entityId: 'w1',
      displayName: 'عامل',
      permissions: '{"students":["view"]}',
    );

    appTest('عامل بصلاحية التلاميذ لا يبلغ المالية برابط مباشر', (
      tester,
    ) async {
      await bootApp(
        tester,
        adminTabs,
        app: AppIdentity.admin,
        accounts: const [reader],
        pages: adminPages,
      );
      await loginWith(tester, reader.email, reader.password);
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      for (final path in [
        '/payments/new',
        '/payouts',
        '/workers',
        '/dues',
        '/settings',
        '/scanner',
        '/attendance',
      ]) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(
          GoRouter.of(tester.element(find.byType(Scaffold).first))
              .routerDelegate
              .currentConfiguration
              .uri
              .path,
          isNot(path),
          reason: '$path محجوبة عنه',
        );
      }
    });

    appTest('عامل بلا صلاحيات: لا تبويبات إدارية ولا أقسام في المزيد', (
      tester,
    ) async {
      const empty = TestAccount(
        id: 'u-empty',
        email: 'empty@school.local',
        password: 'empty-pass-1',
        role: UserRole.worker,
        entityId: 'w2',
        displayName: 'عامل',
        permissions: '{}',
      );
      await bootApp(
        tester,
        adminTabs,
        app: AppIdentity.admin,
        accounts: const [empty],
        pages: adminPages,
      );
      await loginWith(tester, empty.email, empty.password);
      expect(find.text('التلاميذ'), findsNothing);
      expect(find.text('المجموعات'), findsNothing);
      expect(find.text('المدفوعات'), findsNothing);
      await tester.tap(find.text('المزيد').last);
      await tester.pumpAndSettle();
      expect(find.text('لا توجد أقسام متاحة'), findsOneWidget);
    });

    appTest('المالك يرى كل أقسام المزيد (بالتمرير)', (tester) async {
      const boss = TestAccount(
        id: 'u-boss',
        email: 'boss@school.local',
        password: 'boss-pass-1',
        role: UserRole.owner,
        displayName: 'المدير',
      );
      await bootApp(
        tester,
        adminTabs,
        app: AppIdentity.admin,
        accounts: const [boss],
        pages: adminPages,
      );
      await loginWith(tester, boss.email, boss.password);
      await tester.tap(find.text('المزيد').last);
      await tester.pumpAndSettle();
      final scrollable = find.byType(Scrollable).last;
      for (final entry in moreEntries) {
        final finder = find.text(entry.label);
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
        }
        expect(finder, findsOneWidget, reason: entry.label);
      }
    });
  });
}
