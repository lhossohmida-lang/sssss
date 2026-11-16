import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late StatisticsService statistics;

  setUp(() {
    env = TestEnv();
    statistics = StatisticsService(env.db);
  });

  tearDown(() => env.close());

  Future<void> seed() async {
    await env.student(id: 's1');
    await env.student(id: 's2');
    await env.teacher();
    await env.subject();
    await env.group();
    final expenses = ExpenseService(env.db, env.writer);
    final supplies = await expenses.addCategory('لوازم');
    final categoryOther = await expenses.addCategory('أخرى');
    await expenses.addExpense(
      categoryId: supplies,
      amount: 300,
      date: '2026-01-15',
    );
    await expenses.addExpense(
      categoryId: supplies,
      amount: 200,
      date: '2026-02-03',
    );
    await expenses.addExpense(
      categoryId: categoryOther,
      amount: 700,
      date: '2026-02-20',
    );
    final deleted = await expenses.addExpense(
      categoryId: supplies,
      amount: 900,
      date: '2026-02-21',
    );
    await expenses.deleteExpense(deleted);

    Future<void> payment(
      String id,
      int month,
      int amount, {
      bool deleted = false,
    }) => env.db
        .into(env.db.payments)
        .insert(
          PaymentsCompanion.insert(
            id: id,
            createdAt: DateTime(2026, month, 8).millisecondsSinceEpoch,
            updatedAt: 1,
            deletedAt: Value(
              deleted ? DateTime(2026, month, 8).millisecondsSinceEpoch : null,
            ),
            studentId: 's1',
            type: PaymentType.month.code,
            amount: amount,
            receivedBy: 'u1',
            receiptNumber: id,
          ),
        );
    await payment('payment-jan', 1, 1200);
    await payment('payment-feb', 2, 800);
    await payment('payment-deleted', 2, 600, deleted: true);
    await payment('payment-next-year', 1, 350, deleted: false).then((_) async {
      await (env.db.update(
        env.db.payments,
      )..where((row) => row.id.equals('payment-next-year'))).write(
        PaymentsCompanion(
          createdAt: Value(DateTime(2027, 1, 1).millisecondsSinceEpoch),
        ),
      );
    });

    Future<void> payout(
      String id,
      int amount,
      DateTime? paidAt, {
      bool deleted = false,
    }) => env.db
        .into(env.db.teacherPayouts)
        .insert(
          TeacherPayoutsCompanion.insert(
            id: id,
            createdAt: 1,
            updatedAt: 1,
            deletedAt: Value(deleted ? 10 : null),
            teacherId: 't1',
            groupId: 'g1',
            cycleNumber: 1,
            amount: amount,
            paidAt: Value(paidAt?.millisecondsSinceEpoch),
            paidBy: const Value('u1'),
          ),
        );
    await payout('payout-jan', 400, DateTime(2026, 1, 5));
    await payout('payout-feb-unpaid', 1000, null);
    await payout(
      'payout-feb-deleted',
      500,
      DateTime(2026, 2, 5),
      deleted: true,
    );

    Future<void> session(String id, int month, int day) => env.db
        .into(env.db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: id,
            createdAt: 1,
            updatedAt: 1,
            groupId: 'g1',
            cycleNumber: 1,
            sessionNumber: const Value(1),
            date:
                '2026-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
            startMinutes: 600,
            endMinutes: 690,
          ),
        );
    await session('session-jan', 1, 5);
    await session('session-feb', 2, 5);
    await session('session-cancelled', 2, 12);
    await (env.db.update(env.db.sessions)
          ..where((row) => row.id.equals('session-cancelled')))
        .write(const SessionsCompanion(status: Value('cancelled')));
    Future<void> attendance(
      String id,
      String sessionId,
      String studentId,
      String status,
    ) => env.db
        .into(env.db.attendance)
        .insert(
          AttendanceCompanion.insert(
            id: id,
            createdAt: 1,
            updatedAt: 1,
            sessionId: sessionId,
            studentId: studentId,
            status: status,
            method: 'manual',
          ),
        );
    await attendance('attendance-present', 'session-jan', 's1', 'present');
    await attendance('attendance-absent', 'session-feb', 's1', 'absent');
    await attendance('attendance-excused', 'session-feb', 's2', 'excused');
    await attendance(
      'attendance-cancelled',
      'session-cancelled',
      's1',
      'present',
    );

    await env.student(id: 'new-student-jan');
    await env.student(id: 'new-student-feb');
    await env.student(id: 'deleted-student');
    await (env.db.update(
      env.db.students,
    )..where((row) => row.id.equals('new-student-jan'))).write(
      StudentsCompanion(
        createdAt: Value(DateTime(2026, 1, 3).millisecondsSinceEpoch),
      ),
    );
    await (env.db.update(
      env.db.students,
    )..where((row) => row.id.equals('new-student-feb'))).write(
      StudentsCompanion(
        createdAt: Value(DateTime(2026, 2, 9).millisecondsSinceEpoch),
      ),
    );
    await (env.db.update(
      env.db.students,
    )..where((row) => row.id.equals('deleted-student'))).write(
      StudentsCompanion(
        createdAt: Value(DateTime(2026, 2, 10).millisecondsSinceEpoch),
        deletedAt: const Value(20),
      ),
    );

    await env.db
        .into(env.db.groups)
        .insert(
          GroupsCompanion.insert(
            id: 'new-group-jan',
            createdAt: DateTime(2026, 1, 20).millisecondsSinceEpoch,
            updatedAt: 1,
            number: 2,
            subjectId: 'sub',
            teacherId: 't1',
          ),
        );
    await env.db
        .into(env.db.groups)
        .insert(
          GroupsCompanion.insert(
            id: 'new-group-feb',
            createdAt: DateTime(2026, 2, 20).millisecondsSinceEpoch,
            updatedAt: 1,
            deletedAt: const Value(30),
            number: 3,
            subjectId: 'sub',
            teacherId: 't1',
          ),
        );
  }

  const fullScope = StatisticsScope(
    payments: true,
    expenses: true,
    payouts: true,
    attendance: true,
    students: true,
    groups: true,
  );

  test('يعيد 12 شهراً ومجاميع مالية وتشغيلية تستبعد المحذوف والملغى', () async {
    await seed();
    final snapshot = await statistics.load(2026, fullScope);

    expect(snapshot.months, hasLength(12));
    expect(snapshot.months.first.month, 1);
    expect(snapshot.months.last.month, 12);
    expect(snapshot.months[0].receipts, 1200);
    expect(snapshot.months[1].receipts, 800);
    expect(snapshot.months[0].expenses, 300);
    expect(snapshot.months[1].expenses, 900);
    expect(snapshot.months[0].payouts, 400);
    expect(
      snapshot.months[1].payouts,
      0,
      reason: 'الخلاص غير المسلّم والمصروف المحذوف لا يحسبان',
    );
    expect(snapshot.months[0].present, 1);
    expect(snapshot.months[1].absent, 1);
    expect(snapshot.months[1].excused, 1);
    expect(snapshot.months[1].present, 0, reason: 'الحصة الملغاة لا تحسب');
    expect(snapshot.months[0].newStudents, 1);
    expect(snapshot.months[1].newStudents, 1);
    expect(snapshot.months[1].newGroups, 0, reason: 'الفوج المحذوف لا تحسب');
    expect(snapshot.receivedTotal, 2000);
    expect(snapshot.expenseTotal, 1200);
    expect(snapshot.payoutTotal, 400);
    expect(snapshot.attendanceTotal, 3);
    expect(snapshot.activeStudents, 4);
    expect(snapshot.activeGroups, 2);
  });

  test('لا يقرأ أو يملأ أقساماً ليست ضمن صلاحية المستخدم', () async {
    await seed();
    const paymentsOnly = StatisticsScope(payments: true);
    final snapshot = await statistics.load(2026, paymentsOnly);

    expect(snapshot.months[0].receipts, 1200);
    expect(snapshot.months[1].expenses, 0);
    expect(snapshot.months[0].present, 0);
    expect(snapshot.months[0].newStudents, 0);
    expect(snapshot.activeStudents, 0);
  });

  test('البث يتحدث بعد تسجيل عملية ضمن السنة', () async {
    final stream = statistics.watch(
      2026,
      const StatisticsScope(payments: true),
    );
    expect((await stream.first).receivedTotal, 0);
    await env.student();
    await env.db
        .into(env.db.payments)
        .insert(
          PaymentsCompanion.insert(
            id: 'new-payment',
            createdAt: DateTime(2026, 7, 8).millisecondsSinceEpoch,
            updatedAt: 1,
            studentId: 's1',
            type: PaymentType.month.code,
            amount: 1250,
            receivedBy: 'u1',
            receiptNumber: 'new-payment',
          ),
        );

    expect(
      (await statistics
              .watch(2026, const StatisticsScope(payments: true))
              .first)
          .receivedTotal,
      1250,
    );
  });

  test('يرفض سنة غير صالحة ونطاقاً بلا صلاحية', () async {
    await expectLater(
      statistics.load(0, const StatisticsScope(payments: true)),
      throwsFormatException,
    );
    await expectLater(
      statistics.load(2026, const StatisticsScope()),
      throwsArgumentError,
    );
  });
}
