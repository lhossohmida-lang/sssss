import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late DuesService dues;
  late PayoutService payouts;
  var receipt = 0;

  setUp(() async {
    receipt = 0;
    env = TestEnv();
    dues = DuesService(env.db, env.writer);
    payouts = PayoutService(env.db, env.writer, dues);
    await env.subject();
    await env.teacher(); // rate = 1000
    await env.group(); // دورة من 8 حصص
    for (var n = 1; n <= 8; n++) {
      await env.db
          .into(env.db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 'se$n',
              createdAt: 1,
              updatedAt: 1,
              groupId: 'g1',
              cycleNumber: 1,
              sessionNumber: Value(n),
              date: '2026-11-${(10 + n).toString().padLeft(2, '0')}',
              startMinutes: 600,
              endMinutes: 690,
              closedAt: const Value(5),
            ),
          );
    }
  });

  tearDown(() => env.close());

  /// ينسّب تلميذاً ويسجّل حضوره في أول [present] حصة وغيابه في الباقي.
  Future<void> student(
    String id, {
    required int present,
    String discountType = 'none',
    int discountValue = 0,
    int excused = 0,
  }) async {
    await env.student(id: id);
    await env.enroll(
      id: 'gs-$id',
      studentId: id,
      discountType: discountType,
      discountValue: discountValue,
    );
    for (var n = 1; n <= 8; n++) {
      final status = n <= present
          ? 'present'
          : (n <= present + excused ? 'excused' : 'absent');
      await env.db
          .into(env.db.attendance)
          .insert(
            AttendanceCompanion.insert(
              id: 'att-$id-$n',
              createdAt: 1,
              updatedAt: 1,
              sessionId: 'se$n',
              studentId: id,
              status: status,
              method: 'qr',
            ),
          );
    }
  }

  Future<void> pay(String studentId, int amount) => dues.recordMonthPayment(
    studentId: studentId,
    groupId: 'g1',
    cycleNumber: 1,
    amount: amount,
    receivedBy: 'u1',
    receiptNumber: 'A-${(++receipt).toString().padLeft(6, '0')}',
  );

  group('القواعد', () {
    test('الحصص المغطاة بنسبة ما دُفع، مقرَّبة للأسفل', () {
      int covered(int settled, {int net = 2000, bool exempt = false}) =>
          PayoutRules.coveredSessions(
            netPrice: net,
            settled: settled,
            sessionsPerCycle: 8,
            exempt: exempt,
          );
      expect(covered(0), 0);
      expect(covered(1000), 4);
      expect(covered(1200), 4, reason: '4.8 حصة تُقرَّب للأسفل');
      expect(covered(1250), 5);
      expect(covered(2000), 8);
      expect(covered(9999), 8);
      expect(covered(0, exempt: true), 8);
      expect(covered(0, net: 0), 8);
    });

    test('النصيب عن أصغر العددين: المحضورة والمغطاة', () {
      PayoutLine line(int attended, int covered) => PayoutRules.line(
        studentId: 's',
        ratePerStudent: 1000,
        attended: attended,
        covered: covered,
        sessionsPerCycle: 8,
      );
      expect(line(8, 8).earned, 1000);
      expect(line(4, 8).earned, 500);
      expect(line(6, 4).earned, 500);
      expect(line(6, 4).full, 750);
      expect(line(6, 4).pending, 250);
      expect(line(0, 8).earned, 0);
      expect(line(8, 0).earned, 0);
      expect(line(8, 0).pending, 1000);
      expect(line(3, 8).earned, 380, reason: '375 تُقرَّب إلى 380');
    });
  });

  test('مثال المواصفات: حضر 8 ← 1000، حضر 4 ← 500، الخلاص 1500', () async {
    await student('s1', present: 8);
    await student('s2', present: 4);
    await pay('s1', 2000);
    await pay('s2', 2000);

    final payout = await payouts.compute('g1', 1);
    expect(payout.ratePerStudent, 1000);
    expect(
      {for (final l in payout.lines) l.studentId: l.earned},
      {'s1': 1000, 's2': 500},
    );
    expect(payout.earned, 1500);
    expect(payout.pending, 0);
  });

  test('الغياب برخصة أو بدونها لا يُحسب للأستاذ', () async {
    await student('s1', present: 5, excused: 2);
    await pay('s1', 2000);
    final line = (await payouts.compute('g1', 1)).lines.single;
    expect(line.attended, 5);
    expect(line.earned, 630); // 1000 × 5 ÷ 8 = 625 ← 630
  });

  test('تلميذ لم يدفع: لا نصيب للأستاذ حتى يدفع', () async {
    await student('s1', present: 8);
    final payout = await payouts.compute('g1', 1);
    expect(payout.earned, 0);
    expect(payout.pending, 1000);
  });

  test('الدفع الجزئي: نصيب الحصص المدفوعة والمحضورة فقط', () async {
    await student('s1', present: 6);
    await pay('s1', 1000); // نصف الشهر يغطي 4 حصص
    final line = (await payouts.compute('g1', 1)).lines.single;
    expect(line.covered, 4);
    expect(line.attended, 6);
    expect(line.earned, 500);
    expect(line.pending, 250);
  });

  test('دفع كل الشهر وحضر قليلاً: النصيب عن المحضورة فقط', () async {
    await student('s1', present: 2);
    await pay('s1', 2000);
    final line = (await payouts.compute('g1', 1)).lines.single;
    expect(line.earned, 250);
    expect(line.pending, 0);
  });

  test('المعفى يأخذ الأستاذ نصيبه كاملاً حسب الحضور', () async {
    await student('s1', present: 8, discountType: 'exempt');
    await student('s2', present: 4, discountType: 'exempt');
    final payout = await payouts.compute('g1', 1);
    expect(payout.earned, 1500);
    expect(payout.pending, 0);
  });

  test('صاحب التخفيض: تسديد السعر المخفَّض يغطي كل الحصص', () async {
    await student('s1', present: 8, discountType: 'percent', discountValue: 50);
    await pay('s1', 1000);
    expect((await payouts.compute('g1', 1)).earned, 1000);
  });

  test('الرصيد المخصوم يُعتبر مدفوعاً', () async {
    await student('s1', present: 8);
    await env.db
        .into(env.db.studentCredits)
        .insert(
          StudentCreditsCompanion.insert(
            id: 'c1',
            createdAt: 1,
            updatedAt: 1,
            studentId: 's1',
            groupId: 'g1',
            amount: 1000,
            reason: 'mid_join',
            sourceCycleNumber: 0,
            targetCycleNumber: 1,
          ),
        );
    expect((await payouts.compute('g1', 1)).lines.single.covered, 4);
    await pay('s1', 1000);
    expect((await payouts.compute('g1', 1)).earned, 1000);
  });

  test('سعر المجموعة يغلب السعر الافتراضي للأستاذ', () async {
    await (env.db.update(env.db.groups)..where((g) => g.id.equals('g1'))).write(
      const GroupsCompanion(ratePerStudent: Value(1600)),
    );
    await student('s1', present: 8);
    await pay('s1', 2000);
    final payout = await payouts.compute('g1', 1);
    expect(payout.ratePerStudent, 1600);
    expect(payout.earned, 1600);
  });

  test('الحصة الملغاة لا تدخل في الحضور المحسوب', () async {
    await student('s1', present: 8);
    await pay('s1', 2000);
    await (env.db.update(env.db.sessions)..where((s) => s.id.equals('se8')))
        .write(const SessionsCompanion(status: Value('cancelled')));
    expect((await payouts.compute('g1', 1)).lines.single.attended, 7);
  });

  test('حفظ خلاص الدورة مع التفصيل، مرة واحدة فقط', () async {
    await student('s1', present: 8);
    await student('s2', present: 4);
    await pay('s1', 2000);
    await pay('s2', 2000);

    final saved = await payouts.createCyclePayout('g1', 1);
    expect(saved.amount, 1500);
    expect(saved.kind, 'cycle');
    expect(saved.teacherId, 't1');
    expect(saved.paidAt, isNull);
    final lines = PayoutService.linesOf(saved);
    expect(lines.map((l) => l.studentId), ['s1', 's2']);
    expect(lines.map((l) => l.earned), [1000, 500]);

    final again = await payouts.createCyclePayout('g1', 1);
    expect(again.id, saved.id);
    expect(await env.db.select(env.db.teacherPayouts).get(), hasLength(1));
  });

  test('النصيب المعلّق يُصرف في خلاص لاحق عند تسديد التلميذ', () async {
    await student('s1', present: 8);
    await student('s2', present: 8);
    await pay('s1', 2000);
    await pay('s2', 500); // يغطي حصتين

    final first = await payouts.createCyclePayout('g1', 1);
    expect(first.amount, 1250); // 1000 + 250
    expect(await payouts.releasePending('g1'), isEmpty);

    await pay('s2', 500); // صار المغطى 4 حصص
    final partial = await payouts.releasePending('g1');
    expect(partial.single.kind, 'release');
    expect(partial.single.amount, 250);
    expect(PayoutService.linesOf(partial.single).single.studentId, 's2');

    await pay('s2', 1000); // سدّد الكل
    final rest = await payouts.releasePending('g1');
    expect(rest.single.amount, 500);

    expect(
      await payouts.releasePending('g1'),
      isEmpty,
      reason: 'لا يُصرف نفس النصيب مرتين',
    );
    final all = await env.db.select(env.db.teacherPayouts).get();
    expect(all.fold<int>(0, (sum, p) => sum + p.amount), 2000);
  });

  test('تسليم المال يُسجَّل مرة واحدة باسم من سلّم', () async {
    await student('s1', present: 8);
    await pay('s1', 2000);
    final saved = await payouts.createCyclePayout('g1', 1);

    expect(await payouts.markPaid(saved.id, paidBy: 'u1'), isTrue);
    expect(await payouts.markPaid(saved.id, paidBy: 'u2'), isFalse);
    final row = await env.db.select(env.db.teacherPayouts).getSingle();
    expect(row.paidAt, isNotNull);
    expect(row.paidBy, 'u1');

    final audit = await (env.db.select(
      env.db.auditLog,
    )..where((a) => a.action.equals('pay_teacher'))).get();
    expect(audit, hasLength(1));
  });
}
