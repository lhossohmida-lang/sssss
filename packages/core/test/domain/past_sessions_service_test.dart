import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late CycleService cycles;
  late AttendanceService attendance;
  late PastSessionsService past;
  late PayoutService payouts;

  // الفوج يدرس السبت (6) والثلاثاء (2) من 10:00 إلى 11:30. الدورة 4 حصص.
  // اليوم الأربعاء 2026-11-18، فالسبت 14 والثلاثاء 17 مضتا.
  final now = DateTime(2026, 11, 18, 9);
  const saturday = '2026-11-14';
  const tuesday = '2026-11-17';

  setUp(() async {
    env = TestEnv();
    cycles = CycleService(env.db, env.writer);
    final dues = DuesService(env.db, env.writer);
    attendance = AttendanceService(env.db, env.writer, cycles, dues);
    past = PastSessionsService(env.db, env.writer, cycles, attendance);
    payouts = PayoutService(env.db, env.writer, dues);
    await env.subject();
    await env.teacher();
    await env.group(sessionsPerCycle: 4);
    await env.slot(id: 'sl-sat', weekday: 6);
    await env.slot(id: 'sl-tue', weekday: 2);
    await env.student();
    await env.student(id: 's2');
    await env.enroll(id: 'e1', studentId: 's1');
    await env.enroll(id: 'e2', studentId: 's2');
    // المجموعة أُنشئت اليوم: حصصها تبدأ من اليوم فصاعداً.
    await cycles.topUp('g1', fromDate: '2026-11-18');
  });
  tearDown(() => env.close());

  PastSessionInput input(
    String date, {
    int start = 600,
    int end = 690,
    Map<String, AttendanceStatus>? marks,
  }) => PastSessionInput(
    date: date,
    startMinutes: start,
    endMinutes: end,
    marks:
        marks ??
        const {'s1': AttendanceStatus.present, 's2': AttendanceStatus.present},
  );

  Future<List<SessionRow>> cycleSessions() => cycles.cycleSessions('g1', 1);

  Future<CyclePlan> plan(String from, {String groupId = 'g1'}) =>
      past.plan(groupId, from: from, now: now);

  Future<int> capacity() async => (await plan(saturday)).capacity;

  group('الاقتراح والسعة', () {
    test('السعة: حصص الدورة ناقص حصة تبقى لتُغلق تلقائياً', () async {
      expect(await capacity(), 3);
    });

    test('تُحتسب الحصص المنعقدة فتنقص السعة', () async {
      await past.record('g1', [input(saturday)], now: now);
      expect(await capacity(), 2);
    });

    test('يقترح حصص الجدول بين تاريخ البداية وأمس بالترتيب', () async {
      final found = (await plan('2026-11-10')).past;
      expect(found.map((s) => s.date), ['2026-11-10', saturday, tuesday]);
      expect(found.first.startMinutes, 600);
      expect(found.first.endMinutes, 690);
    });

    test('لا يقترح حصة سُجّلت من قبل ولا حصة اليوم', () async {
      await past.record('g1', [input(saturday)], now: now);
      final found = (await plan('2026-11-10')).past;
      expect(found.map((s) => s.date), ['2026-11-10', tuesday]);
      expect((await plan('2026-11-18')).past, isEmpty);
    });

    test('فوج بلا جدول أسبوعي: لا اقتراح', () async {
      await env.group(id: 'g2', number: 2);
      final empty = await plan('2026-11-01', groupId: 'g2');
      expect(empty.past, isEmpty);
      expect(empty.upcoming, isEmpty);
    });

    test('التلاميذ المنتسبون بالاسم، ومن غادر لا يظهر', () async {
      await env.student(id: 's3');
      await env.enroll(id: 'e3', studentId: 's3');
      await env.db.customStatement(
        "UPDATE group_students SET left_at = 5 WHERE id = 'e3'",
      );
      final roster = await past.roster('g1');
      expect(roster.map((s) => s.studentId), ['s1', 's2']);
      expect(roster.first.name, 'تلميذ s1');
    });
  });

  group('التسجيل', () {
    test('ينشئ حصصاً مغلقة في الدورة الحالية بترتيبها ويسجّل الحضور', () async {
      final result = await past.record('g1', [
        input(
          tuesday,
          marks: {
            's1': AttendanceStatus.absent,
            's2': AttendanceStatus.present,
          },
        ),
        input(saturday),
      ], now: now);
      expect(result.sessions, 2);
      expect(result.marks, 4);
      final sessions = await cycleSessions();
      // حصتان سابقتان ثم حصتان قادمتان (الحجم 4 كما هو).
      expect(sessions.map((s) => s.date).take(2), [saturday, tuesday]);
      expect(sessions.map((s) => s.sessionNumber), [1, 2, 3, 4]);
      expect(sessions.take(2).every((s) => s.closedAt != null), isTrue);
      expect(sessions.skip(2).every((s) => s.closedAt == null), isTrue);
      expect(sessions.every((s) => s.cycleNumber == 1), isTrue);
      expect(await cycles.countedSessions('g1', 1), 4);
      expect(result.removedUpcoming, 2);

      final grid = (await GroupGridQueries(env.db).load('g1'))!;
      expect(grid.heldSessions, 2);
      final byStudent = {for (final s in grid.students) s.studentId: s};
      expect(byStudent['s1']!.count(AttendanceStatus.absent), 1);
      expect(byStudent['s1']!.count(AttendanceStatus.present), 1);
      expect(byStudent['s2']!.count(AttendanceStatus.present), 2);
    });

    test('الحصص القادمة الزائدة تُحذف من آخر الدورة لا من أولها', () async {
      final before = await cycleSessions();
      expect(before.length, 4);
      await past.record('g1', [input(saturday)], now: now);
      final after = await cycleSessions();
      expect(after.length, 4);
      // الأولى مضت والأخيرة من الجدول القديم حُذفت.
      expect(after.first.date, saturday);
      expect(after.last.date, before[2].date);
    });

    test('من لا حالة له في الحصة لا يُسجَّل له شيء', () async {
      await past.record('g1', [
        input(saturday, marks: {'s1': AttendanceStatus.present}),
      ], now: now);
      final rows = await env.db.select(env.db.attendance).get();
      expect(rows, hasLength(1));
      expect(rows.single.studentId, 's1');
      expect(rows.single.method, AttendanceMethod.manual.code);
    });

    test('لا تُرسل رسائل ولا تنبيهات للحصص السابقة', () async {
      await past.record('g1', [
        input(
          saturday,
          marks: {'s1': AttendanceStatus.absent, 's2': AttendanceStatus.absent},
        ),
      ], now: now);
      expect(await env.db.select(env.db.smsQueue).get(), isEmpty);
      expect(await env.db.select(env.db.notifications).get(), isEmpty);
    });

    test('الغياب برخصة ينشئ رصيداً للدورة القادمة بإذن المدير', () async {
      await past.record(
        'g1',
        [
          input(
            saturday,
            marks: {
              's1': AttendanceStatus.excused,
              's2': AttendanceStatus.present,
            },
          ),
        ],
        now: now,
        canExcuse: true,
      );
      final credits = (await env.db.select(env.db.studentCredits).get())
          .where((c) => c.deletedAt == null)
          .toList();
      expect(credits, hasLength(1));
      expect(credits.single.studentId, 's1');
      expect(credits.single.reason, 'excused');
      expect(credits.single.targetCycleNumber, 2);
    });

    test('الغياب برخصة يُرفض بلا إذن', () async {
      await expectLater(
        past.record('g1', [
          input(saturday, marks: {'s1': AttendanceStatus.excused}),
        ], now: now),
        throwsA(isA<ValidationException>()),
      );
      expect(await env.db.select(env.db.attendance).get(), isEmpty);
    });

    test('حضورها يدخل في نصيب الأستاذ عند اكتمال الدورة', () async {
      // حصتان سابقتان ثم الحصتان القادمتان تُغلقان بالتوقيت العادي.
      await past.record('g1', [
        input(
          saturday,
          marks: {
            's1': AttendanceStatus.present,
            's2': AttendanceStatus.absent,
          },
        ),
        input(
          tuesday,
          marks: {
            's1': AttendanceStatus.present,
            's2': AttendanceStatus.present,
          },
        ),
      ], now: now);
      final computed = await payouts.compute('g1', 1);
      final lines = {for (final l in computed.lines) l.studentId: l};
      expect(lines['s1']!.attended, 2);
      expect(lines['s2']!.attended, 1);
    });

    test('الحصص القادمة تُغلق بعدها بالتوقيت العادي وتكتمل الدورة', () async {
      await past.record('g1', [input(saturday), input(tuesday)], now: now);
      final upcoming = (await cycleSessions()).where((s) => s.closedAt == null);
      expect(upcoming, hasLength(2));
      final later = DateTime(2030, 1, 1);
      final closed = await attendance.closeDueSessions(later);
      expect(closed, 2);
      final group = await (env.db.select(
        env.db.groups,
      )..where((g) => g.id.equals('g1'))).getSingle();
      expect(group.currentCycleNumber, 2);
    });
  });

  group('التحقق', () {
    test('قائمة فارغة', () async {
      await expectLater(
        past.record('g1', const [], now: now),
        throwsA(isA<ValidationException>()),
      );
    });

    test('اليوم والمستقبل مرفوضان', () async {
      for (final date in ['2026-11-18', '2026-11-19']) {
        await expectLater(
          past.record('g1', [input(date)], now: now),
          throwsA(isA<ValidationException>()),
          reason: date,
        );
      }
    });

    test('تاريخ غير صالح أو وقت معكوس', () async {
      await expectLater(
        past.record('g1', [input('2026-02-30')], now: now),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        past.record('g1', [input('14/11/2026')], now: now),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        past.record('g1', [input(saturday, start: 700, end: 600)], now: now),
        throwsA(isA<ValidationException>()),
      );
    });

    test('حصتان في اليوم والوقت نفسيهما', () async {
      await expectLater(
        past.record('g1', [input(saturday), input(saturday)], now: now),
        throwsA(isA<ValidationException>()),
      );
    });

    test('لا تُسجَّل كل حصص الدورة: تبقى واحدة على الأقل', () async {
      await expectLater(
        past.record('g1', [
          input('2026-11-07'),
          input('2026-11-10'),
          input(saturday),
          input(tuesday),
        ], now: now),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.toString(),
            'الرسالة',
            contains('3 حصة'),
          ),
        ),
      );
      expect(await cycles.countedSessions('g1', 1), 4);
    });

    test('تسجيل حصة موجودة في اليوم والوقت نفسيهما', () async {
      await past.record('g1', [input(saturday)], now: now);
      await expectLater(
        past.record('g1', [input(saturday)], now: now),
        throwsA(isA<ValidationException>()),
      );
    });

    test('تلميذ ليس في الفوج', () async {
      await env.student(id: 's9');
      await expectLater(
        past.record('g1', [
          input(saturday, marks: {'s9': AttendanceStatus.present}),
        ], now: now),
        throwsA(isA<ValidationException>()),
      );
    });

    test('فوج مؤرشف أو غير موجود', () async {
      await env.db.customStatement(
        "UPDATE groups SET archived_at = 5 WHERE id = 'g1'",
      );
      await expectLater(
        past.record('g1', [input(saturday)], now: now),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        plan(saturday, groupId: 'nope'),
        throwsA(isA<ValidationException>()),
      );
    });

    test('الفشل لا يترك شيئاً: كله أو لا شيء', () async {
      await expectLater(
        past.record('g1', [
          input(saturday),
          input(tuesday, marks: {'ghost': AttendanceStatus.present}),
        ], now: now),
        throwsA(isA<ValidationException>()),
      );
      expect(await env.db.select(env.db.attendance).get(), isEmpty);
      expect((await cycleSessions()).every((s) => s.closedAt == null), isTrue);
      expect(await cycles.countedSessions('g1', 1), 4);
    });

    test('لا تُحذف حصة قادمة فيها حضور بل تُبرمج الدورة حولها', () async {
      final marked = (await cycleSessions()).last;
      await attendance.mark(
        sessionId: marked.id,
        studentId: 's1',
        status: AttendanceStatus.present,
      );
      await past.record('g1', [input(saturday)], now: now);
      final after = await cycleSessions();
      expect(after, hasLength(4));
      expect(after.map((s) => s.id), contains(marked.id));
      expect(after.first.date, saturday);
      expect(await cycles.countedSessions('g1', 1), 4);
    });
  });

  group('الحصص المقررة: عدد الدورة وتواريخها من تاريخ أول حصة', () {
    List<String> dates(Iterable<PlannedSession> rows) => [
      for (final row in rows) row.date,
    ];

    test(
      'تاريخ أول حصة الافتراضي أقدم حصة محسوبة في الدورة وإلا اليوم',
      () async {
        expect(await past.firstDate('g1', now: now), '2026-11-21');
        await env.group(id: 'g2', number: 2);
        expect(await past.firstDate('g2', now: now), '2026-11-18');
      },
    );

    test('تخطيط من تاريخ ماضٍ: ماضية ثم قادمة بقدر ما يتسع للدورة', () async {
      final result = await plan('2026-11-10');
      expect(result.cycleSize, 4);
      expect(result.capacity, 3);
      expect(dates(result.past), ['2026-11-10', saturday, tuesday]);
      // أربع حصص قادمة مرشحة من اليوم؛ يُؤخذ منها ما يبقى بعد الماضية المحدَّدة.
      expect(dates(result.upcoming), [
        '2026-11-21',
        '2026-11-24',
        '2026-11-28',
        '2026-12-01',
      ]);
      expect(result.fixed, isEmpty);
    });

    test(
      'تاريخ أول حصة بعد اليوم: لا ماضية والدورة كلها من ذلك التاريخ',
      () async {
        final result = await plan('2026-12-01');
        expect(result.past, isEmpty);
        expect(dates(result.upcoming), [
          '2026-12-01',
          '2026-12-05',
          '2026-12-08',
          '2026-12-12',
        ]);
      },
    );

    test('الماضية لا تزيد على حصص الدورة', () async {
      final result = await plan('2026-09-01');
      expect(result.past, hasLength(4));
      expect(result.past.first.date, '2026-09-01');
    });

    test('المنعقدة المسجَّلة ثابتة وتنقص ما يُبرمج قادماً', () async {
      await past.record('g1', [input(saturday)], now: now);
      final result = await plan(saturday);
      expect(result.fixed.map((s) => (s.date, s.held)), [(saturday, true)]);
      expect(result.upcoming, hasLength(3));
      expect(result.capacity, 2);
    });

    test(
      'تغيير تاريخ أول حصة إلى المستقبل يعيد برمجة الدورة كلها منه',
      () async {
        final result = await past.record(
          'g1',
          const [],
          now: now,
          firstDate: '2026-12-01',
        );
        expect(result.sessions, 0);
        final sessions = await cycleSessions();
        expect(sessions.map((s) => s.date), [
          '2026-12-01',
          '2026-12-05',
          '2026-12-08',
          '2026-12-12',
        ]);
        expect(sessions.map((s) => s.sessionNumber), [1, 2, 3, 4]);
        expect(sessions.every((s) => s.closedAt == null), isTrue);
        expect(await past.firstDate('g1', now: now), '2026-12-01');
        expect(result.removedUpcoming, 0);
      },
    );

    test('بعد تغيير تاريخ أول حصة تبقى الدورة بعدد حصصها دائماً', () async {
      for (final first in ['2026-11-19', '2026-11-25', '2027-01-04']) {
        await past.record('g1', const [], now: now, firstDate: first);
        expect(await cycles.countedSessions('g1', 1), 4, reason: first);
        final sessions = await cycleSessions();
        expect(
          sessions.first.date.compareTo(first) >= 0,
          isTrue,
          reason: first,
        );
        expect(sessions.map((s) => s.sessionNumber), [1, 2, 3, 4]);
      }
    });

    test(
      'تسجيل ماضٍ من أول حصة: القادمة تتبع الماضية دون ثغرة ودون زيادة',
      () async {
        final result = await past.record(
          'g1',
          [input('2026-11-10'), input(saturday)],
          now: now,
          firstDate: '2026-11-10',
        );
        expect(result.sessions, 2);
        final sessions = await cycleSessions();
        expect(sessions.map((s) => s.date), [
          '2026-11-10',
          saturday,
          '2026-11-21',
          '2026-11-24',
        ]);
        expect(sessions.take(2).every((s) => s.closedAt != null), isTrue);
      },
    );

    test(
      'ما لم يُحدَّد من الماضية لم ينعقد فتحلّ محله حصة في آخر الدورة',
      () async {
        // الثلاثاء 17 لم ينعقد: تبقى الدورة بأربع حصص بإضافة قادمة.
        await past.record(
          'g1',
          [input('2026-11-10'), input(saturday)],
          now: now,
          firstDate: '2026-11-10',
        );
        expect(await cycles.countedSessions('g1', 1), 4);
        final sessions = await cycleSessions();
        expect(sessions.map((s) => s.date), isNot(contains(tuesday)));
      },
    );

    test(
      'الحصص الماضية التي برمجها النظام تُغلق بالحضور بدل أن تتكرر',
      () async {
        // فوج أُنشئ بأول حصة ماضية: حصصه الأربع من 10 نوفمبر بعضها مضى.
        await env.db.customStatement('DELETE FROM sessions');
        await cycles.topUp('g1', fromDate: '2026-11-10');
        expect((await cycleSessions()).map((s) => s.date), [
          '2026-11-10',
          saturday,
          tuesday,
          '2026-11-21',
        ]);
        final result = await plan('2026-11-10');
        expect(dates(result.past), ['2026-11-10', saturday, tuesday]);
        // المرشحة للقادم أربع، يُؤخذ منها واحدة لو حُدِّدت الماضية الثلاث.
        expect(dates(result.upcoming), [
          '2026-11-21',
          '2026-11-24',
          '2026-11-28',
          '2026-12-01',
        ]);

        // الثلاثاء 17 لم ينعقد: يُحذف وتحلّ محله قادمة، وما انعقد يُغلق بحضوره.
        await past.record(
          'g1',
          [input('2026-11-10'), input(saturday)],
          now: now,
          firstDate: '2026-11-10',
        );
        final sessions = await cycleSessions();
        expect(sessions.map((s) => s.date), [
          '2026-11-10',
          saturday,
          '2026-11-21',
          '2026-11-24',
        ]);
        expect(sessions.take(2).every((s) => s.closedAt != null), isTrue);
        final marks = await env.db.select(env.db.attendance).get();
        expect(marks, hasLength(4));
        expect(await cycles.countedSessions('g1', 1), 4);
      },
    );

    test('الحصة التعويضية قائمة وتُحسب من حصص الدورة', () async {
      await cycles.addSession(
        groupId: 'g1',
        date: '2026-11-19',
        startMinutes: 900,
        endMinutes: 990,
        status: SessionStatus.makeup,
      );
      final before = await plan(saturday);
      expect(before.fixed.map((s) => s.date), ['2026-11-19']);
      expect(before.upcoming, hasLength(3));
      await past.record('g1', const [], now: now, firstDate: '2026-12-01');
      final sessions = await cycleSessions();
      expect(sessions, hasLength(4));
      expect(sessions.map((s) => s.date), contains('2026-11-19'));
      expect(
        sessions.where((s) => s.status == SessionStatus.makeup.code),
        hasLength(1),
      );
    });

    test('لا يجوز أن تسبق أول حصة حصةً منعقدة مسجَّلة', () async {
      await past.record('g1', [input(saturday)], now: now);
      await expectLater(
        past.record('g1', const [], now: now, firstDate: tuesday),
        throwsA(isA<ValidationException>()),
      );
      expect(await cycles.countedSessions('g1', 1), 4);
    });

    test('حصة مسجَّلة قبل تاريخ أول حصة مرفوضة', () async {
      await expectLater(
        past.record('g1', [input('2026-11-10')], now: now, firstDate: saturday),
        throwsA(isA<ValidationException>()),
      );
      expect(await env.db.select(env.db.attendance).get(), isEmpty);
    });

    test('تاريخ أول حصة غير صالح', () async {
      await expectLater(
        past.record('g1', const [], now: now, firstDate: '2026-13-01'),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(plan('غير تاريخ'), throwsA(isA<ValidationException>()));
    });

    test('الفشل أثناء إعادة البرمجة لا يترك شيئاً', () async {
      final before = (await cycleSessions()).map((s) => s.id).toList();
      await expectLater(
        past.record(
          'g1',
          [
            input(saturday, marks: {'ghost': AttendanceStatus.present}),
          ],
          now: now,
          firstDate: '2026-11-10',
        ),
        throwsA(isA<ValidationException>()),
      );
      expect((await cycleSessions()).map((s) => s.id), before);
    });
  });

  group('تغيير تاريخ حصة قادمة', () {
    // بعد setUp: الحصص القادمة من اليوم (الأربعاء 18): السبت 21، الثلاثاء 24، السبت 28،
    // الثلاثاء 1 ديسمبر، كلها 10:00–11:30.
    const sat21 = '2026-11-21';
    const tue24 = '2026-11-24';
    const sat28 = '2026-11-28';
    const dec1 = '2026-12-01';

    SessionMove move(String from, String to, {int start = 600}) =>
        SessionMove(fromDate: from, startMinutes: start, toDate: to);

    Future<List<String>> shape() async => [
      for (final s in await cycleSessions())
        '${s.date}:${s.status}${s.closedAt == null ? '' : ':closed'}',
    ];

    Future<PastSessionsResult> replan(
      List<SessionMove> moves, {
      DateTime? at,
    }) => past.record(
      'g1',
      const [],
      now: at ?? now,
      firstDate: '2026-11-18',
      moves: moves,
    );

    test(
      'تُنقل إلى تاريخ آخر بوقتها: تُلغى في موعدها وتُضاف تعويضية',
      () async {
        await replan([move(tue24, '2026-11-26')]);
        expect(await shape(), [
          '$sat21:normal',
          '$tue24:cancelled',
          '2026-11-26:makeup',
          '$sat28:normal',
          '$dec1:normal',
        ]);
        final counted = (await cycleSessions()).where(
          (s) => s.status != 'cancelled',
        );
        expect(counted, hasLength(4), reason: 'تبقى الدورة بأربع حصص');
        expect([for (final s in counted) s.sessionNumber], [1, 2, 3, 4]);
        final moved = counted.singleWhere((s) => s.date == '2026-11-26');
        expect([moved.startMinutes, moved.endMinutes], [600, 690]);
      },
    );

    test(
      'تبقى الحصة المنقولة بعد إعادة برمجة لاحقة ولا يعود موعدها القديم',
      () async {
        await replan([move(tue24, '2026-11-26')]);
        await replan(const []);
        expect(await shape(), [
          '$sat21:normal',
          '$tue24:cancelled',
          '2026-11-26:makeup',
          '$sat28:normal',
          '$dec1:normal',
        ]);
        // والمخطط يعرضها كما هي: المنقولة ثابتة والباقي من الجدول دون الموعد القديم.
        final shown = await plan('2026-11-18');
        expect(shown.fixed.map((s) => s.date), ['2026-11-26']);
        expect(shown.upcoming.map((s) => s.date), [sat21, sat28, dec1]);
      },
    );

    test('تُنقل حصة منقولة مرة ثانية', () async {
      await replan([move(tue24, '2026-11-26')]);
      await replan([move('2026-11-26', '2026-11-27')]);
      expect(await shape(), [
        '$sat21:normal',
        '$tue24:cancelled',
        '2026-11-26:cancelled',
        '2026-11-27:makeup',
        '$sat28:normal',
        '$dec1:normal',
      ]);
    });

    test('نقلان متتاليان: الثاني إلى موعد أخلاه الأول', () async {
      await replan([move(tue24, '2026-11-26'), move(sat21, tue24)]);
      final live = (await cycleSessions()).where(
        (s) => s.status != 'cancelled',
      );
      expect(live.map((s) => s.date), [tue24, '2026-11-26', sat28, dec1]);
      expect(live.where((s) => s.status == 'makeup'), hasLength(2));
    });

    test('مع تسجيل حصة سابقة معاً في عملية واحدة', () async {
      final result = await past.record(
        'g1',
        [input(tuesday)],
        now: now,
        firstDate: '2026-11-14',
        moves: [move(tue24, '2026-11-27')],
      );
      expect(result.sessions, 1);
      expect(await shape(), [
        '$tuesday:normal:closed',
        '$sat21:normal',
        '$tue24:cancelled',
        '2026-11-27:makeup',
        '$sat28:normal',
      ]);
    });

    test('لا تُنقل إلى تاريخ مضى ولا من تاريخ مضى ولا إلى نفسها', () async {
      for (final bad in [
        move(tue24, tuesday),
        move(tuesday, '2026-11-26'),
        move(tue24, tue24),
        move(tue24, 'غير تاريخ'),
      ]) {
        await expectLater(
          replan([bad]),
          throwsA(isA<ValidationException>()),
          reason: '${bad.fromDate} → ${bad.toDate}',
        );
      }
      expect(await shape(), [
        '$sat21:normal',
        '$tue24:normal',
        '$sat28:normal',
        '$dec1:normal',
      ], reason: 'لم يتغير شيء');
    });

    test('تكرار الحصة المنقولة أو الوجهة يُرفض', () async {
      await expectLater(
        replan([move(tue24, '2026-11-26'), move(tue24, '2026-11-27')]),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        replan([move(tue24, '2026-11-26'), move(sat28, '2026-11-26')]),
        throwsA(isA<ValidationException>()),
      );
    });

    test('حصة لا وجود لها أو منقولة إلى موعد فيه حصة للفوج', () async {
      await expectLater(
        replan([move('2026-11-25', '2026-11-26')]),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.toString(),
            'الرسالة',
            contains('لا حصة قادمة'),
          ),
        ),
      );
      await expectLater(
        replan([move(tue24, sat28)]),
        throwsA(isA<ValidationException>()),
      );
      expect((await shape()).where((s) => s.contains('makeup')), isEmpty);
    });

    test('حصة سُجّل حضورها لا تُنقل', () async {
      final marked = (await cycleSessions()).firstWhere((s) => s.date == sat21);
      await env.db
          .into(env.db.attendance)
          .insert(
            AttendanceCompanion.insert(
              id: 'att-1',
              createdAt: 1,
              updatedAt: 1,
              sessionId: marked.id,
              studentId: 's1',
              status: 'present',
              method: 'manual',
            ),
          );
      await expectLater(
        replan([move(sat21, '2026-11-22')]),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.toString(),
            'الرسالة',
            contains('سُجّل حضورها'),
          ),
        ),
      );
      expect((await shape()).first, '$sat21:normal');
    });

    test('تعارض الأستاذ في الموعد الجديد يمنع النقل ويُبقي كل شيء', () async {
      // فوج آخر للأستاذ نفسه يدرس الخميس 10:00 فيتعارض مع نقل الحصة إلى خميس 26.
      await env.group(id: 'g2', number: 2);
      await env.slot(id: 'sl-g2', groupId: 'g2', weekday: 4);
      await cycles.topUp('g2', fromDate: '2026-11-18');
      final before = await shape();
      await expectLater(
        replan([move(tue24, '2026-11-26')]),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.toString(),
            'الرسالة',
            contains('تعارض'),
          ),
        ),
      );
      expect(await shape(), before);
    });

    test('إلى اليوم نفسه: مسموح قبل نهاية الحصة ومرفوض بعدها', () async {
      await replan([move(tue24, '2026-11-18')]);
      expect((await shape()).contains('2026-11-18:makeup'), isTrue);
      await expectLater(
        replan([move(sat28, '2026-11-18')], at: DateTime(2026, 11, 18, 12)),
        throwsA(isA<ValidationException>()),
        reason: 'انتهى وقت الحصة (11:30) قبل الثانية عشرة',
      );
    });
  });
}
