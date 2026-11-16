import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'catalog_service.dart';
import 'date_key.dart';
import 'stable_id.dart';

/// من له الدين على صاحب المدرسة: أستاذ أو عامل (السائق عامل).
enum StaffKind {
  teacher('teacher', 'أستاذ'),
  worker('worker', 'عامل');

  const StaffKind(this.code, this.label);

  /// القيمة المخزَّنة في القاعدة المحلية وفي الخادم.
  final String code;

  /// النص العربي الظاهر للمستخدم.
  final String label;

  /// يحوّل القيمة المخزَّنة إلى النوع، ويرمي [ArgumentError] إن كانت مجهولة.
  static StaffKind fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(code, 'code', 'قيمة StaffKind غير معروفة');
  }
}

/// نوع سجل في دفتر الديون.
enum StaffDebtKind {
  debt('debt', 'دين'),
  payment('payment', 'تسديد');

  const StaffDebtKind(this.code, this.label);

  final String code;
  final String label;

  static StaffDebtKind fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(code, 'code', 'قيمة StaffDebtKind غير معروفة');
  }
}

/// دفتر دين أستاذ أو عامل: سجلاته الحية الأحدث أولاً، ومتبقّيه.
class StaffDebtSummary {
  const StaffDebtSummary({required this.entries});

  final List<StaffDebtRow> entries;

  int get debts => _sum(StaffDebtKind.debt);

  int get payments => _sum(StaffDebtKind.payment);

  /// ما بقي على المدرسة له (الديون ناقص التسديدات).
  int get balance => debts - payments;

  int _sum(StaffDebtKind kind) => entries
      .where((e) => e.kind == kind.code)
      .fold(0, (sum, e) => sum + e.amount);
}

/// أستاذ أو عامل ما زال له دين متبقٍّ.
class StaffDebtBalance {
  const StaffDebtBalance({
    required this.kind,
    required this.staffId,
    required this.name,
    required this.balance,
  });

  final StaffKind kind;
  final String staffId;
  final String name;
  final int balance;
}

