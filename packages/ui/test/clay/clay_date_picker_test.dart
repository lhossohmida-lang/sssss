import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// يفتح المنتقي من زر ويعيد ما اختاره المستخدم عبر [result].
Future<void> open(
  WidgetTester tester, {
  DateTime? initial,
  required void Function(DateTime?) onResult,
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
              await showClayDatePicker(
                context,
                title: 'بداية الفصل',
                initial: initial,
                today: DateTime(2026, 11, 10),
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

void main() {
  testWidgets('يفتح على شهر اليوم بأرقام لاتينية ولا يؤكَّد قبل اختيار يوم', (
    tester,
  ) async {
    await open(tester, onResult: (_) {});
    expect(find.text('بداية الفصل'), findsOneWidget);
    expect(find.text('نوفمبر 2026'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    final confirm = tester.widget<ClayButton>(
      find.widgetWithText(ClayButton, 'تأكيد'),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('اختيار يوم ثم التأكيد يعيد التاريخ', (tester) async {
    DateTime? result;
    await open(tester, onResult: (d) => result = d);
    await tester.tap(find.text('15'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ClayButton, 'تأكيد'));
    await tester.pumpAndSettle();
    expect(result, DateTime(2026, 11, 15));
  });

  testWidgets('الانتقال إلى شهر آخر يمسح اليوم المحدد', (tester) async {
    DateTime? result;
    await open(
      tester,
      initial: DateTime(2026, 11, 20),
      onResult: (d) => result = d,
    );
    // اليوم المحدد مسبقاً: التأكيد متاح فوراً.
    expect(
      tester
          .widget<ClayButton>(find.widgetWithText(ClayButton, 'تأكيد'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byTooltip('الشهر التالي'));
    await tester.pump();
    expect(find.text('ديسمبر 2026'), findsOneWidget);
    expect(
      tester
          .widget<ClayButton>(find.widgetWithText(ClayButton, 'تأكيد'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('3'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ClayButton, 'تأكيد'));
    await tester.pumpAndSettle();
    expect(result, DateTime(2026, 12, 3));
  });

  testWidgets('الإلغاء يعيد null', (tester) async {
    DateTime? result = DateTime(2000);
    await open(tester, onResult: (d) => result = d);
    await tester.tap(find.widgetWithText(ClayButton, 'إلغاء'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('التاريخ المبدئي يحدد الشهر ويُحدَّد يومه', (tester) async {
    await open(tester, initial: DateTime(2027, 2, 9), onResult: (_) {});
    expect(find.text('فيفري 2027'), findsOneWidget);
  });
}
