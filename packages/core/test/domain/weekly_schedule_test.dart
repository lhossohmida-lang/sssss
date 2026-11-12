import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late WeeklyScheduleQueries queries;

  setUp(() async {
    env = TestEnv();
    queries = WeeklyScheduleQueries(env.db);
    await env.subject();
    await env.teacher();
    await env.teacher(id: 't2');
    await env.room();
    await env.room(id: 'r2');
  });
  tearDown(() => env.close());

  test('بلا مجموعات: جدول فارغ بحدود افتراضية', () async {
    final schedule = await queries.load();
    expect(schedule.isEmpty, isTrue);
    expect(schedule.firstMinute, 480);
    expect(schedule.lastMinute, 1080);
    expect(schedule.by(ScheduleAxis.room), isEmpty);
  });

  test('الخانات بقاعتها: قاعة الخانة ثم الافتراضية للمجموعة', () async {
    await env.group(roomId: 'r1');
    await env.slot(id: 'a', weekday: 6);
    await env.slot(id: 'b', weekday: 2, roomId: 'r2');
    final schedule = await queries.load();
    final rooms = {for (final e in schedule.entries) e.weekday: e.roomId};
    expect(rooms, {6: 'r1', 2: 'r2'});
    expect(schedule.entries.first.roomName, isNotNull);
  });

  test('التجميع حسب القاعة: مرتب بالاسم و«بلا قاعة» آخراً', () async {
    await env.group(roomId: 'r2');
    await env.group(id: 'g2', number: 2, teacherId: 't2');
    await env.slot(id: 'a', weekday: 6);
    await env.slot(id: 'b', groupId: 'g2', weekday: 6, start: 800, end: 890);
    final rooms = (await queries.load()).by(ScheduleAxis.room);
    expect(rooms.map((r) => r.id), ['r2', null]);
    expect(rooms.last.name, 'بلا قاعة');
    expect(rooms.last.entries.single.groupNumber, 2);
  });

  test('التجميع حسب الأستاذ والترتيب: السبت أولاً ثم ببداية الحصة', () async {
    await env.group(roomId: 'r1');
    await env.slot(id: 'fri', weekday: 5, start: 600, end: 690);
    await env.slot(id: 'tue-late', weekday: 2, start: 900, end: 990);
    await env.slot(id: 'tue-early', weekday: 2, start: 600, end: 690);
    await env.slot(id: 'sat', weekday: 6, start: 700, end: 790);
    final teachers = (await queries.load()).by(ScheduleAxis.teacher);
    expect(teachers.single.id, 't1');
    expect(teachers.single.entries.map((e) => (e.weekday, e.startMinutes)), [
      (6, 700),
      (2, 600),
      (2, 900),
      (5, 600),
    ]);
    expect(teachers.single.on(2), hasLength(2));
    expect(teachers.single.on(3), isEmpty);
  });

  test('حدود المحور من أبكر بداية وأتأخر نهاية', () async {
    await env.group();
    await env.slot(id: 'a', weekday: 6, start: 540, end: 630);
    await env.slot(id: 'b', weekday: 7, start: 1000, end: 1110);
    final schedule = await queries.load();
    expect(schedule.firstMinute, 540);
    expect(schedule.lastMinute, 1110);
  });

  test('المؤرشفة والمحذوفة وخاناتها المحذوفة لا تظهر', () async {
    await env.group(roomId: 'r1');
    await env.group(id: 'g2', number: 2);
    await env.group(id: 'g3', number: 3);
    await env.slot(id: 'a', weekday: 6);
    await env.slot(id: 'b', groupId: 'g2', weekday: 6);
    await env.slot(id: 'c', groupId: 'g3', weekday: 6);
    await env.slot(id: 'd', weekday: 3);
    await env.db.customStatement(
      "UPDATE groups SET archived_at = 5 WHERE id = 'g2'",
    );
    await env.db.customStatement(
      "UPDATE groups SET deleted_at = 5 WHERE id = 'g3'",
    );
    await env.db.customStatement(
      "UPDATE group_slots SET deleted_at = 5 WHERE id = 'd'",
    );
    final schedule = await queries.load();
    expect(schedule.entries.map((e) => e.groupId), ['g1']);
  });

  test('الوصف والوقت', () async {
    await env.group(roomId: 'r1');
    await env.slot(id: 'a', weekday: 6, start: 605, end: 695);
    final entry = (await queries.load()).entries.single;
    expect(entry.timeText, '10:05–11:35');
    expect(entry.label, 'المجموعة 1 · رياضيات · السبت 10:05–11:35');
  });

  test('جدول تلميذ: مجموعاته الحالية فقط', () async {
    await env.student();
    await env.group(roomId: 'r1');
    await env.group(id: 'g2', number: 2, teacherId: 't2');
    await env.group(id: 'g3', number: 3);
    await env.slot(id: 'a', weekday: 6);
    await env.slot(id: 'b', groupId: 'g2', weekday: 2);
    await env.slot(id: 'c', groupId: 'g3', weekday: 3);
    await env.enroll(id: 'e1', studentId: 's1');
    await env.enroll(id: 'e2', groupId: 'g2', studentId: 's1');
    await env.enroll(id: 'e3', groupId: 'g3', studentId: 's1');
    await env.db.customStatement(
      "UPDATE group_students SET left_at = 5 WHERE id = 'e3'",
    );
    final mine = await queries.load(studentId: 's1');
    expect(mine.entries.map((e) => e.groupNumber).toSet(), {1, 2});
    expect((await queries.load()).entries, hasLength(3));
    expect((await queries.load(studentId: 'nobody')).isEmpty, isTrue);
  });

  test('watch يتحدث عند إضافة خانة', () async {
    await env.group();
    final seen = <int>[];
    final sub = queries.watch().listen((s) => seen.add(s.entries.length));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await env.slot(id: 'a', weekday: 6);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await sub.cancel();
    expect(seen.first, 0);
    expect(seen.last, 1);
  });
}
