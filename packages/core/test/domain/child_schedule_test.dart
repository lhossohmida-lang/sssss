import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late ChildScheduleQueries queries;
  // «الآن»: 2026-11-14 الساعة 12:00 (720 دقيقة).
  final now = DateTime(2026, 11, 14, 12);

  setUp(() async {
    env = TestEnv();
    queries = ChildScheduleQueries(env.db, now: () => now);
    await env.subject();
    await env.teacher();
    await env.room();
    await env.group(roomId: 'r1');
    await env.group(id: 'g2', number: 2);
    await env.student();
    await env.student(id: 's2');
    await env.enroll(id: 'e1', studentId: 's1');
    await env.enroll(id: 'e2', groupId: 'g2', studentId: 's2');
  });
  tearDown(() => env.close());

  Future<void> session(
    String id,
    String date, {
    int start = 600,
    int end = 690,
    String group = 'g1',
    String status = 'normal',
    bool closed = false,
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

  test('القادمة بترتيب موعدها: اليوم بعد الآن وما بعده، دون الماضي', () async {
    await session('past', '2026-11-10');
    await session('doneToday', '2026-11-14', start: 600, end: 690);
    await session('laterToday', '2026-11-14', start: 840, end: 930);
    await session('tomorrow', '2026-11-15');
    await session('nextWeek', '2026-11-21', start: 500, end: 590);
    final list = await queries.upcoming('s1');
    expect(list.map((s) => s.sessionId), [
      'laterToday',
      'tomorrow',
      'nextWeek',
    ]);
    expect(list.first.timeText, '14:00 - 15:30');
    expect(list.first.groupNumber, 1);
    expect(list.first.subjectName, 'رياضيات');
    expect(list.first.teacherName, isNotEmpty);
    expect(list.first.roomName, isNotNull);
  });

  test('حصة اليوم الجارية (لم ينتهِ وقتها) تُعدّ قادمة، والمغلقة لا', () async {
    await session('running', '2026-11-14', start: 700, end: 790);
    await session('closed', '2026-11-14', start: 710, end: 800, closed: true);
    expect((await queries.upcoming('s1')).map((s) => s.sessionId), ['running']);
  });

  test('الملغاة تُدرج معلَّمة، ومجموعات الآخرين لا تظهر', () async {
    await session('a', '2026-11-16', status: 'cancelled');
    await session('b', '2026-11-17', group: 'g2');
    final mine = await queries.upcoming('s1');
    expect(mine.single.sessionId, 'a');
    expect(mine.single.cancelled, isTrue);
    expect((await queries.upcoming('s2')).single.sessionId, 'b');
    expect(await queries.upcoming('nobody'), isEmpty);
  });

  test('من غادر المجموعة لا يرى حصصها', () async {
    await session('a', '2026-11-16');
    await env.db.customStatement(
      "UPDATE group_students SET left_at = 5 WHERE id = 'e1'",
    );
    expect(await queries.upcoming('s1'), isEmpty);
  });

  test('الحد الأعلى لعدد الحصص', () async {
    for (var i = 0; i < 5; i++) {
      await session('s$i', '2026-11-${15 + i}');
    }
    expect(await queries.upcoming('s1', limit: 3), hasLength(3));
  });

  test('watchUpcoming يتحدث عند تغيير موعد حصة', () async {
    await session('a', '2026-11-16');
    final seen = <String>[];
    final sub = queries
        .watchUpcoming('s1')
        .listen((l) => seen.add(l.single.date));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await env.db.customUpdate(
      "UPDATE sessions SET date = '2026-11-18' WHERE id = 'a'",
      updates: {env.db.sessions},
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await sub.cancel();
    expect(seen.first, '2026-11-16');
    expect(seen.last, '2026-11-18');
  });
}
