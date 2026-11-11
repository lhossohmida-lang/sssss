import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late CycleService cycles;
  late DuesService dues;
  late ScanService scanner;

  // رموز صالحة الصيغة (بادئة + 10 رموز من الأبجدية المسموحة).
  const studentQr = 'S-AAAAAAAAAA';
  const student2Qr = 'S-BBBBBBBBBB';
  const teacherQr = 'T-AAAAAAAAAA';
  const workerQr = 'W-AAAAAAAAAA';

  // السبت 2026-11-14، والحصة من 10:00 إلى 11:30.
  DateTime at(int hour, int minute, {int day = 14, int second = 0}) =>
      DateTime(2026, 11, day, hour, minute, second);

  Future<void> setQr(String table, String id, String qr) => env.db.customUpdate(
    'UPDATE $table SET qr_code = ? WHERE id = ?',
    variables: [Variable<String>(qr), Variable<String>(id)],
  );

  setUp(() async {
    env = TestEnv();
    cycles = CycleService(env.db, env.writer);
    dues = DuesService(env.db, env.writer);
    scanner = ScanService(env.db, env.writer, cycles, dues);

    await env.subject();
    await env.teacher(id: 't1');
    await setQr('teachers', 't1', teacherQr);
    await env.room(id: 'r1');
    await env.group(id: 'g1', teacherId: 't1', roomId: 'r1');
    await env.slot(id: 'sl1', weekday: 6); // السبت 10:00–11:30
    await env.student(id: 's1');
    await setQr('students', 's1', studentQr);
    await env.enroll(id: 'gs1', studentId: 's1');
    await env.student(id: 's2');
    await setQr('students', 's2', student2Qr);
    await env.db
        .into(env.db.workers)
        .insert(
          WorkersCompanion.insert(
            id: 'w1',
            createdAt: 1,
            updatedAt: 1,
            name: 'سمير',
            phone: '0660000000',
            email: '0660000000@school.local',
            qrCode: workerQr,
            expectedStartMinutes: const Value(480), // 08:00
          ),
        );
    await scanner.loadIndex();
  });

  tearDown(() => env.close());

  Future<List<AttendanceRow>> attendance() =>
      env.db.select(env.db.attendance).get();

  group('الفهرس والرموز', () {
    test('الفهرس يحمّل كل الرموز في الذاكرة', () {
      expect(scanner.indexSize, 4);
    });

    test('رمز ليس من رموز المدرسة أو غير مسجَّل', () async {
      for (final raw in ['hello', 'S-ZZZZZZZZZZ', '', 'X-AAAAAAAAAA']) {
        final result = await scanner.scan(raw, now: at(10, 0));
        expect(result.outcome, ScanOutcome.unknown);
        expect(result.owner, isNull);
      }
    });

    test('صاحب محذوف لا يدخل الفهرس', () async {
      await env.writer.softDelete(env.db.students, key: const {'id': 's1'});
      await scanner.loadIndex();
      final result = await scanner.scan(studentQr, now: at(10, 0));
      expect(result.outcome, ScanOutcome.unknown);
    });

    test('الرمز يُقبل بحروف صغيرة ومسافات', () async {
      final result = await scanner.scan(' s-aaaaaaaaaa ', now: at(10, 0));
      expect(result.owner?.id, 's1');
    });
  });

  group('التلميذ', () {
    test('حصة الآن: تُنشأ تلقائياً ويُسجَّل حضوره (أخضر)', () async {
      final result = await scanner.scan(studentQr, now: at(9, 55));
      expect(result.outcome, ScanOutcome.studentOk);
      expect(result.owner?.name, 'تلميذ s1');
      expect(result.subjectName, 'رياضيات');
      expect(result.groupNumber, 1);
      expect(result.roomName, 'القاعة r1');
      expect(result.sessionCreated, isTrue);

      final session = await env.db.select(env.db.sessions).getSingle();
      expect(session.date, '2026-11-14');
      expect(session.startMinutes, 600);
      expect(session.status, 'normal');
      expect(session.sessionNumber, 1);

      final row = (await attendance()).single;
      expect(row.status, 'present');
      expect(row.method, 'qr');
      expect(row.scannedAt, isNotNull);
      expect(row.sessionId, session.id);
    });

    test('حصة مبرمجة مسبقاً تُستعمل ولا تُنشأ أخرى', () async {
      await cycles.topUp('g1', fromDate: '2026-11-14');
      final before = (await env.db.select(env.db.sessions).get()).length;
      final result = await scanner.scan(studentQr, now: at(10, 20));
      expect(result.outcome, ScanOutcome.studentOk);
      expect(result.sessionCreated, isFalse);
      expect(await env.db.select(env.db.sessions).get(), hasLength(before));
    });

    test('المسح المكرر لا يُسجَّل مرتين', () async {
      await scanner.scan(studentQr, now: at(9, 55));
      final soon = await scanner.scan(studentQr, now: at(9, 55, second: 5));
      expect(soon.outcome, ScanOutcome.repeated, reason: 'قراءة مزدوجة');
      final later = await scanner.scan(studentQr, now: at(10, 30));
      expect(later.outcome, ScanOutcome.studentAlreadyPresent);
      expect(await attendance(), hasLength(1));
    });

    test('هامش المسح: 30 دقيقة قبل البداية وحتى نهاية الحصة', () async {
      Future<ScanOutcome> outcomeAt(DateTime now) async {
        final fresh = ScanService(env.db, env.writer, cycles, dues);
        await fresh.loadIndex();
        return (await fresh.scan(studentQr, now: now)).outcome;
      }

      expect(await outcomeAt(at(9, 29)), ScanOutcome.studentNoSession);
      expect(await outcomeAt(at(11, 31)), ScanOutcome.studentNoSession);
      expect(await attendance(), isEmpty, reason: 'لا يُسجَّل شيء دون حصة');
      expect(await env.db.select(env.db.sessions).get(), isEmpty);
      expect(await outcomeAt(at(9, 30)), ScanOutcome.studentOk);
    });

    test('الهامش قابل للضبط', () async {
      final strict = ScanService(
        env.db,
        env.writer,
        cycles,
        dues,
        config: const ScanConfig(marginMinutes: 10),
      );
      await strict.loadIndex();
      expect(
        (await strict.scan(studentQr, now: at(9, 40))).outcome,
        ScanOutcome.studentNoSession,
      );
      expect(
        (await strict.scan(studentQr, now: at(9, 50, second: 30))).outcome,
        ScanOutcome.studentOk,
      );
    });

    test('لا حصة له الآن: يوم آخر أو تلميذ بلا مجموعة (أحمر)', () async {
      final wrongDay = await scanner.scan(studentQr, now: at(10, 0, day: 15));
      expect(wrongDay.outcome, ScanOutcome.studentNoSession);
      expect(wrongDay.owner?.id, 's1');

      final noGroup = await scanner.scan(student2Qr, now: at(10, 0));
      expect(noGroup.outcome, ScanOutcome.studentNoSession);
      expect(await attendance(), isEmpty);
    });

    test('الحصة الملغاة ليست حصة', () async {
      await cycles.topUp('g1', fromDate: '2026-11-14');
      final first = (await cycles.cycleSessions('g1', 1)).first;
      await cycles.cancelSession(first.id);
      final result = await scanner.scan(studentQr, now: at(10, 0));
      expect(result.outcome, ScanOutcome.studentNoSession);
      expect(await attendance(), isEmpty);
    });

    test('من غادر المجموعة لا حصة له', () async {
      await (env.db.update(env.db.groupStudents)
            ..where((gs) => gs.id.equals('gs1')))
          .write(const GroupStudentsCompanion(leftAt: Value(5)));
      final result = await scanner.scan(studentQr, now: at(10, 0));
      expect(result.outcome, ScanOutcome.studentNoSession);
    });

    test('عليه مستحقات: يدخل ويُسجَّل حضوره مع التنبيه (برتقالي)', () async {
      // دورة سابقة غير مسدَّدة.
      await (env.db.update(env.db.groups)..where((g) => g.id.equals('g1')))
          .write(const GroupsCompanion(currentCycleNumber: Value(2)));
      final result = await scanner.scan(studentQr, now: at(10, 0));
      expect(result.outcome, ScanOutcome.studentDues);
      expect((await attendance()).single.status, 'present');
    });

    test('من سدّد ليس عليه تنبيه', () async {
      await (env.db.update(env.db.groups)..where((g) => g.id.equals('g1')))
          .write(const GroupsCompanion(currentCycleNumber: Value(2)));
      for (final cycle in [1, 2]) {
        await dues.recordMonthPayment(
          studentId: 's1',
          groupId: 'g1',
          cycleNumber: cycle,
          amount: 2000,
          receivedBy: 'u1',
          receiptNumber: 'A-00000$cycle',
        );
      }
      final result = await scanner.scan(studentQr, now: at(10, 0));
      expect(result.outcome, ScanOutcome.studentOk);
    });

    test('مسح من سُجّل غائباً برخصة يصحّحه إلى حاضر ويلغي رصيده', () async {
      await cycles.topUp('g1', fromDate: '2026-11-14');
      final session = (await cycles.cycleSessions('g1', 1)).first;
      await env.db
          .into(env.db.attendance)
          .insert(
            AttendanceCompanion.insert(
              id: 'a1',
              createdAt: 1,
              updatedAt: 1,
              sessionId: session.id,
              studentId: 's1',
              status: 'excused',
              method: 'manual',
            ),
          );
      await dues.syncExcusedCredit(sessionId: session.id, studentId: 's1');
      expect(await env.db.select(env.db.studentCredits).get(), hasLength(1));

      final result = await scanner.scan(studentQr, now: at(10, 5));
      expect(result.outcome, ScanOutcome.studentOk);
      final row = (await attendance()).single;
      expect(row.status, 'present');
      expect(row.method, 'qr');
      final credit = await env.db.select(env.db.studentCredits).getSingle();
      expect(credit.deletedAt, isNotNull);
    });

    test('تلميذ في مجموعتين: يُختار الأقرب بداية', () async {
      await env.teacher(id: 't2');
      await env.group(id: 'g2', teacherId: 't2');
      await env.slot(
        id: 'sl2',
        groupId: 'g2',
        weekday: 6,
        start: 690,
        end: 780,
      );
      await env.enroll(id: 'gs2', groupId: 'g2', studentId: 's1');

      final early = await scanner.scan(studentQr, now: at(9, 50));
      expect((await env.db.select(env.db.sessions).getSingle()).groupId, 'g1');
      expect(early.outcome, ScanOutcome.studentOk);

      final second = await scanner.scan(studentQr, now: at(11, 25));
      expect(second.outcome, ScanOutcome.studentOk);
      final groups = (await env.db.select(env.db.sessions).get())
          .map((s) => s.groupId)
          .toSet();
      expect(groups, {'g1', 'g2'});
      expect(await attendance(), hasLength(2));
    });
  });

  group('الأستاذ', () {
    test('دخول لحصته في الوقت: لا تأخر', () async {
      final result = await scanner.scan(teacherQr, now: at(9, 50));
      expect(result.outcome, ScanOutcome.teacherIn);
      expect(result.owner?.name, 'الأستاذ t1');
      expect(result.groupNumber, 1);
      expect(result.roomName, 'القاعة r1');
      expect(result.lateMinutes, 0);
      expect(result.sessionCreated, isTrue);

      final row = await env.db.select(env.db.teacherAttendance).getSingle();
      expect(row.sessionId, result.sessionId);
      expect(row.checkIn, isNotNull);
      expect(row.checkOut, isNull);
      expect(row.date, '2026-11-14');
    });

    test('التأخر يُحسب عن بداية الحصة بعد مهلة السماح', () async {
      Future<int> lateAt(DateTime now) async {
        final env2 = ScanService(env.db, env.writer, cycles, dues);
        await env2.loadIndex();
        await env.db.delete(env.db.teacherAttendance).go();
        return (await env2.scan(teacherQr, now: now)).lateMinutes;
      }

      expect(await lateAt(at(10, 5)), 0, reason: 'داخل مهلة 5 دقائق');
      expect(await lateAt(at(10, 6)), 6);
      expect(await lateAt(at(10, 20)), 20);
    });

    test('المسح الثاني خروج', () async {
      await scanner.scan(teacherQr, now: at(9, 50));
      final out = await scanner.scan(teacherQr, now: at(11, 35));
      expect(out.outcome, ScanOutcome.teacherOut);
      expect(out.groupNumber, 1);
      final row = await env.db.select(env.db.teacherAttendance).getSingle();
      expect(row.checkOut, isNotNull);
      expect(row.checkOut! > row.checkIn!, isTrue);
    });

    test('لا حصة له الآن: حضور عام مع تنبيه، ثم خروج', () async {
      final result = await scanner.scan(teacherQr, now: at(15, 0));
      expect(result.outcome, ScanOutcome.teacherGeneralIn);
      expect(result.sessionId, isNull);
      final row = await env.db.select(env.db.teacherAttendance).getSingle();
      expect(row.sessionId, isNull);
      expect(await env.db.select(env.db.sessions).get(), isEmpty);

      final out = await scanner.scan(teacherQr, now: at(16, 0));
      expect(out.outcome, ScanOutcome.teacherOut);
      expect(await env.db.select(env.db.teacherAttendance).get(), hasLength(1));
    });

    test('حصتان في اليوم: دخول وخروج لكل حصة', () async {
      await env.group(id: 'g2', teacherId: 't1');
      await env.slot(
        id: 'sl2',
        groupId: 'g2',
        weekday: 6,
        start: 840,
        end: 930,
      );

      expect(
        (await scanner.scan(teacherQr, now: at(9, 55))).outcome,
        ScanOutcome.teacherIn,
      );
      expect(
        (await scanner.scan(teacherQr, now: at(11, 30))).outcome,
        ScanOutcome.teacherOut,
      );
      final second = await scanner.scan(teacherQr, now: at(13, 50));
      expect(second.outcome, ScanOutcome.teacherIn);
      expect(
        (await scanner.scan(teacherQr, now: at(15, 30))).outcome,
        ScanOutcome.teacherOut,
      );
      final rows = await env.db.select(env.db.teacherAttendance).get();
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.sessionId).toSet(), hasLength(2));
      expect(rows.every((r) => r.checkOut != null), isTrue);
    });

    test('الأستاذ والتلميذ يتشاركان نفس الحصة المنشأة تلقائياً', () async {
      final teacher = await scanner.scan(teacherQr, now: at(9, 50));
      final student = await scanner.scan(studentQr, now: at(9, 58));
      expect(student.sessionId, teacher.sessionId);
      expect(student.sessionCreated, isFalse);
      expect(await env.db.select(env.db.sessions).get(), hasLength(1));
    });
  });

  group('العامل', () {
    test('أول مسح دخول مع حساب التأخر، والثاني خروج', () async {
      final inScan = await scanner.scan(workerQr, now: at(8, 20));
      expect(inScan.outcome, ScanOutcome.workerIn);
      expect(inScan.owner?.name, 'سمير');
      expect(inScan.lateMinutes, 20);

      final out = await scanner.scan(workerQr, now: at(17, 0));
      expect(out.outcome, ScanOutcome.workerOut);

      final row = await env.db.select(env.db.workerAttendance).getSingle();
      expect(row.date, '2026-11-14');
      expect(row.lateMinutes, 20);
      expect(row.checkIn, isNotNull);
      expect(row.checkOut, isNotNull);
    });

    test('داخل مهلة السماح أو قبل الوقت: لا تأخر', () async {
      expect((await scanner.scan(workerQr, now: at(8, 4))).lateMinutes, 0);
      final early = await scanner.scan(workerQr, now: at(7, 30, day: 15));
      expect(early.outcome, ScanOutcome.workerIn);
      expect(early.lateMinutes, 0);
    });

    test('مسح ثالث يحدّث وقت الخروج ولا ينشئ سجلاً جديداً', () async {
      await scanner.scan(workerQr, now: at(8, 0));
      await scanner.scan(workerQr, now: at(12, 0));
      final first =
          (await env.db.select(env.db.workerAttendance).getSingle()).checkOut;
      final third = await scanner.scan(workerQr, now: at(17, 0));
      expect(third.outcome, ScanOutcome.workerOut);
      final rows = await env.db.select(env.db.workerAttendance).get();
      expect(rows, hasLength(1));
      expect(rows.single.checkOut! > first!, isTrue);
    });

    test('يوم جديد سجل جديد', () async {
      await scanner.scan(workerQr, now: at(8, 0));
      final next = await scanner.scan(workerQr, now: at(8, 0, day: 15));
      expect(next.outcome, ScanOutcome.workerIn);
      expect(await env.db.select(env.db.workerAttendance).get(), hasLength(2));
    });

    test('يوم عدّله المدير دون مسح: المسح الأول يبقى دخولاً', () async {
      await WageService(
        env.db,
        env.writer,
      ).setOverride(workerId: 'w1', date: '2026-11-14', kind: WorkDayKind.full);
      final result = await scanner.scan(workerQr, now: at(8, 0));
      expect(result.outcome, ScanOutcome.workerIn);
      final row = await env.db.select(env.db.workerAttendance).getSingle();
      expect(row.checkIn, isNotNull);
      expect(row.overrideKind, 'full');
    });
  });

  test('كل مسح يدخل طابور المزامنة', () async {
    await scanner.scan(studentQr, now: at(10, 0));
    await scanner.scan(workerQr, now: at(10, 0));
    final tables = (await env.db.select(env.db.outbox).get())
        .map((o) => o.targetTable)
        .toSet();
    expect(
      tables,
      containsAll(['attendance', 'sessions', 'worker_attendance']),
    );
  });
}
