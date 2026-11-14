import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late ExpenseService service;

  setUp(() {
    env = TestEnv();
    service = ExpenseService(env.db, env.writer);
  });

  tearDown(() => env.close());

  test('نوع المصروف معرّفه ثابت والاسم الفارغ أو المكرر مرفوض', () async {
    final id = await service.addCategory('  صيانة  ');
    expect(id, StableId.expenseCategory('صيانة'));
    final categories = await service.watchCategories().first;
    expect(categories, hasLength(1));
    expect(categories.single.id, id);
    expect(categories.single.name, 'صيانة');
    expect(categories.single.isWages, isFalse);
    await expectLater(service.addCategory('صيانة'), throwsStateError);
    await expectLater(service.addCategory(' '), throwsFormatException);
  });

  test('إعادة تسمية النوع تبقي ربط السجل وتمنع التكرار', () async {
    final first = await service.addCategory('كهرباء');
    await service.addCategory('ماء');
    final expense = await service.addExpense(
      categoryId: first,
      amount: 900,
      date: '2026-05-14',
    );

    await expectLater(service.renameCategory(first, 'ماء'), throwsStateError);
    await service.renameCategory(first, 'غاز');
    final items = await service.watchMonth(year: 2026, month: 5).first;

    expect(items.single.id, expense);
    expect(items.single.categoryName, 'غاز');
  });

  test('إعادة إنشاء اسم نوع محذوف تعيد السجل بمعرّفه الثابت', () async {
    final id = await service.addCategory('نظافة');
    await service.deleteCategory(id);

    final restored = await service.addCategory(' نظافة ');

    expect(restored, id);
    final categories = await service.watchCategories().first;
    expect(categories, hasLength(1));
    expect(categories.single.id, id);
  });

  test(
    'إضافة المصروف تتحقق من النوع والمبلغ والتاريخ وتسجل صاحب العملية',
    () async {
      final category = await service.addCategory('قرطاسية');

      await expectLater(
        service.addExpense(categoryId: category, amount: 0, date: '2026-05-14'),
        throwsFormatException,
      );
      await expectLater(
        service.addExpense(
          categoryId: category,
          amount: 20,
          date: '2026-02-30',
        ),
        throwsFormatException,
      );
      await expectLater(
        service.addExpense(
          categoryId: 'missing',
          amount: 20,
          date: '2026-05-14',
        ),
        throwsStateError,
      );

      final id = await service.addExpense(
        categoryId: category,
        amount: 2750,
        date: '2026-05-14',
        note: '  أدوات للصف  ',
      );
      final expense = await (env.db.select(
        env.db.expenses,
      )..where((row) => row.id.equals(id))).getSingle();

      expect(expense.amount, 2750);
      expect(expense.date, '2026-05-14');
      expect(expense.note, 'أدوات للصف');
      expect(expense.createdBy, 'u1');
      expect(expense.workerId, isNull);
    },
  );

  test(
    'ملخص الشهر والسنة واستعلام الشهر تستعمل المصاريف غير المحذوفة',
    () async {
      final category = await service.addCategory('صيانة');
      final mayFirst = await service.addExpense(
        categoryId: category,
        amount: 100,
        date: '2026-05-01',
      );
      await service.addExpense(
        categoryId: category,
        amount: 200,
        date: '2026-05-31',
      );
      await service.addExpense(
        categoryId: category,
        amount: 300,
        date: '2026-06-01',
      );
      await service.addExpense(
        categoryId: category,
        amount: 400,
        date: '2025-12-31',
      );

      final totals = await service.watchTotals(year: 2026, month: 5).first;
      final may = await service.watchMonth(year: 2026, month: 5).first;
      expect(totals.month, '2026-05');
      expect(totals.monthTotal, 300);
      expect(totals.yearTotal, 600);
      expect(totals.monthCount, 2);
      expect(may.map((item) => item.date), ['2026-05-31', '2026-05-01']);

      await service.deleteExpense(mayFirst);
      final afterDelete = await service.watchTotals(year: 2026, month: 5).first;
      final deleted = await (env.db.select(
        env.db.expenses,
      )..where((row) => row.id.equals(mayFirst))).getSingle();
      expect(afterDelete.monthTotal, 200);
      expect(afterDelete.yearTotal, 500);
      expect(afterDelete.monthCount, 1);
      expect(deleted.deletedAt, isNotNull);
    },
  );

  test('لا يُحذف نوع له مصروف قائم، ويمكن حذفه بعد حذفه ناعماً', () async {
    final category = await service.addCategory('نظافة');
    final id = await service.addExpense(
      categoryId: category,
      amount: 300,
      date: '2026-05-14',
    );

    await expectLater(service.deleteCategory(category), throwsStateError);
    await service.deleteExpense(id);
    await service.deleteCategory(category);

    expect(await service.watchCategories().first, isEmpty);
    expect(await service.watchMonth(year: 2026, month: 5).first, isEmpty);
  });

  test('أنواع الأجور لا تقبل مصروفاً عاماً بلا عامل مرتبط', () async {
    final category = await service.addCategory('أجور العمال', isWages: true);
    await expectLater(
      service.addExpense(
        categoryId: category,
        amount: 1000,
        date: '2026-05-14',
      ),
      throwsStateError,
    );
  });
}