/// ديون صاحب المدرسة لأساتذته وعماله، وتسديدها.
///
/// تُدخَل ديون ما قبل استعمال النظام (أجور وخلاصات لم تُسلَّم) كسجلات «دين»، ثم
/// تُسدَّد كلها أو بعضها. كل تسديد يُنشئ مصروفاً مقابلاً (نوع محجوز) في المصاريف،
/// فيدخل في التقرير الشهري والإحصاءات كمبلغ خرج من الصندوق في تاريخ التسديد،
/// ويُحذف معه إن حُذف التسديد. كل كتابة تمر عبر [SyncWriter].
class StaffDebtService {
  StaffDebtService(this.db, this.writer, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final SyncWriter writer;
  final DateTime Function() _clock;

  /// أكبر مبلغ مقبول في سجل واحد (يصدّ خطأ الإدخال بأصفار زائدة).
  static const int maxAmount = 1000000000;

  static const int _maxNote = 200;

  static const String categoryName = 'تسديد ديون الأساتذة والعمال';

  /// معرّف نوع المصروف المحجوز لتسديد الديون.
  static String get categoryId => StableId.staffDebtCategory();

  // ---------------------------------------------------------------------------
  // القراءة
  // ---------------------------------------------------------------------------

  SimpleSelectStatement<$StaffDebtsTable, StaffDebtRow> _entries(
    StaffKind kind,
    String staffId,
  ) => db.select(db.staffDebts)
    ..where(
      (d) =>
          d.staffType.equals(kind.code) &
          d.staffId.equals(staffId) &
          d.deletedAt.isNull(),
    )
    ..orderBy([
      (d) => OrderingTerm.desc(d.date),
      (d) => OrderingTerm.desc(d.createdAt),
      (d) => OrderingTerm.desc(d.id),
    ]);

  /// دفتر [staffId] لحظياً.
  Stream<StaffDebtSummary> watch(StaffKind kind, String staffId) => _entries(
    kind,
    staffId,
  ).watch().map((rows) => StaffDebtSummary(entries: rows));

  Future<StaffDebtSummary> summary(StaffKind kind, String staffId) async =>
      StaffDebtSummary(entries: await _entries(kind, staffId).get());

  /// استعلام المتبقّين: أستاذ أو عامل حي له رصيد موجب، بالأكبر أولاً.
  Selectable<QueryRow> _outstandingQuery() => db.customSelect(
    'SELECT d.staff_type, d.staff_id, '
    "SUM(CASE d.kind WHEN 'debt' THEN d.amount ELSE -d.amount END) "
    'AS balance, '
    'COALESCE(t.name, w.name) AS staff_name '
    'FROM staff_debts d '
    "LEFT JOIN teachers t ON d.staff_type = 'teacher' "
    'AND t.id = d.staff_id AND t.deleted_at IS NULL '
    "LEFT JOIN workers w ON d.staff_type = 'worker' "
    'AND w.id = d.staff_id AND w.deleted_at IS NULL '
    'WHERE d.deleted_at IS NULL '
    'GROUP BY d.staff_type, d.staff_id '
    'HAVING balance > 0 AND staff_name IS NOT NULL '
    'ORDER BY balance DESC, staff_name, d.staff_id',
    readsFrom: {db.staffDebts, db.teachers, db.workers},
  );

  static List<StaffDebtBalance> _balances(List<QueryRow> rows) => [
    for (final row in rows)
      StaffDebtBalance(
        kind: StaffKind.fromCode(row.read<String>('staff_type')),
        staffId: row.read<String>('staff_id'),
        name: row.read<String>('staff_name'),
        balance: row.read<int>('balance'),
      ),
  ];

  /// كل من له دين متبقٍّ (أساتذة وعمال أحياء) بالأكبر أولاً، ولحظياً.
  Stream<List<StaffDebtBalance>> watchOutstanding() =>
      _outstandingQuery().watch().map(_balances);

  Future<List<StaffDebtBalance>> outstanding() async =>
      _balances(await _outstandingQuery().get());

  // ---------------------------------------------------------------------------
  // الكتابة
  // ---------------------------------------------------------------------------

  /// يضيف ديناً للأستاذ أو العامل. [date] تاريخ استحقاقه (ليس في المستقبل).
  Future<String> addDebt({
    required StaffKind kind,
    required String staffId,
    required int amount,
    required String date,
    String note = '',
  }) async {
    _validate(amount: amount, date: date, note: note);
    return db.transaction(() async {
      await _staffName(kind, staffId);
      final id = writer.newId();
      await _save(id, kind, staffId, StaffDebtKind.debt, amount, date, note);
      return id;
    });
  }

  /// يسجّل تسديد [amount] من الدين: لا يزيد عن المتبقي، وينشئ مصروفه المقابل.
  Future<String> pay({
    required StaffKind kind,
    required String staffId,
    required int amount,
    required String date,
    String note = '',
  }) async {
    _validate(amount: amount, date: date, note: note);
    return db.transaction(() async {
      final name = await _staffName(kind, staffId);
      final balance = (await summary(kind, staffId)).balance;
      if (amount > balance) {
        throw ValidationException.field(
          'amount',
          balance <= 0
              ? 'لا دين متبقٍّ للتسديد'
              : 'المبلغ أكبر من الدين المتبقي ($balance دج)',
        );
      }
      final id = writer.newId();
      final expenseId = await _saveExpense(
        paymentId: id,
        kind: kind,
        staffId: staffId,
        name: name,
        amount: amount,
        date: date,
        note: note,
      );
      await _save(
        id,
        kind,
        staffId,
        StaffDebtKind.payment,
        amount,
        date,
        note,
        expenseId: expenseId,
      );
      return id;
    });
  }

  /// يحذف سجلاً أُدخل خطأً (وتسديداً بمصروفه). لا يُحذف دين يجعل المتبقي سالباً:
  /// احذف تسديداته أولاً.
  Future<void> remove(String entryId) {
    return db.transaction(() async {
      final row =
          await (db.select(db.staffDebts)
                ..where((d) => d.id.equals(entryId) & d.deletedAt.isNull()))
              .getSingleOrNull();
      if (row == null) return;
      if (row.kind == StaffDebtKind.debt.code) {
        final summary = await this.summary(
          StaffKind.fromCode(row.staffType),
          row.staffId,
        );
        if (summary.balance - row.amount < 0) {
          throw ValidationException.field(
            'amount',
            'سُدِّد جزء من هذا الدين: احذف التسديدات أولاً',
          );
        }
      }
      await writer.softDelete(db.staffDebts, key: {'id': entryId});
      final expenseId = row.expenseId;
      if (expenseId != null) {
        await writer.softDelete(db.expenses, key: {'id': expenseId});
      }
    });
  }

  // ---------------------------------------------------------------------------
  // داخلي
  // ---------------------------------------------------------------------------

  void _validate({
    required int amount,
    required String date,
    required String note,
  }) {
    if (amount <= 0) {
      throw ValidationException.field(
        'amount',
        'المبلغ يجب أن يكون أكبر من صفر',
      );
    }
    if (amount > maxAmount) {
      throw ValidationException.field('amount', 'المبلغ كبير جداً');
    }
    final valid = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date);
    if (!valid || DateKey.of(DateKey.parse(date)) != date) {
      throw ValidationException.field('date', 'اختر تاريخاً صحيحاً');
    }
    if (date.compareTo(DateKey.of(_clock())) > 0) {
      throw ValidationException.field('date', 'التاريخ لا يكون في المستقبل');
    }
    if (note.trim().length > _maxNote) {
      throw ValidationException.field(
        'note',
        'الملاحظة أطول من $_maxNote حرفاً',
      );
    }
  }

