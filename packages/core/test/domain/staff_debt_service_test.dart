import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late StaffDebtService debts;
  late ExpenseService expenses;
  final now = DateTime(2026, 11, 20, 10);

  Future<void> worker({String id = 'w1', String name = 'سمير'}) => env.db
      .into(env.db.workers)
      .insert(
        WorkersCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          name: name,
          phone: '0660000000',
          email: '$id@school.local',
          qrCode: 'W-$id',
        ),
      );

  setUp(() async {
    env = TestEnv();
    debts = StaffDebtService(env.db, env.writer, clock: () => now);
    expenses = ExpenseService(env.db, env.writer);
    await env.teacher();
    await worker();
  });
  tearDown(() => env.close());

  Future<String> teacherDebt([
    int amount = 50000,
    String date = '2026-10-01',
  ]) => debts.addDebt(
    kind: StaffKind.teacher,
    staffId: 't1',
    amount: amount,
    date: date,
    note: 'خلاصات ما قبل النظام',
  );

  Future<List<ExpenseRow>> liveExpenses() async =>
      (await env.db.select(env.db.expenses).get())
          .where((e) => e.deletedAt == null)
          .toList();

  group('الديون', () {
    test('دين أستاذ وعامل، لكل منهما دفتره ومتبقّيه', () async {
      await teacherDebt();
      await debts.addDebt(
        kind: StaffKind.teacher,
        staffId: 't1',
        amount: 10000,
        date: '2026-10-15',
      );
      await debts.addDebt(
        kind: StaffKind.worker,
        staffId: 'w1',
        amount: 30000,
        date: '2026-09-30',
        note: 'أجر سبتمبر',
      );
      final teacher = await debts.summary(StaffKind.teacher, 't1');
      expect(teacher.debts, 60000);
      expect(teacher.payments, 0);
      expect(teacher.balance, 60000);
      // الأحدث تاريخاً أولاً.
      expect(teacher.entries.map((e) => e.date), ['2026-10-15', '2026-10-01']);
      final driver = await debts.summary(StaffKind.worker, 'w1');
      expect(driver.balance, 30000);
      expect(driver.entries.single.note, 'أجر سبتمبر');
      expect(driver.entries.single.staffType, 'worker');
    });

    test('الدين لا يمسّ المصاريف ولا الخزينة', () async {
      await teacherDebt();
      expect(await liveExpenses(), isEmpty);
    });

    test('يُسجَّل في سجل العمليات وطابور المزامنة', () async {
      final id = await teacherDebt();
      final audit = await env.db.select(env.db.auditLog).get();
      expect(audit.where((a) => a.entity == 'staff_debts'), hasLength(1));
      final outbox = await env.db.select(env.db.outbox).get();
      expect(outbox.where((o) => o.targetTable == 'staff_debts'), isNotEmpty);
      expect(
        (await env.db.select(env.db.staffDebts).get()).single.createdBy,
        'u1',
      );
      expect(id, isNotEmpty);
    });

    test('التحقق من المدخلات', () async {
      Future<void> add({
        int amount = 1000,
        String date = '2026-10-01',
        String note = '',
        String staffId = 't1',
        StaffKind kind = StaffKind.teacher,
      }) => debts.addDebt(
        kind: kind,
        staffId: staffId,
        amount: amount,
        date: date,
        note: note,
      );
      for (final amount in [0, -5, StaffDebtService.maxAmount + 1]) {
        await expectLater(
          add(amount: amount),
          throwsA(isA<ValidationException>()),
          reason: '$amount',
        );
      }
      for (final date in [
        '2026-11-21',
        '2027-01-01',
        '2026-02-30',
        '1/10/2026',
      ]) {
        await expectLater(
          add(date: date),
          throwsA(isA<ValidationException>()),
          reason: date,
        );
      }
      await expectLater(add(date: '2026-11-20'), completes);
      await expectLater(
        add(note: 'ا' * 201),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        add(staffId: 'ghost'),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        add(kind: StaffKind.worker, staffId: 't1'),
        throwsA(isA<ValidationException>()),
        reason: 'معرّف أستاذ لا يصلح لعامل',
      );
    });

    test('أستاذ أو عامل محذوف لا يُضاف له دين', () async {
      await env.db.customStatement(
        "UPDATE teachers SET deleted_at = 5 WHERE id = 't1'",
      );
      await expectLater(teacherDebt(), throwsA(isA<ValidationException>()));
    });
  });

  group('التسديد', () {
    test('يخفض المتبقي وينشئ مصروفاً مقابلاً بنوعه المحجوز', () async {
      await teacherDebt();
      final paymentId = await debts.pay(
        kind: StaffKind.teacher,
        staffId: 't1',
        amount: 20000,
        date: '2026-11-18',
        note: 'دفعة أولى',
      );
      final summary = await debts.summary(StaffKind.teacher, 't1');
      expect(summary.payments, 20000);
      expect(summary.balance, 30000);

      final payment = summary.entries.firstWhere((e) => e.id == paymentId);
      expect(payment.kind, 'payment');
      final expense = (await liveExpenses()).single;
      expect(payment.expenseId, expense.id);
      expect(expense.amount, 20000);
      expect(expense.date, '2026-11-18');
      expect(expense.categoryId, StaffDebtService.categoryId);
      expect(expense.workerId, isNull);
      expect(expense.note, contains('الأستاذ t1'));
      expect(expense.note, contains('دفعة أولى'));
      final category = await (env.db.select(
        env.db.expenseCategories,
      )..where((c) => c.id.equals(StaffDebtService.categoryId))).getSingle();
      expect(category.name, StaffDebtService.categoryName);
      expect(category.isWages, isFalse);
    });

    test('تسديد عامل يربط المصروف بالعامل لا بنوع الأجور', () async {
      await debts.addDebt(
        kind: StaffKind.worker,
        staffId: 'w1',
        amount: 8000,
        date: '2026-10-01',
      );
      await debts.pay(
        kind: StaffKind.worker,
        staffId: 'w1',
        amount: 8000,
        date: '2026-11-19',
      );
      final expense = (await liveExpenses()).single;
      expect(expense.workerId, 'w1');
      expect(expense.categoryId, StaffDebtService.categoryId);
      expect((await debts.summary(StaffKind.worker, 'w1')).balance, 0);
      // مسدَّد بالكامل: لا يظهر في قائمة المتبقّين.
      expect(await debts.outstanding(), isEmpty);
    });

    test('النوع المحجوز ينشأ مرة واحدة مهما تعدد التسديد', () async {
      await teacherDebt();
      for (var i = 0; i < 3; i++) {
        await debts.pay(
          kind: StaffKind.teacher,
          staffId: 't1',
          amount: 1000,
          date: '2026-11-1${i + 1}',
        );
      }
      final categories = await env.db.select(env.db.expenseCategories).get();
      expect(
        categories.where((c) => c.id == StaffDebtService.categoryId),
        hasLength(1),
      );
      expect(await liveExpenses(), hasLength(3));
    });

    test('لا يزيد التسديد عن المتبقي ولا يُقبل بلا دين', () async {
      await expectLater(
        debts.pay(
          kind: StaffKind.teacher,
          staffId: 't1',
          amount: 100,
          date: '2026-11-18',
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.toString(),
            'الرسالة',
            contains('لا دين متبقٍّ'),
          ),
        ),
      );
      await teacherDebt(5000);
      await expectLater(
        debts.pay(
          kind: StaffKind.teacher,
          staffId: 't1',
          amount: 5001,
          date: '2026-11-18',
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.toString(),
            'الرسالة',
            contains('5000'),
          ),
        ),
      );
      expect(await liveExpenses(), isEmpty);
      await expectLater(
        debts.pay(
          kind: StaffKind.teacher,
          staffId: 't1',
          amount: 5000,
          date: '2026-11-18',
        ),
        completes,
      );
    });

    test('الفشل لا يترك مصروفاً ولا تسديداً', () async {
      await teacherDebt(5000);
      await expectLater(
        debts.pay(
          kind: StaffKind.teacher,
          staffId: 't1',
          amount: 6000,
          date: '2026-11-18',
        ),
        throwsA(isA<ValidationException>()),
      );
      final summary = await debts.summary(StaffKind.teacher, 't1');
      expect(summary.payments, 0);
      expect(await liveExpenses(), isEmpty);
    });
  });

  group('الحذف', () {
    test('حذف تسديد يعيد المتبقي ويحذف مصروفه', () async {
      await teacherDebt(10000);
      final paymentId = await debts.pay(
        kind: StaffKind.teacher,
        staffId: 't1',
        amount: 4000,
        date: '2026-11-18',
      );
      await debts.remove(paymentId);
      expect((await debts.summary(StaffKind.teacher, 't1')).balance, 10000);
      expect(await liveExpenses(), isEmpty);
    });

    test('حذف دين سُدِّد بعضه ممنوع حتى تُحذف التسديدات', () async {
      final debtId = await teacherDebt(10000);
      final paymentId = await debts.pay(
        kind: StaffKind.teacher,
        staffId: 't1',
        amount: 4000,
        date: '2026-11-18',
      );
      await expectLater(
        debts.remove(debtId),
        throwsA(isA<ValidationException>()),
      );
      await debts.remove(paymentId);
      await debts.remove(debtId);
      expect((await debts.summary(StaffKind.teacher, 't1')).entries, isEmpty);
    });

    test('حذف أحد دينين يبقى معه المتبقي موجباً', () async {
      final first = await teacherDebt(10000);
      await teacherDebt(5000, '2026-10-10');
      await debts.pay(
        kind: StaffKind.teacher,
        staffId: 't1',
        amount: 4000,
        date: '2026-11-18',
      );
      // المتبقي 11000؛ حذف دين 10000 يُنزله إلى 1000 فيُقبل.
      await debts.remove(first);
      expect((await debts.summary(StaffKind.teacher, 't1')).balance, 1000);
    });

    test('حذف سجل غير موجود لا يفعل شيئاً', () async {
      await expectLater(debts.remove('nope'), completes);
    });
  });

  group('المتبقّون', () {
    test('كل من له متبقٍّ بالأكبر أولاً، ومن حُذف لا يظهر', () async {
      await worker(id: 'w2', name: 'أمين');
      await teacherDebt(20000);
      await debts.addDebt(
        kind: StaffKind.worker,
        staffId: 'w1',
        amount: 45000,
        date: '2026-10-01',
      );
      await debts.addDebt(
        kind: StaffKind.worker,
        staffId: 'w2',
        amount: 5000,
        date: '2026-10-01',
      );
      var list = await debts.outstanding();
      expect(list.map((b) => b.staffId), ['w1', 't1', 'w2']);
      expect(list.map((b) => b.balance), [45000, 20000, 5000]);
      expect(list.first.kind, StaffKind.worker);
      expect(list.first.name, 'سمير');
      await env.db.customStatement(
        "UPDATE workers SET deleted_at = 5 WHERE id = 'w1'",
      );
      list = await debts.outstanding();
      expect(list.map((b) => b.staffId), ['t1', 'w2']);
    });

    test('المتابعة اللحظية لدفتر أستاذ', () async {
      final seen = debts.watch(StaffKind.teacher, 't1');
      final done = expectLater(
        seen,
        emitsThrough(predicate<StaffDebtSummary>((s) => s.balance == 7000)),
      );
      await teacherDebt(7000);
      await done;
    });
  });

  group('المصاريف والتقارير', () {
    test('التسديد يظهر في التقرير المالي لشهر التسديد بنوعه', () async {
      await teacherDebt(30000);
      await debts.pay(
        kind: StaffKind.teacher,
        staffId: 't1',
        amount: 12000,
        date: '2026-11-18',
      );
      final november = await MonthlyFinanceReports(env.db).load('2026-11');
      final item = november.expenses.single;
      expect(item.categoryName, StaffDebtService.categoryName);
      expect(item.amount, 12000);
      expect(item.isWages, isFalse);
      expect(november.outgoingAmount, 12000);
      // شهر الدين الأصلي لا مصروف فيه: الدين وحده ليس خروج مال.
      final october = await MonthlyFinanceReports(env.db).load('2026-10');
      expect(october.expenses, isEmpty);
      expect(october.outgoingAmount, 0);
    });

    test('نوع التسديد مخفي من قائمة الأنواع', () async {
      await teacherDebt();
      await debts.pay(
        kind: StaffKind.teacher,
        staffId: 't1',
        amount: 1000,
        date: '2026-11-18',
      );
      await expenses.addCategory('كهرباء');
      final categories = await expenses.watchCategories().first;
      expect(categories.map((c) => c.name), ['كهرباء']);
    });

    test('مصروف التسديد لا يُعدَّل ولا يُحذف من المصاريف', () async {
      await teacherDebt();
      await debts.pay(
        kind: StaffKind.teacher,
        staffId: 't1',
        amount: 1000,
        date: '2026-11-18',
      );
      final expense = (await liveExpenses()).single;
      await expectLater(
        expenses.deleteExpense(expense.id),
        throwsA(isA<StateError>()),
      );
      final other = await expenses.addCategory('كهرباء');
      await expectLater(
        expenses.updateExpense(
          id: expense.id,
          categoryId: other,
          amount: 5,
          date: '2026-11-18',
          note: 'x',
        ),
        throwsA(isA<StateError>()),
      );
      expect(await liveExpenses(), hasLength(1));
    });

    test('لا يُسجَّل مصروف عادي في نوع التسديد', () async {
      await expectLater(
        expenses.addExpense(
          categoryId: StaffDebtService.categoryId,
          amount: 100,
          date: '2026-11-18',
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        expenses.renameCategory(StaffDebtService.categoryId, 'غيره'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        expenses.deleteCategory(StaffDebtService.categoryId),
        throwsA(isA<StateError>()),
      );
    });
  });

  test('معرّفات المصروف المقابل ثابتة لكل تسديد', () {
    expect(StableId.staffDebtExpense('p1'), StableId.staffDebtExpense('p1'));
    expect(
      StableId.staffDebtExpense('p1'),
      isNot(StableId.staffDebtExpense('p2')),
    );
    expect(StableId.staffDebtCategory(), StableId.staffDebtCategory());
  });
}
