import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import 'date_key.dart';
import 'enums.dart';

/// المبالغ المقبوضة في الشهر حسب نوع الوصل.
class MonthlyPaymentTotal {
  const MonthlyPaymentTotal({
    required this.type,
    required this.amount,
    required this.count,
  });

  final PaymentType type;
  final int amount;
  final int count;
}

/// المصاريف في الشهر حسب النوع.
class MonthlyExpenseTotal {
  const MonthlyExpenseTotal({
    required this.categoryId,
    required this.categoryName,
    required this.isWages,
    required this.amount,
    required this.count,
  });

  final String categoryId;
  final String categoryName;
  final bool isWages;
  final int amount;
  final int count;
}

/// خلاصة الشهر المالي.
class MonthlyFinanceReport {
  MonthlyFinanceReport({
    required this.month,
    required List<MonthlyPaymentTotal> payments,
    required List<MonthlyExpenseTotal> expenses,
    required this.teacherPayoutAmount,
    required this.teacherPayoutCount,
  }) : payments = List.unmodifiable(payments),
       expenses = List.unmodifiable(expenses);

  /// الشهر بصيغة `YYYY-MM`.
  final String month;
  final List<MonthlyPaymentTotal> payments;
  final List<MonthlyExpenseTotal> expenses;
  final int teacherPayoutAmount;
  final int teacherPayoutCount;

  int get receivedAmount => payments.fold(0, (sum, item) => sum + item.amount);
  int get receiptCount => payments.fold(0, (sum, item) => sum + item.count);
  int get expenseAmount => expenses.fold(0, (sum, item) => sum + item.amount);
  int get expenseCount => expenses.fold(0, (sum, item) => sum + item.count);
  int get outgoingAmount => expenseAmount + teacherPayoutAmount;
  int get netAmount => receivedAmount - outgoingAmount;
}

/// التقرير المالي المحلي للشهر. المقبوضات حسب وقت تسجيل الوصل، والمصاريف
/// حسب تاريخها، وخلاص الأساتذة حسب وقت تسليم المال.
class MonthlyFinanceReports {
  MonthlyFinanceReports(this.db);

  final AppDatabase db;

  Stream<MonthlyFinanceReport> watch(String month) {
    final range = _monthRange(month);
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            db.payments,
            db.expenses,
            db.expenseCategories,
            db.teacherPayouts,
          },
        )
        .watch()
        .asyncMap((_) => _load(month, range));
  }

  Future<MonthlyFinanceReport> load(String month) async {
    return _load(month, _monthRange(month));
  }

  Future<MonthlyFinanceReport> _load(
    String month,
    ({int from, int to, String start, String end}) range,
  ) async {
    final bounds = range;
    final paymentRows = await db
        .customSelect(
          'SELECT type, COUNT(*) AS count, COALESCE(SUM(amount), 0) AS amount '
          'FROM payments WHERE deleted_at IS NULL '
          'AND created_at >= ? AND created_at < ? GROUP BY type',
          variables: [Variable<int>(bounds.from), Variable<int>(bounds.to)],
          readsFrom: {db.payments},
        )
        .get();
    final payments = <MonthlyPaymentTotal>[];
    for (final row in paymentRows) {
      final PaymentType type;
      try {
        type = PaymentType.fromCode(row.read<String>('type'));
      } on ArgumentError {
        continue;
      }
      payments.add(
        MonthlyPaymentTotal(
          type: type,
          amount: row.read<int>('amount'),
          count: row.read<int>('count'),
        ),
      );
    }
    payments.sort((a, b) => a.type.index.compareTo(b.type.index));

    final expenseRows = await db
        .customSelect(
          'SELECT c.id AS category_id, c.name AS category_name, '
          'c.is_wages AS is_wages, COUNT(*) AS count, '
          'COALESCE(SUM(e.amount), 0) AS amount '
          'FROM expenses e JOIN expense_categories c ON c.id = e.category_id '
          'WHERE e.deleted_at IS NULL AND e.date >= ? AND e.date < ? '
          'GROUP BY c.id, c.name, c.is_wages '
          'ORDER BY amount DESC, c.name, c.id',
          variables: [
            Variable<String>(bounds.start),
            Variable<String>(bounds.end),
          ],
          readsFrom: {db.expenses, db.expenseCategories},
        )
        .get();
    final expenses = [
      for (final row in expenseRows)
        MonthlyExpenseTotal(
          categoryId: row.read<String>('category_id'),
          categoryName: row.read<String>('category_name'),
          isWages: row.read<bool>('is_wages'),
          amount: row.read<int>('amount'),
          count: row.read<int>('count'),
        ),
    ];

    final payoutRow = await db
        .customSelect(
          'SELECT COUNT(*) AS count, COALESCE(SUM(amount), 0) AS amount '
          'FROM teacher_payouts WHERE deleted_at IS NULL '
          'AND paid_at >= ? AND paid_at < ?',
          variables: [Variable<int>(bounds.from), Variable<int>(bounds.to)],
          readsFrom: {db.teacherPayouts},
        )
        .getSingle();

    return MonthlyFinanceReport(
      month: month,
      payments: payments,
      expenses: expenses,
      teacherPayoutAmount: payoutRow.read<int>('amount'),
      teacherPayoutCount: payoutRow.read<int>('count'),
    );
  }

  ({int from, int to, String start, String end}) _monthRange(String value) {
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(value)) {
      throw const FormatException('اكتب الشهر بصيغة YYYY-MM');
    }
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(5, 7));
    if (year < 1 || year > 9998 || month < 1 || month > 12) {
      throw const FormatException('الشهر غير صالح');
    }
    final startDate = DateTime(year, month);
    final start = DateKey.of(startDate);
    final next = DateKey.shiftMonth(start, 1);
    final endDate = DateTime(year, month + 1);
    return (
      from: startDate.millisecondsSinceEpoch,
      to: endDate.millisecondsSinceEpoch,
      start: start,
      end: next,
    );
  }
}
