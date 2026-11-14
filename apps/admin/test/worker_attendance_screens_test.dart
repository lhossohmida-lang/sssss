import 'package:admin/admin_tabs.dart';
import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

const _owner = TestAccount(
  id: 'u-owner',
  email: 'owner@school.local',
  password: 'owner-pass-1',
  role: UserRole.owner,
  displayName: 'المدير',
);

const _viewer = TestAccount(
  id: 'u-wv',
  email: 'wv@school.local',
  password: 'wv-pass-1',
  role: UserRole.worker,
  entityId: 'w9',
  displayName: 'عامل',
  permissions: '{"workers":["view"]}',
);

const _expenseRecorder = TestAccount(
  id: 'u-expense-recorder',
  email: 'expense-recorder@school.local',
  password: 'expense-recorder-pass-1',
  role: UserRole.worker,
  entityId: 'w9',
  displayName: 'مسجّل الأجور',
  permissions: '{"workers":["view"],"expenses":["add"]}',
);

/// كل أيام الأسبوع يوم كامل: أجر الشهر يتبع الحضور وتعديلاته فقط.
const _allDays =
    '{"1":"full","2":"full","3":"full","4":"full","5":"full",'
    '"6":"full","7":"full"}';

/// يبذر عاملاً حضر أول الشهر الجاري ثم يفتح «حضور العمال».
Future<AppRuntime> openSheet(
  WidgetTester tester, {
  TestAccount account = _owner,
  bool withWorker = true,
}) async {
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: [account],
    pages: adminPages,
  );
  await loginWith(tester, account.email, account.password);
  if (withWorker) {
    final db = runtime.db;
    await runDb(tester, () async {
      await db
          .into(db.workers)
          .insert(
            WorkersCompanion.insert(
              id: 'w1',
              createdAt: 1,
              updatedAt: 1,
              name: 'سمير',
              phone: '0660000000',
              email: '0660000000@school.local',
              qrCode: 'W-AAAAAAAAAA',
              fullDayWage: const Value(1000),
              halfDayWage: const Value(600),
              weeklySchedule: const Value(_allDays),
            ),
          );
      await db
          .into(db.workerAttendance)
          .insert(
            WorkerAttendanceCompanion.insert(
              id: 'wa-1',
              createdAt: 1,
              updatedAt: 1,
              workerId: 'w1',
              date: '${currentMonthKey()}-01',
              checkIn: Value(
                DateTime(2026, 1, 1, 8, 10).toUtc().millisecondsSinceEpoch,
              ),
              checkOut: Value(
                DateTime(2026, 1, 1, 17).toUtc().millisecondsSinceEpoch,
              ),
              lateMinutes: const Value(10),
            ),
          );
    });
  }
  await openMoreEntry(tester, 'حضور العمال');
  return runtime;
}

