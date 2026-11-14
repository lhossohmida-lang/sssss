import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'date_key.dart';
import 'enums.dart';
import 'stable_id.dart';

/// برنامج عمل العامل الأسبوعي: لكل يوم «يوم كامل» أو «نصف يوم» أو «لا يعمل».
class WorkerSchedule {
  const WorkerSchedule(this._days);

  /// يقرأ البرنامج من JSON بصيغة `{"1": "full", "6": "half"}`
  /// (1 = الاثنين … 7 = الأحد). اليوم غير المذكور «لا يعمل».
  factory WorkerSchedule.fromJson(String json) {
    final decoded = jsonDecode(json.isEmpty ? '{}' : json);
    if (decoded is! Map) {
      throw const FormatException('برنامج العمل يجب أن يكون كائن JSON');
    }
    final days = <int, WorkDayKind>{};
    for (final entry in decoded.entries) {
      final weekday = int.tryParse(entry.key.toString());
      if (weekday == null || weekday < 1 || weekday > 7) {
        throw FormatException('يوم غير صالح في برنامج العمل', entry.key);
      }
      days[weekday] = WorkDayKind.fromCode(entry.value.toString());
    }
    return WorkerSchedule(days);
  }

  final Map<int, WorkDayKind> _days;

  /// برنامج يوم الأسبوع [weekday] (1 = الاثنين … 7 = الأحد).
  WorkDayKind kindOn(int weekday) => _days[weekday] ?? WorkDayKind.off;

  String toJson() => jsonEncode({
    for (final entry in _days.entries)
      if (entry.value != WorkDayKind.off) '${entry.key}': entry.value.code,
  });
}

/// يوم واحد في كشف حضور وأجر العامل.
class WorkerDay {
  const WorkerDay({
    required this.date,
    required this.scheduled,
    required this.present,
    required this.paidKind,
    required this.wage,
    required this.lateMinutes,
    required this.overridden,
    this.checkIn,
    this.checkOut,
  });

  final String date;

  /// ما يقوله برنامج العمل لهذا اليوم.
  final WorkDayKind scheduled;

  /// هل مسح العامل دخوله هذا اليوم؟
  final bool present;

  /// ما يُدفع عنه فعلاً: كامل / نصف / لا شيء.
  final WorkDayKind paidKind;

  /// أجر هذا اليوم بالدينار.
  final int wage;

  /// دقائق التأخر، للعرض فقط ولا أثر مالي لها.
  final int lateMinutes;

  /// هل عدّل المدير هذا اليوم يدوياً؟
  final bool overridden;

  final int? checkIn;
  final int? checkOut;

  /// يوم عمل مبرمج لم يحضره العامل (ولم يعدّله المدير).
  bool get isAbsence => scheduled != WorkDayKind.off && !present && !overridden;
}

/// كشف شهر لعامل.
class WorkerMonth {
  const WorkerMonth({required this.workerId, required this.days});

  final String workerId;
  final List<WorkerDay> days;

  /// مجموع أجر الشهر.
  int get total => days.fold(0, (sum, day) => sum + day.wage);

  int get fullDays => days.where((d) => d.paidKind == WorkDayKind.full).length;

  int get halfDays => days.where((d) => d.paidKind == WorkDayKind.half).length;

  /// أيام الغياب حتى [today] (ما بعده لم يحن بعد).
  int absencesUntil(String today) =>
      days.where((d) => d.isAbsence && d.date.compareTo(today) <= 0).length;

  int get totalLateMinutes => days.fold(0, (sum, day) => sum + day.lateMinutes);
}

/// قواعد أجر اليوم (دوال صافية).
abstract final class WageRules {
  /// ما يُدفع عن اليوم.
  ///
  /// - تعديل المدير اليدوي يغلب كل شيء.
  /// - من حضر يأخذ أجر اليوم حسب برنامجه (كامل أو نصف).
  /// - من غاب، أو حضر في يوم ليس من برنامجه، لا يأخذ شيئاً.
  /// - التأخر لا يخصم شيئاً.
  static WorkDayKind paidKind({
    required WorkDayKind scheduled,
    required bool present,
    WorkDayKind? override,
  }) {
    if (override != null) return override;
    return present ? scheduled : WorkDayKind.off;
  }

  /// الأجر بالدينار عن يوم من النوع [kind].
  static int wageFor(
    WorkDayKind kind, {
    required int fullDayWage,
    required int halfDayWage,
  }) => switch (kind) {
    WorkDayKind.full => fullDayWage,
    WorkDayKind.half => halfDayWage,
    WorkDayKind.off => 0,
  };
}

