import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late DuesService dues;
  late CycleService cycles;
  var receipt = 0;

  String nextReceipt() => 'A-${(++receipt).toString().padLeft(6, '0')}';

  setUp(() async {
    receipt = 0;
    env = TestEnv();
    dues = DuesService(env.db, env.writer);
    cycles = CycleService(env.db, env.writer);
    await env.subject();
    await env.teacher();
    await env.group(); // دورة من 8 حصص
    await env.student();
  });

  tearDown(() => env.close());

  Future<void> pay(int amount, {int cycle = 1, String student = 's1'}) =>
      dues.recordMonthPayment(
        studentId: student,
        groupId: 'g1',
        cycleNumber: cycle,
        amount: amount,
        receivedBy: 'u1',
        receiptNumber: nextReceipt(),
      );

  Future<void> setCycle(int cycle) async {
    await (env.db.update(env.db.groups)..where((g) => g.id.equals('g1'))).write(
      GroupsCompanion(currentCycleNumber: Value(cycle)),
    );
  }

  Future<SessionRow> session(
    String id, {
    int cycle = 1,
    int number = 1,
    bool closed = false,
  }) async {
    await env.db
        .into(env.db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: id,
            createdAt: 1,
            updatedAt: 1,
            groupId: 'g1',
            cycleNumber: cycle,
            sessionNumber: Value(number),
            date: '2026-11-${(10 + number).toString().padLeft(2, '0')}',
            startMinutes: 600 + cycle,
            endMinutes: 690,
            closedAt: Value(closed ? 5 : null),
          ),
        );
    return (env.db.select(
      env.db.sessions,
    )..where((s) => s.id.equals(id))).getSingle();
  }

  Future<void> attend(String sessionId, AttendanceStatus status) async {
    await env.db
        .into(env.db.attendance)
        .insertOnConflictUpdate(
          AttendanceCompanion.insert(
            id: 'att-$sessionId',
            createdAt: 1,
            updatedAt: 1,
            sessionId: sessionId,
            studentId: 's1',
            status: status.code,
            method: 'manual',
          ),
        );
  }

  group('الأسعار', () {
    test('التخفيض بالنسبة وبالمبلغ والإعفاء', () {
      int net(DiscountType t, int v, {int price = 2000}) =>
          Pricing.netPrice(price: price, discountType: t, discountValue: v);
      expect(net(DiscountType.none, 0), 2000);
      expect(net(DiscountType.percent, 25), 1500);
      expect(net(DiscountType.percent, 33), 1340);
      expect(net(DiscountType.percent, 150), 0, reason: 'النسبة لا تتجاوز 100');
      expect(net(DiscountType.fixed, 300), 1700);
      expect(net(DiscountType.fixed, 5000), 0, reason: 'لا سعر سالب');
      expect(net(DiscountType.exempt, 0), 0);
      expect(
        () => Pricing.netPrice(
          price: -1,
          discountType: DiscountType.none,
          discountValue: 0,
        ),
        throwsArgumentError,
      );
    });

    test('قيمة الحصص من الدورة', () {
      int value(int sessions, {int net = 2000, int spc = 8}) =>
          Pricing.sessionsValue(
            netPrice: net,
            sessions: sessions,
            sessionsPerCycle: spc,
          );
      expect(value(1), 250);
      expect(value(4), 1000);
      expect(value(0), 0);
      expect(value(20), 2000, reason: 'لا تتجاوز سعر الدورة');
      expect(value(1, net: 1000, spc: 3), 330);
      expect(() => value(1, spc: 0), throwsArgumentError);
    });
  });

  group('مستحقات الدورة', () {
    test('التلميذ مدين بالشهر كاملاً منذ التحاقه', () async {
      await env.enroll(id: 'gs1', studentId: 's1');
      final due = (await dues.cycleDues(studentId: 's1')).single;
      expect(due.cycleNumber, 1);
      expect(due.netPrice, 2000);
      expect(due.due, 2000);
      expect(due.paid, 0);
      expect(due.remaining, 2000);
      expect(due.isSettled, isFalse);
    });

    test('الغياب دون رخصة لا يخصم شيئاً', () async {
      await env.enroll(id: 'gs1', studentId: 's1');
      final s = await session('se1');
      await attend(s.id, AttendanceStatus.absent);
      await dues.syncExcusedCredit(sessionId: s.id, studentId: 's1');
      await setCycle(2);
      final all = await dues.cycleDues(studentId: 's1');
      expect(all.map((d) => d.due), [2000, 2000]);
    });

    test('الدفع الجزئي ثم إكمال الباقي، ورفض الزيادة', () async {
      await env.enroll(id: 'gs1', studentId: 's1');
      await pay(800);
      var due = (await dues.cycleDues(studentId: 's1')).single;
      expect(due.paid, 800);
      expect(due.remaining, 1200);

      await expectLater(pay(1300), throwsArgumentError);
      await expectLater(pay(0), throwsArgumentError);
      await expectLater(pay(-5), throwsArgumentError);

      await pay(1200);
      due = (await dues.cycleDues(studentId: 's1')).single;
      expect(due.isSettled, isTrue);
      expect(await dues.cycleDues(unpaidOnly: true), isEmpty);
      await expectLater(pay(10), throwsArgumentError);
    });

    test('الدفع عن دورة غير ملزَم بها يُرفض', () async {
      await env.enroll(id: 'gs1', studentId: 's1');
      await expectLater(pay(100, cycle: 5), throwsStateError);
      await env.student(id: 's2');
      await expectLater(pay(100, student: 's2'), throwsStateError);
    });

    test('التخفيض والإعفاء في المستحق', () async {
      await env.student(id: 's2');
      await env.student(id: 's3');
      await env.enroll(
        id: 'gs1',
        studentId: 's1',
        discountType: 'percent',
        discountValue: 50,
      );
      await env.enroll(
        id: 'gs2',
        studentId: 's2',
        discountType: 'fixed',
        discountValue: 500,
      );
      await env.enroll(id: 'gs3', studentId: 's3', discountType: 'exempt');
      final all = await dues.cycleDues(groupId: 'g1');
      expect(
        {for (final d in all) d.studentId: d.due},
        {'s1': 1000, 's2': 1500, 's3': 0},
      );
      final exempt = all.firstWhere((d) => d.studentId == 's3');
      expect(exempt.exempt, isTrue);
      expect(exempt.isSettled, isTrue);
      expect(
        (await dues.cycleDues(
          groupId: 'g1',
          unpaidOnly: true,
        )).map((d) => d.studentId),
        ['s1', 's2'],
      );
    });

    test('دفعة محذوفة حذفاً ناعماً لا تُحسب', () async {
      await env.enroll(id: 'gs1', studentId: 's1');
      await pay(2000);
      final payment = await env.db.select(env.db.payments).getSingle();
      await env.writer.softDelete(env.db.payments, key: {'id': payment.id});
      expect((await dues.cycleDues(studentId: 's1')).single.remaining, 2000);
    });

    test('من غادر المجموعة لا تُحسب عليه الدورات اللاحقة', () async {
      await env.enroll(id: 'gs1', studentId: 's1');
      await session('se1', cycle: 1, number: 1); // 2026-11-11
      await session('se2', cycle: 2, number: 9); // 2026-11-19
      await setCycle(3);
      final leftAt = DateTime(2026, 11, 12, 12).millisecondsSinceEpoch;
      await (env.db.update(env.db.groupStudents)
            ..where((gs) => gs.id.equals('gs1')))
          .write(GroupStudentsCompanion(leftAt: Value(leftAt)));
      final all = await dues.cycleDues(studentId: 's1');
      expect(all.map((d) => d.cycleNumber), [1]);
    });
  });

  group('الأرصدة', () {
    test('الغياب برخصة يصير رصيداً يُخصم من الدورة التالية', () async {
      await env.enroll(id: 'gs1', studentId: 's1');
      final s1 = await session('se1', number: 1);
      final s2 = await session('se2', number: 2);
      await attend(s1.id, AttendanceStatus.excused);
      await attend(s2.id, AttendanceStatus.excused);
      await dues.syncExcusedCredit(sessionId: s1.id, studentId: 's1');
      await dues.syncExcusedCredit(sessionId: s2.id, studentId: 's1');
      await dues.syncExcusedCredit(sessionId: s2.id, studentId: 's1');

      final credits = await env.db.select(env.db.studentCredits).get();
      expect(credits, hasLength(2), reason: 'لا يُحتسب الرصيد مرتين');
      expect(credits.map((c) => c.amount), everyElement(250));
      expect(credits.map((c) => c.targetCycleNumber), everyElement(2));

      await setCycle(2);
      final all = await dues.cycleDues(studentId: 's1');
      expect(all[0].due, 2000, reason: 'الدورة الحالية تُدفع كاملة');
      expect(all[1].credits, 500);
      expect(all[1].due, 1500);
    });

    test('تصحيح الغياب برخصة إلى حاضر يلغي الرصيد', () async {
      await env.enroll(id: 'gs1', studentId: 's1');
      final s = await session('se1');
      await attend(s.id, AttendanceStatus.excused);
      await dues.syncExcusedCredit(sessionId: s.id, studentId: 's1');
      await attend(s.id, AttendanceStatus.present);
      await dues.syncExcusedCredit(sessionId: s.id, studentId: 's1');

      await setCycle(2);
      final all = await dues.cycleDues(studentId: 's1');
      expect(all[1].credits, 0);
      expect(all[1].due, 2000);
    });

    test(
      'رصيد الغياب برخصة يُحسب على السعر بعد التخفيض، ولا رصيد للمعفى',
      () async {
        await env.student(id: 's2');
        await env.enroll(
          id: 'gs1',
          studentId: 's1',
          discountType: 'percent',
          discountValue: 50,
        );
        final s = await session('se1');
        await attend(s.id, AttendanceStatus.excused);
        await dues.syncExcusedCredit(sessionId: s.id, studentId: 's1');
        expect(
          (await env.db.select(env.db.studentCredits).getSingle()).amount,
          130, // 1000 ÷ 8 = 125 ← تُقرَّب إلى 130
        );

        await env.enroll(id: 'gs2', studentId: 's2', discountType: 'exempt');
        await env.db
            .into(env.db.attendance)
            .insert(
              AttendanceCompanion.insert(
                id: 'att-s2',
                createdAt: 1,
                updatedAt: 1,
                sessionId: s.id,
                studentId: 's2',
                status: 'excused',
                method: 'manual',
              ),
            );
        await dues.syncExcusedCredit(sessionId: s.id, studentId: 's2');
        expect(await env.db.select(env.db.studentCredits).get(), hasLength(1));
      },
    );

    test(
      'الملتحق في منتصف الدورة: مثال 2000 دج، دورة 8، التحق عند الحصة 5',
      () async {
        await env.enroll(id: 'gs1', studentId: 's1', joinedSession: 5);
        expect(
          await dues.createMidJoinCredit(studentId: 's1', groupId: 'g1'),
          1000,
        );
        expect(
          await dues.createMidJoinCredit(studentId: 's1', groupId: 'g1'),
          1000,
          reason: 'لا يُنشأ الرصيد مرتين',
        );
        expect(await env.db.select(env.db.studentCredits).get(), hasLength(1));

        await setCycle(2);
        final all = await dues.cycleDues(studentId: 's1');
        expect(all[0].due, 2000, reason: 'يدفع شهر الالتحاق كاملاً');
        expect(all[1].due, 1000, reason: 'الفرق رصيد للشهر القادم');
      },
    );

    test('الملتحق من بداية الدورة لا رصيد له', () async {
      await env.enroll(id: 'gs1', studentId: 's1');
      expect(await dues.createMidJoinCredit(studentId: 's1', groupId: 'g1'), 0);
      expect(await env.db.select(env.db.studentCredits).get(), isEmpty);
    });

    test('الملتحق في دورة لاحقة غير مدين بما قبلها', () async {
      await setCycle(3);
      await env.enroll(id: 'gs1', studentId: 's1', joinedCycle: 3);
      final all = await dues.cycleDues(studentId: 's1');
      expect(all.map((d) => d.cycleNumber), [3]);
    });

    test('الرصيد الزائد عن السعر لا يجعل المستحق سالباً', () async {
      await env.enroll(id: 'gs1', studentId: 's1', joinedSession: 8);
      await dues.createMidJoinCredit(studentId: 's1', groupId: 'g1'); // 1750
      final s = await session('se1', number: 8);
      await attend(s.id, AttendanceStatus.excused);
      await dues.syncExcusedCredit(sessionId: s.id, studentId: 's1'); // 250
      final s2 = await session('se2', number: 7);
      await attend(s2.id, AttendanceStatus.excused);
      await dues.syncExcusedCredit(sessionId: s2.id, studentId: 's1'); // 250
      await setCycle(2);
      final second = (await dues.cycleDues(studentId: 's1'))[1];
      expect(second.credits, 2250);
      expect(second.due, 0);
      expect(second.remaining, 0);
    });
  });

  group('عليه مستحقات', () {
    test('دورة سابقة غير مسدَّدة', () async {
      await env.enroll(id: 'gs1', studentId: 's1');
      await setCycle(2);
      await pay(2000, cycle: 2);
      expect(await dues.hasOutstanding(studentId: 's1', groupId: 'g1'), isTrue);
      await pay(2000, cycle: 1);
      expect(
        await dues.hasOutstanding(studentId: 's1', groupId: 'g1'),
        isFalse,
      );
    });

    test('الدورة الحالية: مهلة حتى انعقاد حصتها الثانية', () async {
      await env.enroll(id: 'gs1', studentId: 's1');
      await session('se1', number: 1, closed: true);
      expect(
        await dues.hasOutstanding(studentId: 's1', groupId: 'g1'),
        isFalse,
      );
      await session('se2', number: 2, closed: true);
      expect(await dues.hasOutstanding(studentId: 's1', groupId: 'g1'), isTrue);
      expect(
        await dues.hasOutstanding(
          studentId: 's1',
          groupId: 'g1',
          graceSessions: 4,
        ),
        isFalse,
        reason: 'المهلة قابلة للضبط',
      );
      await pay(2000);
      expect(
        await dues.hasOutstanding(studentId: 's1', groupId: 'g1'),
        isFalse,
      );
    });

    test('المعفى ليس عليه مستحقات', () async {
      await env.enroll(id: 'gs1', studentId: 's1', discountType: 'exempt');
      await session('se1', number: 1, closed: true);
      await session('se2', number: 2, closed: true);
      expect(
        await dues.hasOutstanding(studentId: 's1', groupId: 'g1'),
        isFalse,
      );
    });
  });

  group('حقوق التسجيل', () {
    test('مرة واحدة لكل فترة مهما كان عدد المواد', () async {
      final first = await dues.ensureRegistrationFee(
        studentId: 's1',
        periodKey: '2026-2027',
        amount: 500,
      );
      final again = await dues.ensureRegistrationFee(
        studentId: 's1',
        periodKey: '2026-2027',
        amount: 900,
      );
      expect(again.id, first.id);
      expect(again.amount, 500);
      expect(await env.db.select(env.db.registrationFees).get(), hasLength(1));

      await dues.ensureRegistrationFee(
        studentId: 's1',
        periodKey: '2027-2028',
        amount: 500,
      );
      expect(await env.db.select(env.db.registrationFees).get(), hasLength(2));
    });

    test('الدفع الجزئي ثم الكامل يعلّمها مدفوعة', () async {
      await dues.ensureRegistrationFee(
        studentId: 's1',
        periodKey: '2026-2027',
        amount: 500,
      );
      Future<void> payFee(int amount) => dues.payRegistrationFee(
        studentId: 's1',
        periodKey: '2026-2027',
        amount: amount,
        receivedBy: 'u1',
        receiptNumber: nextReceipt(),
      );
      await payFee(200);
      expect(
        await dues.registrationFeeRemaining(
          studentId: 's1',
          periodKey: '2026-2027',
        ),
        300,
      );
      expect(
        (await env.db.select(env.db.registrationFees).getSingle()).paid,
        isFalse,
      );
      await expectLater(payFee(400), throwsArgumentError);
      await payFee(300);
      expect(
        (await env.db.select(env.db.registrationFees).getSingle()).paid,
        isTrue,
      );
      await expectLater(payFee(1), throwsArgumentError);
    });

    test('الدفع دون حقوق مسجَّلة يُرفض، والمبلغ صفر يُعتبر مدفوعاً', () async {
      await expectLater(
        dues.payRegistrationFee(
          studentId: 's1',
          periodKey: 'x',
          amount: 1,
          receivedBy: 'u1',
          receiptNumber: nextReceipt(),
        ),
        throwsStateError,
      );
      final free = await dues.ensureRegistrationFee(
        studentId: 's1',
        periodKey: 'free',
        amount: 0,
      );
      expect(free.paid, isTrue);
    });
  });

  group('النقل', () {
    test('سعر شهري منفصل حسب شهر التقويم', () async {
      expect(
        await dues.transportRemaining(studentId: 's1', month: '2026-11'),
        0,
        reason: 'لا يستعمل النقل',
      );
      await (env.db.update(
        env.db.students,
      )..where((s) => s.id.equals('s1'))).write(
        const StudentsCompanion(
          usesTransport: Value(true),
          transportPrice: Value(1500),
        ),
      );
      expect(
        await dues.transportRemaining(studentId: 's1', month: '2026-11'),
        1500,
      );
      await dues.payTransport(
        studentId: 's1',
        month: '2026-11',
        amount: 1500,
        receivedBy: 'u1',
        receiptNumber: nextReceipt(),
      );
      expect(
        await dues.transportRemaining(studentId: 's1', month: '2026-11'),
        0,
      );
      expect(
        await dues.transportRemaining(studentId: 's1', month: '2026-12'),
        1500,
      );
      await expectLater(
        dues.payTransport(
          studentId: 's1',
          month: '2026-11',
          amount: 100,
          receivedBy: 'u1',
          receiptNumber: nextReceipt(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('الوصولات', () {
    test('رقم تسلسلي لكل بادئة جهاز', () async {
      await env.enroll(id: 'gs1', studentId: 's1');
      expect(await dues.nextReceiptNumber('A'), 'A-000001');
      await dues.recordMonthPayment(
        studentId: 's1',
        groupId: 'g1',
        cycleNumber: 1,
        amount: 100,
        receivedBy: 'u1',
        receiptNumber: await dues.nextReceiptNumber('A'),
      );
      await dues.recordMonthPayment(
        studentId: 's1',
        groupId: 'g1',
        cycleNumber: 1,
        amount: 100,
        receivedBy: 'u1',
        receiptNumber: await dues.nextReceiptNumber('A'),
      );
      expect(await dues.nextReceiptNumber('A'), 'A-000003');
      expect(await dues.nextReceiptNumber('B'), 'B-000001');
    });

    test('استلام المال يُسجَّل في سجل العمليات باسم المستلم', () async {
      await env.enroll(id: 'gs1', studentId: 's1');
      await pay(500);
      final entry = await (env.db.select(
        env.db.auditLog,
      )..where((a) => a.entity.equals('payments'))).getSingle();
      expect(entry.action, 'receive_money');
      expect(entry.userName, 'المدير');
    });
  });

  test('المستحقات تتبع اكتمال الدورة الفعلي', () async {
    await env.slot(id: 'sl', weekday: 6);
    await (env.db.update(env.db.groups)..where((g) => g.id.equals('g1'))).write(
      const GroupsCompanion(sessionsPerCycle: Value(2)),
    );
    await env.enroll(id: 'gs1', studentId: 's1');
    await cycles.topUp('g1', fromDate: '2026-11-14');
    for (final s in await cycles.cycleSessions('g1', 1)) {
      await cycles.closeSession(s.id);
    }
    await cycles.completeCycleIfDone('g1', fromDate: '2026-11-22');
    final all = await dues.cycleDues(studentId: 's1');
    expect(all.map((d) => d.cycleNumber), [1, 2]);
  });
}
