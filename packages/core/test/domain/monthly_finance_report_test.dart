import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

Uint8List cairo() => File('../ui/assets/fonts/Cairo.ttf').readAsBytesSync();

void main() {
  late TestEnv env;
  late MonthlyFinanceReports reports;

  setUp(() {
    env = TestEnv();
    reports = MonthlyFinanceReports(env.db);
  });

  tearDown(() => env.close());

  test('يجمع المقبوضات والمصاريف والخلاص حسب تاريخ كل سجل', () async {
    await env.student();
    await env.teacher();
    await env.subject();
    await env.group();
    await env.db
        .into(env.db.workers)
        .insert(
          WorkersCompanion.insert(
            id: 'w1',
            createdAt: 1,
            updatedAt: 1,
            name: 'عامل',
            phone: '0660000000',
            email: 'worker@school.local',
            qrCode: 'W-AAAAAAAAAA',
          ),
        );
    final expenses = ExpenseService(env.db, env.writer);
    final supplies = await expenses.addCategory('لوازم');
    final wages = await expenses.addCategory('أجور العمال', isWages: true);
    await expenses.addExpense(
      categoryId: supplies,
      amount: 300,
      date: '2026-02-02',
    );
    await expenses.addExpense(
      categoryId: wages,
      amount: 800,
      date: '2026-02-28',
      workerId: 'w1',
    );
    final deletedExpense = await expenses.addExpense(
      categoryId: supplies,
      amount: 100,
      date: '2026-02-15',
    );
    await expenses.deleteExpense(deletedExpense);

    Future<void> payment(
      String id,
      String type,
      int amount,
      DateTime at, {
      bool deleted = false,
    }) => env.db
        .into(env.db.payments)
        .insert(
          PaymentsCompanion.insert(
            id: id,
            createdAt: at.millisecondsSinceEpoch,
            updatedAt: at.millisecondsSinceEpoch,
            deletedAt: Value(deleted ? at.millisecondsSinceEpoch : null),
            studentId: 's1',
            type: type,
            amount: amount,
            receivedBy: 'u1',
            receiptNumber: id,
          ),
        );

    await payment('feb-month', 'month', 1200, DateTime(2026, 2, 1));
    await payment(
      'feb-transport',
      'transport',
      700,
      DateTime(2026, 2, 28, 23, 59),
    );
    await payment('mar-registration', 'registration', 500, DateTime(2026, 3));
    await payment(
      'deleted-payment',
      'month',
      200,
      DateTime(2026, 2, 10),
      deleted: true,
    );

    Future<void> payout(String id, int amount, DateTime? paidAt) => env.db
        .into(env.db.teacherPayouts)
        .insert(
          TeacherPayoutsCompanion.insert(
            id: id,
            createdAt: 1,
            updatedAt: 1,
            deletedAt: const Value(null),
            teacherId: 't1',
            groupId: 'g1',
            cycleNumber: 1,
            amount: amount,
            paidAt: Value(paidAt?.millisecondsSinceEpoch),
            paidBy: const Value('u1'),
          ),
        );

    await payout('feb-payout', 400, DateTime(2026, 2, 5));
    await payout('unpaid-payout', 650, null);
    await payout('mar-payout', 250, DateTime(2026, 3, 1));

    final report = await reports.load('2026-02');

    expect(report.month, '2026-02');
    expect(report.receivedAmount, 1900);
    expect(report.receiptCount, 2);
    expect(report.payments.map((item) => item.type), [
      PaymentType.month,
      PaymentType.transport,
    ]);
    expect(report.expenseAmount, 1100);
    expect(report.expenseCount, 2);
    expect(report.expenses.map((item) => item.categoryName), [
      'أجور العمال',
      'لوازم',
    ]);
    expect(report.teacherPayoutAmount, 400);
    expect(report.teacherPayoutCount, 1);
    expect(report.outgoingAmount, 1500);
    expect(report.netAmount, 400);
  });

  test('يتحدث التقرير مع تغيّر القيود المحلية', () async {
    final category = await ExpenseService(
      env.db,
      env.writer,
    ).addCategory('ماء');
    final stream = reports.watch('2026-04');
    expect((await stream.first).expenseAmount, 0);
    await ExpenseService(
      env.db,
      env.writer,
    ).addExpense(categoryId: category, amount: 250, date: '2026-04-12');
    expect((await reports.watch('2026-04').first).expenseAmount, 250);
  });

  test('يرفض مفتاح شهر غير صالح', () async {
    await expectLater(reports.load('2026-2'), throwsFormatException);
    await expectLater(reports.load('2026-13'), throwsFormatException);
    expect(() => reports.watch('2026-00'), throwsFormatException);
  });

  test('ينشئ PDF عربيّاً صالحاً بخط Cairo', () async {
    final report = MonthlyFinanceReport(
      month: '2026-02',
      payments: const [
        MonthlyPaymentTotal(type: PaymentType.month, amount: 1900, count: 2),
      ],
      expenses: const [
        MonthlyExpenseTotal(
          categoryId: 'wages',
          categoryName: 'أجور العمال',
          isWages: true,
          amount: 800,
          count: 1,
        ),
      ],
      teacherPayoutAmount: 400,
      teacherPayoutCount: 1,
    );
    final bytes = await MonthlyFinanceReportPdf.build(
      MonthlyFinanceReportPdfData(
        report: report,
        schoolName: 'مدرسة النجاح',
        schoolAddress: 'حي السلام، الجزائر',
        schoolPhone: '0550123456',
        generatedAt: DateTime(2026, 3, 1),
      ),
      fontData: cairo(),
    );
    final text = latin1.decode(bytes, allowInvalid: true);

    expect(text.startsWith('%PDF-'), isTrue);
    expect(text.trimRight().endsWith('%%EOF'), isTrue);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text), hasLength(1));
  });
}
