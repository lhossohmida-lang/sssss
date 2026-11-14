import 'package:drift/drift.dart';

import '../data/local/app_database.dart';

/// وحدات البيانات التي يسمح المستخدم بقراءتها في شاشة الإحصائيات.
/// لا يستعلم [StatisticsService] عن جدول وحدة غير مسموحة.
class StatisticsScope {
  const StatisticsScope({
    this.payments = false,
    this.expenses = false,
    this.payouts = false,
    this.attendance = false,
    this.students = false,
    this.groups = false,
  });

  final bool payments;
  final bool expenses;
  final bool payouts;
  final bool attendance;
  final bool students;
  final bool groups;

  bool get hasAny =>
      payments || expenses || payouts || attendance || students || groups;
  bool get hasFinance => payments || expenses || payouts;
  bool get hasEnrollment => students || groups;

  Set<TableInfo<Table, Object?>> tables(AppDatabase db) => {
    if (payments) db.payments,
    if (expenses) db.expenses,
    if (payouts) db.teacherPayouts,
    if (attendance) ...{db.attendance, db.sessions},
    if (students) db.students,
    if (groups) db.groups,
  };
}

/// أرقام شهر واحد في كشف الإحصائيات السنوي.
class StatisticsMonth {
  const StatisticsMonth({
    required this.month,
    this.receipts = 0,
    this.expenses = 0,
    this.payouts = 0,
    this.present = 0,
    this.absent = 0,
    this.excused = 0,
    this.newStudents = 0,
    this.newGroups = 0,
  });

  /// رقم الشهر من 1 إلى 12.
  final int month;
  final int receipts;
  final int expenses;
  final int payouts;
  final int present;
  final int absent;
  final int excused;
  final int newStudents;
  final int newGroups;

  StatisticsMonth copyWith({
    int? receipts,
    int? expenses,
    int? payouts,
    int? present,
    int? absent,
    int? excused,
    int? newStudents,
    int? newGroups,
  }) => StatisticsMonth(
    month: month,
    receipts: receipts ?? this.receipts,
    expenses: expenses ?? this.expenses,
    payouts: payouts ?? this.payouts,
    present: present ?? this.present,
    absent: absent ?? this.absent,
    excused: excused ?? this.excused,
    newStudents: newStudents ?? this.newStudents,
    newGroups: newGroups ?? this.newGroups,
  );
}

/// إحصائيات السنة المختارة، بصف واحد لكل شهر تقويمي.
class StatisticsSnapshot {
  StatisticsSnapshot({
    required this.year,
    required this.scope,
    required List<StatisticsMonth> months,
    this.activeStudents = 0,
    this.activeGroups = 0,
  }) : months = List.unmodifiable(months);

  final int year;
  final StatisticsScope scope;
  final List<StatisticsMonth> months;
  final int activeStudents;
  final int activeGroups;

  int get receivedTotal =>
      months.fold(0, (total, item) => total + item.receipts);
  int get expenseTotal =>
      months.fold(0, (total, item) => total + item.expenses);
  int get payoutTotal => months.fold(0, (total, item) => total + item.payouts);
  int get attendanceTotal => months.fold(
    0,
    (total, item) => total + item.present + item.absent + item.excused,
  );
}

/// إحصائيات سنوية محلية مجمّعة في SQL، مع بثّ يتأثر بجداول الصلاحيات فقط.
class StatisticsService {
  StatisticsService(this.db);

  final AppDatabase db;

  Stream<StatisticsSnapshot> watch(int year, StatisticsScope scope) {
    _validate(year, scope);
    return db
        .customSelect('SELECT 1', readsFrom: scope.tables(db))
        .watch()
        .asyncMap((_) => load(year, scope));
  }