/// ينتظر وصول تحديث القاعدة إلى الشاشة (الاستعلامات اللحظية في زمن حقيقي).
Future<void> settleDb(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

/// يُعيد حساب الكشف من القاعدة (لا يصلنا إشعار الاستعلام اللحظي داخل منطقة
/// الاختبار الوهمية، وهو يعمل في التطبيق الحقيقي).
Future<void> reopenWorker(WidgetTester tester) async {
  ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
      .invalidate(workerSheetProvider);
  await settleDb(tester);
}

Future<void> openWorker(WidgetTester tester) async {
  await tester.tap(find.text('سمير'));
  await tester.pumpAndSettle();
}

void main() {
  appTest('لا عمال: رسالة فارغة', (tester) async {
    await openSheet(tester, withWorker: false);
    expect(find.text('لا يوجد عمال'), findsOneWidget);
    expect(find.text(DateKey.monthLabel(currentMonthKey())), findsOneWidget);
  });

  appTest('الكشف الجامع: أيام العامل وأجره وتأخره وإجمالي الشهر', (
    tester,
  ) async {
    await openSheet(tester);
    final today = DateTime.now().day;
    expect(find.text('سمير'), findsOneWidget);
    expect(
      find.textContaining('1 يوم كامل · 0 نصف · ${today - 1} غياب'),
      findsOneWidget,
    );
    expect(find.textContaining('تأخر 10 د'), findsOneWidget);
    expect(find.text('إجمالي أجور الشهر'), findsOneWidget);
    expect(find.text(Money.format(1000)), findsNWidgets(2));
  });

  appTest('صلاحية إضافة المصاريف تسجل أجر العامل كمصروف', (tester) async {
    final runtime = await openSheet(tester, account: _expenseRecorder);
    final workerRow = find.ancestor(
      of: find.text('سمير').first,
      matching: find.byType(ClayListTile),
    );
    await tester.tap(
      find.descendant(
        of: workerRow,
        matching: find.byTooltip('تسجيل الأجر كمصروف'),
      ),
    );
    await settleDb(tester);

    final rows = await runDb(
      tester,
      () => runtime.db.select(runtime.db.expenses).get(),
    );
    final categories = await runDb(
      tester,
      () => runtime.db.select(runtime.db.expenseCategories).get(),
    );
    final now = DateTime.now();
    final monthEnd = DateTime(now.year, now.month + 1, 0).day;
    expect(rows, hasLength(1));
    expect(rows.single.amount, 1000);
    expect(rows.single.workerId, 'w1');
    expect(
      rows.single.date,
      '${currentMonthKey()}-${monthEnd.toString().padLeft(2, '0')}',
    );
    expect(rows.single.createdBy, _expenseRecorder.id);
    expect(categories.single.isWages, isTrue);
    expect(
      find.descendant(
        of: workerRow,
        matching: find.byTooltip('الأجر مسجّل كمصروف'),
      ),
      findsOneWidget,
    );
  });

  appTest('كشف العامل اليومي: يوم الحضور بساعاته وتأخره وأجره', (tester) async {
    await openSheet(tester);
    await openWorker(tester);
    expect(
      find.textContaining('أجر الشهر ${Money.format(1000)}'),
      findsOneWidget,
    );
    expect(find.textContaining('حضر 08:10–17:00 · تأخر 10 د'), findsOneWidget);
    expect(find.text('يوم كامل'), findsWidgets);
  });

  appTest('تعديل يدوي: نصف يوم ثم إلغاؤه', (tester) async {
    final runtime = await openSheet(tester);
    await openWorker(tester);
    // اليوم الثاني من الشهر (لم يحضره): نصف يوم.
    await tester.tap(
      find.textContaining('2 ${DateKey.monthName(DateTime.now().month)}'),
    );
    await tester.pumpAndSettle();
    expect(find.text('تعديل يوم ${currentMonthKey()}-02'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'نصف يوم'));
    await tester.pumpAndSettle();
    await settleDb(tester);
    final row = await runDb(
      tester,
      () => (runtime.db.select(
        runtime.db.workerAttendance,
      )..where((a) => a.date.equals('${currentMonthKey()}-02'))).getSingle(),
    );
    expect(row.overrideKind, 'half');
    await reopenWorker(tester);
    expect(find.textContaining('(معدَّل)'), findsOneWidget);
    expect(
      find.textContaining('أجر الشهر ${Money.format(1600)}'),
      findsOneWidget,
    );

    await tester.tap(find.textContaining('(معدَّل)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'إلغاء التعديل'));
    await tester.pumpAndSettle();
    await settleDb(tester);
    await reopenWorker(tester);
    expect(find.textContaining('(معدَّل)'), findsNothing);
    expect(
      find.textContaining('أجر الشهر ${Money.format(1000)}'),
      findsOneWidget,
    );
  });

  appTest('تعديل يوم الحضور إلى غائب يلغي أجره', (tester) async {
    await openSheet(tester);
    await openWorker(tester);
    await tester.tap(find.textContaining('حضر 08:10'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'غائب (بلا أجر)'));
    await tester.pumpAndSettle();
    await settleDb(tester);
    await reopenWorker(tester);
    expect(find.textContaining('أجر الشهر ${Money.format(0)}'), findsOneWidget);
  });

  appTest('إغلاق نافذة التعديل لا يغيّر شيئاً', (tester) async {
    final runtime = await openSheet(tester);
    await openWorker(tester);
    await tester.tap(find.textContaining('حضر 08:10'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'إغلاق'));
    await tester.pumpAndSettle();
    final rows = await runDb(
      tester,
      () => runtime.db.select(runtime.db.workerAttendance).get(),
    );
    expect(rows.single.overrideKind, isNull);
  });

  appTest('التنقل بين الأشهر: الشهر التالي بلا حضور', (tester) async {
    await openSheet(tester);
    await tester.tap(find.byTooltip('الشهر التالي'));
    await tester.pumpAndSettle();
    final next = DateKey.shiftMonth(currentMonthKey(), 1);
    expect(find.text(DateKey.monthLabel(next)), findsOneWidget);
    expect(find.textContaining('0 يوم كامل · 0 نصف · 0 غياب'), findsOneWidget);
    await tester.tap(find.byTooltip('الشهر السابق'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 يوم كامل'), findsOneWidget);
  });

  appTest('صلاحية العرض فقط: الأيام بلا نافذة تعديل', (tester) async {
    await openSheet(tester, account: _viewer);
    expect(find.byTooltip('تسجيل الأجر كمصروف'), findsNothing);
    await openWorker(tester);
    await tester.tap(find.textContaining('حضر 08:10'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تعديل يوم'), findsNothing);
  });
}
