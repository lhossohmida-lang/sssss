import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late ChildAttendanceService service;
  // «الآن»: 2026-11-14 الساعة 12:00.
  final now = DateTime(2026, 11, 14, 12);

  setUp(() async {
    env = TestEnv();
    service = ChildAttendanceService(env.db, now: () => now);
    await env.subject();
    await env.teacher();
    await env.group();
    await env.student();
    await env.student(id: 's2');
    await env.enroll(id: 'e1', studentId: 's1');
  });
  tearDown(() => env.close());

  Future<void> session(
    String id,
    String date, {
    int start = 600,
    int end = 690,
    String status = 'normal',
    bool closed = false,
    String group = 'g1',
  }) => env.db
      .into(env.db.sessions)
      .insert(
        SessionsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          groupId: group,
          cycleNumber: 1,
          date: date,
          startMinutes: start,
          endMinutes: end,
          status: Value(status),
          closedAt: Value(closed ? 5 : null),
        ),
      );

  Future<void> mark(String id, String session, String student, String status) =>
      env.db
          .into(env.db.attendance)
          .insert(
            AttendanceCompanion.insert(
              id: id,
              createdAt: 1,
              updatedAt: 1,
              sessionId: session,
              studentId: student,
              status: status,
              method: 'manual',
            ),
          );

  Future<List<ChildSessionState>> states([
    String student = 's1',
    String month = '2026-11',
  ]) async => [
    for (final s in await service.sessions(student, 'g1', month)) s.state,
  ];

  test('حال كل حصة: حضر وغاب وبرخصة وملغاة وقادمة وغير مسجَّلة', () async {
    await session('a', '2026-11-01');
    await session('b', '2026-11-03');
    await session('c', '2026-11-05');
    await session('d', '2026-11-07', status: 'cancelled');
    await session('e', '2026-11-10');
    await session('f', '2026-11-20');
    await mark('m1', 'a', 's1', 'present');
    await mark('m2', 'b', 's1', 'absent');
    await mark('m3', 'c', 's1', 'excused');
    expect(await states(), [
      ChildSessionState.present,
      ChildSessionState.absent,
      ChildSessionState.excused,
      ChildSessionState.cancelled,
      ChildSessionState.pending,
      ChildSessionState.upcoming,
    ]);
  });

  test(
    'حصة اليوم: قادمة قبل نهايتها، وغير مسجَّلة بعدها أو بعد إغلاقها',
    () async {
      await session('x', '2026-11-14', start: 840, end: 930);
      await session('y', '2026-11-14', start: 600, end: 690);
      await session('z', '2026-11-14', start: 900, end: 990, closed: true);
      expect(await states(), [
        ChildSessionState.pending, // 10:00–11:30 انتهت
        ChildSessionState.upcoming, // 14:00–15:30 لم تبدأ
        ChildSessionState.pending, // أُغلقت دون تسجيل
      ]);
    },
  );

  test('الشهر فقط، وحصص تلميذ آخر لا تؤثر في حاله', () async {
    await session('a', '2026-10-31');
    await session('b', '2026-11-02');
    await session('c', '2026-12-01');
    await mark('m1', 'b', 's2', 'present');
    final list = await service.sessions('s1', 'g1', '2026-11');
    expect(list.map((s) => s.date), ['2026-11-02']);
    expect(list.single.state, ChildSessionState.pending);
    expect(await service.sessions('s1', 'g1', '2026-10'), hasLength(1));
  });

  test('حصص مجموعة أخرى لا تظهر، ومن ليس منتسباً لا كشف له', () async {
    await env.group(id: 'g2', number: 2);
    await session('a', '2026-11-02', group: 'g2');
    await session('b', '2026-11-03');
    expect(
      (await service.sessions('s1', 'g1', '2026-11')).single.sessionId,
      'b',
    );
    expect(await service.sessions('s2', 'g1', '2026-11'), isEmpty);
  });

  test(
    'فترة الانتساب: لا حصص سبقت انضمامه ولا بعد مغادرته إلا ما سُجّل',
    () async {
      final joined = DateTime(2026, 11, 5, 9).toUtc().millisecondsSinceEpoch;
      final left = DateTime(2026, 11, 12, 9).toUtc().millisecondsSinceEpoch;
      await env.db.customStatement(
        'UPDATE group_students SET joined_at = $joined, left_at = $left '
        "WHERE id = 'e1'",
      );
      await session('a', '2026-11-02');
      await session('b', '2026-11-05');
      await session('c', '2026-11-09');
      await session('d', '2026-11-13');
      await session('e', '2026-11-02', start: 800, end: 890);
      // حضور مسجَّل قبل الانضمام يبقى ظاهراً.
      await mark('m1', 'e', 's1', 'present');
      final list = await service.sessions('s1', 'g1', '2026-11');
      expect(list.map((s) => s.sessionId), ['e', 'b', 'c']);
    },
  );

  test('العدّادات تحسب الحاضر والغائب والبرخصة فقط', () async {
    await session('a', '2026-11-01');
    await session('b', '2026-11-02');
    await session('c', '2026-11-03');
    await session('d', '2026-11-04', status: 'cancelled');
    await session('e', '2026-11-05');
    await session('f', '2026-11-30');
    await mark('m1', 'a', 's1', 'present');
    await mark('m2', 'b', 's1', 'present');
    await mark('m3', 'c', 's1', 'absent');
    await mark('m4', 'e', 's1', 'excused');
    final summary = ChildAttendanceService.summarize(
      await service.sessions('s1', 'g1', '2026-11'),
    );
    expect(summary.present, 2);
    expect(summary.absent, 1);
    expect(summary.excused, 1);
    expect(summary.total, 4);
  });

  test('حصة ملغاة سُجّل فيها حضور تبقى ملغاة', () async {
    await session('a', '2026-11-02', status: 'cancelled');
    await mark('m1', 'a', 's1', 'present');
    expect(await states(), [ChildSessionState.cancelled]);
  });

  test('watchMonth يتحدث بعد تسجيل الحضور', () async {
    await session('a', '2026-11-02');
    final seen = <ChildSessionState>[];
    final sub = service
        .watchMonth('s1', 'g1', '2026-11')
        .listen((l) => seen.add(l.single.state));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await mark('m1', 'a', 's1', 'present');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await sub.cancel();
    expect(seen.first, ChildSessionState.pending);
    expect(seen.last, ChildSessionState.present);
  });
}
