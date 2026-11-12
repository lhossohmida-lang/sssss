import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;
import 'payments_screens_test.dart' hide main;

/// يفتح «المستحقات» من «المزيد» بعد بذر بيانات المدفوعات.
Future<AppRuntime> openDues(
  WidgetTester tester, {
  TestAccount account = owner,
}) async {
  final runtime = await openPayments(tester, account: account);
  await openMoreEntry(tester, 'المستحقات');
  return runtime;
}

void main() {
  appTest('من عليه مال: الملخص والتلميذ وبنده وهاتفه', (tester) async {
    await openDues(tester);
    expect(find.text('1 تلميذ عليهم مستحقات'), findsOneWidget);
    expect(find.text(Money.format(2000)), findsNWidgets(2));
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(
      find.textContaining('رياضيات · المجموعة 1 · الدورة 1'),
      findsOneWidget,
    );
    expect(find.textContaining('0550123451'), findsOneWidget);
    // نور غير منتسب فلا يظهر.
    expect(find.text('نور بن علي'), findsNothing);
  });

  appTest('بعد السداد الكامل: لا مستحقات', (tester) async {
    final runtime = await openDues(tester);
    await runDb(tester, () async {
      final group = (await runtime.db.select(runtime.db.groups).get()).single;
      await DuesService(runtime.db, runtime.writer).recordMonthPayment(
        studentId: 's1',
        groupId: group.id,
        cycleNumber: 1,
        amount: 2000,
        receivedBy: 'u-owner',
        receiptNumber: 'AAA-000001',
      );
    });
    await tester.pumpAndSettle();
    expect(find.text('لا مستحقات'), findsOneWidget);
    expect(find.text('0 تلميذ عليهم مستحقات'), findsOneWidget);
  });

  appTest('الدفع الجزئي يخفض المبلغ المعروض', (tester) async {
    final runtime = await openDues(tester);
    await runDb(tester, () async {
      final group = (await runtime.db.select(runtime.db.groups).get()).single;
      await DuesService(runtime.db, runtime.writer).recordMonthPayment(
        studentId: 's1',
        groupId: group.id,
        cycleNumber: 1,
        amount: 500,
        receivedBy: 'u-owner',
        receiptNumber: 'AAA-000001',
      );
    });
    await tester.pumpAndSettle();
    expect(find.text(Money.format(1500)), findsNWidgets(2));
  });

  appTest('البحث بلا نتيجة ثم الحصر بمجموعة', (tester) async {
    await openDues(tester);
    await tester.enterText(find.byType(TextField).first, 'نور');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('لا نتائج مطابقة'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('سمير بن علي'), findsOneWidget);

    await pick(tester, 'المجموعة', 'المجموعة 1 · رياضيات');
    expect(find.text('سمير بن علي'), findsOneWidget);
  });

  appTest('زر الدفع يفتح التسجيل بالتلميذ مختاراً', (tester) async {
    await openDues(tester);
    await tester.tap(find.byTooltip('تسجيل دفعة لـ سمير بن علي'));
    await tester.pumpAndSettle();
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('رياضيات · المجموعة 1 · الدورة 1'), findsOneWidget);
    // التلميذ مختار من الخارج فلا زر «تغيير».
    expect(find.text('تغيير'), findsNothing);
  });

  appTest('النقر على التلميذ يفتح ملفه', (tester) async {
    await openDues(tester);
    await tester.tap(find.text('سمير بن علي'));
    await tester.pumpAndSettle();
    expect(find.text('1 تلميذ عليهم مستحقات'), findsNothing);
    expect(find.text('سمير بن علي'), findsWidgets);
  });

  appTest('صلاحية العرض فقط: لا زر دفع', (tester) async {
    await openDues(tester, account: paymentsViewer);
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.byTooltip('تسجيل دفعة لـ سمير بن علي'), findsNothing);
  });
}