  /// اسم الأستاذ أو العامل الحي، ويرمي إن لم يوجد.
  Future<String> _staffName(StaffKind kind, String staffId) async {
    final name = switch (kind) {
      StaffKind.teacher =>
        (await (db.select(db.teachers)
                  ..where((t) => t.id.equals(staffId) & t.deletedAt.isNull()))
                .getSingleOrNull())
            ?.name,
      StaffKind.worker =>
        (await (db.select(db.workers)
                  ..where((w) => w.id.equals(staffId) & w.deletedAt.isNull()))
                .getSingleOrNull())
            ?.name,
    };
    if (name == null) {
      throw ValidationException.field(
        'staff',
        kind == StaffKind.teacher
            ? 'الأستاذ غير موجود أو محذوف'
            : 'العامل غير موجود أو محذوف',
      );
    }
    return name;
  }

  Future<void> _save(
    String id,
    StaffKind kind,
    String staffId,
    StaffDebtKind entryKind,
    int amount,
    String date,
    String note, {
    String? expenseId,
  }) {
    final stamp = writer.now();
    return writer.save(
      db.staffDebts,
      StaffDebtsCompanion.insert(
        id: id,
        createdAt: stamp,
        updatedAt: stamp,
        deletedAt: const Value(null),
        staffType: kind.code,
        staffId: staffId,
        kind: entryKind.code,
        amount: amount,
        date: date,
        note: Value(note.trim()),
        createdBy: writer.actor().userId,
        expenseId: Value(expenseId),
      ),
      key: {'id': id},
    );
  }

  /// ينشئ المصروف المقابل لتسديد (ونوعه المحجوز إن لم يوجد) ويعيد معرّفه.
  Future<String> _saveExpense({
    required String paymentId,
    required StaffKind kind,
    required String staffId,
    required String name,
    required int amount,
    required String date,
    required String note,
  }) async {
    final stamp = writer.now();
    final category = await (db.select(
      db.expenseCategories,
    )..where((c) => c.id.equals(categoryId))).getSingleOrNull();
    if (category == null || category.deletedAt != null) {
      await writer.save(
        db.expenseCategories,
        ExpenseCategoriesCompanion.insert(
          id: categoryId,
          createdAt: stamp,
          updatedAt: stamp,
          deletedAt: const Value(null),
          name: categoryName,
        ),
        key: {'id': categoryId},
      );
    }
    final id = StableId.staffDebtExpense(paymentId);
    final extra = note.trim();
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
        note: Value(
          'تسديد دين ${kind.label} $name${extra.isEmpty ? '' : ' — $extra'}',
        ),
        invoicePhotoUrl: const Value(null),
        invoicePhotoLocalPath: const Value(null),
        workerId: Value(kind == StaffKind.worker ? staffId : null),
        createdBy: writer.actor().userId,
      ),
      key: {'id': id},
    );
    return id;
  }
}
