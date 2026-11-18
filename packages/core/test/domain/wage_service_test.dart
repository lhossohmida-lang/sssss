import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late WageService wages;

  // نوفمبر 2026: 2 و9 و16 أيام اثنين، و7 سبت. العمال بلا أيام محددة: يُحسب اليوم من مدة بقاء
  // العامل (الافتراضي: نصف يوم من 4 ساعات، ويوم كامل من 8 ساعات).

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
          ),
        );
  });

  tearDown(() => env.close());

  int at(String date, int hour, [int minute = 0]) {
    final h = '$hour'.padLeft(2, '0');
    final m = '$minute'.padLeft(2, '0');
    return DateTime.parse('${date}T$h:$m:00').toUtc().millisecondsSinceEpoch;
  }

  /// يدخل العامل الساعة [from] ويخرج الساعة [to] (بلا خروج إن كان `null`).
  Future<void> scan(
    String date, {
    int late = 0,
    int from = 8,
    int? to = 16,
    int toMinute = 30,
  }) => env.db
      .into(env.db.workerAttendance)
      .insert(
        WorkerAttendanceCompanion.insert(
          id: 'wa-$date',
          createdAt: 1,
          updatedAt: 1,
          workerId: 'w1',
          date: date,
          checkIn: Value(at(date, from)),
          checkOut: Value(to == null ? null : at(date, to, toMinute)),
          lateMinutes: Value(late),
        ),
      );

  WorkerDay day(WorkerMonth month, String date) =>
      month.days.firstWhere((d) => d.date == date);

  group('القواعد', () {
    test('مدة العمل من الدخول والخروج', () {
      expect(WageRules.workedMinutes(null, 5), isNull);
      expect(WageRules.workedMinutes(5, null), isNull);
      expect(WageRules.workedMinutes(0, 90 * 60000), 90);
      expect(WageRules.workedMinutes(10 * 60000, 0), 0, reason: 'لا مدة سالبة');
    });

    test('نوع اليوم من المدة: نصف يوم من حدّه، ويوم كامل من حدّه', () {
      WorkDayKind kind(int minutes) => WageRules.kindForMinutes(
        minutes,
        halfDayMinutes: 240,
        fullDayMinutes: 480,
      );
      expect(kind(0), WorkDayKind.off);
      expect(kind(239), WorkDayKind.off);
      expect(kind(240), WorkDayKind.half);
      expect(kind(479), WorkDayKind.half);
      expect(kind(480), WorkDayKind.full);
      expect(kind(900), WorkDayKind.full);
    });

    test('ما يُدفع عن اليوم: المدة تحسمه وتعديل المدير يغلبها', () {
      WorkDayKind paid(int? minutes, [WorkDayKind? o]) => WageRules.paidKind(
        workedMinutes: minutes,
        halfDayMinutes: 240,
        fullDayMinutes: 480,
        override: o,
      );
      expect(paid(500), WorkDayKind.full);
      expect(paid(300), WorkDayKind.half);
      expect(paid(100), WorkDayKind.off);
      expect(paid(null), WorkDayKind.off, reason: 'لم يمسح خروجه');
      expect(paid(null, WorkDayKind.full), WorkDayKind.full);
      expect(paid(500, WorkDayKind.half), WorkDayKind.half);
      expect(paid(500, WorkDayKind.off), WorkDayKind.off);
    });

    test('أجر اليوم الكامل ونصف اليوم مبلغان مستقلان', () {
      int wage(WorkDayKind k) =>
          WageRules.wageFor(k, fullDayWage: 2000, halfDayWage: 1200);
      expect(wage(WorkDayKind.full), 2000);
      expect(wage(WorkDayKind.half), 1200);
      expect(wage(WorkDayKind.off), 0);
    });

    test('مدة اليوم بالعربية', () {
      expect(DateKey.durationText(45), '45 دقيقة');
      expect(DateKey.durationText(60), 'ساعة');
      expect(DateKey.durationText(120), 'ساعتان');
      expect(DateKey.durationText(240), '4 ساعات');
      expect(DateKey.durationText(150), 'ساعتان و30 دقيقة');
      expect(DateKey.durationText(11 * 60), '11 ساعة');
    });
  });

  test(
    'يوم العامل يُحسب من مدة بقائه: نصف يوم ثم يوم كامل ثم أقل من النصف',
    () async {
      await scan('2026-11-02', to: 12); // 4س30: نصف يوم
      await scan('2026-11-09'); // 8س30: يوم كامل
      await scan('2026-11-16', to: 10, toMinute: 0); // ساعتان: دون النصف

      final month = await wages.month('w1', '2026-11');
      expect(month.days, hasLength(30));
      expect(day(month, '2026-11-02').paidKind, WorkDayKind.half);
      expect(day(month, '2026-11-02').wage, 1200);
      expect(day(month, '2026-11-02').workedMinutes, 270);
      expect(day(month, '2026-11-09').paidKind, WorkDayKind.full);
      expect(day(month, '2026-11-09').wage, 2000);
      expect(day(month, '2026-11-16').wage, 0);
      expect(day(month, '2026-11-16').isBelowHalf, isTrue);
      expect(month.total, 3200);
      expect(month.fullDays, 1);
      expect(month.halfDays, 1);
      expect(month.totalWorkedMinutes, 270 + 510 + 120);
    },
  );

  test('لا أيام محددة: يأتي العامل أي يوم، ومن لم يأتِ لا غياب عليه', () async {
    await scan('2026-11-06', to: 13); // جمعة: نصف يوم
    final month = await wages.month('w1', '2026-11');
    expect(day(month, '2026-11-06').wage, 1200);
    expect(day(month, '2026-11-03').present, isFalse);
    expect(day(month, '2026-11-03').wage, 0);
    expect(day(month, '2026-11-03').isOpen, isFalse);
  });

  test('حدّا نصف اليوم واليوم الكامل من الإعدادات', () async {
    await SettingsService(env.db, env.writer).save(
      const SchoolSettings(
        workerHalfDayMinutes: 120,
        workerFullDayMinutes: 300,
      ),
    );
    await scan('2026-11-02', to: 10, toMinute: 30); // ساعتان ونصف: نصف يوم
    await scan('2026-11-09', to: 13, toMinute: 30); // 5س30: يوم كامل

    final month = await wages.month('w1', '2026-11');
    expect(day(month, '2026-11-02').paidKind, WorkDayKind.half);
    expect(day(month, '2026-11-09').paidKind, WorkDayKind.full);
    expect(month.total, 3200);
  });

  test('التأخر لا يخصم من الأجر ويظهر للعرض فقط', () async {
    await scan('2026-11-02', late: 45);
    final month = await wages.month('w1', '2026-11');
    expect(day(month, '2026-11-02').wage, 2000);
    expect(day(month, '2026-11-02').lateMinutes, 45);
    expect(month.totalLateMinutes, 45);
  });

  test('من لم يمسح خروجه لا يُحسب يومه حتى يخرج أو يعدّله المدير', () async {
    await scan('2026-11-02', to: null);
    var month = await wages.month('w1', '2026-11');
    expect(day(month, '2026-11-02').wage, 0);
    expect(day(month, '2026-11-02').isOpen, isTrue);
    expect(day(month, '2026-11-02').checkOut, isNull);
    // اليوم نفسه قد يكون ما زال في عمله فلا يُعدّ نقصاً، وما قبله يُعدّ.
    expect(month.openDaysBefore('2026-11-02'), 0);
    expect(month.openDaysBefore('2026-11-03'), 1);

    await wages.setOverride(
      workerId: 'w1',
      date: '2026-11-02',
      kind: WorkDayKind.full,
    );
    month = await wages.month('w1', '2026-11');
    expect(day(month, '2026-11-02').wage, 2000);
    expect(day(month, '2026-11-02').isOpen, isFalse);
  });

  test(
    'تعديل المدير يغلب المدة: يوم دون النصف يصير كاملاً ثم التراجع',
    () async {
      await scan('2026-11-02', to: 9, toMinute: 0); // ساعة: لا شيء
      expect((await wages.month('w1', '2026-11')).total, 0);

      await wages.setOverride(
        workerId: 'w1',
        date: '2026-11-02',
        kind: WorkDayKind.full,
      );
      var month = await wages.month('w1', '2026-11');
      expect(day(month, '2026-11-02').wage, 2000);
      expect(day(month, '2026-11-02').overridden, isTrue);

      await wages.setOverride(workerId: 'w1', date: '2026-11-02', kind: null);
      month = await wages.month('w1', '2026-11');
      expect(day(month, '2026-11-02').wage, 0);
      expect(day(month, '2026-11-02').overridden, isFalse);
    },
  );

  test('يوم لم يحضره العامل يُحتسب بتعديل المدير وحده', () async {
    await wages.setOverride(
      workerId: 'w1',
      date: '2026-11-03',
      kind: WorkDayKind.half,
    );
    final month = await wages.month('w1', '2026-11');
    expect(day(month, '2026-11-03').wage, 1200);
    expect(day(month, '2026-11-03').present, isFalse);
  });

  test('إلغاء تعديل غير موجود لا يفعل شيئاً', () async {
    await wages.setOverride(workerId: 'w1', date: '2026-11-20', kind: null);
    expect(await env.db.select(env.db.workerAttendance).get(), isEmpty);
  });

  test('الشهر يُحصر بأيامه: فبراير في سنة كبيسة 29 يوماً', () async {
    await scan('2028-03-06'); // خارج فبراير
    final month = await wages.month('w1', '2028-02');
    expect(month.days, hasLength(29));
    expect(month.days.last.date, '2028-02-29');
    expect(month.total, 0);
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
      await scan('2026-11-02'); // يوم كامل
      await scan('2026-11-07', to: 12); // نصف يوم
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
