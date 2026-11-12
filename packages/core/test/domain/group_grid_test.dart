import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late GroupGridQueries queries;

  setUp(() async {
    env = TestEnv();
    queries = GroupGridQueries(env.db);
    await env.subject();
    await env.teacher();
    await env.group();
    await env.student();
    await env.student(id: 's2');
  });
  tearDown(() => env.close());

  Future<void> session(
    String id, {
    int cycle = 1,
    String date = '2026-11-07',
    int start = 600,
    String status = 'normal',
    bool closed = false,
    bool deleted = false,
  }) => env.db
      .into(env.db.sessions)
      .insert(
        SessionsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          groupId: 'g1',
          cycleNumber: cycle,
          date: date,
          startMinutes: start,
          endMinutes: start + 90,
          status: Value(status),
          closedAt: Value(closed ? 5 : null),
          deletedAt: Value(deleted ? 9 : null),
        ),
      );

  Future<void> mark(String sessionId, String studentId, String status) => env.db
      .into(env.db.attendance)
      .insert(
        AttendanceCompanion.insert(
          id: 'a-$sessionId-$studentId',
          createdAt: 1,
          updatedAt: 1,
          sessionId: sessionId,
          studentId: studentId,
          status: status,
          method: 'manual',
        ),
      );

  test('مجموعة مجهولة: null', () async {
    expect(await queries.load('missing'), isNull);
  });

  test('الحصص مرتبة زمنياً دون المحذوفة، والملغاة تبقى ظاهرة', () async {
    await session('b', date: '2026-11-10');
    await session('a', date: '2026-11-07');
    await session('c', date: '2026-11-14', status: 'cancelled');
    await session('gone', date: '2026-11-15', deleted: true);
    final grid = (await queries.load('g1'))!;
    expect(grid.sessions.map((s) => s.id), ['a', 'b', 'c']);
    expect(grid.countedSessions, 2);
    expect(grid.cycleNumber, 1);
    expect(grid.isCurrent, isTrue);
  });

  test('المنعقدة هي المُغلقة المحسوبة', () async {
    await session('a', closed: true);
    await session('b', date: '2026-11-10', closed: true, status: 'cancelled');
    await session('c', date: '2026-11-14');
    expect((await queries.load('g1'))!.heldSessions, 1);
  });

  test('التلاميذ بحالاتهم في كل حصة، ومن لا حضور له خلية فارغة', () async {
    await env.enroll(id: 'e1', studentId: 's1');
    await env.enroll(id: 'e2', studentId: 's2');
    await session('a');
    await session('b', date: '2026-11-10');
    await session('c', date: '2026-11-14');
    await mark('a', 's1', 'present');
    await mark('b', 's1', 'absent');
    await mark('c', 's1', 'excused');
    await mark('a', 's2', 'present');
    final grid = (await queries.load('g1'))!;
    final s1 = grid.students.firstWhere((s) => s.studentId == 's1');
    expect(s1.cells, {
      'a': AttendanceStatus.present,
      'b': AttendanceStatus.absent,
      'c': AttendanceStatus.excused,
    });
    expect(s1.count(AttendanceStatus.present), 1);
    expect(s1.count(AttendanceStatus.excused), 1);
    final s2 = grid.students.firstWhere((s) => s.studentId == 's2');
    expect(s2.cells, {'a': AttendanceStatus.present});
    expect(s2.cells['b'], isNull);
  });

  test('التلاميذ مرتبون باللقب والاسم', () async {
    await env.student(id: 's0');
    for (final id in ['s1', 's2', 's0']) {
      await env.enroll(id: 'e-$id', studentId: id);
    }
    final grid = (await queries.load('g1'))!;
    expect(grid.students.map((s) => s.studentId), ['s0', 's1', 's2']);
  });

  test('من التحق في دورة لاحقة لا يظهر في السابقة', () async {
    await env.enroll(id: 'e1', studentId: 's1');
    await env.enroll(id: 'e2', studentId: 's2', joinedCycle: 2);
    await session('a');
    await session('x', cycle: 2, date: '2026-12-05');
    final first = (await queries.load('g1', cycleNumber: 1))!;
    expect(first.students.map((s) => s.studentId), ['s1']);
    final second = (await queries.load('g1', cycleNumber: 2))!;
    expect(second.students.map((s) => s.studentId), ['s1', 's2']);
    expect(second.sessions.single.id, 'x');
  });

  test('من غادر يظهر في الدورة التي حضر فيها فقط', () async {
    await env.enroll(id: 'e1', studentId: 's1');
    await env.db.customStatement(
      "UPDATE group_students SET left_at = 50 WHERE id = 'e1'",
    );
    await session('a');
    await session('x', cycle: 2, date: '2026-12-05');
    // لا حضور له: لا يظهر.
    expect((await queries.load('g1', cycleNumber: 1))!.students, isEmpty);
    await mark('a', 's1', 'present');
    final grid = (await queries.load('g1', cycleNumber: 1))!;
    expect(grid.students.single.leftGroup, isTrue);
    expect((await queries.load('g1', cycleNumber: 2))!.students, isEmpty);
  });

  test('تلميذ محذوف أو انتساب محذوف لا يظهر', () async {
    await env.enroll(id: 'e1', studentId: 's1');
    await env.enroll(id: 'e2', studentId: 's2');
    await env.db.customStatement(
      "UPDATE students SET deleted_at = 9 WHERE id = 's1'",
    );
    await env.db.customStatement(
      "UPDATE group_students SET deleted_at = 9 WHERE id = 'e2'",
    );
    expect((await queries.load('g1'))!.students, isEmpty);
  });

  test('الدورة الافتراضية هي الحالية ويمكن اختيار سابقة', () async {
    await env.db.customStatement(
      "UPDATE groups SET current_cycle_number = 3 WHERE id = 'g1'",
    );
    expect((await queries.load('g1'))!.cycleNumber, 3);
    expect((await queries.load('g1', cycleNumber: 2))!.isCurrent, isFalse);
  });

  test('watch يتحدث مع الحضور الجديد', () async {
    await env.enroll(id: 'e1', studentId: 's1');
    await session('a');
    final seen = <int>[];
    final sub = queries
        .watch('g1')
        .listen((g) => seen.add(g?.students.single.cells.length ?? -1));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await mark('a', 's1', 'present');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await sub.cancel();
    expect(seen.first, 0);
    expect(seen.last, 1);
  });
}
