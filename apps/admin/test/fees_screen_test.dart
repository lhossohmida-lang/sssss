import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;
import 'payments_screens_test.dart' hide main;

/// مفتاح الفترة الجارية بالإعدادات الافتراضية (سنة دراسية).
String currentPeriod() =>
    const SchoolSettings().feePeriodKey(DateKey.of(DateTime.now()));

/// يفتح «حقوق التسجيل» من «المزيد»؛ [withFees] يبذر حقوقاً لتلميذين.
Future<AppRuntime> openFees(
  WidgetTester tester, {
  bool withFees = true,
  TestAccount account = owner,
}) async {
  final runtime = await openPayments(tester, account: account);
  if (withFees) {
    await runDb(tester, () async {
      final dues = DuesService(runtime.db, runtime.writer);
      final period = currentPeriod();
      await dues.ensureRegistrationFee(
        studentId: 's1',
        periodKey: period,
        amount: 1000,
      );
      await dues.ensureRegistrationFee(
        studentId: 's2',
        periodKey: period,
        amount: 1000,
      );
      await dues.ensureRegistrationFee(
        studentId: 's1',
        periodKey: '2020-2021',
        amount: 800,
      );
      await dues.payRegistrationFee(
        studentId: 's1',
        periodKey: period,
        amount: 1000,
        receivedBy: 'u-owner',
        receiptNumber: 'AAA-000001',
      );
      await dues.payRegistrationFee(
        studentId: 's2',
        periodKey: period,
        amount: 400,
        receivedBy: 'u-owner',
        receiptNumber: 'AAA-000002',
      );
    });
  }
  await openMoreEntry(tester, 'حقوق التسجيل');
  return runtime;
}

void main() {
  appTest('الفترة الجارية: حالة كل تلميذ وملخص المطلوب والمحصَّل', (
    tester,
  ) async {
    await openFees(tester);
    expect(find.text('${currentPeriod()} (الجارية)'), findsOneWidget);
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('نور بن علي'), findsOneWidget);
    expect(find.text('مسدَّد'), findsOneWidget);
    expect(find.text('الباقي ${Money.format(600)}'), findsOneWidget);
    expect(
      find.text(
        'المطلوب ${Money.format(2000)} · المحصَّل ${Money.format(1400)}',
      ),
      findsOneWidget,
    );
    expect(
      find.text('الباقي ${Money.format(600)} عند 1 تلميذ'),
      findsOneWidget,
    );
  });

  appTest('فترة سابقة بحقوقها', (tester) async {
    await openFees(tester);
    await tester.tap(find.text('2020-2021'));
    await tester.pumpAndSettle();
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('نور بن علي'), findsNothing);
    expect(find.text('الباقي ${Money.format(800)}'), findsOneWidget);
  });

  appTest('غير المسدَّد فقط', (tester) async {
    await openFees(tester);
    await tester.tap(find.widgetWithText(ClayChip, 'غير المسدَّد فقط'));
    await tester.pumpAndSettle();
    expect(find.text('سمير بن علي'), findsNothing);
    expect(find.text('نور بن علي'), findsOneWidget);
  });

  appTest('البحث بلا نتيجة', (tester) async {
    await openFees(tester);
    await tester.enterText(find.byType(TextField).first, 'لا أحد');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('لا نتائج مطابقة'), findsOneWidget);
  });

  appTest('زر الدفع يفتح التسجيل بحقوق الفترة', (tester) async {
    await openFees(tester);
    await tester.tap(find.byTooltip('تسجيل دفعة لـ نور بن علي'));
    await tester.pumpAndSettle();
    expect(find.text('حقوق التسجيل ${currentPeriod()}'), findsOneWidget);
    expect(find.text('الباقي ${Money.format(600)}'), findsOneWidget);
  });

  appTest('فترة جارية بلا حقوق: رسالة فارغة', (tester) async {
    await openFees(tester, withFees: false);
    expect(find.text('لا حقوق في الفترة'), findsOneWidget);
    expect(find.text('${currentPeriod()} (الجارية)'), findsOneWidget);
  });

  appTest('صلاحية العرض فقط: لا زر دفع', (tester) async {
    await openFees(tester, account: paymentsViewer);
    expect(find.text('نور بن علي'), findsOneWidget);
    expect(find.byTooltip('تسجيل دفعة لـ نور بن علي'), findsNothing);
  });
}
