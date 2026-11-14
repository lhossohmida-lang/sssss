import 'dart:convert';

import 'package:admin/admin_tabs.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/testing.dart';

import 'catalog_screens_test.dart' show openSection, owner;

const auditReader = TestAccount(
  id: 'u-audit-reader',
  email: 'audit-reader@school.local',
  password: 'audit-pass-1',
  role: UserRole.worker,
  entityId: 'w-audit',
  displayName: 'مراجع السجل',
  permissions: '{"audit":["view"]}',
);

Future<void> seedAuditEntries(AppRuntime runtime) async {
  await runtime.db
      .into(runtime.db.auditLog)
      .insert(
        AuditLogCompanion.insert(
          id: 'audit-student-update',
          userId: 'u-owner',
          userName: const Value('المدير'),
          action: 'update',
          entity: 'students',
          entityId: 'student-1',
          before: Value(
            jsonEncode({
              'id': 'student-1',
              'first_name': 'سليم',
              'password_hash': 'secret-before',
            }),
          ),
          after: Value(
            jsonEncode({
              'id': 'student-1',
              'first_name': 'سليمان',
              'password_hash': 'secret-after',
            }),
          ),
          createdAt: DateTime(2026, 5, 10, 14, 30).millisecondsSinceEpoch,
          updatedAt: DateTime(2026, 5, 10, 14, 30).millisecondsSinceEpoch,
        ),
      );
  await runtime.db
      .into(runtime.db.auditLog)
      .insert(
        AuditLogCompanion.insert(
          id: 'audit-payment',
          userId: 'u-owner',
          userName: const Value('المدير'),
          action: 'receive_money',
          entity: 'payments',
          entityId: 'receipt-100',
          after: Value(jsonEncode({'amount': 2500, 'receipt_number': 'R-100'})),
          createdAt: DateTime(2026, 5, 11, 9, 5).millisecondsSinceEpoch,
          updatedAt: DateTime(2026, 5, 11, 9, 5).millisecondsSinceEpoch,
        ),
      );
}

Future<AppRuntime> openAuditScreenWithEntries(WidgetTester tester) async {
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: [owner],
    pages: adminPages,
  );
  await loginWith(tester, owner.email, owner.password);
  await runDb(tester, () => seedAuditEntries(runtime));
  await openMoreEntry(tester, 'سجل العمليات');
  return runtime;
}

void main() {
  appTest('يعرض السجل الأحدث ويفتح تفاصيل القيم قبل وبعد', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    await openAuditScreenWithEntries(tester);
    await tester.pumpAndSettle();

    expect(find.text('استلام المال · المدفوعات'), findsOneWidget);
    expect(find.text('تعديل · التلاميذ'), findsOneWidget);

    await tester.tap(find.text('تعديل · التلاميذ'));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل التغيير'), findsOneWidget);
    expect(find.text('الاسم الأول'), findsOneWidget);
    expect(find.textContaining('قبل: سليم'), findsOneWidget);
    expect(find.textContaining('بعد: سليمان'), findsOneWidget);
    expect(find.textContaining('secret-after'), findsNothing);
  });

  appTest('يفلتر حسب نوع العملية وبحث اسم المنفذ', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    await openAuditScreenWithEntries(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('استلام المال').last);
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.text('استلام المال · المدفوعات'), findsOneWidget);
    expect(find.text('تعديل · التلاميذ'), findsNothing);

    await tester.enterText(find.byType(TextField), 'المدير');
    await tester.tap(find.byTooltip('بحث'));
    await tester.pumpAndSettle();
    expect(find.text('استلام المال · المدفوعات'), findsOneWidget);
  });

  appTest('عامل بصلاحية السجل يراه عبر «المزيد»', (tester) async {
    tester.view.physicalSize = const Size(600, 1200);
    await openSection(tester, auditReader, 'سجل العمليات');

    expect(find.text('لا توجد عمليات مطابقة'), findsOneWidget);
    expect(find.text('الحركة المالية الشهرية'), findsNothing);
  });
}
