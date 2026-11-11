import 'package:admin/admin_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

TestAccount worker(String permissions) => TestAccount(
  id: 'u-worker',
  email: 'worker@school.local',
  password: 'worker-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'عامل',
  permissions: permissions,
);

/// يفتح قسماً من «المزيد».
Future<AppRuntime> openSection(
  WidgetTester tester,
  TestAccount account,
  String section,
) async {
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: [account],
    pages: adminPages,
  );
  await loginWith(tester, account.email, account.password);
  await tester.tap(find.text('المزيد').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(section));
  await tester.pumpAndSettle();
  return runtime;
}

Finder fieldOf(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

Future<void> saveDialog(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ClayButton, 'حفظ').last);
  await tester.pumpAndSettle();
}

void main() {
  group('المواد', () {
    appTest('قائمة فارغة برسالة وزر إضافة', (tester) async {
      await openSection(tester, owner, 'المواد');
      expect(find.text('لا توجد مواد بعد'), findsOneWidget);
      expect(find.widgetWithText(ClayButton, 'إضافة مادة'), findsOneWidget);
    });

    appTest('إضافة مادة بمستوى وسعر', (tester) async {
      final runtime = await openSection(tester, owner, 'المواد');
      await runDb(
        tester,
        () => LevelService(
          runtime.db,
          runtime.writer,
        ).add(name: '3 متوسط', stage: EducationStage.middle),
      );
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة مادة'));
      await tester.pumpAndSettle();
      await tester.enterText(fieldOf('اسم المادة'), 'رياضيات');
      await tester.enterText(fieldOf('سعر الشهر (دج)'), '2500');
      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 متوسط').last);
      await tester.pumpAndSettle();
      await saveDialog(tester);
      expect(find.text('رياضيات'), findsOneWidget);
      expect(find.text('3 متوسط · 2 500 دج'), findsOneWidget);
    });

    appTest('أخطاء التحقق تظهر في الحقول ولا يُغلق الحوار', (tester) async {
      await openSection(tester, owner, 'المواد');
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة مادة'));
      await tester.pumpAndSettle();
      await tester.enterText(fieldOf('سعر الشهر (دج)'), '2005');
      await saveDialog(tester);
      expect(find.text('أدخل اسم المادة'), findsOneWidget);
      expect(find.text('السعر من مضاعفات 10 دج'), findsOneWidget);
      expect(find.byType(ClayDialog), findsOneWidget);
    });

    appTest('سعر فارغ: «أدخل سعر الشهر»', (tester) async {
      await openSection(tester, owner, 'المواد');
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة مادة'));
      await tester.pumpAndSettle();
      await tester.enterText(fieldOf('اسم المادة'), 'رياضيات');
      await saveDialog(tester);
      expect(find.text('أدخل سعر الشهر'), findsOneWidget);
    });

    appTest('تعديل وحذف مع التأكيد', (tester) async {
      final runtime = await openSection(tester, owner, 'المواد');
      await runDb(
        tester,
        () => SubjectService(
          runtime.db,
          runtime.writer,
        ).add(name: 'فيزياء', monthlyPrice: 2000),
      );
      expect(find.text('فيزياء'), findsOneWidget);

      await tester.tap(find.byTooltip('تعديل فيزياء'));
      await tester.pumpAndSettle();
      await tester.enterText(fieldOf('سعر الشهر (دج)'), '2200');
      await saveDialog(tester);
      expect(find.text('كل المستويات · 2 200 دج'), findsOneWidget);

      await tester.tap(find.byTooltip('حذف فيزياء'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'حذف').last);
      await tester.pumpAndSettle();
      expect(find.text('فيزياء'), findsNothing);
      expect(find.text('لا توجد مواد بعد'), findsOneWidget);
    });

    appTest('البحث يصفّي القائمة', (tester) async {
      final runtime = await openSection(tester, owner, 'المواد');
      await runDb(tester, () async {
        final service = SubjectService(runtime.db, runtime.writer);
        await service.add(name: 'رياضيات', monthlyPrice: 2000);
        await service.add(name: 'فيزياء', monthlyPrice: 2000);
      });
      await tester.enterText(find.byType(TextField).first, 'فيز');
      await tester.pump();
      expect(find.text('فيزياء'), findsOneWidget);
      expect(find.text('رياضيات'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'لا شيء');
      await tester.pump();
      expect(find.text('لا نتائج مطابقة للبحث'), findsOneWidget);
    });

    appTest('عامل بصلاحية العرض فقط: بلا إضافة ولا أزرار', (tester) async {
      final runtime = await openSection(
        tester,
        worker('{"subjects":["view"]}'),
        'المواد',
      );
      expect(find.text('لا توجد مواد بعد'), findsOneWidget);
      expect(find.widgetWithText(ClayButton, 'إضافة مادة'), findsNothing);
      // الخادم نفسه سيرفض الكتابة؛ هنا يكفي أن الواجهة لا تعرضها.
      expect(runtime.auth.current?.role, UserRole.worker);
    });
  });

  group('القاعات', () {
    appTest('إضافة قاعة وعرض سعتها', (tester) async {
      await openSection(tester, owner, 'القاعات');
      expect(find.text('لا توجد قاعات بعد'), findsOneWidget);
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة قاعة'));
      await tester.pumpAndSettle();
      await tester.enterText(fieldOf('اسم القاعة'), 'القاعة 1');
      await tester.enterText(fieldOf('السعة (عدد المقاعد)'), '25');
      await saveDialog(tester);
      expect(find.text('القاعة 1'), findsOneWidget);
      expect(find.text('السعة: 25 مقعد'), findsOneWidget);
    });

    appTest('سعة صفر واسم مكرر مرفوضان', (tester) async {
      final runtime = await openSection(tester, owner, 'القاعات');
      await runDb(
        tester,
        () => RoomService(
          runtime.db,
          runtime.writer,
        ).add(name: 'القاعة 1', capacity: 20),
      );
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة قاعة'));
      await tester.pumpAndSettle();
      await tester.enterText(fieldOf('اسم القاعة'), 'القاعة 1');
      await tester.enterText(fieldOf('السعة (عدد المقاعد)'), '0');
      await saveDialog(tester);
      expect(find.text('توجد قاعة بهذا الاسم'), findsOneWidget);
      expect(find.text('السعة 1 على الأقل'), findsOneWidget);
    });

    appTest('تعديل قاعة وحذفها', (tester) async {
      final runtime = await openSection(tester, owner, 'القاعات');
      await runDb(
        tester,
        () => RoomService(
          runtime.db,
          runtime.writer,
        ).add(name: 'القاعة 2', capacity: 20),
      );
      await tester.tap(find.byTooltip('تعديل القاعة 2'));
      await tester.pumpAndSettle();
      await tester.enterText(fieldOf('السعة (عدد المقاعد)'), '30');
      await saveDialog(tester);
      expect(find.text('السعة: 30 مقعد'), findsOneWidget);
      await tester.tap(find.byTooltip('حذف القاعة 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'حذف').last);
      await tester.pumpAndSettle();
      expect(find.text('لا توجد قاعات بعد'), findsOneWidget);
    });

    appTest('بلا صلاحية القاعات: القسم غائب من «المزيد»', (tester) async {
      await bootApp(
        tester,
        adminTabs,
        app: AppIdentity.admin,
        accounts: [worker('{"subjects":["view"]}')],
        pages: adminPages,
      );
      await loginWith(tester, 'worker@school.local', 'worker-pass-1');
      await tester.tap(find.text('المزيد').last);
      await tester.pumpAndSettle();
      expect(find.text('القاعات'), findsNothing);
      expect(find.text('المواد'), findsWidgets);
    });
  });
}
