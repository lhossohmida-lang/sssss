import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late DuesService dues;
  late CycleService cycles;
  late AttendanceService attendance;
  late PaymentService payments;
  late PayoutService payouts;
  late PayoutQueries queries;

  // سبت 2026-11-14 وثلاثاء 2026-11-17؛ دورة من حصتين، ونصيب الأستاذ 1000.
  setUp(() async {
    env = TestEnv();
    dues = DuesService(env.db, env.writer);
    cycles = CycleService(env.db, env.writer);
    attendance = AttendanceService(env.db, env.writer, cycles, dues);
    payments = PaymentService(
      env.db,
      env.writer,
      dues,
      DeviceInfoStore(env.db, random: Random(3)),
    );
    payouts = PayoutService(env.db, env.writer, dues);
    queries = PayoutQueries(env.db, payouts);
    await env.subject();
    await env.teacher();
    await env.group(sessionsPerCycle: 2, rate: 1000);
    await env.slot(id: 'sl-sat', weekday: 6);
    await env.slot(id: 'sl-tue', weekday: 2);
    await env.student();
    await env.student(id: 's2');
    await env.enroll(id: 'e1', studentId: 's1', price: 2000);
    await env.enroll(id: 'e2', studentId: 's2', price: 2000);
    await cycles.topUp('g1', fromDate: '2026-11-14');
  });
  tearDown(() => env.close());

  /// الطالبان يحضران الحصتين، ويسدّد s1 فقط، ثم تنتهي الدورة.
  Future<void> completeCycleWithS1Paid() async {
    for (final s in await cycles.cycleSessions('g1', 1)) {
      await attendance.markAllPresent(s.id);
    }
    await payments.record(
      studentId: 's1',
      type: PaymentType.month,
      groupId: 'g1',
      cycleNumber: 1,
      amount: 2000,
    );
    await attendance.closeDueSessions(DateTime(2026, 11, 18));
  }

  test('لا خلاصات: قوائم وملخص فارغان', () async {
    expect(await queries.list(), isEmpty);
    final summary = await queries.summary();
    expect(summary.unpaid, 0);
    expect(summary.paid, 0);
    expect(summary.pending, 0);
    expect(await queries.detail('nope'), isNull);
  });

  test(
    'اكتمال الدورة ينشئ الخلاص تلقائياً: المسدَّد فقط يستحق ومعه معلّق',
    () async {
      await completeCycleWithS1Paid();
      final items = await queries.list();
      expect(items, hasLength(1));
      final item = items.single;
      expect(item.isRelease, isFalse);
      expect(item.kindLabel, 'اكتمال الدورة');
      expect(item.teacherName, 'الأستاذ t1');
      expect(item.groupLabel, 'رياضيات · المجموعة 1 · الدورة 1');
      expect(item.amount, 1000);
      expect(item.isPaid, isFalse);

      final summary = await queries.summary();
      expect(summary.unpaid, 1000);
      expect(summary.paid, 0);
      expect(summary.pending, 1000);
    },
  );

  test('التفصيل بأسماء التلاميذ والنصيب المعلّق', () async {
    await completeCycleWithS1Paid();
    final id = (await queries.list()).single.id;
    final detail = (await queries.detail(id))!;
    expect(detail.ratePerStudent, 1000);
    expect(detail.pending, 1000);
    final s1 = detail.lines.firstWhere((l) => l.name == 'تلميذ s1');
    expect(s1.line.attended, 2);
    expect(s1.line.earned, 1000);
    final s2 = detail.lines.firstWhere((l) => l.name == 'تلميذ s2');
    expect(s2.line.earned, 0);
    expect(s2.line.pending, 1000);
    expect(detail.paidByName, isNull);
  });

  test('التسليم يغيّر الحالة والملخص والمصفّيات', () async {
    await completeCycleWithS1Paid();
    final id = (await queries.list()).single.id;
    expect(await payouts.markPaid(id, paidBy: 'u1'), isTrue);
    expect(await payouts.markPaid(id, paidBy: 'u1'), isFalse);
    expect(await queries.list(status: PayoutStatus.unpaid), isEmpty);
    expect(await queries.list(status: PayoutStatus.paid), hasLength(1));
    final summary = await queries.summary();
    expect(summary.unpaid, 0);
    expect(summary.paid, 1000);
    final detail = (await queries.detail(id))!;
    expect(detail.item.isPaid, isTrue);
    expect(detail.paidByName, '—', reason: 'حساب المسلِّم غير موجود محلياً');
  });

  test(
    'تسديد التلميذ المتأخر يُفرج عن نصيبه في خلاص جديد غير مسلَّم',
    () async {
      await completeCycleWithS1Paid();
      final first = (await queries.list()).single;
      await payouts.markPaid(first.id, paidBy: 'u1');

      await payments.record(
        studentId: 's2',
        type: PaymentType.month,
        groupId: 'g1',
        cycleNumber: 1,
        amount: 2000,
      );
      final items = await queries.list();
      expect(items, hasLength(2));
      final release = items.firstWhere((i) => i.isRelease);
      expect(release.kindLabel, 'إفراج عن نصيب معلّق');
      expect(release.amount, 1000);
      expect(release.isPaid, isFalse);
      final summary = await queries.summary();
      expect(summary.unpaid, 1000);
      expect(summary.paid, 1000);
      expect(summary.pending, 0);
    },
  );

  test('الدفع الجزئي يُفرج عن جزء، ولا يتكرر الإفراج', () async {
    await completeCycleWithS1Paid();
    await payments.record(
      studentId: 's2',
      type: PaymentType.month,
      groupId: 'g1',
      cycleNumber: 1,
      amount: 1000,
    );
    final releases = (await queries.list()).where((i) => i.isRelease).toList();
    expect(releases, hasLength(1));
    // نصف الدورة مدفوع = حصة واحدة مغطاة: 1000 × 1 ÷ 2.
    expect(releases.single.amount, 500);
    // دفعة أخرى للباقي تُفرج عن الجزء الثاني فقط.
    await payments.record(
      studentId: 's2',
      type: PaymentType.month,
      groupId: 'g1',
      cycleNumber: 1,
      amount: 1000,
    );
    final all = (await queries.list()).where((i) => i.isRelease).toList();
    expect(all, hasLength(2));
    expect(all.fold<int>(0, (sum, i) => sum + i.amount), 1000);
  });

  test('الحصر بالأستاذ', () async {
    await completeCycleWithS1Paid();
    expect(await queries.list(teacherId: 't1'), hasLength(1));
    expect(await queries.list(teacherId: 'other'), isEmpty);
    expect((await queries.summary(teacherId: 'other')).unpaid, 0);
    expect((await queries.summary(teacherId: 't1')).unpaid, 1000);
  });

  test('watch يتحدث عند التسليم', () async {
    await completeCycleWithS1Paid();
    final id = (await queries.list()).single.id;
    final seen = <bool>[];
    final sub = queries.watch().listen((l) => seen.add(l.single.isPaid));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await payouts.markPaid(id, paidBy: 'u1');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await sub.cancel();
    expect(seen.first, isFalse);
    expect(seen.last, isTrue);
  });
}
