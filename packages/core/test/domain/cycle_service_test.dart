import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late CycleService cycles;

  // 2026-11-14 يوم سبت (weekday = 6)، و2026-11-17 يوم ثلاثاء (weekday = 2).
  const saturday = '2026-11-14';

  setUp(() async {
    env = TestEnv();
    cycles = CycleService(env.db, env.writer);
    await env.subject();
    await env.teacher();
    await env.room();
    await env.group(sessionsPerCycle: 4, roomId: 'r1');
    await env.slot(id: 'sl-sat', weekday: 6);
    await env.slot(id: 'sl-tue', weekday: 2, start: 900, end: 990);
  });

  tearDown(() => env.close());

  Future<List<String>> describe(int cycle) async {
    final sessions = await cycles.cycleSessions('g1', cycle);
    return [
      for (final s in sessions)
        '${s.date}#${s.sessionNumber ?? '-'}:${s.status}',
    ];
  }

  test('أدوات التاريخ', () {
    expect(DateKey.of(DateTime(2026, 1, 5)), '2026-01-05');
    expect(DateKey.next('2026-12-31'), '2027-01-01');
    expect(DateKey.next('2028-02-28'), '2028-02-29');
    expect(DateKey.weekday(saturday), DateTime.saturday);
    expect(DateKey.formatMinutes(605), '10:05');
    expect(DateKey.minutesOf(DateTime(2026, 1, 1, 14, 30)), 870);
    expect(() => DateKey.parse('2026/01/01'), throwsFormatException);
  });

  test('برمجة الدورة من الجدول الأسبوعي حتى تبلغ حدّها', () async {
    final created = await cycles.topUp('g1', fromDate: saturday);
    expect(created, hasLength(4));
    expect(await describe(1), [
      '2026-11-14#1:normal',
      '2026-11-17#2:normal',
      '2026-11-21#3:normal',
      '2026-11-24#4:normal',
    ]);
    final first = (await cycles.cycleSessions('g1', 1)).first;
    expect(first.roomId, 'r1', reason: 'القاعة الافتراضية للمجموعة');
    expect(first.startMinutes, 600);

    expect(
      await cycles.topUp('g1', fromDate: saturday),
      isEmpty,
      reason: 'الدورة مكتملة البرمجة فلا يُضاف شيء',
    );
  });

  test('الحصة الملغاة لا تُحسب، ويُعاد الترقيم، وتُبرمج بديلة', () async {
    await cycles.topUp('g1', fromDate: saturday);
    final second = (await cycles.cycleSessions('g1', 1))[1];

    await cycles.cancelSession(second.id);

    expect(await describe(1), [
      '2026-11-14#1:normal',
      '2026-11-17#-:cancelled',
      '2026-11-21#2:normal',
      '2026-11-24#3:normal',
      '2026-11-28#4:normal',
    ]);
    expect(await cycles.countedSessions('g1', 1), 4);

    await cycles.cancelSession(second.id);
    expect(
      await cycles.countedSessions('g1', 1),
      4,
      reason: 'الإلغاء مرة واحدة',
    );
  });

  test('الحصة المضافة والتعويضية تُحسبان ضمن الدورة', () async {
    await cycles.topUp('g1', fromDate: saturday);
    final added = await cycles.addSession(
      groupId: 'g1',
      date: '2026-11-15',
      startMinutes: 480,
      endMinutes: 570,
    );
    expect(added.sessionNumber, 2);
    expect(added.status, 'added');

    final makeup = await cycles.addSession(
      groupId: 'g1',
      date: '2026-11-16',
      startMinutes: 480,
      endMinutes: 570,
      status: SessionStatus.makeup,
    );
    expect(makeup.sessionNumber, 3);
    expect(await cycles.countedSessions('g1', 1), 6);
  });

  test('إضافة حصة بوقت غير صالح أو ملغاة تُرفض', () async {
    expect(
      () => cycles.addSession(
        groupId: 'g1',
        date: saturday,
        startMinutes: 600,
        endMinutes: 600,
      ),
      throwsArgumentError,
    );
    expect(
      () => cycles.addSession(
        groupId: 'g1',
        date: saturday,
        startMinutes: 600,
        endMinutes: 700,
        status: SessionStatus.cancelled,
      ),
      throwsArgumentError,
    );
  });

  test('الدورة تكتمل ببلوغ الحصص المغلقة حدّها وتبدأ التالية', () async {
    await cycles.topUp('g1', fromDate: saturday);
    final sessions = await cycles.cycleSessions('g1', 1);

    for (final s in sessions.take(3)) {
      expect(await cycles.closeSession(s.id), isTrue);
    }
    expect(await cycles.isCurrentCycleComplete('g1'), isFalse);
    expect(
      await cycles.completeCycleIfDone('g1', fromDate: '2026-11-25'),
      isNull,
    );

    await cycles.closeSession(sessions.last.id);
    expect(await cycles.closeSession(sessions.last.id), isFalse);
    expect(await cycles.isCurrentCycleComplete('g1'), isTrue);

    final finished = await cycles.completeCycleIfDone(
      'g1',
      fromDate: '2026-11-25',
    );
    expect(finished, 1);

    final group = await env.db.select(env.db.groups).getSingle();
    expect(group.currentCycleNumber, 2);
    expect(await describe(2), [
      '2026-11-28#1:normal',
      '2026-12-01#2:normal',
      '2026-12-05#3:normal',
      '2026-12-08#4:normal',
    ]);
  });

  test(
    'الحصة المضافة تُكمل الدورة أبكر، والباقي ينتقل للدورة التالية',
    () async {
      await cycles.topUp('g1', fromDate: saturday);
      final added = await cycles.addSession(
        groupId: 'g1',
        date: '2026-11-15',
        startMinutes: 480,
        endMinutes: 570,
      );
      final planned = await cycles.cycleSessions('g1', 1);
      // تُغلق أول أربع حصص زمنياً: 14، 15 (المضافة)، 17، 21.
      for (final s in planned.take(4)) {
        await cycles.closeSession(s.id);
      }
      expect(planned.take(4).map((s) => s.id), contains(added.id));

      expect(await cycles.completeCycleIfDone('g1', fromDate: '2026-11-22'), 1);

      expect(await describe(1), [
        '2026-11-14#1:normal',
        '2026-11-15#2:added',
        '2026-11-17#3:normal',
        '2026-11-21#4:normal',
      ]);
      final next = await describe(2);
      expect(next.first, '2026-11-24#1:normal', reason: 'الحصة الباقية انتقلت');
      expect(next, hasLength(4));
    },
  );

  test('لا تُلغى حصة أُغلقت', () async {
    await cycles.topUp('g1', fromDate: saturday);
    final first = (await cycles.cycleSessions('g1', 1)).first;
    await cycles.closeSession(first.id);
    expect(() => cycles.cancelSession(first.id), throwsStateError);
  });

  test('مجموعة بلا جدول أسبوعي لا تُبرمج لها حصص', () async {
    await env.group(id: 'g2');
    expect(await cycles.topUp('g2', fromDate: saturday), isEmpty);
  });

  test('كل تغيير في الحصص يدخل طابور المزامنة', () async {
    await cycles.topUp('g1', fromDate: saturday);
    final pending = await (env.db.select(
      env.db.outbox,
    )..where((o) => o.targetTable.equals('sessions'))).get();
    expect(pending, hasLength(4));
  });
}
