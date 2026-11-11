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

/// أجور العمال من جدول حضورهم.
class WageService {
  WageService(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  /// كشف شهر [month] (`YYYY-MM`) للعامل: يوم بيوم مع الأجر.
  Future<WorkerMonth> month(String workerId, String month) async {
    final worker = await (db.select(
      db.workers,
    )..where((w) => w.id.equals(workerId))).getSingle();
    final schedule = WorkerSchedule.fromJson(worker.weeklySchedule);
    final first = '$month-01';
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
