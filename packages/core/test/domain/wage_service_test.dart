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

  group('الكشف الجامع لكل العمال', () {
    Future<void> secondWorker() => env.db
        .into(env.db.workers)
        .insert(
          WorkersCompanion.insert(
            id: 'w0',
            createdAt: 1,
            updatedAt: 1,
            name: 'أمين',
            phone: '0660000001',
            email: '0660000001@school.local',
            qrCode: 'W-BBBBBBBBBB',
            fullDayWage: const Value(1000),
            weeklySchedule: const Value('{"2": "full"}'),
          ),
        );

    test('كل العمال مرتبون بالاسم بكشف الشهر لكل منهم', () async {
      await secondWorker();
      await scan('2026-11-02');
      final sheet = await wages.sheet('2026-11');
      expect(sheet.map((s) => s.name), ['أمين', 'سمير']);
      expect(sheet.first.month.total, 0);
      expect(sheet.last.month.total, 2000);
      expect(sheet.last.workerId, 'w1');
    });

    test('المحذوف لا يظهر', () async {
      await secondWorker();
      await env.db.customStatement(
        "UPDATE workers SET deleted_at = 9 WHERE id = 'w0'",
      );
      expect((await wages.sheet('2026-11')).map((s) => s.workerId), ['w1']);
    });

    test('watchSheet يتحدث بعد التعديل اليدوي', () async {
      final totals = <int>[];
      final sub = wages
          .watchSheet('2026-11')
          .listen((s) => totals.add(s.single.month.total));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await wages.setOverride(
        workerId: 'w1',
        date: '2026-11-03',
        kind: WorkDayKind.full,
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await sub.cancel();
      expect(totals.first, 0);
      expect(totals.last, 2000);
    });
  });

  group('تسجيل الأجور كمصروفات', () {
    test('مصروف ثابت للعامل والشهر، ويتحدث بعد تصحيح الحضور', () async {
      await scan('2026-11-02');
      await scan('2026-11-07');
      final id = await wages.recordAsExpense(workerId: 'w1', month: '2026-11');
      final categoryId = StableId.workerWagesCategory();
      final firstExpense = await env.db.select(env.db.expenses).getSingle();
      final category = await (env.db.select(
        env.db.expenseCategories,
      )..where((row) => row.id.equals(categoryId))).getSingle();

      expect(id, StableId.workerWageExpense('w1', '2026-11'));
      expect(firstExpense.id, id);
      expect(firstExpense.workerId, 'w1');
      expect(firstExpense.categoryId, categoryId);
      expect(firstExpense.amount, 3200);
      expect(firstExpense.date, '2026-11-30');
      expect(firstExpense.note, 'أجر شهر 2026-11');
      expect(firstExpense.createdBy, 'u1');
      expect(category.name, 'أجور العمال');
      expect(category.isWages, isTrue);

      final auditCount = await env.db.select(env.db.auditLog).get();
      expect(await wages.recordAsExpense(workerId: 'w1', month: '2026-11'), id);
      expect(await env.db.select(env.db.expenses).get(), hasLength(1));
      expect(
        await env.db.select(env.db.auditLog).get(),
        hasLength(auditCount.length),
      );

      await wages.setOverride(
        workerId: 'w1',
        date: '2026-11-07',
        kind: WorkDayKind.off,
      );
      await wages.recordAsExpense(workerId: 'w1', month: '2026-11');

      final updated = await env.db.select(env.db.expenses).getSingle();
      expect(updated.id, id);
      expect(updated.amount, 2000);
      expect(await env.db.select(env.db.expenses).get(), hasLength(1));
      final summary = (await wages.sheet('2026-11')).single;
      expect(summary.wageExpenseId, id);
      expect(summary.wageExpenseAmount, 2000);
      expect(summary.wageExpenseIsCurrent, isTrue);
    });

    test('الأجر الصفري والشهر غير الصحيح لا ينشئان مصروفاً', () async {
      await expectLater(
        wages.recordAsExpense(workerId: 'w1', month: '2026-11'),
        throwsStateError,
      );
      await expectLater(
        wages.recordAsExpense(workerId: 'w1', month: '2026-13'),
        throwsFormatException,
      );
      expect(await env.db.select(env.db.expenses).get(), isEmpty);
      expect(await env.db.select(env.db.expenseCategories).get(), isEmpty);
    });

    test('مصروف الأجر لا يمكن حذفه من شاشة المصاريف', () async {
      await scan('2026-11-02');
      final id = await wages.recordAsExpense(workerId: 'w1', month: '2026-11');

      await expectLater(
        ExpenseService(env.db, env.writer).deleteExpense(id),
        throwsStateError,
      );
      expect(
        (await env.db.select(env.db.expenses).getSingle()).deletedAt,
        isNull,
      );
    });
  });

  test('أسماء الأشهر والتنقل بينها', () {
    expect(DateKey.monthName(1), 'جانفي');
    expect(DateKey.monthName(12), 'ديسمبر');
    expect(DateKey.monthLabel('2026-11'), 'نوفمبر 2026');
    expect(DateKey.shiftMonth('2026-11', 1), '2026-12');
    expect(DateKey.shiftMonth('2026-12', 1), '2027-01');
    expect(DateKey.shiftMonth('2026-01', -1), '2025-12');
    expect(DateKey.shiftMonth('2026-03', 0), '2026-03');
  });
}
