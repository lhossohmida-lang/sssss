import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/testing.dart';

import 'catalog_screens_test.dart' show openSection, owner;

const expenseCreator = TestAccount(
  id: 'u-expense-creator',
  email: 'expense@school.local',
  password: 'expense-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'عامل مصاريف',
  permissions: '{"expenses":["add"]}',
);

void main() {
  appTest('قائمة المصاريف فارغة والمجاميع صفر', (tester) async {
    await openSection(tester, owner, 'المصاريف');

    expect(find.text('لا مصاريف في هذا الشهر'), findsOneWidget);
    expect(find.textContaining('مجموع سنة'), findsOneWidget);
    expect(find.textContaining(Money.format(0)), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, 'إضافة مصروف'), findsOneWidget);
  });

  appTest('إضافة النوع والمصروف يحدّث القائمة والمجاميع', (tester) async {
    final runtime = await openSection(tester, owner, 'المصاريف');
    await tester.tap(find.widgetWithText(FilledButton, 'إضافة مصروف'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة نوع جديد'));
    await tester.pumpAndSettle();
    final nameDialog = find.byType(AlertDialog).last;
    await tester.enterText(
      find.descendant(of: nameDialog, matching: find.byType(TextField)),
      'صيانة',
    );
    await tester.tap(
      find.descendant(
        of: nameDialog,
        matching: find.widgetWithText(FilledButton, 'حفظ'),
      ),
    );
    await tester.pumpAndSettle();

    final expenseDialog = find.byType(AlertDialog).last;
    await tester.enterText(
      find
          .descendant(of: expenseDialog, matching: find.byType(TextField))
          .at(0),
      '1650',
    );
    await tester.enterText(
      find
          .descendant(of: expenseDialog, matching: find.byType(TextField))
          .at(1),
      'إصلاح المصباح',
    );
    await tester.tap(
      find.descendant(
        of: expenseDialog,
        matching: find.widgetWithText(FilledButton, 'حفظ'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('صيانة'), findsOneWidget);
    expect(find.textContaining('إصلاح المصباح'), findsOneWidget);
    expect(find.text(Money.format(1650)), findsOneWidget);
    expect(find.text('سُجّل المصروف'), findsOneWidget);

    final rows = await runDb(
      tester,
      () => runtime.db.select(runtime.db.expenses).get(),
    );
    expect(rows, hasLength(1));
    expect(rows.single.amount, 1650);
    expect(rows.single.note, 'إصلاح المصباح');
    expect(rows.single.createdBy, 'u-owner');
  });

  appTest('صلاحية الإضافة وحدها لا تكشف السجل أو مجموع المصاريف', (
    tester,
  ) async {
    final runtime = await openSection(tester, expenseCreator, 'المصاريف');
    await runDb(tester, () async {
      final service = ExpenseService(runtime.db, runtime.writer);
      final category = await service.addCategory('صيانة');
      await service.addExpense(
        categoryId: category,
        amount: 4200,
        date: DateKey.of(DateTime.now()),
      );
    });
    await tester.pumpAndSettle();

    expect(find.text('سجل المصاريف مخفي'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'إضافة مصروف'), findsOneWidget);
    expect(find.textContaining('مجموع سنة'), findsNothing);
    expect(find.text(Money.format(4200)), findsNothing);
    expect(find.text('صيانة'), findsNothing);
  });
}