/// ملخص شهر عامل في الكشف الجامع.
class WorkerMonthSummary {
  const WorkerMonthSummary({
    required this.workerId,
    required this.name,
    required this.month,
    this.wageExpenseId,
    this.wageExpenseAmount,
  });

  final String workerId;
  final String name;
  final WorkerMonth month;
  final String? wageExpenseId;
  final int? wageExpenseAmount;

  bool get wageExpenseIsCurrent =>
      wageExpenseId != null && wageExpenseAmount == month.total;
}

/// أجور العمال من جدول حضورهم.
class WageService {
  WageService(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  /// كشف شهر [month] (`YYYY-MM`) للعامل: يوم بيوم مع الأجر.
  Future<WorkerMonth> month(String workerId, String month) async {
    final first = _monthStart(month);
    final worker = await (db.select(
      db.workers,
    )..where((w) => w.id.equals(workerId))).getSingle();
    final schedule = WorkerSchedule.fromJson(worker.weeklySchedule);
    final start = DateKey.parse(first);
    final daysInMonth = DateTime(start.year, start.month + 1, 0).day;
    final last = '$month-${daysInMonth.toString().padLeft(2, '0')}';

    final rows =
        await (db.select(db.workerAttendance)..where(
              (a) =>
                  a.workerId.equals(workerId) &
                  a.date.isBetweenValues(first, last) &
                  a.deletedAt.isNull(),
            ))
            .get();
    final byDate = {for (final row in rows) row.date: row};

    final days = <WorkerDay>[];
    var date = first;
    for (var i = 0; i < daysInMonth; i++) {
      final row = byDate[date];
      final scheduled = schedule.kindOn(DateKey.weekday(date));
      final present = row?.checkIn != null;
      final override = row?.overrideKind == null
          ? null
          : WorkDayKind.fromCode(row!.overrideKind!);
      final paid = WageRules.paidKind(
        scheduled: scheduled,
        present: present,
        override: override,
      );
      days.add(
        WorkerDay(
          date: date,
          scheduled: scheduled,
          present: present,
          paidKind: paid,
          wage: WageRules.wageFor(
            paid,
            fullDayWage: worker.fullDayWage,
            halfDayWage: worker.halfDayWage,
          ),
          lateMinutes: row?.lateMinutes ?? 0,
          overridden: override != null,
          checkIn: row?.checkIn,
          checkOut: row?.checkOut,
        ),
      );
      date = DateKey.next(date);
    }
    return WorkerMonth(workerId: workerId, days: days);
  }

  /// كشف شهر [month] (`YYYY-MM`) لكل العمال الأحياء مرتبين بالاسم، ولحظياً.
  Stream<List<WorkerMonthSummary>> watchSheet(String month) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            db.workers,
            db.workerAttendance,
            db.expenses,
            db.expenseCategories,
          },
        )
        .watch()
        .asyncMap((_) => sheet(month));
  }

  Future<List<WorkerMonthSummary>> sheet(String month) async {
    _monthStart(month);
    final workers =
        await (db.select(db.workers)
              ..where((w) => w.deletedAt.isNull())
              ..orderBy([(w) => OrderingTerm.asc(w.name)]))
            .get();
    final expenses = await _wageExpenses(month);
    return [
      for (final w in workers)
        WorkerMonthSummary(
          workerId: w.id,
          name: w.name,
          month: await this.month(w.id, month),
          wageExpenseId: expenses[w.id]?.id,
          wageExpenseAmount: expenses[w.id]?.amount,
        ),
    ];
  }

  /// يسجّل أجر الشهر المحسوب من الحضور كمصروف للعامل.
  ///
  /// المعرّف ثابت لكل عامل وشهر؛ تكرار العملية لا ينشئ صفاً آخر، بل يحدّث
  /// المبلغ إذا تغيّر الحضور أو تصحيحه بعد التسجيل.
  Future<String> recordAsExpense({
    required String workerId,
    required String month,
  }) async {
    _monthStart(month);
    final last = _monthEnd(month);
    final worker =
        await (db.select(
              db.workers,
            )..where((row) => row.id.equals(workerId) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (worker == null) throw StateError('العامل غير موجود أو محذوف');

    final amount = (await this.month(workerId, month)).total;
    if (amount <= 0) throw StateError('لا يوجد أجر مستحق لتسجيله');

    final categoryId = await _ensureWageCategory();
    final id = StableId.workerWageExpense(workerId, month);
    const notePrefix = 'أجر شهر ';
    final note = '$notePrefix$month';
    final existing = await (db.select(
      db.expenses,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (existing != null && existing.workerId != workerId) {
      throw StateError('سجل أجر العامل لا يطابق معرّفه الثابت');
    }
    if (existing != null &&
        existing.deletedAt == null &&
        existing.categoryId == categoryId &&
        existing.amount == amount &&
        existing.date == last &&
        existing.note == note) {
      return id;
    }

    if (existing != null) {
      final updated = await writer.patch(
        db.expenses,
        key: {'id': id},
        values: {
          'category_id': categoryId,
          'amount': amount,
          'date': last,
          'note': note,
          'worker_id': workerId,
          'deleted_at': null,
        },
      );
      if (updated) return id;
    }

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
        date: last,
        note: Value(note),
        invoicePhotoUrl: const Value(null),
        invoicePhotoLocalPath: const Value(null),
        workerId: Value(workerId),
        createdBy: writer.actor().userId,
      ),
      key: {'id': id},
    );
    return id;
  }

  Future<String> _ensureWageCategory() async {
    final id = StableId.workerWagesCategory();
    final existing = await (db.select(
      db.expenseCategories,
    )..where((category) => category.id.equals(id))).getSingleOrNull();
    if (existing != null && existing.isWages && existing.deletedAt == null) {
      return id;
    }
    if (existing != null && !existing.isWages) {
      throw StateError('معرّف نوع الأجور مستخدم لنوع مصروف عادي');
    }
    final stamp = writer.now();
    await writer.save(
      db.expenseCategories,
      ExpenseCategoriesCompanion.insert(
        id: id,
        createdAt: stamp,
        updatedAt: stamp,
        deletedAt: const Value(null),
        name: 'أجور العمال',
        isWages: const Value(true),
      ),
      key: {'id': id},
    );
    return id;
  }

  Future<Map<String, ({String id, int amount})>> _wageExpenses(
    String month,
  ) async {
    final first = _monthStart(month);
    final next = DateKey.shiftMonth(month, 1);
    final rows = await db
        .customSelect(
          'SELECT e.worker_id, e.id, e.amount FROM expenses e '
          'JOIN expense_categories c ON c.id = e.category_id '
          'WHERE e.deleted_at IS NULL AND c.deleted_at IS NULL '
          'AND c.is_wages = 1 AND e.worker_id IS NOT NULL '
          'AND e.date >= ? AND e.date < ? '
          'ORDER BY e.updated_at DESC, e.id',
          variables: [Variable<String>(first), Variable<String>(next)],
          readsFrom: {db.expenses, db.expenseCategories},
        )
        .get();
    final result = <String, ({String id, int amount})>{};
    for (final row in rows) {
      result.putIfAbsent(
        row.read<String>('worker_id'),
        () => (id: row.read<String>('id'), amount: row.read<int>('amount')),
      );
    }
    return result;
  }

  String _monthStart(String month) {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month)) {
      throw FormatException('اختر شهراً صحيحاً', month);
    }
    final first = '$month-01';
    final date = DateKey.parse(first);
    if (date.year < 1 || date.year > 9998 || DateKey.of(date) != first) {
      throw FormatException('اختر شهراً صحيحاً', month);
    }
    return first;
  }

  String _monthEnd(String month) {
    final first = _monthStart(month);
    final start = DateKey.parse(first);
    final day = DateTime(start.year, start.month + 1, 0).day;
    return '$month-${day.toString().padLeft(2, '0')}';
  }

  /// تعديل المدير اليدوي ليوم: كامل / نصف / غائب، أو `null` لإلغاء التعديل
  /// والرجوع إلى ما يحسبه البرنامج والحضور.
  Future<void> setOverride({
    required String workerId,
    required String date,
    required WorkDayKind? kind,
  }) {
    return db.transaction(() async {
      final existing =
          await (db.select(db.workerAttendance)..where(
                (a) => a.workerId.equals(workerId) & a.date.equals(date),
              ))
              .getSingleOrNull();
      if (existing == null) {
        if (kind == null) return;
        final stamp = writer.now();
        final row = WorkerAttendanceRow(
          id: StableId.workerAttendance(workerId, date),
          createdAt: stamp,
          updatedAt: stamp,
          workerId: workerId,
          date: date,
          lateMinutes: 0,
          overrideKind: kind.code,
        );
        await writer.save(db.workerAttendance, row, key: {'id': row.id});
        return;
      }
      await writer.save(
        db.workerAttendance,
        existing.copyWith(
          overrideKind: Value(kind?.code),
          deletedAt: const Value(null),
        ),
        key: {'id': existing.id},
      );
    });
  }
}
