import 'package:admin/admin_tabs.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/testing.dart';

import 'catalog_screens_test.dart' show owner;

const reportReader = TestAccount(
  id: 'u-report-reader',
  email: 'report@school.local',
  password: 'report-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'قارئ التقارير',
  permissions: '{"payments":["view"],"expenses":["view"]}',
);

void main() {
  appTest('التقرير يجمع الشهر ويصدر PDF', (tester) async {
    final presenter = FakePdfPresenter();
    final runtime = await bootApp(
      tester,
      adminTabs,
      app: AppIdentity.admin,
      accounts: [owner],
      pages: adminPages,
      pdfPresenter: presenter,
    );
    await loginWith(tester, owner.email, owner.password);
    await openMoreEntry(tester, 'التقرير الشهري');

    final now = DateTime.now();
    await runDb(tester, () async {
      await runtime.db
          .into(runtime.db.students)
          .insert(
            StudentsCompanion.insert(
              id: 's-report',
              createdAt: 1,
              updatedAt: 1,
              firstName: 'أحمد',
              lastName: 'التقرير',
              parentPhone: '0550123456',
              qrCode: 'S-REPORT',
            ),
          );
      await runtime.db
          .into(runtime.db.payments)
          .insert(
            PaymentsCompanion.insert(
              id: 'p-report',
              createdAt: now.millisecondsSinceEpoch,
              updatedAt: now.millisecondsSinceEpoch,
              deletedAt: const Value(null),
              studentId: 's-report',
              type: PaymentType.month.code,
              amount: 700,
              receivedBy: owner.id,
              receiptNumber: 'RPT-000001',
            ),
          );
      final service = ExpenseService(runtime.db, runtime.writer);
      final category = await service.addCategory('قرطاسية');
      await service.addExpense(
        categoryId: category,
        amount: 250,
        date: DateKey.of(now),
      );
    });
    await tester.pumpAndSettle();

    expect(find.text(Money.format(700)), findsWidgets);
    expect(find.text(Money.format(250)), findsWidgets);
    expect(find.text(Money.format(450)), findsOneWidget);
    expect(find.text('قرطاسية'), findsOneWidget);

    await tester.tap(find.byTooltip('تصدير التقرير PDF'));
    await tester.pumpAndSettle();
    expect(presenter.shown, hasLength(1));
    expect(presenter.shown.single.fileName, startsWith('monthly-finance-'));
    expect(presenter.shown.single.title, contains('التقرير المالي'));
  });

  appTest('لا يظهر التقرير لمن لا يملك صلاحية عرض الخلاص', (tester) async {
    await bootApp(
      tester,
      adminTabs,
      app: AppIdentity.admin,
      accounts: [reportReader],
      pages: adminPages,
    );
    await loginWith(tester, reportReader.email, reportReader.password);
    await tester.tap(find.text('المزيد').last);
    await tester.pumpAndSettle();

    expect(find.text('التقرير الشهري'), findsNothing);
  });
}
