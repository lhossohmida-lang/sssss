import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'catalog_screens_test.dart' show openSection, owner;

const transportViewer = TestAccount(
  id: 'u-transport-viewer',
  email: 'transport-viewer@school.local',
  password: 'transport-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'عامل النقل',
  permissions: '{"transport":["view"]}',
);

Future<void> addTransportStudent(AppRuntime runtime, String id) async {
  await runtime.db
      .into(runtime.db.students)
      .insert(
        StudentsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          firstName: 'أمين',
          lastName: 'بن صالح',
          parentPhone: '0550123456',
          qrCode: 'S-$id',
        ),
      );
  await runtime.writer.patch(
    runtime.db.students,
    key: {'id': id},
    values: {'uses_transport': true, 'transport_price': 1800},
  );
}

void main() {
  appTest('إضافة خط بسائقه وحافلته وإسناد تلميذ إليه', (tester) async {
    final runtime = await openSection(tester, owner, 'النقل');
    expect(find.text('لا توجد خطوط نقل بعد'), findsOneWidget);

    await tester.tap(find.widgetWithText(ClayButton, 'إضافة خط نقل'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'خط الجامعة');
    await tester.enterText(fields.at(1), 'مراد');
    await tester.enterText(fields.at(2), '0550123456');
    await tester.enterText(fields.at(3), '16-202');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('خط الجامعة'), findsOneWidget);
    expect(find.textContaining('مراد'), findsOneWidget);
    expect(find.textContaining('16-202'), findsOneWidget);

    await tester.tap(find.byTooltip('تعديل خط الجامعة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(3), '16-303');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('16-303'), findsOneWidget);

    await runDb(tester, () => addTransportStudent(runtime, 's1'));
    await tester.pump();

    await tester.tap(find.text('خط الجامعة'));
    await tester.pumpAndSettle();
    expect(find.text('السائق: مراد'), findsOneWidget);
    expect(find.text('الهاتف: 0550123456'), findsOneWidget);
    expect(find.text('الحافلة: 16-303'), findsOneWidget);
    expect(find.text('لا تلاميذ في هذا الخط'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(ClayButton, 'إضافة أو نقل تلاميذ إلى الخط'),
    );
    await tester.pumpAndSettle();
    expect(find.text('أمين بن صالح'), findsOneWidget);
    await tester.tap(find.byTooltip('إسناد إلى الخط'));
    await tester.pumpAndSettle();
    expect(find.text('أمين بن صالح'), findsOneWidget);
    expect(find.textContaining(Money.format(1800)), findsOneWidget);
    expect(find.textContaining('شهرياً'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'إغلاق'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('إزالة أمين بن صالح من الخط'));
    await tester.pumpAndSettle();
    expect(find.text('لا تلاميذ في هذا الخط'), findsOneWidget);

    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('حذف خط الجامعة'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'حذف').last);
    await tester.pumpAndSettle();
    expect(find.text('لا توجد خطوط نقل بعد'), findsOneWidget);
  });

  appTest('عامل العرض يرى الخط ولا تظهر له إجراءات التعديل والإسناد', (
    tester,
  ) async {
    final runtime = await openSection(tester, transportViewer, 'النقل');
    await runDb(
      tester,
      () => TransportService(
        runtime.db,
        runtime.writer,
      ).addLine(name: 'خط المطار', driverName: 'سامي', busNumber: '02-120'),
    );
    await tester.pump();
    expect(find.text('خط المطار'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'إضافة خط نقل'), findsNothing);

    await tester.tap(find.text('خط المطار'));
    await tester.pumpAndSettle();
    expect(find.text('السائق: سامي'), findsOneWidget);
    expect(find.byTooltip('تعديل خط النقل'), findsNothing);
    expect(find.text('قائمة التلاميذ مخفية'), findsOneWidget);
    expect(
      find.widgetWithText(ClayButton, 'إضافة أو نقل تلاميذ إلى الخط'),
      findsNothing,
    );
  });
}
