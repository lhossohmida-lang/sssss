import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late AttendanceService attendance;
  late CycleService cycles;

  // 2026-11-14 سبت، و2026-11-17 ثلاثاء. الحصص من 10:00 إلى 11:30.
  const saturday = '2026-11-14';
  const tuesday = '2026-11-17';

  setUp(() async {
    env = TestEnv();
    cycles = CycleService(env.db, env.writer);
    attendance = AttendanceService(
      env.db,
      env.writer,
      cycles,
      DuesService(env.db, env.writer),
    );
    await env.subject();
    await env.teacher();
    await env.group(sessionsPerCycle: 2);
    await env.slot(id: 'sl-sat', weekday: 6);
    await env.slot(id: 'sl-tue', weekday: 2);
    await env.student();
    await env.student(id: 's2');
    await env.enroll(id: 'e1', studentId: 's1');
    await env.enroll(id: 'e2', studentId: 's2');
    await cycles.topUp('g1', fromDate: saturday);
  });
  tearDown(() => env.close());

  Future<SessionRow> sessionOn(String date) async =>
      (await cycles.cycleSessions('g1', 1)).firstWhere((s) => s.date == date);

  Future<Map<String, String>> statuses(String sessionId) async {
    final rows = await env.db.select(env.db.attendance).get();
    return {
      for (final r in rows)
        if (r.sessionId == sessionId && r.deletedAt == null)
          r.studentId: r.status,
    };
  }

  Future<List<StudentCreditRow>> credits() => env.db
      .select(env.db.studentCredits)
      .get()
      .then((rows) => rows.where((c) => c.deletedAt == null).toList());

  Future<int> auditCount() async =>
      (await env.db.select(env.db.auditLog).get()).length;

  group('القراءة', () {
    test('حصص اليوم بعدّاداتها', () async {
      final sat = await sessionOn(saturday);
      await attendance.mark(
        sessionId: sat.id,
        studentId: 's1',
        status: AttendanceStatus.present,
      );
      await attendance.mark(
        sessionId: sat.id,
        studentId: 's2',
        status: AttendanceStatus.absent,
      );
      final day = await attendance.day(saturday);
      expect(day, hasLength(1));
      expect(day.single.students, 2);
      expect(day.single.present, 1);
      expect(day.single.absent, 1);
      expect(day.single.excused, 0);
      expect(day.single.unmarked, 0);
      expect(day.single.groupNumber, 1);
      expect(day.single.subjectName, 'رياضيات');
      expect(await attendance.day('2026-12-01'), isEmpty);
    });

    test('حصة بلا تسجيل: كل التلاميذ غير مسجَّلين', () async {
      final day = await attendance.day(tuesday);
      expect(day.single.unmarked, 2);
      expect(day.single.closed, isFalse);
      expect(day.single.cancelled, isFalse);
    });

    test('الحصة الملغاة تظهر في اليوم', () async {
      final tue = await sessionOn(tuesday);
      await cycles.cancelSession(tue.id);
      final day = await attendance.day(tuesday);
      expect(day.single.cancelled, isTrue);
    });

    test(
      'الورقة: التلاميذ مرتبون بحالاتهم، ومن غادر دون حضور لا يظهر',
      () async {
        await env.student(id: 's0');
        await env.enroll(id: 'e0', studentId: 's0');
        await env.db.customStatement(
          "UPDATE group_students SET left_at = 5 WHERE id = 'e0'",
        );
        final sat = await sessionOn(saturday);
        await attendance.mark(
          sessionId: sat.id,
          studentId: 's1',
          status: AttendanceStatus.excused,
          canExcuse: true,
        );
        final roster = (await attendance.roster(sat.id))!;
        expect(roster.students.map((s) => s.studentId), ['s1', 's2']);
        expect(roster.students.first.status, AttendanceStatus.excused);
        expect(roster.students.first.method, AttendanceMethod.manual);
        expect(roster.students.last.status, isNull);
        expect(roster.count(AttendanceStatus.excused), 1);
        expect(roster.unmarked, 1);
        expect(roster.teacherName, 'الأستاذ t1');
      },
    );

    test('من غادر وله حضور في الحصة يبقى ظاهراً', () async {
      final sat = await sessionOn(saturday);
      await attendance.mark(
        sessionId: sat.id,
        studentId: 's1',
        status: AttendanceStatus.present,
      );
      await env.db.customStatement(
        "UPDATE group_students SET left_at = 5 WHERE id = 'e1'",
      );
      final roster = (await attendance.roster(sat.id))!;
      expect(roster.students.map((s) => s.studentId), contains('s1'));
    });

    test('ورقة حصة مجهولة: null', () async {
      expect(await attendance.roster('nope'), isNull);
    });

    test('watchDay يتحدث بعد التسجيل', () async {
      final sat = await sessionOn(saturday);
      final seen = <int>[];
      final sub = attendance
          .watchDay(saturday)
          .listen((d) => seen.add(d.single.present));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await attendance.mark(
        sessionId: sat.id,
        studentId: 's1',
        status: AttendanceStatus.present,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();
      expect(seen.first, 0);
      expect(seen.last, 1);
    });
  });

  group('التسجيل اليدوي', () {
    test('حاضر ثم تغيير إلى غائب بنفس السجل', () async {
      final sat = await sessionOn(saturday);
      await attendance.mark(
        sessionId: sat.id,
        studentId: 's1',
        status: AttendanceStatus.present,
      );
      await attendance.mark(
        sessionId: sat.id,
        studentId: 's1',
        status: AttendanceStatus.absent,
      );
      expect(await statuses(sat.id), {'s1': 'absent'});
      expect(await env.db.select(env.db.attendance).get(), hasLength(1));
    });

    test('تكرار نفس الحالة لا يكتب شيئاً', () async {
      final sat = await sessionOn(saturday);
      await attendance.mark(
        sessionId: sat.id,
        studentId: 's1',
        status: AttendanceStatus.present,
      );
      final before = await auditCount();
      await attendance.mark(
        sessionId: sat.id,
        studentId: 's1',
        status: AttendanceStatus.present,
      );
      expect(await auditCount(), before);
    });

    test('«غائب برخصة» مرفوض دون صلاحية', () async {
      final sat = await sessionOn(saturday);
      await expectLater(
        attendance.mark(
          sessionId: sat.id,
          studentId: 's1',
          status: AttendanceStatus.excused,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await statuses(sat.id), isEmpty);
    });

    test('«غائب برخصة» تنشئ رصيداً، وتغييرها إلى حاضر يلغيه', () async {
      final sat = await sessionOn(saturday);
      await attendance.mark(
        sessionId: sat.id,
        studentId: 's1',
        status: AttendanceStatus.excused,
        canExcuse: true,
      );
      final created = await credits();
      expect(created, hasLength(1));
      // 2000 × 1 ÷ 2 حصص.
      expect(created.single.amount, 1000);
      expect(created.single.reason, 'excused');

      await attendance.mark(
        sessionId: sat.id,
        studentId: 's1',
        status: AttendanceStatus.present,
      );
      expect(await credits(), isEmpty);
    });

    test('تلميذ ليس في المجموعة، أو حصة مجهولة أو ملغاة: مرفوض', () async {
      await env.student(id: 'x');
      final sat = await sessionOn(saturday);
      await expectLater(
        attendance.mark(
          sessionId: sat.id,
          studentId: 'x',
          status: AttendanceStatus.present,
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        attendance.mark(
          sessionId: 'nope',
          studentId: 's1',
          status: AttendanceStatus.present,
        ),
        throwsA(isA<ValidationException>()),
      );
      await cycles.cancelSession(sat.id);
      await expectLater(
        attendance.mark(
          sessionId: sat.id,
          studentId: 's1',
          status: AttendanceStatus.present,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('المسح: يزيل التسجيل والرصيد، وممنوع بعد الإغلاق', () async {
      final sat = await sessionOn(saturday);
      await attendance.mark(
        sessionId: sat.id,
        studentId: 's1',
        status: AttendanceStatus.excused,
        canExcuse: true,
      );
      await attendance.clear(sessionId: sat.id, studentId: 's1');
      expect(await statuses(sat.id), isEmpty);
      expect(await credits(), isEmpty);

      // بعد المسح يمكن التسجيل من جديد بنفس السجل المحسوم.
      await attendance.mark(
        sessionId: sat.id,
        studentId: 's1',
        status: AttendanceStatus.present,
      );
      expect(await statuses(sat.id), {'s1': 'present'});

      await cycles.closeSession(sat.id);
      await expectLater(
        attendance.clear(sessionId: sat.id, studentId: 's1'),
        throwsA(isA<ValidationException>()),
      );
    });

    test('التصحيح بعد الإغلاق مسموح: غائب تلقائي إلى برخصة', () async {
      final sat = await sessionOn(saturday);
      await attendance.closeDueSessions(DateTime(2026, 11, 14, 12));
      expect(await statuses(sat.id), {'s1': 'absent', 's2': 'absent'});
      await attendance.mark(
        sessionId: sat.id,
        studentId: 's1',
        status: AttendanceStatus.excused,
        canExcuse: true,
      );
      expect((await statuses(sat.id))['s1'], 'excused');
      expect(await credits(), hasLength(1));
    });

    test('تسجيل الكل حاضراً لا يمس من سُجّل غائباً', () async {
      final sat = await sessionOn(saturday);
      await attendance.mark(
        sessionId: sat.id,
        studentId: 's1',
        status: AttendanceStatus.absent,
      );
      expect(await attendance.markAllPresent(sat.id), 1);
      expect(await statuses(sat.id), {'s1': 'absent', 's2': 'present'});
      expect(await attendance.markAllPresent(sat.id), 0);
    });
  });

  group('التغييب التلقائي', () {
    test('قبل نهاية الحصة لا يُغلق شيء، وعند النهاية تماماً يُغلق', () async {
      final sat = await sessionOn(saturday);
      expect(
        await attendance.closeDueSessions(DateTime(2026, 11, 14, 11, 29)),
        0,
      );
      expect((await sessionOn(saturday)).closedAt, isNull);
      expect(
        await attendance.closeDueSessions(DateTime(2026, 11, 14, 11, 30)),
        1,
      );
      expect((await sessionOn(saturday)).closedAt, isNotNull);
      expect(await statuses(sat.id), {'s1': 'absent', 's2': 'absent'});
    });

    test('من سُجّل حضوره أو رخصته يبقى، والباقي غائب بطريقة يدوية', () async {
      final sat = await sessionOn(saturday);
      await attendance.mark(
        sessionId: sat.id,
        studentId: 's1',
        status: AttendanceStatus.present,
      );
      await env.student(id: 's3');
      await env.enroll(id: 'e3', studentId: 's3');
      await attendance.mark(
        sessionId: sat.id,
        studentId: 's3',
        status: AttendanceStatus.excused,
        canExcuse: true,
      );
      await attendance.closeDueSessions(DateTime(2026, 11, 14, 12));
      expect(await statuses(sat.id), {
        's1': 'present',
        's2': 'absent',
        's3': 'excused',
      });
      final rows = await env.db.select(env.db.attendance).get();
      expect(
        rows.firstWhere((r) => r.studentId == 's2').method,
        AttendanceMethod.manual.code,
      );
    });

    test('آمن عند التكرار', () async {
      expect(await attendance.closeDueSessions(DateTime(2026, 11, 14, 12)), 1);
      final audit = await auditCount();
      expect(await attendance.closeDueSessions(DateTime(2026, 11, 14, 12)), 0);
      expect(await auditCount(), audit);
    });

    test('التلميذ المحذوف لا يُغيَّب، والحصة الملغاة لا تُغلق', () async {
      final tue = await sessionOn(tuesday);
      await env.db.customStatement(
        "UPDATE students SET deleted_at = 9 WHERE id = 's2'",
      );
      await attendance.closeDueSessions(DateTime(2026, 11, 14, 12));
      expect((await statuses((await sessionOn(saturday)).id)).keys, ['s1']);
      expect((await sessionOn(tuesday)).closedAt, isNull);

      await cycles.cancelSession(tue.id);
      await attendance.closeDueSessions(DateTime(2026, 12, 1));
      final cancelled = (await env.db.select(env.db.sessions).get()).firstWhere(
        (s) => s.id == tue.id,
      );
      expect(cancelled.closedAt, isNull);
    });

    test('مجموعة مؤرشفة لا تُعالج', () async {
      await env.db.customStatement(
        'UPDATE groups SET archived_at = 5 WHERE id = ?',
        ['g1'],
      );
      expect(await attendance.closeDueSessions(DateTime(2026, 12, 1)), 0);
    });

    test('إغلاق آخر حصة يكمل الدورة ويبرمج التالية', () async {
      expect(await attendance.closeDueSessions(DateTime(2026, 11, 18)), 2);
      final group = (await env.db.select(env.db.groups).get()).single;
      expect(group.currentCycleNumber, 2);
      final next = await cycles.cycleSessions('g1', 2);
      expect(next, hasLength(2));
      expect(next.every((s) => s.closedAt == null), isTrue);
      // حصص الدورة الأولى كلها مُغلقة وحضورها مسجَّل.
      for (final s in await cycles.cycleSessions('g1', 1)) {
        expect(s.closedAt, isNotNull);
        expect(await statuses(s.id), {'s1': 'absent', 's2': 'absent'});
      }
    });
  });
}
