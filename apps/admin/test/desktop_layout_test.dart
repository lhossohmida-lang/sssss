import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/testing.dart';

import 'payments_screens_test.dart' hide main;

/// مراجعة نسخة Windows: كل شاشات الإدارة تُبنى على عرض سطح المكتب وعلى عرض
/// الهاتف دون فيض أو استثناء (فيض التخطيط يُفشل الاختبار تلقائياً).
void main() {
  Future<void> visit(WidgetTester tester, List<String> paths) async {
    for (final path in paths) {
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: path);
    }
  }

  Future<List<String>> paths(WidgetTester tester, AppRuntime runtime) async {
    final group = await runDb(
      tester,
      () => runtime.db.select(runtime.db.groups).getSingle(),
    );
    return [
      '/dashboard',
      '/students',
      '/groups',
      '/payments',
      '/more',
      '/groups/${group.id}',
      '/groups/${group.id}/edit',
      '/groups/new',
      '/students/s1',
      '/students/new',
      '/schedule',
      '/attendance',
      '/waiting',
      '/dues',
      '/fees',
      '/payouts',
      '/workers',
      '/workers/new',
      '/worker-attendance',
      '/teacher-attendance',
      '/teachers',
      '/subjects',
      '/rooms',
      '/settings',
      '/payments/new',
      '/scanner',
      '/entrance',
    ];
  }

  for (final (label, width, height) in [
    ('Windows 1280×800', 1280.0, 800.0),
    ('Windows 1920×1080', 1920.0, 1080.0),
    ('هاتف 360×740', 360.0, 740.0),
  ]) {
    appTest('كل الشاشات بلا فيض على $label', (tester) async {
      tester.view.physicalSize = Size(width, height);
      final runtime = await openPayments(tester);
      await visit(tester, await paths(tester, runtime));
    });
  }
}
