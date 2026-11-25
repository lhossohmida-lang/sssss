import 'dart:math';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

/// طلبات صاحب المدرسة في الحضور والدفع:
///
/// - حذف حضور حصة كله بنقرة، ودفع حصة بنقرة، وتسجيل حضور حصة لم يأتِ موعدها.
/// - في كل فوج: ما دفعه التلاميذ، وحق الأستاذ، وحق المدير (الأول ناقص الثاني).
/// - تلميذ مجاني: لا يُحسب على أحد، أو على الإدارة (الأستاذ يأخذ حقه)، أو على الأستاذ (لا يأخذ شيئاً
///   ويعطي المدرسة نصيبها).
/// - الانتساب من حصة يختارها المدير (الثالثة مثلاً): ما قبلها رصيد يظهر مدفوعاً في الشهر التالي،
///   ودفع عدد من الحصص (3 أو 5).
///
/// الأسعار: الشهر 2000 دج لـ8 حصص (250 للحصة)، ونصيب الأستاذ 1000 دج.
void main() {
  late TestEnv env;
  late CycleService cycles;
  late DuesService dues;
  late AttendanceService attendance;
  late EnrolmentService enrolments;
  late PaymentService payments;
  late PayoutService payouts;

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
    payouts = PayoutService(env.db, env.writer, dues);
    await env.subject();
    await env.teacher();
    await env.group();
    await env.slot(id: 'sl-sat', weekday: 6);
    await env.slot(id: 'sl-tue', weekday: 2);
    await cycles.topUp('g1', fromDate: '2026-11-14');
  });

  tearDown(() => env.close());

  Future<List<SessionRow>> sessions() =>
      (env.db.select(env.db.sessions)
            ..where((s) => s.groupId.equals('g1') & s.cycleNumber.equals(1))
            ..orderBy([(s) => OrderingTerm(expression: s.date)]))
          .get();

  Future<void> enrol(
    String id, {
    DiscountType type = DiscountType.none,
    DiscountBearer bearer = DiscountBearer.school,
    int? custom,
    int? firstSession,
  }) async {
    await env.student(id: id);
    await enrolments.enrol(
      studentId: id,
      groupId: 'g1',
      discountType: type,
      bearer: bearer,
      customTeacherAmount: custom,
      firstSession: firstSession,
    );
  }

  test('حذف حضور حصة كله، ولو مغلقة، ومعه رصيد الغياب برخصة', () async {
    await enrol('a');
    await enrol('b');
    final first = (await sessions()).first;
    await attendance.markAllPresent(first.id);
    await attendance.mark(
      sessionId: first.id,
      studentId: 'b',
      status: AttendanceStatus.excused,
      canExcuse: true,
    );
    await (env.db.update(env.db.sessions)..where((s) => s.id.equals(first.id)))
        .write(const SessionsCompanion(closedAt: Value(5)));
    expect(await attendance.clearSession(first.id), 2);
    final left = await (env.db.select(
      env.db.attendance,
    )..where((a) => a.deletedAt.isNull())).get();
    expect(left, isEmpty);
    final credits = await (env.db.select(
      env.db.studentCredits,
    )..where((c) => c.deletedAt.isNull())).get();
    expect(credits, isEmpty);
  });

  test('حضور حصة لم يأتِ موعدها يُسجَّل', () async {
    await enrol('a');
    final last = (await sessions()).last;
    await attendance.mark(
      sessionId: last.id,
      studentId: 'a',
      status: AttendanceStatus.present,
    );
    final row = await env.db.select(env.db.attendance).getSingle();
    expect(row.status, AttendanceStatus.present.code);
  });

  test('دفع حصة بنقرة: ثمنها للحاضرين غير المسدَّدين وحدهم', () async {
    await enrol('a');
    await enrol('b');
    await enrol('free', type: DiscountType.exempt);
    final first = (await sessions()).first;
    await attendance.mark(
      sessionId: first.id,
      studentId: 'a',
      status: AttendanceStatus.present,
    );
    await attendance.mark(
      sessionId: first.id,
      studentId: 'free',
      status: AttendanceStatus.present,
    );
    await attendance.mark(
      sessionId: first.id,
      studentId: 'b',
      status: AttendanceStatus.absent,
    );
    expect(await payments.paySessionForPresent(first.id), 1);
    final paid = await env.db.select(env.db.payments).getSingle();
    expect(paid.studentId, 'a');
    expect(paid.amount, 250);
    final due = await dues.cycleDue(
      studentId: 'a',
      groupId: 'g1',
      cycleNumber: 1,
    );
    expect(due!.coveredSessions(8), 1);
  });

  test('دفع عدد من الحصص (3 ثم 5) يغطيها في الشبكة', () async {
    await enrol('a');
    await payments.paySessions(
      studentId: 'a',
      groupId: 'g1',
      cycleNumber: 1,
      sessions: 3,
    );
    await payments.paySessions(
      studentId: 'a',
      groupId: 'g1',
      cycleNumber: 1,
      sessions: 5,
    );
    final grid = await GroupGridQueries(env.db, dues: dues).load('g1');
    expect(grid!.students.single.coveredSessions, 8);
    await expectLater(
      payments.paySessions(studentId: 'a', groupId: 'g1', cycleNumber: 1),
      throwsA(isA<ValidationException>()),
    );
  });

  test('يبدأ من الحصة الثالثة ويدفع الشهر: حصتان تظهران مدفوعتين (بالأزرق) في الشهر التالي', () async {
    await enrol('a', firstSession: 3);
    final enrolment = await env.db.select(env.db.groupStudents).getSingle();
    expect(enrolment.joinedAtSessionNumber, 3);
    await payments.paySessions(
      studentId: 'a',
      groupId: 'g1',
      cycleNumber: 1,
      sessions: 8,
    );
    // الشهر الثاني.
    await env.db.customStatement(
      "UPDATE groups SET current_cycle_number = 2 WHERE id = 'g1'",
    );
    final grid = await GroupGridQueries(
      env.db,
      dues: dues,
    ).load('g1', cycleNumber: 2);
    final student = grid!.students.single;
    expect(student.creditSessions, 2);
    expect(student.creditAt(1), isTrue);
    expect(student.creditAt(2), isFalse);
    expect(student.coveredSessions, 2);
  });

  group('تلميذ مجاني', () {
    Future<int> teacherFor(String id) async {
      final row = await (env.db.select(
        env.db.groupStudents,
      )..where((g) => g.studentId.equals(id))).getSingle();
      return row.teacherAmount ?? 1000;
    }

    test('لا يُحسب على أحد: الأستاذ لا يأخذ شيئاً', () async {
      await enrol(
        'n',
        type: DiscountType.exempt,
        bearer: DiscountBearer.custom,
        custom: 0,
      );
      expect(await teacherFor('n'), 0);
    });

    test('على الإدارة: الأستاذ يأخذ حقه كاملاً', () async {
      await enrol('s', type: DiscountType.exempt);
      expect(await teacherFor('s'), 1000);
    });

    test('على الأستاذ: لا يأخذ شيئاً ويُخصم من حقه نصيب المدرسة', () async {
      await enrol(
        't',
        type: DiscountType.exempt,
        bearer: DiscountBearer.teacherFull,
      );
      // نصيب المدرسة من 2000 هو 1000.
      expect(await teacherFor('t'), -1000);
    });
  });

  test('مال الفوج: ما دفعه التلاميذ، وحق الأستاذ، وحق المدير', () async {
    await enrol('a');
    await enrol('b');
    await enrol('s', type: DiscountType.exempt);
    final first = (await sessions()).first;
    await attendance.markAllPresent(first.id);
    await payments.paySessions(
      studentId: 'a',
      groupId: 'g1',
      cycleNumber: 1,
      sessions: 8,
    );
    final money = await payouts.groupMoney('g1', 1);
    expect(money.paid, 2000);
    // حصة واحدة حضرها كل منهم: a دفع (130 بالتقريب)، والمجاني على الإدارة يُحسب (130)، وb لم يدفع (معلّق).
    expect(money.teacher, 260);
    expect(money.teacherPending, 130);
    expect(money.admin, 1740);
  });
}
