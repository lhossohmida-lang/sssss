import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';

import '../support/fixtures.dart';

/// رحلة كاملة عبر الخدمات الحقيقية (لا محاكاة سوى مزوّد الحسابات): مجموعة
/// بدورة من 4 حصص ← تسجيل تلميذين ← دفعة كاملة لأحدهما وجزئية للآخر ← مسح
/// كل حصة وإغلاقها ← اكتمال الدورة وخلاص الأستاذ بحسب ما دُفع ← دفع المتأخر
/// فيُفرَج عن النصيب المعلّق ← تسليم المال للأستاذ.
void main() {
  late TestEnv env;
  late GroupService groups;
  late CycleService cycles;
  late DuesService dues;
  late RegistrationService registration;
  late ScanService scanner;
  late AttendanceService attendance;
  late PaymentService payments;
  late PayoutService payouts;
  late PayoutQueries payoutQueries;
  late GroupRow group;
  late StudentRow ahmed;
  late StudentRow nour;

  // أيام السبت الأربعة لدورة الحصص (الحصة من 10:00 إلى 11:30).
  const saturdays = ['2026-11-07', '2026-11-14', '2026-11-21', '2026-11-28'];

  DateTime at(String date, int hour, int minute) {
    final d = DateKey.parse(date);
    return DateTime(d.year, d.month, d.day, hour, minute);
  }

  setUp(() async {
    env = TestEnv();
    cycles = CycleService(env.db, env.writer);
    dues = DuesService(env.db, env.writer);
    groups = GroupService(env.db, env.writer, ScheduleService(env.db), cycles);
    registration = RegistrationService(
      env.db,
      env.writer,
      accounts: AccountService(env.db, env.writer, FakeAccountProvisioner()),
      enrolments: EnrolmentService(env.db, env.writer, dues, cycles),
      dues: dues,
    );
    scanner = ScanService(env.db, env.writer, cycles, dues);
    attendance = AttendanceService(env.db, env.writer, cycles, dues);
    payments = PaymentService(
      env.db,
      env.writer,
      dues,
      DeviceInfoStore(env.db, random: Random(3)),
    );
    payouts = PayoutService(env.db, env.writer, dues);
    payoutQueries = PayoutQueries(env.db, payouts);

    await env.subject();
    await env.teacher(); // نصيبه 1000 دج عن التلميذ الكامل في الدورة
    await env.room();
    await env.db
        .into(env.db.teacherSubjects)
        .insert(
          TeacherSubjectsCompanion.insert(
            teacherId: 't1',
            subjectId: 'sub',
            updatedAt: 1,
          ),
        );
    group = await groups.create(
      subjectId: 'sub',
      teacherId: 't1',
      roomId: 'r1',
      sessionsPerCycle: 4,
      slots: [
        const GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690),
      ],
      startDate: saturdays.first,
    );

    RegistrationRequest request(String first, String phone) =>
        RegistrationRequest(
          firstName: first,
          lastName: 'بن علي',
          parentName: 'ولي $first',
          parentPhone: phone,
          choices: [
            SubjectChoice(
              subjectId: 'sub',
              groupId: group.id,
              monthlyPrice: 2000,
            ),
          ],
          date: saturdays.first,
        );
    const settings = SchoolSettings();
    ahmed = (await registration.register(
      request('أحمد', '0550000001'),
      settings: settings,
    )).student;
    nour = (await registration.register(
      request('نور', '0550000002'),
      settings: settings,
    )).student;
    // الفهرس في الذاكرة يُحمَّل بعد التسجيل ليعرف رمزي التلميذين.
    await scanner.loadIndex();
  });
  tearDown(() => env.close());

  Future<PaymentRow> payMonth(StudentRow student, int amount) =>
      payments.record(
        studentId: student.id,
        type: PaymentType.month,
        groupId: group.id,
        cycleNumber: 1,
        amount: amount,
      );

  /// مسح التلميذين في حصة اليوم ثم إغلاق الحصص المنتهية.
  Future<void> runSession(String date) async {
    for (final student in [ahmed, nour]) {
      final result = await scanner.scan(student.qrCode, now: at(date, 10, 5));
      expect(
        {ScanOutcome.studentOk, ScanOutcome.studentDues},
        contains(result.outcome),
        reason: 'مسح ${student.firstName} في $date',
      );
      expect(result.sessionCreated, isFalse, reason: 'الحصة مبرمجة سلفاً');
    }
    expect(await attendance.closeDueSessions(at(date, 12, 0)), 1);
  }

  test('التسجيل: تلميذان برمزين وحسابَي وليّ ومستحقات الدورة الأولى', () async {
    expect(ahmed.qrCode, startsWith('S-'));
    expect(nour.qrCode, isNot(ahmed.qrCode));
    expect(
      (await env.db.select(env.db.parents).get()).map((p) => p.phone).toSet(),
      {'0550000001', '0550000002'},
    );
    final sessions = await cycles.cycleSessions(group.id, 1);
    expect(sessions.map((s) => s.date), saturdays);
    final items = await payments.payables(
      ahmed.id,
      now: at(saturdays.first, 9, 0),
    );
    final cycle = items.singleWhere((i) => i.type == PaymentType.month);
    expect(cycle.remaining, 2000);
    expect(cycle.cycleNumber, 1);
  });

  test('الرحلة الكاملة: مسح ودفع واكتمال الدورة وخلاص الأستاذ', () async {
    // 1) الدفع: أحمد كاملاً (2000)، ونور جزئياً (1000 = نصف الدورة).
    final fullReceipt = await payMonth(ahmed, 2000);
    final partReceipt = await payMonth(nour, 1000);
    expect(fullReceipt.receiptNumber, isNot(partReceipt.receiptNumber));
    final nourItems = await payments.payables(
      nour.id,
      now: at(saturdays.first, 9, 0),
    );
    expect(
      nourItems.singleWhere((i) => i.type == PaymentType.month).remaining,
      1000,
    );
    expect(
      (await payments.payables(
        ahmed.id,
        now: at(saturdays.first, 9, 0),
      )).where((i) => i.type == PaymentType.month),
      isEmpty,
      reason: 'دورة أحمد مسدَّدة',
    );

    // 2) ثلاث حصص: الدورة لم تكتمل ولا خلاص بعد.
    for (final date in saturdays.take(3)) {
      await runSession(date);
    }
    expect(await payoutQueries.list(), isEmpty);
    expect(
      (await env.db.select(env.db.groups).get()).single.currentCycleNumber,
      1,
    );

    // 3) المسح المكرر لا يضاعف الحضور.
    final again = await scanner.scan(
      ahmed.qrCode,
      now: at(saturdays[2], 10, 40),
    );
    expect(again.outcome, ScanOutcome.studentAlreadyPresent);

    // 4) الحصة الرابعة تُكمل الدورة فتنتقل المجموعة إلى الثانية ويُنشأ الخلاص.
    await runSession(saturdays.last);
    expect(
      (await env.db.select(env.db.groups).get()).single.currentCycleNumber,
      2,
    );
    expect(await cycles.cycleSessions(group.id, 2), isNotEmpty);

    final present = await env.db.select(env.db.attendance).get();
    expect(present.where((a) => a.status == 'present'), hasLength(8));

    // 5) الخلاص: أحمد 1000 كاملة، ونور حضر 4 وغطّى دفعه حصتين فيستحق 500،
    // والنصف الآخر معلّق حتى يدفع.
    final unpaid = await payoutQueries.list(status: PayoutStatus.unpaid);
    expect(unpaid, hasLength(1));
    final cyclePayout = unpaid.single;
    expect(cyclePayout.isRelease, isFalse);
    expect(cyclePayout.amount, 1500);
    final lines = {
      for (final l in PayoutService.linesOf(cyclePayout.payout)) l.studentId: l,
    };
    expect(lines[ahmed.id]!.attended, 4);
    expect(lines[ahmed.id]!.earned, 1000);
    expect(lines[nour.id]!.attended, 4);
    expect(lines[nour.id]!.covered, 2);
    expect(lines[nour.id]!.earned, 500);
    expect(lines[nour.id]!.pending, 500);
    var summary = await payoutQueries.summary();
    expect(summary.unpaid, 1500);
    expect(summary.pending, 500);
    expect(summary.paid, 0);

    // 6) نور تسدّد الباقي فيُفرَج عن نصيب الأستاذ المعلّق.
    await payMonth(nour, 1000);
    final all = await payoutQueries.list();
    expect(all, hasLength(2));
    final release = all.singleWhere((p) => p.isRelease);
    expect(release.amount, 500);
    summary = await payoutQueries.summary();
    expect(summary.unpaid, 2000);
    expect(summary.pending, 0);

    // 7) تسليم المال للأستاذ: مرة واحدة لكل خلاص.
    for (final item in all) {
      expect(await payouts.markPaid(item.id, paidBy: 'u1'), isTrue);
    }
    expect(await payouts.markPaid(cyclePayout.id, paidBy: 'u1'), isFalse);
    summary = await payoutQueries.summary();
    expect(summary.paid, 2000);
    expect(summary.unpaid, 0);
    expect(summary.pending, 0);
  });

  test('الأثر المحفوظ: سجل عمليات وطابور مزامنة لكل خطوة', () async {
    await payMonth(ahmed, 2000);
    for (final date in saturdays) {
      await runSession(date);
    }
    final payout = (await payoutQueries.list()).single;
    await payouts.markPaid(payout.id, paidBy: 'u1');

    final outbox = await env.db.select(env.db.outbox).get();
    final tables = outbox.map((o) => o.targetTable).toSet();
    expect(
      tables,
      containsAll([
        'students',
        'parents',
        'group_students',
        'sessions',
        'attendance',
        'payments',
        'teacher_payouts',
      ]),
    );
    final audit = await env.db.select(env.db.auditLog).get();
    expect(audit.any((a) => a.action == 'pay_teacher'), isTrue);
    expect(audit.any((a) => a.entity == 'payments'), isTrue);
  });

  test('تلميذ لم يدفع شيئاً: يحضر ولا يستحق الأستاذ منه حتى يدفع', () async {
    await payMonth(ahmed, 2000);
    for (final date in saturdays) {
      await runSession(date);
    }
    final payout = (await payoutQueries.list()).single;
    expect(payout.amount, 1000, reason: 'نصيب أحمد وحده');
    final nourLine = PayoutService.linesOf(payout.payout)
        .singleWhere((l) => l.studentId == nour.id);
    expect(nourLine.covered, 0);
    expect(nourLine.earned, 0);
    expect(nourLine.full, 1000);

    await payMonth(nour, 2000);
    final release = (await payoutQueries.list()).singleWhere(
      (p) => p.isRelease,
    );
    expect(release.amount, 1000);
  });
}
