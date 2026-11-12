import 'package:drift/drift.dart';

import '../data/local/app_database.dart';

/// حقوق تسجيل تلميذ في فترة، بما دُفع منها.
class FeeItem {
  const FeeItem({
    required this.studentId,
    required this.name,
    required this.parentPhone,
    required this.periodKey,
    required this.amount,
    required this.paid,
  });

  final String studentId;
  final String name;
  final String parentPhone;
  final String periodKey;
  final int amount;

  /// مجموع ما دُفع عنها.
  final int paid;

  int get remaining => amount - paid < 0 ? 0 : amount - paid;
  bool get isSettled => remaining == 0;
}

/// تقرير حقوق التسجيل لفترة: كل التلاميذ بحالتهم، وإجماليا المطلوب والمحصَّل.
class FeeReport {
  const FeeReport(this.items);

  final List<FeeItem> items;

  bool get isEmpty => items.isEmpty;
  int get totalAmount => items.fold(0, (sum, i) => sum + i.amount);
  int get totalPaid => items.fold(0, (sum, i) => sum + i.paid);
  int get totalRemaining => items.fold(0, (sum, i) => sum + i.remaining);
  int get unpaidCount => items.where((i) => !i.isSettled).length;
}

/// حقوق التسجيل: مرة واحدة لكل تلميذ في الفترة (سنة أو فصل)، مهما كان عدد
/// موادّه. تقرأ الحقوق المسجَّلة وما دُفع عنها باستعلام مجمّع واحد.
class RegistrationFeeReports {
  RegistrationFeeReports(this.db);

  final AppDatabase db;

  /// الفترات التي لها حقوق مسجَّلة، الأحدث أولاً.
  Future<List<String>> periods() async {
    final rows = await db
        .customSelect(
          'SELECT DISTINCT period_key FROM registration_fees '
          'WHERE deleted_at IS NULL ORDER BY period_key DESC',
          readsFrom: {db.registrationFees},
        )
        .get();
    return [for (final r in rows) r.read<String>('period_key')];
  }

  /// تقرير [periodKey]، ويتحدث مع كل دفعة أو تغيير في الحقوق. [unpaidOnly]
  /// يخفي المسدَّدين، و[query] يبحث بالاسم أو هاتف الوليّ.
  Stream<FeeReport> watch({
    required String periodKey,
    bool unpaidOnly = false,
    String query = '',
  }) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {db.registrationFees, db.payments, db.students},
        )
        .watch()
        .asyncMap(
          (_) =>
              load(periodKey: periodKey, unpaidOnly: unpaidOnly, query: query),
        );
  }

  Future<FeeReport> load({
    required String periodKey,
    bool unpaidOnly = false,
    String query = '',
  }) async {
    final rows = await db
        .customSelect(
          'SELECT f.student_id, f.amount, s.first_name, s.last_name, '
          's.parent_phone, COALESCE((SELECT SUM(p.amount) FROM payments p '
          "WHERE p.student_id = f.student_id AND p.type = 'registration' "
          'AND p.period_key = f.period_key AND p.deleted_at IS NULL), 0) '
          'AS paid FROM registration_fees f '
          'JOIN students s ON s.id = f.student_id AND s.deleted_at IS NULL '
          'WHERE f.period_key = ? AND f.deleted_at IS NULL '
          'ORDER BY s.last_name, s.first_name, s.id',
          variables: [Variable<String>(periodKey)],
          readsFrom: {db.registrationFees, db.payments, db.students},
        )
        .get();
    final needle = query.trim();
    final items = <FeeItem>[];
    for (final row in rows) {
      final name =
          '${row.read<String>('first_name')} ${row.read<String>('last_name')}';
      final phone = row.read<String>('parent_phone');
      if (needle.isNotEmpty &&
          !name.contains(needle) &&
          !phone.contains(needle)) {
        continue;
      }
      final item = FeeItem(
        studentId: row.read<String>('student_id'),
        name: name,
        parentPhone: phone,
        periodKey: periodKey,
        amount: row.read<int>('amount'),
        paid: row.read<int>('paid'),
      );
      if (unpaidOnly && item.isSettled) continue;
      items.add(item);
    }
    return FeeReport(items);
  }
}
