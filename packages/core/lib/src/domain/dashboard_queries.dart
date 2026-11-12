import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'date_key.dart';
import 'dues_service.dart';
import 'payment_service.dart';
import 'teacher_attendance.dart';
import 'waiting_service.dart';

/// مبلغ ليوم (لرسم مقبوضات الأسبوع).
class DailyAmount {
  const DailyAmount({required this.date, required this.amount});

  final String date;
  final int amount;
}

/// أرقام لوحة التحكم: لقطة واحدة تُعرض حسب صلاحيات المستخدم.
class DashboardStats {
  const DashboardStats({
    required this.students,
    required this.activeGroups,
    required this.todaySessions,
    required this.todayPresent,
    required this.receivedToday,
    required this.receivedMonth,
    required this.duesTotal,
    required this.duesStudents,
    required this.payoutsUnpaid,
    required this.payoutsUnpaidCount,
    required this.waitingReady,
    required this.pendingRequests,
    required this.missedSessions,
    required this.weekReceipts,
  });

  /// التلاميذ الأحياء.
  final int students;

  /// المجموعات غير المؤرشفة.
  final int activeGroups;

  /// حصص اليوم غير الملغاة.
  final int todaySessions;

  /// ما سُجّل حاضراً اليوم (تلميذ × حصة).
  final int todayPresent;

  final int receivedToday;
  final int receivedMonth;

  /// مجموع المستحقات وعدد من عليهم.
  final int duesTotal;
  final int duesStudents;

  /// خلاصات الأساتذة غير المسلَّمة: مجموعها وعددها.
  final int payoutsUnpaid;
  final int payoutsUnpaidCount;

  /// قوائم انتظار بلغت حدّها.
  final int waitingReady;

  /// طلبات الأساتذة المعلّقة.
  final int pendingRequests;

  /// حصص آخر 7 أيام لم يحضرها أستاذها.
  final int missedSessions;

  /// مقبوضات آخر 7 أيام (الأقدم أولاً، وآخرها اليوم).
  final List<DailyAmount> weekReceipts;

  int get weekTotal => weekReceipts.fold(0, (sum, d) => sum + d.amount);
}

/// أرقام لوحة التحكم باستعلامات مجمّعة صغيرة؛ المنطق المالي والحضور من
/// الخدمات نفسها فلا يتكرر.
class DashboardQueries {
  DashboardQueries(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  /// عدد أيام تنبيه الحصص الفائتة ورسم المقبوضات.
  static const int windowDays = 7;

  /// اللوحة، وتتحدث مع كل تغيّر فيما تعتمد عليه.
  Stream<DashboardStats> watch() {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            db.students,
            db.groups,
            db.sessions,
            db.attendance,
            db.payments,
            db.groupStudents,
            db.studentCredits,
            db.teacherPayouts,
            db.waitingLists,
            db.waitingEntries,
            db.sessionRequests,
            db.teacherAttendance,
          },
        )
        .watch()
        .asyncMap((_) => load(now: DateTime.now()));
  }

  Future<DashboardStats> load({required DateTime now}) async {
    final today = DateKey.of(now);
    final monthStart = DateTime(now.year, now.month);
    final monthEnd = DateTime(now.year, now.month + 1);
    final payments = PaymentService(
      db,
      writer,
      DuesService(db, writer),
      DeviceInfoStore(db),
    );

    final counts = await db
        .customSelect(
          'SELECT '
          '(SELECT COUNT(*) FROM students WHERE deleted_at IS NULL) AS students, '
          '(SELECT COUNT(*) FROM groups WHERE deleted_at IS NULL '
          'AND archived_at IS NULL) AS groups, '
          '(SELECT COUNT(*) FROM sessions WHERE date = ? '
          "AND deleted_at IS NULL AND status <> 'cancelled') AS sessions, "
          '(SELECT COUNT(*) FROM attendance a JOIN sessions s '
          'ON s.id = a.session_id WHERE s.date = ? AND s.deleted_at IS NULL '
          "AND a.deleted_at IS NULL AND a.status = 'present') AS present, "
          '(SELECT COUNT(*) FROM teacher_payouts WHERE deleted_at IS NULL '
          'AND paid_at IS NULL) AS payouts_count, '
          '(SELECT COALESCE(SUM(amount), 0) FROM teacher_payouts '
          'WHERE deleted_at IS NULL AND paid_at IS NULL) AS payouts_sum, '
          "(SELECT COUNT(*) FROM session_requests WHERE status = 'pending' "
          'AND deleted_at IS NULL) AS requests',
          variables: [Variable<String>(today), Variable<String>(today)],
          readsFrom: {
            db.students,
            db.groups,
            db.sessions,
            db.attendance,
            db.teacherPayouts,
            db.sessionRequests,
          },
        )
        .getSingle();

    final dues = await DuesService(db, writer).cycleDues(unpaidOnly: true);
    final duesTotal = dues.fold<int>(0, (sum, d) => sum + d.remaining);
    final duesStudents = {for (final d in dues) d.studentId}.length;

    final waiting = await WaitingService(db, writer).lists();
    final missed = await TeacherAttendanceQueries(db, writer).missed(
      since: DateKey.of(now.subtract(const Duration(days: windowDays))),
      now: now,
    );

    final week = <DailyAmount>[];
    for (var i = windowDays - 1; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day - i);
      week.add(
        DailyAmount(
          date: DateKey.of(day),
          amount: await payments.receivedOn(day),
        ),
      );
    }

    return DashboardStats(
      students: counts.read<int>('students'),
      activeGroups: counts.read<int>('groups'),
      todaySessions: counts.read<int>('sessions'),
      todayPresent: counts.read<int>('present'),
      receivedToday: week.last.amount,
      receivedMonth: await payments.receivedBetween(
        from: monthStart.toUtc().millisecondsSinceEpoch,
        to: monthEnd.toUtc().millisecondsSinceEpoch,
      ),
      duesTotal: duesTotal,
      duesStudents: duesStudents,
      payoutsUnpaid: counts.read<int>('payouts_sum'),
      payoutsUnpaidCount: counts.read<int>('payouts_count'),
      waitingReady: waiting.where((l) => l.reachedThreshold).length,
      pendingRequests: counts.read<int>('requests'),
      missedSessions: missed.length,
      weekReceipts: week,
    );
  }
}
