import 'package:flutter/material.dart' show Column, TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'home_test.dart' hide main;
import 'widget_test.dart' show parent;

Finder field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

void main() {
  appTest('حسابي: الاسم والدور والبريد والهاتف والأبناء والمدرسة', (
    tester,
  ) async {
    await openParent(tester);
    await tester.tap(find.text('حسابي').last);
    await tester.pumpAndSettle();
    expect(find.text('ولي التلميذ'), findsOneWidget);
    expect(find.text('وليّ'), findsOneWidget);
    expect(find.text('parent@school.local'), findsOneWidget);
    expect(find.text('0550000001'), findsOneWidget);
    expect(find.text('سمير بن علي، نور بن علي'), findsOneWidget);
    expect(find.text('مدرسة النجاح'), findsOneWidget);
  });

  appTest('تغيير كلمة السر: الحالية الخاطئة ثم الصحيحة', (tester) async {
    await openParent(tester);
    await tester.tap(find.text('حسابي').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'تغيير كلمة السر'));
    await tester.pumpAndSettle();

    Future<void> submit(String current, String next) async {
      await tester.enterText(field('كلمة السر الحالية'), current);
      await tester.enterText(field('كلمة السر الجديدة'), next);
      await tester.enterText(field('تأكيد كلمة السر الجديدة'), next);
      await tester.tap(find.widgetWithText(ClayButton, 'حفظ'));
      await tester.pumpAndSettle();
    }

    await submit('wrong-pass-1', 'BrandNewPass1');
    expect(find.text('كلمة السر الحالية غير صحيحة'), findsOneWidget);
    await submit(parent.password, 'BrandNewPass1');
    expect(find.text('تم تغيير كلمة السر'), findsOneWidget);
  });

  appTest('الخروج يعيد إلى شاشة الدخول', (tester) async {
    await openParent(tester);
    await tester.tap(find.text('حسابي').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'خروج'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'خروج').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ClayButton, 'دخول'), findsOneWidget);
  });

  appTest('كل التبويبات الخمسة تفتح بالبيانات دون أخطاء', (tester) async {
    await openParent(tester);
    for (final label in [
      'الحضور',
      'الجدول',
      'المدفوعات',
      'حسابي',
      'الرئيسية',
    ]) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
    expect(find.text('سمير بن علي'), findsOneWidget);
  });
}
