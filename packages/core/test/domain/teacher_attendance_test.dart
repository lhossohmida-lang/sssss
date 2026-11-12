import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late CycleService cycles;
  late AttendanceService attendance;
  late TeacherAttendanceQueries queries;

  // سبت 2026-11-14 وثلاثاء 2026-11-17، والحصة من 10:00 إلى 11:30.
  final afterAll = DateTime(2026, 12, 31);

  setUp(() async {
    env = TestEnv();
    cycles = CycleService(env.db, env.writer);
    attendance = AttendanceService(
      env.db,
      env.writer,
      cycles,
      DuesService(env.db, env.writer),
    );
    queries = TeacherAttendanceQueries(env.db, env.writer);
    await env.subject();
    await env.teacher();
    await env.teacher(id: 't2');
    await env.group(sessionsPerCycle: 4);
    await env.group(id: 'g2', number: 2, teacherId: 't2');
    await env.slot(id: 'sl-sat', weekday: 6);
    await env.slot(id: 'sl-tue', weekday: 2);
    await env.slot(id: 'sl2', groupId: 'g2', weekday: 6, start: 840, end: 930);
    await cycles.topUp('g1', fromDate: '2026-11-14');
    await cycles.topUp('g2', fromDate: '2026-11-14');
    await env.db
        .into(env.db.userAccounts)
        .insert(
          UserAccountsCompanion.insert(
            id: 'owner1',
            createdAt: 1,
            updatedAt: 1,
            email: 'owner@school.local',
            role: UserRole.owner.code,
          ),
        );
  });
  tearDown(() => env.close());

  Future<SessionRow> sessionOf(String groupId, String date) async =>
      (await cycles.cycleSessions(
        groupId,
        1,
      )).firstWhere((s) => s.date == date);

  Future<void> checkIn(
    String teacherId,
    String sessionId, {
    int late = 0,
    bool out = false,
  }) => env.db
      .into(env.db.teacherAttendance)
      .insert(
        TeacherAttendanceCompanion.insert(
          id: 'ta-$teacherId-$sessionId',
          createdAt: 1,
          updatedAt: 1,
          teacherId: teacherId,
          sessionId: Value(sessionId),
          date: '2026-11-14',
          checkIn: const Value(100),
          checkOut: Value(out ? 200 : null),
          lateMinutes: Value(late),
        ),
      );

  test('كشف الشهر: حصص كل أستاذ بحالتها وعدّاداته', () async {
    final sat = await sessionOf('g1', '2026-11-14');
    await checkIn('t1', sat.id, late: 7, out: true);
    final sheet = await queries.sheet('2026-11', now: afterAll);
    expect(sheet.map((m) => m.teacherId), ['t1', 't2']);
    final t1 = sheet.first;
    expect(t1.name, 'الأستاذ t1');
    expect(t1.sessions, hasLength(4));
    expect(t1.attended, 1);
    expect(t1.missed, 3);
    expect(t1.held, 4);
    expect(t1.totalLateMinutes, 7);
    final first = t1.sessions.first;
    expect(first.status, TeacherSessionStatus.present);
    expect(first.lateMinutes, 7);
    expect(first.checkIn, isNotNull);
    expect(first.checkOut, isNotNull);
    expect(first.groupLabel, 'المجموعة 1 · رياضيات');
    expect(sheet.last.missed, 3, reason: 'حصص نوفمبر للمجموعة 2: 14 و21 و28');
  });

  test('الحصص التي لم تنتهِ بعد معلّقة لا غياب', () async {
    final sheet = await queries.sheet(
      '2026-11',
      now: DateTime(2026, 11, 14, 9, 0),
    );
    final t1 = sheet.first;
    expect(
      t1.sessions.every((s) => s.status == TeacherSessionStatus.pending),
      isTrue,
    );
    expect(t1.missed, 0);
    // انتهت حصة السبت الأولى فقط عند 11:30.
    final later = await queries.sheet(
      '2026-11',
      now: DateTime(2026, 11, 14, 11, 30),
    );
    expect(later.first.sessions.first.status, TeacherSessionStatus.absent);
    expect(later.first.sessions[1].status, TeacherSessionStatus.pending);
  });

  test('الحصة المغلقة بلا حضور أستاذها غائبة ولو لم يحن وقتها', () async {
    final sat = await sessionOf('g1', '2026-11-14');
    await env.db.customStatement(
      'UPDATE sessions SET closed_at = 5 WHERE id = ?',
      [sat.id],
    );
    final sheet = await queries.sheet('2026-11', now: DateTime(2026, 11, 1));
    expect(sheet.first.sessions.first.status, TeacherSessionStatus.absent);
  });

  test('الملغاة والمحذوفة وشهر آخر لا تظهر', () async {
    final tue = await sessionOf('g1', '2026-11-17');
    await cycles.cancelSession(tue.id);
    final sheet = await queries.sheet('2026-11', now: afterAll);
    expect(sheet.first.sessions.any((s) => s.sessionId == tue.id), isFalse);
    expect((await queries.sheet('2026-10', now: afterAll)), isEmpty);
  });

  test('الحصص الفائتة: الأحدث أولاً وبمن لم يحضر', () async {
    final sat = await sessionOf('g1', '2026-11-14');
    await checkIn('t1', sat.id);
    final missed = await queries.missed(since: '2026-11-01', now: afterAll);
    // 3 حصص للمجموعة 1 (دون التي حضرها) و7 فائتة للمجموعة 2 (آخر حصة
    // 2027-01-02 لم تحن بعد).
    expect(missed, hasLength(10));
    expect(missed.first.date, '2026-12-26');
    expect(
      missed.any((m) => m.sessionId == sat.id),
      isFalse,
      reason: 'حضرها أستاذها',
    );
    final recent = await queries.missed(since: '2026-11-17', now: afterAll);
    expect(recent.every((m) => m.date.compareTo('2026-11-17') >= 0), isTrue);
    expect(recent.map((m) => m.teacherName).toSet(), contains('الأستاذ t1'));
  });

  test('تسجيل حضور الأستاذ يدوياً يزيل الغياب ولا يتكرر', () async {
    final sat = await sessionOf('g1', '2026-11-14');
    expect(await queries.markPresent(sat.id), isTrue);
    expect(await queries.markPresent(sat.id), isFalse);
    final row = (await queries.sheet(
      '2026-11',
      now: afterAll,
    )).first.sessions.firstWhere((s) => s.sessionId == sat.id);
    expect(row.status, TeacherSessionStatus.present);
    expect(await queries.markPresent('nope'), isFalse);
  });

  test('تسجيل يدوي بعد حذف ناعم لسجل الحضور يعيده', () async {
    final sat = await sessionOf('g1', '2026-11-14');
    await queries.markPresent(sat.id);
    await env.db.customStatement(
      'UPDATE teacher_attendance SET deleted_at = 9',
    );
    expect(await queries.markPresent(sat.id), isTrue);
  });

  test('تسجيل حضور حصة ملغاة مرفوض', () async {
    final tue = await sessionOf('g1', '2026-11-17');
    await cycles.cancelSession(tue.id);
    expect(await queries.markPresent(tue.id), isFalse);
  });

  group('تنبيه الغياب عند إغلاق الحصة', () {
    Future<List<NotificationRow>> alerts() => env.db
        .select(env.db.notifications)
        .get()
        .then(
          (rows) => rows
              .where((n) => n.kind == AttendanceService.notifyTeacherAbsent)
              .toList(),
        );

    test('حصة أُغلقت ولم يحضرها أستاذها: إشعار للمالك', () async {
      await attendance.closeDueSessions(DateTime(2026, 11, 14, 16));
      final sent = await alerts();
      expect(sent, hasLength(2), reason: 'حصة g1 وحصة g2 في السبت');
      expect(sent.every((n) => n.userId == 'owner1'), isTrue);
      expect(sent.every((n) => n.entity == 'sessions'), isTrue);
      expect(
        sent.map((n) => n.body).join(' '),
        allOf(contains('الأستاذ t1'), contains('الأستاذ t2')),
      );
      expect(sent.first.body, contains('2026-11-14'));
    });

    test('حصة حضرها أستاذها: لا إشعار', () async {
      final sat = await sessionOf('g1', '2026-11-14');
      await checkIn('t1', sat.id);
      await attendance.closeDueSessions(DateTime(2026, 11, 14, 16));
      final sent = await alerts();
      expect(sent, hasLength(1));
      expect(sent.single.body, contains('الأستاذ t2'));
    });

    test('إعادة التشغيل لا تكرر الإشعار', () async {
      await attendance.closeDueSessions(DateTime(2026, 11, 14, 16));
      final before = (await alerts()).length;
      await attendance.closeDueSessions(DateTime(2026, 11, 14, 16));
      expect(await alerts(), hasLength(before));
    });
  });

  test('watchSheet يتحدث عند تسجيل الحضور', () async {
    final sat = await sessionOf('g1', '2026-11-14');
    final seen = <int>[];
    final sub = queries
        .watchSheet('2026-11')
        .listen((s) => seen.add(s.first.attended));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await queries.markPresent(sat.id);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await sub.cancel();
    expect(seen.first, 0);
    expect(seen.last, 1);
  });
}
