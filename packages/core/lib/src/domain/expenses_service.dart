import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'date_key.dart';
import 'stable_id.dart';

/// نوع مصروف متاح للاختيار.
class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.isWages,
  });

  final String id;
  final String name;
  final bool isWages;
}

/// مصروف مع اسم نوعه وحقول عرض الإيصال.
class ExpenseItem {
  const ExpenseItem({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.amount,
    required this.date,
    required this.note,
    required this.createdBy,
    this.invoicePhotoUrl,
    this.invoicePhotoLocalPath,
    this.workerId,
  });

  final String id;
  final String categoryId;
  final String categoryName;
  final int amount;
  final String date;
  final String note;
  final String createdBy;
  final String? invoicePhotoUrl;
  final String? invoicePhotoLocalPath;
  final String? workerId;
}

/// مجموع مصاريف شهر وسنته وعدد سجلات الشهر.
class ExpenseTotals {
  const ExpenseTotals({
    required this.month,
    required this.monthTotal,
    required this.yearTotal,
    required this.monthCount,
  });

  final String month;
  final int monthTotal;
  final int yearTotal;
  final int monthCount;
}

/// أنواع المصاريف وسجلها ومجاميعها.
///
/// كل كتابة تمر عبر [SyncWriter] ليبقى السجل وطابور المزامنة متطابقين.
class ExpenseService {
  ExpenseService(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  /// الأنواع غير المحذوفة، مرتبة بالاسم.
  Stream<List<ExpenseCategory>> watchCategories() =>
      (db.select(db.expenseCategories)
            ..where((category) => category.deletedAt.isNull())
            ..orderBy([(category) => OrderingTerm.asc(category.name)]))
          .watch()
          .map(
            (rows) => [
              for (final row in rows)
                ExpenseCategory(
                  id: row.id,
                  name: row.name,
                  isWages: row.isWages,
                ),
            ],
          );

  /// يسجّل نوعاً ثابت المعرّف كي لا تنشئ الأجهزة نوعاً مكرراً عند العمل دون
  /// إنترنت. أسماء الأنواع غير حساسة لحالة الأحرف اللاتينية أو المسافات.
  Future<String> addCategory(String name, {bool isWages = false}) async {
    final cleanName = _categoryName(name);
    await _ensureUniqueCategoryName(cleanName);
    final id = StableId.expenseCategory(cleanName.toLowerCase());
    final stamp = writer.now();
    await writer.save(
      db.expenseCategories,
      ExpenseCategoriesCompanion.insert(
        id: id,
        createdAt: stamp,
        updatedAt: stamp,
        deletedAt: const Value(null),
        name: cleanName,
        isWages: Value(isWages),
      ),
      key: {'id': id},
    );
    return id;
  }

  /// يعيد تسمية نوع من دون تغيير معرّفه، فتحافظ المصروفات السابقة على ربطها.
  Future<void> renameCategory(String id, String name) async {
    final cleanName = _categoryName(name);
    await _ensureUniqueCategoryName(cleanName, exceptId: id);
    final category = await _category(id);
    if (category == null) throw StateError('نوع المصروف غير موجود');
    await writer.patch(
      db.expenseCategories,
      key: {'id': id},
      values: {'name': cleanName},
    );
  }

  /// حذف ناعم لنوع لم يُستخدم في مصروف قائم.
  Future<void> deleteCategory(String id) async {
    final category = await _category(id);
    if (category == null) return;
    final expenses =
        await (db.select(db.expenses)
              ..where(
                (expense) =>
                    expense.categoryId.equals(id) & expense.deletedAt.isNull(),
              )
              ..limit(1))
            .get();
    if (expenses.isNotEmpty) {
      throw StateError('لا يمكن حذف نوع مرتبط بمصاريف مسجلة');
    }
    await writer.softDelete(db.expenseCategories, key: {'id': id});
  }

  /// إضافة مصروف بالدينار؛ يقبل ربط العامل فقط إذا كان النوع نوع أجور.
  Future<String> addExpense({
    required String categoryId,
    required int amount,
    required String date,
    String note = '',
    String? workerId,
  }) async {
    if (amount <= 0) {
      throw const FormatException('المبلغ يجب أن يكون أكبر من صفر');
    }
    _validateDate(date);
    final category = await _category(categoryId);
    if (category == null) throw StateError('اختر نوع مصروف متاحاً');
    if (category.isWages != (workerId != null)) {
      throw StateError(
        category.isWages
            ? 'نوع أجور العمال يحتاج إلى اختيار العامل'
            : 'لا يمكن ربط عامل بنوع مصروف عادي',
      );
    }
    if (workerId != null) {
      final worker =
          await (db.select(db.workers)..where(
                (row) => row.id.equals(workerId) & row.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (worker == null) throw StateError('العامل غير موجود أو محذوف');
    }

    final id = writer.newId();
    final stamp = writer.now();
    await writer.save(
      db.expenses,
      ExpensesCompanion.insert(
        id: id,
        createdAt: stamp,
        updatedAt: stamp,
        deletedAt: const Value(null),
        categoryId: categoryId,
        amount: amount,
        date: date,
        note: Value(note.trim()),
        invoicePhotoUrl: const Value(null),
        invoicePhotoLocalPath: const Value(null),
        workerId: Value(workerId),
        createdBy: writer.actor().userId,
      ),
      key: {'id': id},
    );
    return id;
  }

  /// تعديل مصروف عادي مع إبقاء بيانات الإنشاء والإيصال.
  Future<void> updateExpense({
    required String id,
    required String categoryId,
    required int amount,
    required String date,
    required String note,
  }) async {
    if (amount <= 0) {
      throw const FormatException('المبلغ يجب أن يكون أكبر من صفر');
    }
    _validateDate(date);
    final category = await _category(categoryId);
    if (category == null || category.isWages) {
      throw StateError('اختر نوع مصروف عادي متاحاً');
    }
    final expense =
        await (db.select(db.expenses)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (expense == null) throw StateError('المصروف غير موجود');
    if (expense.workerId != null) {
      throw StateError('تُعدّل أجور العمال من كشف العامل');
    }
    await writer.patch(
      db.expenses,
      key: {'id': id},
      values: {
        'category_id': categoryId,
        'amount': amount,
        'date': date,
        'note': note.trim(),
      },
    );
  }

  /// حذف ناعم يحفظ الأثر المالي في سجل العمليات.
  Future<void> deleteExpense(String id) async {
    final expense =
        await (db.select(db.expenses)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (expense == null) return;
    if (expense.workerId != null) {
      throw StateError('تُدار أجور العمال من كشف العامل');
    }
    await writer.softDelete(db.expenses, key: {'id': id});
  }

  /// سجلات شهر واحد، الأحدث أولاً، مع اسم النوع.
  Stream<List<ExpenseItem>> watchMonth({
    required int year,
    required int month,
  }) {
    final key = _monthKey(year, month);
    return db
        .customSelect(
          'SELECT e.id, e.category_id, c.name AS category_name, e.amount, '
          'e.date, e.note, e.created_by, e.invoice_photo_url, '
          'e.invoice_photo_local_path, e.worker_id '
          'FROM expenses e JOIN expense_categories c '
          'ON c.id = e.category_id '
          'WHERE e.deleted_at IS NULL AND c.deleted_at IS NULL '
          'AND e.date >= ? AND e.date < ? '
          'ORDER BY e.date DESC, e.created_at DESC, e.id LIMIT 200',
          variables: [
            Variable<String>(key),
            Variable<String>(DateKey.shiftMonth(key, 1)),
          ],
          readsFrom: {db.expenses, db.expenseCategories},
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              ExpenseItem(
                id: row.read<String>('id'),
                categoryId: row.read<String>('category_id'),
                categoryName: row.read<String>('category_name'),
                amount: row.read<int>('amount'),
                date: row.read<String>('date'),
                note: row.read<String>('note'),
                createdBy: row.read<String>('created_by'),
                invoicePhotoUrl: row.read<String?>('invoice_photo_url'),
                invoicePhotoLocalPath: row.read<String?>(
                  'invoice_photo_local_path',
                ),
                workerId: row.read<String?>('worker_id'),
              ),
          ],
        );
  }

  /// إجمالي الشهر والسنة باستعلام SQL مجمّع واحد.
  Stream<ExpenseTotals> watchTotals({required int year, required int month}) {
    final key = _monthKey(year, month);
    return db
        .customSelect(
          'SELECT '
          'COALESCE(SUM(CASE WHEN date >= ? AND date < ? '
          'THEN amount ELSE 0 END), 0) AS month_total, '
          'COALESCE(SUM(CASE WHEN date >= ? AND date < ? '
          'THEN amount ELSE 0 END), 0) AS year_total, '
          'COUNT(CASE WHEN date >= ? AND date < ? THEN 1 END) AS month_count '
          'FROM expenses WHERE deleted_at IS NULL',
          variables: [
            Variable<String>(key),
            Variable<String>(DateKey.shiftMonth(key, 1)),
            Variable<String>('${year.toString().padLeft(4, '0')}-01-01'),
            Variable<String>('${(year + 1).toString().padLeft(4, '0')}-01-01'),
            Variable<String>(key),
            Variable<String>(DateKey.shiftMonth(key, 1)),
          ],
          readsFrom: {db.expenses},
        )
        .watch()
        .map((rows) {
          final row = rows.single;
          return ExpenseTotals(
            month: key,
            monthTotal: row.read<int>('month_total'),
            yearTotal: row.read<int>('year_total'),
            monthCount: row.read<int>('month_count'),
          );
        });
  }

  Future<ExpenseCategoryRow?> _category(String id) =>
      (db.select(db.expenseCategories)..where(
            (category) => category.id.equals(id) & category.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  Future<void> _ensureUniqueCategoryName(
    String name, {
    String? exceptId,
  }) async {
    final normalized = name.toLowerCase();
    final rows = await (db.select(
      db.expenseCategories,
    )..where((category) => category.deletedAt.isNull())).get();
    if (rows.any(
      (category) =>
          category.id != exceptId &&
          category.name.trim().toLowerCase() == normalized,
    )) {
      throw StateError('اسم نوع المصروف مسجل من قبل');
    }
  }

  String _categoryName(String value) {
    final name = value.trim();
    if (name.isEmpty) throw const FormatException('اكتب اسم نوع المصروف');
    if (name.length > 60) {
      throw const FormatException('اسم النوع أطول من 60 حرفاً');
    }
    return name;
  }

  void _validateDate(String value) {
    try {
      if (DateKey.of(DateKey.parse(value)) != value) {
        throw FormatException('تاريخ غير صالح', value);
      }
    } on FormatException {
      throw const FormatException('اختر تاريخاً صحيحاً');
    }
  }

  String _monthKey(int year, int month) {
    if (year < 1 || year > 9998 || month < 1 || month > 12) {
      throw ArgumentError('السنة أو الشهر غير صالح');
    }
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}';
  }
}
