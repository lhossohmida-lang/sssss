import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

Future<void> open(
  WidgetTester tester, {
  int initial = 600,
  required void Function(int?) onResult,
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ClayApp(
      app: AppIdentity.admin,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(
              await showClayTimePicker(
                context,
                title: 'بداية الحصة',
                initial: initial,
              ),
            ),
            child: const Text('افتح'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('افتح'));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String label, String option) async {
  final dropdown = find.descendant(
    of: find
        .ancestor(of: find.text(label), matching: find.byType(Column))
        .first,
    matching: find.byWidgetPredicate((w) => w is DropdownButton),
  );
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('يفتح على الوقت المبدئي بأرقام لاتينية', (tester) async {
    await open(tester, initial: 16 * 60 + 30, onResult: (_) {});
    expect(find.text('بداية الحصة'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
  });

  testWidgets('اختيار ساعة ودقيقة ثم التأكيد يعيد الدقائق منذ منتصف الليل', (
    tester,
  ) async {
    int? result;
    await open(tester, onResult: (v) => result = v);
    await choose(tester, 'الساعة', '14');
    await choose(tester, 'الدقيقة', '45');
    await tester.tap(find.widgetWithText(ClayButton, 'تأكيد'));
    await tester.pumpAndSettle();
    expect(result, 14 * 60 + 45);
  });

  testWidgets('التأكيد دون تغيير يعيد الوقت المبدئي', (tester) async {
    int? result;
    await open(tester, initial: 9 * 60 + 15, onResult: (v) => result = v);
    await tester.tap(find.widgetWithText(ClayButton, 'تأكيد'));
    await tester.pumpAndSettle();
    expect(result, 9 * 60 + 15);
  });

  testWidgets('الوقت المبدئي يُقرَّب إلى خطوة الخمس دقائق', (tester) async {
    int? result;
    await open(tester, initial: 10 * 60 + 13, onResult: (v) => result = v);
    await tester.tap(find.widgetWithText(ClayButton, 'تأكيد'));
    await tester.pumpAndSettle();
    expect(result, 10 * 60 + 15);
  });

  testWidgets('59 دقيقة لا تقفز إلى الساعة التالية', (tester) async {
    int? result;
    await open(tester, initial: 10 * 60 + 59, onResult: (v) => result = v);
    await tester.tap(find.widgetWithText(ClayButton, 'تأكيد'));
    await tester.pumpAndSettle();
    expect(result, 10 * 60 + 55);
  });

  testWidgets('الإلغاء يعيد null', (tester) async {
    int? result = 1;
    await open(tester, onResult: (v) => result = v);
    await tester.tap(find.widgetWithText(ClayButton, 'إلغاء'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
