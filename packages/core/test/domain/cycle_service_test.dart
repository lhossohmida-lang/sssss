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

  test('الحصص المرشحة من الجدول دون كتابة، وتتخطى الخانات المأخوذة', () async {
    final found = await cycles.occurrences('g1', fromDate: saturday, count: 3);
    expect(found.map((o) => o.key), [
      '2026-11-14|600',
      '2026-11-17|900',
      '2026-11-21|600',
    ]);
    expect(found.first.roomId, 'r1', reason: 'القاعة الافتراضية للفوج');
    expect(await cycles.cycleSessions('g1', 1), isEmpty, reason: 'لا كتابة');

    await cycles.topUp('g1', fromDate: saturday);
    final firstId = (await cycles.cycleSessions('g1', 1)).first.id;
    final next = await cycles.occurrences('g1', fromDate: saturday, count: 2);
    expect(next.map((o) => o.date), ['2026-11-28', '2026-12-01']);
    final ignoring = await cycles.occurrences(
      'g1',
      fromDate: saturday,
      count: 1,
      ignore: {firstId},
    );
    expect(ignoring.single.date, saturday, reason: 'كأن الحصة محذوفة');
    expect(
      await cycles.occurrences('g1', fromDate: saturday, count: 0),
      isEmpty,
    );
  });

  Future<void> dropTwoEarliest() async {
    await cycles.topUp('g1', fromDate: '2026-12-01');
    expect(await describe(1), [
      '2026-12-01#1:normal',
      '2026-12-05#2:normal',
      '2026-12-08#3:normal',
      '2026-12-12#4:normal',
    ]);
    await env.db.customStatement(
      "UPDATE sessions SET deleted_at = 5 WHERE date IN ('2026-12-01', '2026-12-05')",
    );
  }

  test('البرمجة الافتراضية تلحق بما بعد آخر حصة مبرمجة', () async {
    await dropTwoEarliest();
    final added = await cycles.topUp('g1', fromDate: '2026-12-01');
    expect(added.map((s) => s.date), ['2026-12-15', '2026-12-19']);
  });

  test('البرمجة من تاريخ بعينه تملأ الفراغ بدل أن تلحق بآخر حصة', () async {
    await dropTwoEarliest();
    final added = await cycles.topUp(
      'g1',
      fromDate: '2026-12-01',
      continueAfterLast: false,
    );
    expect(added.map((s) => s.date), ['2026-12-01', '2026-12-05']);
    expect(await describe(1), [
      '2026-12-01#1:normal',
      '2026-12-05#2:normal',
      '2026-12-08#3:normal',
      '2026-12-12#4:normal',
    ]);
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
    expect(first.roomId, 'r1', reason: 'القاعة الافتراضية للفوج');
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

  group('نقل حصة قادمة إلى تاريخ آخر', () {
    // الحصص بعد البرمجة من السبت 14: 14 (سبت)، 17 (ثلاثاء 15:00)، 21 (سبت)، 24 (ثلاثاء).
    setUp(() => cycles.topUp('g1', fromDate: saturday));

    Future<SessionRow> on(String date) async => (await cycles.cycleSessions(
      'g1',
      1,
    )).firstWhere((s) => s.date == date && s.status != 'cancelled');

    test('تُلغى في موعدها وتُضاف تعويضية بوقتها دون برمجة بديلة', () async {
      final tuesday = (await cycles.cycleSessions('g1', 1))[1];
      expect(tuesday.date, '2026-11-17');
      final moved = await cycles.moveSession(tuesday.id, toDate: '2026-11-19');

      expect(moved.date, '2026-11-19');
      expect(moved.startMinutes, 900);
      expect(moved.endMinutes, 990);
      expect(moved.status, 'makeup');
      expect(moved.cycleNumber, 1);
      expect(moved.roomId, tuesday.roomId);
      expect(await describe(1), [
        '2026-11-14#1:normal',
        '2026-11-17#-:cancelled',
        '2026-11-19#2:makeup',
        '2026-11-21#3:normal',
        '2026-11-24#4:normal',
      ]);
      expect(
        await cycles.countedSessions('g1', 1),
        4,
        reason: 'عدد حصص الدورة لا يتغير ولا تُبرمج بديلة',
      );
      // الموعد القديم يبقى محجوزاً بحصته الملغاة فلا يُعاد برمجته.
      expect(await cycles.topUp('g1', fromDate: saturday), isEmpty);
    });

    test('لا تُنقل حصة أُغلقت أو سُجّل حضورها أو أُلغيت', () async {
      final first = await on('2026-11-14');
      await env.student();
      await env.enroll(id: 'e1', studentId: 's1');
      await env.db
          .into(env.db.attendance)
          .insert(
            AttendanceCompanion.insert(
              id: 'a1',
              createdAt: 1,
              updatedAt: 1,
              sessionId: first.id,
              studentId: 's1',
              status: 'present',
              method: 'manual',
            ),
          );
      expect(
        () => cycles.moveSession(first.id, toDate: '2026-11-20'),
        throwsA(isA<StateError>()),
        reason: 'سُجّل فيها حضور',
      );

      final second = await on('2026-11-17');
      await cycles.closeSession(second.id);
      expect(
        () => cycles.moveSession(second.id, toDate: '2026-11-20'),
        throwsA(isA<StateError>()),
        reason: 'أُغلقت',
      );

      final third = await on('2026-11-21');
      await cycles.cancelSession(third.id);
      expect(
        () => cycles.moveSession(third.id, toDate: '2026-11-22'),
        throwsA(isA<StateError>()),
        reason: 'ملغاة',
      );
    });

    test('لا تُنقل إلى تاريخها نفسه ولا إلى موعد فيه حصة للفوج', () async {
      final tuesday = await on('2026-11-17');
      expect(
        () => cycles.moveSession(tuesday.id, toDate: '2026-11-17'),
        throwsA(isA<StateError>()),
      );
      // الحصة الثانية (سبت 21) بوقت 10:00 لا تُنقل إلى يوم فيه حصة بالوقت نفسه.
      final saturday21 = await on('2026-11-21');
      expect(
        () => cycles.moveSession(saturday21.id, toDate: '2026-11-14'),
        throwsA(isA<StateError>()),
      );
      expect(await describe(1), hasLength(4), reason: 'لم يتغير شيء');
    });

    test('الموعد الملغى بالنقل يصلح وجهةً: العودة إلى الموعد الأول', () async {
      final tuesday = await on('2026-11-17');
      final moved = await cycles.moveSession(tuesday.id, toDate: '2026-11-19');
      final back = await cycles.moveSession(moved.id, toDate: '2026-11-17');
      expect(back.id, tuesday.id, reason: 'المعرّف الثابت لموعدها الأول');
      expect(back.status, 'makeup');
      expect(await describe(1), [
        '2026-11-14#1:normal',
        '2026-11-17#2:makeup',
        '2026-11-19#-:cancelled',
        '2026-11-21#3:normal',
        '2026-11-24#4:normal',
      ]);
      expect(await cycles.countedSessions('g1', 1), 4);
    });

    test('النقل يدخل طابور المزامنة', () async {
      final tuesday = await on('2026-11-17');
      await env.db.delete(env.db.outbox).go();
      await cycles.moveSession(tuesday.id, toDate: '2026-11-19');
      final pending = await (env.db.select(
        env.db.outbox,
      )..where((o) => o.targetTable.equals('sessions'))).get();
      expect(pending, isNotEmpty);
    });
  });

  test('فوج بلا جدول أسبوعي لا تُبرمج لها حصص', () async {
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
