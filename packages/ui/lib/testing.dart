/// أدوات اختبار الواجهة المشتركة بين التطبيقات الثلاثة. لا تُستعمل في كود
/// الإنتاج.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';

import 'school_ui.dart';

/// يشغّل اختبار واجهة بشاشة هاتف، ثم يفكّ الشجرة ويُفرغ مؤقتات drift
/// المعلّقة (فتح استعلام متدفق يترك مؤقتاً صفرياً عند إغلاقه) قبل أن يتحقق
/// الإطار من المؤقتات.
void appTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await body(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

/// يشغّل تطبيقاً من التطبيقات الثلاثة على وقت تشغيل اختباري ويتجاوز شاشة
/// البداية، فيقف عند شاشة الدخول (أو عند التبويبات إن كانت هناك جلسة).
Future<AppRuntime> bootApp(
  WidgetTester tester,
  List<AppTab> tabs, {
  required AppIdentity app,
  required List<TestAccount> accounts,
}) async {
  final runtime = (await tester.runAsync(
    () => startTestRuntime(app: app, accounts: accounts),
  ))!;
  addTearDown(() async {
    await tester.runAsync(() async {
      await runtime.auth.dispose();
      await runtime.db.close();
    });
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [runtimeProvider.overrideWithValue(runtime)],
      child: SchoolApp(tabs: tabs),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  return runtime;
}

/// يملأ شاشة الدخول ويضغط «دخول».
Future<void> loginWith(
  WidgetTester tester,
  String email,
  String password,
) async {
  Finder field(String label) => find.descendant(
    of: find
        .ancestor(of: find.text(label), matching: find.byType(Column))
        .first,
    matching: find.byType(TextField),
  );
  await tester.enterText(field('البريد'), email);
  await tester.enterText(field('كلمة السر'), password);
  await tester.tap(find.widgetWithText(ClayButton, 'دخول'));
  await tester.pumpAndSettle();
}
