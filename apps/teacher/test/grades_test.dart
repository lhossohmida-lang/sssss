import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'home_screens_test.dart' hide main;

Future<AppRuntime> openGrades(WidgetTester tester) async {
  final runtime = await openTeacher(tester);
  await tester.tap(find.text('مجموعاتي').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('المجموعة 1 · رياضيات'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ClayButton, 'النتائج'));
  await tester.pumpAndSettle();
  return runtime;
}

Future<void> refresh(WidgetTester tester) async {
  ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
      .invalidate(assessmentsProvider);
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<void> newTest(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ClayButton, 'اختبار جديد'));
  await tester.pumpAndSettle();
  tester.view.physicalSize = const Size(420, 2400);
  await tester.pumpAndSettle();
}

void main() {
  appTest('لا نتائج: رسالة وزر اختبار جديد', (tester) async {
    await openGrades(tester);
    expect(find.text('لا نتائج بعد'), findsOneWidget);
    expect(find.text('نتائج المجموعة 1'), findsOneWidget);
  });

  appTest('إدخال اختبار: علامة بفاصلة وملاحظة، ومن تُترك علامته لا نتيجة له', (
    tester,
  ) async {
    final runtime = await openGrades(tester);
    await newTest(tester);
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('نور بن علي'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'اختبار الفصل الأول');
    // حقول التلاميذ بعد العنوان والسلّم: علامة وملاحظة لكل تلميذ.
    await tester.enterText(find.byType(TextField).at(2), '15,5');
    await tester.enterText(find.byType(TextField).at(3), 'جيد جداً');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ النتائج'));
    await tester.pumpAndSettle();
    await refresh(tester);

    expect(find.text('اختبار الفصل الأول'), findsOneWidget);
    expect(find.textContaining('1 نتيجة'), findsOneWidget);
    expect(find.text('المتوسط 15.5/20'), findsOneWidget);
    final rows = await runDb(
      tester,
      () => runtime.db.select(runtime.db.grades).get(),
    );
    expect(rows.single.score, 15.5);
    expect(rows.single.note, 'جيد جداً');
    expect(rows.single.studentId, 's1');
  });

  appTest('أخطاء: عنوان فارغ وعلامة فوق السلّم', (tester) async {
    await openGrades(tester);
    await newTest(tester);
    await tester.enterText(find.byType(TextField).at(2), '25');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ النتائج'));
    await tester.pumpAndSettle();
    expect(find.text('أدخل عنوان الاختبار'), findsOneWidget);
    expect(find.text('العلامة بين 0 و20'), findsOneWidget);
  });

  appTest('تعديل اختبار قائم ثم حذفه', (tester) async {
    final runtime = await openGrades(tester);
    await runDb(tester, () async {
      await GradeService(runtime.db, runtime.writer).saveAssessment(
        groupId: 'g1',
        title: 'فرض',
        date: '2026-11-10',
        maxScore: 10,
        teacherId: 't1',
        results: {'s1': (score: 7.0, note: ''), 's2': (score: 9.0, note: '')},
      );
    });
    await refresh(tester);
    expect(find.text('المتوسط 8/10'), findsOneWidget);

    await tester.tap(find.text('فرض'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(420, 2400);
    await tester.pumpAndSettle();
    expect(find.text('تعديل الاختبار'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      '7',
    );
    await tester.enterText(find.byType(TextField).at(2), '8');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ النتائج'));
    await tester.pumpAndSettle();
    await refresh(tester);
    expect(find.text('المتوسط 8.5/10'), findsOneWidget);

    await tester.tap(find.text('فرض'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('حذف الاختبار'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حذف'));
    await tester.pumpAndSettle();
    await refresh(tester);
    expect(find.text('لا نتائج بعد'), findsOneWidget);
  });
}
