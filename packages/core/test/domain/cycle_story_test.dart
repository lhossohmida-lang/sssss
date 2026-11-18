import 'dart:math';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

/// قصة الدورة كما وصفها صاحب المدرسة، من التسجيل حتى خلاص الأستاذ وتجديد الشهر،
/// عبر الخدمات الحقيقية (لا صفوف مُدرَجة يدوياً):
///
/// - الشهر دورة من 8 حصص. باكتمال حصصها المنعقدة يأخذ الأستاذ نصيبه من حضور التلاميذ
///   في تلك الحصص وحدها، ثم تُجدَّد الدورة على التوالي.
/// - ملتحق في منتصف الشهر (حضر الحصة 5) دفع شهراً كاملاً (8 حصص) ولم يدرس فيه إلا 4:
///   في الشهر الثاني يظهر أنه دفع 4 حصص منه.
/// - الأستاذ لا يأخذ مالاً عن حصص لم تُدرَّس بعد، ولو كان التلميذ دفعها.
///
/// الأسعار: الشهر 2000 دج، ونصيب الأستاذ 1000 دج لكل تلميذ في الدورة (125 دج للحصة).
void main() {
  late TestEnv env;
  late CycleService cycles;
  late DuesService dues;
  late AttendanceService attendance;
  late EnrolmentService enrolments;
  late PaymentService payments;

  // السبت 14 نوفمبر 2026، ثم السبت والثلاثاء من كل أسبوع.
  const cycleOne = [
    '2026-11-14',
    '2026-11-17',
    '2026-11-21',
    '2026-11-24',
    '2026-11-28',
    '2026-12-01',
    '2026-12-05',
    '2026-12-08',
  ];

  setUp(() async {
    env = TestEnv();
    cycles = CycleService(env.db, env.writer);
    dues = DuesService(env.db, env.writer);
    attendance = AttendanceService(env.db, env.writer, cycles, dues);
    enrolments = EnrolmentService(env.db, env.writer, dues, cycles);
    payments = PaymentService(
      env.db,
      env.writer,
      dues,
      DeviceInfoStore(env.db, random: Random(3)),
    );
    await env.subject(); // سعر الشهر 2000
    await env.teacher(); // نصيبه 1000 لكل تلميذ في الدورة
    await env.group(); // دورة من 8 حصص
    await env.slot(id: 'sl-sat', weekday: 6);
    await env.slot(id: 'sl-tue', weekday: 2);
    await env.student(id: 'old');
    await env.student(id: 'late');
    await env.enroll(id: 'e-old', studentId: 'old');
    await cycles.topUp('g1', fromDate: cycleOne.first);
  });

  tearDown(() => env.close());

  Future<SessionRow> sessionOn(String date) async =>
      (await (env.db.select(env.db.sessions)..where(
            (s) =>
                s.groupId.equals('g1') &
                s.date.equals(date) &
                s.deletedAt.isNull(),
          ))
          .getSingle());

  /// تنعقد حصة [date]: يُسجَّل [present] حاضرين، ثم يغلقها المغلِق التلقائي بعد نهايتها
  /// (فيُسجَّل غائباً من لم يُسجَّل، وتكتمل الدورة إن اكتملت بها).
  Future<void> hold(String date, List<String> present) async {
    final session = await sessionOn(date);
    for (final id in present) {
      await attendance.mark(
        sessionId: session.id,
        studentId: id,
        status: AttendanceStatus.present,
      );
    }
    await attendance.closeDueSessions(DateTime.parse('${date}T12:00:00'));
  }

  Future<void> pay(String student, int cycle, int amount) => payments.record(
    studentId: student,
    type: PaymentType.month,
    groupId: 'g1',
    cycleNumber: cycle,
    amount: amount,
  );

  Future<GroupRow> group() => (env.db.select(
    env.db.groups,
  )..where((g) => g.id.equals('g1'))).getSingle();

  Future<List<TeacherPayoutRow>> payoutRows(String kind, int cycle) =>
      (env.db.select(env.db.teacherPayouts)..where(
            (p) =>
                p.groupId.equals('g1') &
                p.cycleNumber.equals(cycle) &
                p.kind.equals(kind) &
                p.deletedAt.isNull(),
          ))
          .get();

  PayoutLine lineOf(TeacherPayoutRow payout, String student) =>
      PayoutService.linesOf(payout).singleWhere((l) => l.studentId == student);

  /// تُعقد حصص الدورة 1 الأربع الأولى، ثم يلتحق «late» قبل الخامسة.
  Future<void> firstFourThenLateJoins() async {
    for (final date in cycleOne.take(4)) {
      await hold(date, ['old']);
    }
    await enrolments.enrol(
      studentId: 'late',
      groupId: 'g1',
      monthlyPrice: 2000,
    );
  }

  test(
    'الملتحق في الحصة 5: يدفع الشهر كاملاً ويظهر في الثاني أنه دفع 4 حصص',
    () async {
      await firstFourThenLateJoins();

      // التحق عند الحصة 5؛ فاتته 4 حصص قيمتها 1000 دج رصيد للدورة التالية.
      final enrolment = await (env.db.select(
        env.db.groupStudents,
      )..where((e) => e.studentId.equals('late'))).getSingle();
      expect(enrolment.joinedAtCycleNumber, 1);
      expect(enrolment.joinedAtSessionNumber, 5);
      final credit = await env.db.select(env.db.studentCredits).getSingle();
      expect(credit.studentId, 'late');
      expect(credit.amount, 1000);
      expect(credit.reason, DuesService.reasonMidJoin);
      expect(credit.sourceCycleNumber, 1);
      expect(credit.targetCycleNumber, 2);

      // يدفع شهراً كاملاً (8 حصص) رغم أنه لن يدرس منه إلا 4.
      final first = await dues.cycleDue(
        studentId: 'late',
        groupId: 'g1',
        cycleNumber: 1,
      );
      expect(first!.due, 2000);
      await pay('late', 1, 2000);
      await pay('old', 1, 2000);

      for (final date in cycleOne.skip(4)) {
        await hold(date, ['old', 'late']);
      }

      // اكتملت الحصص الثماني المنعقدة: دورة جديدة، وحصصها مبرمجة على التوالي.
      expect((await group()).currentCycleNumber, 2);
      final next = await cycles.cycleSessions('g1', 2);
      expect(next, hasLength(8));
      expect(next.first.date.compareTo(cycleOne.last), greaterThan(0));
      expect(next.every((s) => s.closedAt == null), isTrue);
      expect([for (final s in next) s.sessionNumber], [1, 2, 3, 4, 5, 6, 7, 8]);

      // خلاص الأستاذ عن الدورة 1 من حضورهم في حصصها الثماني فقط: «old» حضر 8 فأخذ 1000،
      // و«late» حضر 4 رغم دفعه 8 فأخذ 500 فقط؛ الحصص الأربع الباقية لم تُدرَّس بعد.
      final cycleOnePayout = (await payoutRows('cycle', 1)).single;
      expect(cycleOnePayout.amount, 1500);
      final old = lineOf(cycleOnePayout, 'old');
      expect([old.attended, old.covered, old.earned], [8, 8, 1000]);
      final late = lineOf(cycleOnePayout, 'late');
      expect(
        [late.attended, late.covered, late.earned, late.full],
        [4, 8, 500, 500],
      );
      expect(late.pending, 0);

      // في الشهر الثاني يظهر أنه دفع 4 حصص منه (رصيد 1000 دج من 2000)، ويبقى عليه نصفه.
      final second = await dues.cycleDue(
        studentId: 'late',
        groupId: 'g1',
        cycleNumber: 2,
      );
      expect(second!.netPrice, 2000);
      expect(second.credits, 1000);
      expect(second.due, 1000);
      expect(second.paid, 0);
      final oldSecond = await dues.cycleDue(
        studentId: 'old',
        groupId: 'g1',
        cycleNumber: 2,
      );
      expect(oldSecond!.due, 2000, reason: 'القديم يدفع الشهر الثاني كاملاً');

      final item = (await payments.payables(
        'late',
        now: DateTime(2026, 12, 9),
      )).singleWhere((i) => i.cycleNumber == 2);
      expect(item.credits, 1000);
      expect(item.creditSessions, 4, reason: 'الرصيد يُعرض حصصاً أيضاً');
      expect(item.total, 1000);

      // يتمّ الشهر الثاني: دفع النصف الباقي وحضر 8 حصص، فيأخذ الأستاذ نصيب الحصص الثماني
      // كاملاً (4 منها دُفعت في الشهر الأول وصارت رصيداً). مجموع ما أخذه عنه 1500 لـ12 حصة.
      await pay('late', 2, 1000);
      await pay('old', 2, 2000);
      for (final session in next) {
        await hold(session.date, ['old', 'late']);
      }
      expect((await group()).currentCycleNumber, 3);
      expect(await cycles.cycleSessions('g1', 3), hasLength(8));
      final cycleTwoPayout = (await payoutRows('cycle', 2)).single;
      final lateSecond = lineOf(cycleTwoPayout, 'late');
      expect(
        [lateSecond.attended, lateSecond.covered, lateSecond.earned],
        [8, 8, 1000],
      );
      expect(lateSecond.earned + late.earned, 1500);
      expect(cycleTwoPayout.amount, 2000);
    },
  );

  test('لو بقي عليه نصف الشهر الأول: لا يأخذ الأستاذ إلا عن الحصص المدفوعة والمحضورة', () async {
    await firstFourThenLateJoins();
    await pay('old', 1, 2000);
    await pay('late', 1, 1000); // 4 حصص فقط من 8
    for (final date in cycleOne.skip(4)) {
      await hold(date, ['old', 'late']);
    }
    final payout = (await payoutRows('cycle', 1)).single;
    final late = lineOf(payout, 'late');
    expect([late.attended, late.covered, late.earned], [4, 4, 500]);
    expect(late.pending, 0);
    // ويبقى عليه ألف دج عن الشهر الأول تظهر في مستحقاته.
    final first = await dues.cycleDue(
      studentId: 'late',
      groupId: 'g1',
      cycleNumber: 1,
    );
    expect(first!.remaining, 1000);
  });

  test(
    'لم يدفع شيئاً: لا نصيب للأستاذ ويُفرَج عنه عند الدفع، ولا يتجاوز المحضور',
    () async {
      await firstFourThenLateJoins();
      await pay('old', 1, 2000);
      for (final date in cycleOne.skip(4)) {
        await hold(date, ['old', 'late']);
      }
      final payout = (await payoutRows('cycle', 1)).single;
      final late = lineOf(payout, 'late');
      expect(
        [late.attended, late.covered, late.earned, late.pending],
        [4, 0, 0, 500],
      );
      expect(payout.amount, 1000);

      // يدفع الشهر كاملاً بعد انتهائه: يُفرَج عن 500 (الحصص الأربع التي درسها) لا 1000.
      await pay('late', 1, 2000);
      final released = await payoutRows('release', 1);
      expect(released, hasLength(1));
      expect(released.single.amount, 500);
      expect(lineOf(released.single, 'late').earned, 500);
    },
  );

  test(
    'الحصة الملغاة لا تُحسب: تكتمل الدورة بثماني حصص منعقدة فعلاً',
    () async {
      // تُلغى حصة قبل انعقادها فتُبرمج بدلها حصة في آخر الدورة.
      final cancelled = await sessionOn('2026-11-17');
      await cycles.cancelSession(cancelled.id);
      final dates = [
        for (final s in await cycles.cycleSessions('g1', 1))
          if (s.status != SessionStatus.cancelled.code) s.date,
      ];
      expect(dates, hasLength(8));
      expect(dates, isNot(contains('2026-11-17')));
      for (final date in dates.take(7)) {
        await hold(date, ['old']);
      }
      expect(
        (await group()).currentCycleNumber,
        1,
        reason: 'سبع حصص لا تكمل الشهر',
      );
      await hold(dates.last, ['old']);
      expect((await group()).currentCycleNumber, 2);
    },
  );
}
