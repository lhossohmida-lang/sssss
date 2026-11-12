import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'home_screens_test.dart' hide main;

Future<void> openAccount(WidgetTester tester) async {
  await openTeacher(tester);
  await tester.tap(find.text('حسابي').last);
  await tester.pumpAndSettle();
}

Finder passwordField(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

Future<void> fillPasswords(
  WidgetTester tester, {
  required String current,
  required String next,
  required String confirm,
}) async {
  await tester.enterText(passwordField('كلمة السر الحالية'), current);
  await tester.enterText(passwordField('كلمة السر الجديدة'), next);
  await tester.enterText(passwordField('تأكيد كلمة السر الجديدة'), confirm);
  await tester.tap(find.widgetWithText(ClayButton, 'حفظ'));
  await tester.pumpAndSettle();
}

void main() {
  appTest('حسابي: الاسم والدور والبريد والهاتف والمدرسة', (tester) async {
    await openAccount(tester);
    expect(find.text('الأستاذ كمال'), findsOneWidget);
    expect(find.text('أستاذ'), findsOneWidget);
    expect(find.text('teacher@school.local'), findsOneWidget);
    expect(find.text('0660000001'), findsOneWidget);
    expect(find.text('مدرسة النجاح'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'تغيير كلمة السر'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'خروج'), findsOneWidget);
  });

  appTest('تغيير كلمة السر: أخطاء الحقول ثم النجاح', (tester) async {
    final runtime = await openTeacher(tester);
    await tester.tap(find.text('حسابي').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'تغيير كلمة السر'));
    await tester.pumpAndSettle();

    // حقول فارغة وجديدة قصيرة وتأكيد مختلف.
    await fillPasswords(tester, current: '', next: 'short', confirm: 'other');
    expect(find.text('أدخل كلمة السر الحالية'), findsOneWidget);
    expect(find.textContaining('8'), findsWidgets);
    expect(find.text('كلمتا السر غير متطابقتين'), findsOneWidget);

    // الحالية خاطئة.
    await fillPasswords(
      tester,
      current: 'wrong-pass-1',
      next: 'BrandNewPass1',
      confirm: 'BrandNewPass1',
    );
    expect(find.text('كلمة السر الحالية غير صحيحة'), findsOneWidget);

    // الصحيحة تُغيّر وتُغلق النافذة وتُظهر تأكيداً.
    await fillPasswords(
      tester,
      current: teacher.password,
      next: 'BrandNewPass1',
      confirm: 'BrandNewPass1',
    );
    expect(find.text('تم تغيير كلمة السر'), findsOneWidget);
    expect(find.text('تغيير كلمة السر').evaluate().length, 1);
    expect(runtime.auth.current, isNotNull);
  });

  appTest('الخروج بتأكيد يعيد إلى شاشة الدخول', (tester) async {
    await openAccount(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'خروج'));
    await tester.pumpAndSettle();
    expect(find.text('الخروج'), findsOneWidget);

    // «لا» تُبقي الجلسة.
    await tester.tap(find.widgetWithText(ClayButton, 'إلغاء'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ClayButton, 'خروج'), findsOneWidget);

    await tester.tap(find.widgetWithText(ClayButton, 'خروج'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'خروج').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ClayButton, 'دخول'), findsOneWidget);
  });
}
