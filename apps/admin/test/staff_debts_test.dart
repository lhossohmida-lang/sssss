import 'package:admin/admin_tabs.dart';
import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

const owner = TestAccount(
  id: 'u-owner',
  email: 'owner@school.local',
  password: 'owner-pass-1',
  role: UserRole.owner,
  displayName: 'المدير',
);

const staff = TestAccount(
  id: 'u-worker',
  email: 'worker@school.local',
  password: 'worker-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'عامل',
  permissions: '{"teachers":["view"],"workers":["view","edit"]}',
);

/// يفتح ملف أستاذ (أو عامل) من «المزيد» ببذرة أستاذ وعامل (سائق).
Future<AppRuntime> openProfile(
  WidgetTester tester, {
  TestAccount account = owner,
  required String path,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: [account],
    pages: adminPages,
    provisioner: FakeAccountProvisioner(),
  );
  await loginWith(tester, account.email, account.password);
  final db = runtime.db;
  await runDb(tester, () async {
    await db
        .into(db.teachers)
        .insert(
          TeachersCompanion.insert(
            id: 't1',
            createdAt: 1,
            updatedAt: 1,
            name: 'كمال',
            phone: '0660000001',
            email: 't1@school.local',
            qrCode: 'T-AAAAAAAAAA',
          ),
        );
    await db
        .into(db.workers)
        .insert(
          WorkersCompanion.insert(
            id: 'w9',
            createdAt: 1,
            updatedAt: 1,
            name: 'السائق مراد',
            phone: '0660000009',
            email: 'w9@school.local',
            qrCode: 'W-AAAAAAAAAA',
            fullDayWage: const Value(2000),
          ),
        );
  });
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await tester.pumpAndSettle();
  return runtime;
}

Future<void> fillAmount(WidgetTester tester, String value) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(ClayDialog),
      matching: find.byType(TextField).first,
    ),
    value,
  );
  await tester.pump();
}

/// يفرغ مؤقتات drift المعلّقة بعد كتابة من الواجهة، فتصل نتائج الاستعلامات الحية.
Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

void main() {
  appTest('ملف الأستاذ: بطاقة الديون فارغة ثم إضافة دين ثم تسديد جزء منه', (
    tester,
  ) async {
    final runtime = await openProfile(tester, path: '/teachers/t1');
    expect(find.text('الديون على المدرسة'), findsOneWidget);
    expect(find.text('لا دين'), findsOneWidget);
    expect(find.text('0 دج'), findsWidgets);

    await tester.tap(find.widgetWithText(ClayButton, 'إضافة دين'));
    await tester.pumpAndSettle();
    expect(find.text('إضافة دين لـكمال'), findsOneWidget);
    await fillAmount(tester, '50000');
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة الدين'));
    await settle(tester);
    expect(find.text('دين قائم'), findsOneWidget);
    expect(find.text(Money.format(50000)), findsWidgets);
    expect(find.text('+ ${Money.format(50000)}'), findsOneWidget);

    // التسديد يملأ المتبقي افتراضياً؛ نغيّره إلى جزء منه.
    await tester.tap(find.widgetWithText(ClayButton, 'تسديد'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('المتبقي ${Money.format(50000)}'),
      findsOneWidget,
    );
    await fillAmount(tester, '20000');
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل التسديد'));
    await settle(tester);
    expect(find.text(Money.format(30000)), findsWidgets);
    expect(find.text('− ${Money.format(20000)}'), findsOneWidget);

    final db = runtime.db;
    final expenses = await (db.select(
      db.expenses,
    )..where((e) => e.deletedAt.isNull())).get();
    expect(expenses, hasLength(1));
    expect(expenses.single.amount, 20000);
    expect(expenses.single.categoryId, StaffDebtService.categoryId);
  });

  appTest('تسديد أكثر من المتبقي يُرفض بالرسالة في النافذة', (tester) async {
    await openProfile(tester, path: '/teachers/t1');
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة دين'));
    await tester.pumpAndSettle();
    await fillAmount(tester, '1000');
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة الدين'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'تسديد'));
    await tester.pumpAndSettle();
    await fillAmount(tester, '2000');
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل التسديد'));
    await settle(tester);
    expect(find.textContaining('أكبر من الدين المتبقي'), findsOneWidget);
    expect(find.byType(ClayDialog), findsOneWidget);
  });

  appTest('ملف العامل (السائق): إضافة دين وحذفه', (tester) async {
    await openProfile(tester, path: '/workers/w9');
    expect(find.text('الديون على المدرسة'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة دين'));
    await tester.pumpAndSettle();
    expect(find.text('إضافة دين لـالسائق مراد'), findsOneWidget);
    await fillAmount(tester, '12000');
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة الدين'));
    await settle(tester);
    expect(find.text(Money.format(12000)), findsWidgets);

    await tester.tap(find.byTooltip('حذف الدين'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حذف'));
    await settle(tester);
    expect(find.text('لا دين'), findsOneWidget);
  });

  appTest('البطاقة لصاحب المدرسة وحده: العامل المخوَّل لا يراها', (
    tester,
  ) async {
    await openProfile(tester, account: staff, path: '/teachers/t1');
    expect(find.text('كمال'), findsWidgets);
    expect(find.text('الديون على المدرسة'), findsNothing);
  });

  appTest('شاشة ديون الأساتذة والعمال: المتبقّون ومجموعهم', (tester) async {
    final runtime = await openProfile(tester, path: '/staff-debts');
    expect(find.text('لا ديون على المدرسة'), findsOneWidget);
    final debts = StaffDebtService(runtime.db, runtime.writer);
    await runDb(tester, () async {
      await debts.addDebt(
        kind: StaffKind.teacher,
        staffId: 't1',
        amount: 30000,
        date: '2026-10-01',
      );
      await debts.addDebt(
        kind: StaffKind.worker,
        staffId: 'w9',
        amount: 12000,
        date: '2026-10-01',
      );
    });
    await tester.pumpAndSettle();
    expect(find.text('كمال'), findsOneWidget);
    expect(find.text('السائق مراد'), findsOneWidget);
    expect(find.text(Money.format(42000)), findsOneWidget);
    expect(find.text(Money.format(30000)), findsOneWidget);
    // النقر يفتح ملف صاحب الدين.
    await tester.tap(find.text('السائق مراد'));
    await tester.pumpAndSettle();
    expect(find.text('ملف العامل'), findsOneWidget);
  });
}