  Future<StatisticsSnapshot> load(int year, StatisticsScope scope) async {
    _validate(year, scope);
    final months = [
      for (var month = 1; month <= 12; month++) StatisticsMonth(month: month),
    ];
    var activeStudents = 0;
    var activeGroups = 0;
    final start = DateTime(year).millisecondsSinceEpoch;
    final end = DateTime(year + 1).millisecondsSinceEpoch;
    final fromDate = '$year-01-01';
    final toDate = '${year + 1}-01-01';

    if (scope.payments) {
      final rows = await db
          .customSelect(
            'SELECT CAST(strftime(\'%m\', datetime(created_at / 1000, '
            '\'unixepoch\', \'localtime\')) AS INTEGER) AS month, '
            'COALESCE(SUM(amount), 0) AS amount FROM payments '
            'WHERE deleted_at IS NULL AND created_at >= ? AND created_at < ? '
            'GROUP BY month',
            variables: [Variable<int>(start), Variable<int>(end)],
            readsFrom: {db.payments},
          )
          .get();
      for (final row in rows) {
        final month = row.read<int>('month');
        if (month < 1 || month > 12) continue;
        months[month - 1] = months[month - 1].copyWith(
          receipts: row.read<int>('amount'),
        );
      }
    }

    if (scope.expenses) {
      final rows = await db
          .customSelect(
            'SELECT CAST(substr(date, 6, 2) AS INTEGER) AS month, '
            'COALESCE(SUM(amount), 0) AS amount FROM expenses '
            'WHERE deleted_at IS NULL AND date >= ? AND date < ? '
            'GROUP BY month',
            variables: [Variable<String>(fromDate), Variable<String>(toDate)],
            readsFrom: {db.expenses},
          )
          .get();
      for (final row in rows) {
        final month = row.read<int>('month');
        if (month < 1 || month > 12) continue;
        months[month - 1] = months[month - 1].copyWith(
          expenses: row.read<int>('amount'),
        );
      }
    }

    if (scope.payouts) {
      final rows = await db
          .customSelect(
            'SELECT CAST(strftime(\'%m\', datetime(paid_at / 1000, '
            '\'unixepoch\', \'localtime\')) AS INTEGER) AS month, '
            'COALESCE(SUM(amount), 0) AS amount FROM teacher_payouts '
            'WHERE deleted_at IS NULL AND paid_at IS NOT NULL '
            'AND paid_at >= ? AND paid_at < ? GROUP BY month',
            variables: [Variable<int>(start), Variable<int>(end)],
            readsFrom: {db.teacherPayouts},
          )
          .get();
      for (final row in rows) {
        final month = row.read<int>('month');
        if (month < 1 || month > 12) continue;
        months[month - 1] = months[month - 1].copyWith(
          payouts: row.read<int>('amount'),
        );
      }
    }

    if (scope.attendance) {
      final rows = await db
          .customSelect(
            'SELECT CAST(substr(s.date, 6, 2) AS INTEGER) AS month, '
            'a.status, COUNT(*) AS count FROM attendance a '
            'JOIN sessions s ON s.id = a.session_id '
            'WHERE a.deleted_at IS NULL AND s.deleted_at IS NULL '
            'AND s.status <> \'cancelled\' AND s.date >= ? AND s.date < ? '
            'GROUP BY month, a.status',
            variables: [Variable<String>(fromDate), Variable<String>(toDate)],
            readsFrom: {db.attendance, db.sessions},
          )
          .get();
      for (final row in rows) {
        final month = row.read<int>('month');
        if (month < 1 || month > 12) continue;
        final count = row.read<int>('count');
        final status = row.read<String>('status');
        final previous = months[month - 1];
        months[month - 1] = previous.copyWith(
          present: previous.present + (status == 'present' ? count : 0),
          absent: previous.absent + (status == 'absent' ? count : 0),
          excused: previous.excused + (status == 'excused' ? count : 0),
        );
      }
    }

    if (scope.students) {
      final rows = await db
          .customSelect(
            'SELECT CAST(strftime(\'%m\', datetime(created_at / 1000, '
            '\'unixepoch\', \'localtime\')) AS INTEGER) AS month, '
            'COUNT(*) AS count FROM students WHERE deleted_at IS NULL '
            'AND created_at >= ? AND created_at < ? GROUP BY month',
            variables: [Variable<int>(start), Variable<int>(end)],
            readsFrom: {db.students},
          )
          .get();
      final active = await db
          .customSelect(
            'SELECT COUNT(*) AS count FROM students WHERE deleted_at IS NULL',
            readsFrom: {db.students},
          )
          .getSingle();
      activeStudents = active.read<int>('count');
      for (final row in rows) {
        final month = row.read<int>('month');
        if (month < 1 || month > 12) continue;
        months[month - 1] = months[month - 1].copyWith(
          newStudents: row.read<int>('count'),
        );
      }
    }

    if (scope.groups) {
      final rows = await db
          .customSelect(
            'SELECT CAST(strftime(\'%m\', datetime(created_at / 1000, '
            '\'unixepoch\', \'localtime\')) AS INTEGER) AS month, '
            'COUNT(*) AS count FROM groups WHERE deleted_at IS NULL '
            'AND created_at >= ? AND created_at < ? GROUP BY month',
            variables: [Variable<int>(start), Variable<int>(end)],
            readsFrom: {db.groups},
          )
          .get();
      final active = await db
          .customSelect(
            'SELECT COUNT(*) AS count FROM groups '
            'WHERE deleted_at IS NULL AND archived_at IS NULL',
            readsFrom: {db.groups},
          )
          .getSingle();
      activeGroups = active.read<int>('count');
      for (final row in rows) {
        final month = row.read<int>('month');
        if (month < 1 || month > 12) continue;
        months[month - 1] = months[month - 1].copyWith(
          newGroups: row.read<int>('count'),
        );
      }
    }

    return StatisticsSnapshot(
      year: year,
      scope: scope,
      months: months,
      activeStudents: activeStudents,
      activeGroups: activeGroups,
    );
  }

  void _validate(int year, StatisticsScope scope) {
    if (year < 1 || year > 9998) {
      throw const FormatException('السنة غير صالحة');
    }
    if (!scope.hasAny) {
      throw ArgumentError('تحتاج الإحصائيات إلى صلاحية عرض واحدة على الأقل');
    }
  }
}
