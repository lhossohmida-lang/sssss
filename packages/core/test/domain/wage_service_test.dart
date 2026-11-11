import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late WageService wages;

  // نوفمبر 2026: 1 أحد، 2 اثنين، 3 ثلاثاء، 7 سبت، 14 سبت.
  // البرنامج: الاثنين والثلاثاء يوم كامل، السبت نصف يوم.
  const schedule = '{"1": "full", "2": "full", "6": "half"}';

  setUp(() async {
    env = TestEnv();
    wages = WageService(env.db, env.writer);
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
            qrCode: 'W-AAAAAAAAAA',
            fullDayWage: const Value(2000),
            halfDayWage: const Value(1200),
            weeklySchedule: const Value(schedule),
          ),
        );
  });

  tearDown(() => env.close());

  Future<void> scan(String date, {int late = 0, bool out = true}) => env.db
      .into(env.db.workerAttendance)
      .insert(
        WorkerAttendanceCompanion.insert(
          id: 'wa-$date',
          createdAt: 1,
          updatedAt: 1,
          workerId: 'w1',
          date: date,
          checkIn: const Value(100),
          checkOut: Value(out ? 200 : null),
          lateMinutes: Value(late),
        ),
      );

  WorkerDay day(WorkerMonth month, String date) =>
      month.days.firstWhere((d) => d.date == date);

  group('القواعد', () {
    test('برنامج العمل يُقرأ ويُكتب', () {
      final s = WorkerSchedule.fromJson(schedule);
      expect(s.kindOn(1), WorkDayKind.full);
      expect(s.kindOn(6), WorkDayKind.half);
      expect(s.kindOn(5), WorkDayKind.off);
      expect(WorkerSchedule.fromJson(s.toJson()).kindOn(6), WorkDayKind.half);
      expect(WorkerSchedule.fromJson('').kindOn(1), WorkDayKind.off);
      expect(WorkerSchedule.fromJson('{}').kindOn(1), WorkDayKind.off);
      expect(() => WorkerSchedule.fromJson('[]'), throwsFormatException);
      expect(
        () => WorkerSchedule.fromJson('{"9": "full"}'),
        throwsFormatException,
      );
      expect(
        () => WorkerSchedule.fromJson('{"1": "double"}'),
        throwsArgumentError,
      );
    });

    test('ما يُدفع عن اليوم', () {
      WorkDayKind paid(WorkDayKind s, bool present, [WorkDayKind? o]) =>
          WageRules.paidKind(scheduled: s, present: present, override: o);
      expect(paid(WorkDayKind.full, true), WorkDayKind.full);
      expect(paid(WorkDayKind.half, true), WorkDayKind.half);
      expect(paid(WorkDayKind.full, false), WorkDayKind.off);
      expect(paid(WorkDayKind.off, true), WorkDayKind.off);
      expect(paid(WorkDayKind.full, false, WorkDayKind.full), WorkDayKind.full);
      expect(paid(WorkDayKind.full, true, WorkDayKind.half), WorkDayKind.half);
      expect(paid(WorkDayKind.full, true, WorkDayKind.off), WorkDayKind.off);
    });

    test('أجر اليوم الكامل ونصف اليوم مبلغان مستقلان', () {
      int wage(WorkDayKind k) =>
          WageRules.wageFor(k, fullDayWage: 2000, halfDayWage: 1200);
      expect(wage(WorkDayKind.full), 2000);
      expect(wage(WorkDayKind.half), 1200);
      expect(wage(WorkDayKind.off), 0);
    });
  });

  test('من حضر يأخذ أجر يومه حسب برنامجه، ومن غاب لا يأخذ شيئاً', () async {
    await scan('2026-11-02'); // اثنين: كامل
    await scan('2026-11-07'); // سبت: نصف
    // الثلاثاء 3 نوفمبر: غائب

    final month = await wages.month('w1', '2026-11');
    expect(month.days, hasLength(30));
    expect(day(month, '2026-11-02').wage, 2000);
    expect(day(month, '2026-11-07').wage, 1200);
    expect(day(month, '2026-11-03').wage, 0);
    expect(day(month, '2026-11-03').isAbsence, isTrue);
    expect(day(month, '2026-11-01').isAbsence, isFalse, reason: 'ليس يوم عمل');
    expect(month.total, 3200);
    expect(month.fullDays, 1);
    expect(month.halfDays, 1);
  });

  test('التأخر لا يخصم من الأجر ويظهر للعرض فقط', () async {
    await scan('2026-11-02', late: 45);
    final month = await wages.month('w1', '2026-11');
    expect(day(month, '2026-11-02').wage, 2000);
    expect(day(month, '2026-11-02').lateMinutes, 45);
    expect(month.totalLateMinutes, 45);
  });

  test('من نسي مسح الخروج يُحسب له يومه', () async {
    await scan('2026-11-02', out: false);
    final month = await wages.month('w1', '2026-11');
    expect(day(month, '2026-11-02').wage, 2000);
    expect(day(month, '2026-11-02').checkOut, isNull);
  });

  test('الحضور في يوم ليس من البرنامج لا أجر له إلا بتعديل المدير', () async {
    await scan('2026-11-01'); // أحد: لا يعمل
    var month = await wages.month('w1', '2026-11');
    expect(day(month, '2026-11-01').wage, 0);

    await wages.setOverride(
      workerId: 'w1',
      date: '2026-11-01',
      kind: WorkDayKind.half,
    );
    month = await wages.month('w1', '2026-11');
    expect(day(month, '2026-11-01').wage, 1200);
    expect(day(month, '2026-11-01').overridden, isTrue);
  });

  test(
    'تعديل المدير: احتساب يوم غياب، أو إلغاء يوم حضور، ثم التراجع',
    () async {
      await wages.setOverride(
        workerId: 'w1',
        date: '2026-11-03',
        kind: WorkDayKind.full,
      );
      await scan('2026-11-02');
      await wages.setOverride(
        workerId: 'w1',
        date: '2026-11-02',
        kind: WorkDayKind.off,
      );

      var month = await wages.month('w1', '2026-11');
      expect(day(month, '2026-11-03').wage, 2000);
      expect(day(month, '2026-11-03').isAbsence, isFalse);
      expect(day(month, '2026-11-02').wage, 0);
      expect(month.total, 2000);

      await wages.setOverride(workerId: 'w1', date: '2026-11-02', kind: null);
      await wages.setOverride(workerId: 'w1', date: '2026-11-03', kind: null);
      month = await wages.month('w1', '2026-11');
      expect(day(month, '2026-11-02').wage, 2000);
      expect(day(month, '2026-11-03').wage, 0);
      expect(day(month, '2026-11-03').isAbsence, isTrue);
    },
  );

  test('إلغاء تعديل غير موجود لا يفعل شيئاً', () async {
    await wages.setOverride(workerId: 'w1', date: '2026-11-20', kind: null);
    expect(await env.db.select(env.db.workerAttendance).get(), isEmpty);
  });

  test('الغيابات تُعدّ حتى اليوم فقط', () async {
    final month = await wages.month('w1', '2026-11');
    // حتى 8 نوفمبر: الاثنين 2، الثلاثاء 3، السبت 7.
    expect(month.absencesUntil('2026-11-08'), 3);
    expect(month.absencesUntil('2026-11-01'), 0);
  });

  test('الشهر يُحصر بأيامه: فبراير في سنة كبيسة 29 يوماً', () async {
    await scan('2028-03-06'); // خارج فبراير
    final month = await wages.month('w1', '2028-02');
    expect(month.days, hasLength(29));
    expect(month.days.last.date, '2028-02-29');
    expect(month.total, 0);
  });

  test('عامل بلا برنامج لا أجر له ولا غيابات', () async {
    await (env.db.update(env.db.workers)..where((w) => w.id.equals('w1')))
        .write(const WorkersCompanion(weeklySchedule: Value('{}')));
    await scan('2026-11-02');
    final month = await wages.month('w1', '2026-11');
    expect(month.total, 0);
    expect(month.absencesUntil('2026-11-30'), 0);
  });
}
