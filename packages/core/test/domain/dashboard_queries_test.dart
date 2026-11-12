import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late DashboardQueries dashboard;
  late DuesService dues;
  late CycleService cycles;

  // سبت 2026-11-14 الساعة 12:00.
  final now = DateTime(2026, 11, 14, 12);
  int ms(DateTime t) => t.toUtc().millisecondsSinceEpoch;

  setUp(() async {
    env = TestEnv();
    dashboard = DashboardQueries(env.db, env.writer);
    dues = DuesService(env.db, env.writer);
    cycles = CycleService(env.db, env.writer);
    await env.subject();
    await env.teacher();
  });
  tearDown(() => env.close());

  test('مدرسة فارغة: أصفار وأسبوع من 7 أيام آخره اليوم', () async {
    final stats = await dashboard.load(now: now);
    expect(stats.students, 0);
    expect(stats.activeGroups, 0);
    expect(stats.todaySessions, 0);
    expect(stats.todayPresent, 0);
    expect(stats.receivedToday, 0);
    expect(stats.receivedMonth, 0);
    expect(stats.duesTotal, 0);
    expect(stats.duesStudents, 0);
    expect(stats.payoutsUnpaid, 0);
    expect(stats.waitingReady, 0);
    expect(stats.pendingRequests, 0);
    expect(stats.missedSessions, 0);
    expect(stats.weekReceipts, hasLength(7));
    expect(stats.weekReceipts.first.date, '2026-11-08');
    expect(stats.weekReceipts.last.date, '2026-11-14');
    expect(stats.weekTotal, 0);
  });

  test('التلاميذ والمجموعات وحصص اليوم والحاضرون', () async {
    await env.group();
    await env.group(id: 'g2', number: 2);
    await env.db.customStatement(
      "UPDATE groups SET archived_at = 5 WHERE id = 'g2'",
    );
    await env.slot(id: 'sl', weekday: 6);
    await env.student();
    await env.student(id: 's2');
    await env.student(id: 's3');
    await env.db.customStatement(
      "UPDATE students SET deleted_at = 9 WHERE id = 's3'",
    );
    await env.enroll(id: 'e1', studentId: 's1');
    await env.enroll(id: 'e2', studentId: 's2');
    await cycles.topUp('g1', fromDate: '2026-11-14');
    final sat = (await cycles.cycleSessions('g1', 1)).first;
    final attendance = AttendanceService(env.db, env.writer, cycles, dues);
    await attendance.mark(
      sessionId: sat.id,
      studentId: 's1',
      status: AttendanceStatus.present,
    );
    await attendance.mark(
      sessionId: sat.id,
      studentId: 's2',
      status: AttendanceStatus.absent,
    );
    final stats = await dashboard.load(now: now);
    expect(stats.students, 2);
    expect(stats.activeGroups, 1);
    expect(stats.todaySessions, 1);
    expect(stats.todayPresent, 1);
  });

  test('المقبوضات: اليوم والشهر ورسم الأسبوع', () async {
    await env.group();
    await env.student();
    await env.enroll(id: 'e1', studentId: 's1', price: 5000);
    final payments = PaymentService(
      env.db,
      env.writer,
      dues,
      DeviceInfoStore(env.db),
    );
    // اليوم 14، قبله بيومين 12، وشهر سابق (أكتوبر).
    env.time = ms(DateTime(2026, 10, 20, 10));
    await payments.record(
      studentId: 's1',
      type: PaymentType.month,
      groupId: 'g1',
      cycleNumber: 1,
      amount: 1000,
    );
    env.time = ms(DateTime(2026, 11, 12, 10));
    await payments.record(
      studentId: 's1',
      type: PaymentType.month,
      groupId: 'g1',
      cycleNumber: 1,
      amount: 700,
    );
    env.time = ms(DateTime(2026, 11, 14, 9));
    await payments.record(
      studentId: 's1',
      type: PaymentType.month,
      groupId: 'g1',
      cycleNumber: 1,
      amount: 500,
    );
    final stats = await dashboard.load(now: now);
    expect(stats.receivedToday, 500);
    expect(stats.receivedMonth, 1200);
    expect(stats.weekTotal, 1200);
    final byDate = {for (final d in stats.weekReceipts) d.date: d.amount};
    expect(byDate['2026-11-12'], 700);
    expect(byDate['2026-11-14'], 500);
    expect(byDate['2026-11-13'], 0);
  });

  test('المستحقات: مجموع الباقي وعدد من عليهم', () async {
    await env.group();
    await env.student();
    await env.student(id: 's2');
    await env.enroll(id: 'e1', studentId: 's1', price: 2000);
    await env.enroll(id: 'e2', studentId: 's2', price: 3000);
    var stats = await dashboard.load(now: now);
    expect(stats.duesTotal, 5000);
    expect(stats.duesStudents, 2);
    await dues.recordMonthPayment(
      studentId: 's1',
      groupId: 'g1',
      cycleNumber: 1,
      amount: 2000,
      receivedBy: 'u1',
      receiptNumber: 'A-1',
    );
    stats = await dashboard.load(now: now);
    expect(stats.duesTotal, 3000);
    expect(stats.duesStudents, 1);
  });

  test(
    'الخلاصات غير المسلَّمة والقوائم البالغة حدّها والطلبات المعلّقة',
    () async {
      await env.group();
      await env.db.customStatement(
        'INSERT INTO teacher_payouts (id, created_at, updated_at, teacher_id, '
        'group_id, cycle_number, kind, amount, details) VALUES '
        "('p1', 1, 1, 't1', 'g1', 1, 'cycle', 1500, '[]'), "
        "('p2', 1, 1, 't1', 'g1', 2, 'cycle', 700, '[]')",
      );
      await env.db.customStatement(
        "UPDATE teacher_payouts SET paid_at = 5 WHERE id = 'p2'",
      );
      await env.db.customStatement(
        'INSERT INTO session_requests (id, created_at, updated_at, teacher_id, '
        'group_id, type, status) VALUES '
        "('r1', 1, 1, 't1', 'g1', 'cancel', 'pending'), "
        "('r2', 1, 1, 't1', 'g1', 'cancel', 'approved')",
      );
      final enrolments = EnrolmentService(env.db, env.writer, dues, cycles);
      for (var i = 0; i < 2; i++) {
        await env.student(id: 'w$i');
        await enrolments.addToWaiting(studentId: 'w$i', subjectId: 'sub');
      }
      await env.db.customStatement('UPDATE waiting_lists SET threshold = 2');
      final stats = await dashboard.load(now: now);
      expect(stats.payoutsUnpaid, 1500);
      expect(stats.payoutsUnpaidCount, 1);
      expect(stats.pendingRequests, 1);
      expect(stats.waitingReady, 1);
    },
  );

  test('الحصص الفائتة في آخر 7 أيام', () async {
    await env.group();
    await env.slot(id: 'sl', weekday: 6);
    await cycles.topUp('g1', fromDate: '2026-11-07');
    final stats = await dashboard.load(now: now);
    // حصتا السبت 7 و14 (10:00–11:30) انتهتا ولا مسح دخول لأستاذهما.
    expect(stats.missedSessions, 2);
  });

  test('watch يتحدث عند أي تغيّر', () async {
    final seen = <int>[];
    final sub = dashboard.watch().listen((s) => seen.add(s.students));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await env.student();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await sub.cancel();
    expect(seen.first, 0);
    expect(seen.last, 1);
  });
}
