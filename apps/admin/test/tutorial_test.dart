import 'package:admin/admin_tabs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'account_screen_test.dart' hide main;

void main() {
  test('لكل تبويب في الإدارة درس يشرحه، و«المزيد» يفتح الدليل كله', () {
    for (final tab in adminTabs) {
      final lesson = TutorialCatalog.forTab(AppIdentity.admin, tab.path);
      if (tab.path == '/more') {
        expect(lesson, isNull, reason: tab.path);
      } else {
        expect(lesson, isNotNull, reason: tab.path);
      }
    }
  });

  appTest('«المزيد»: بطاقة دليل الاستخدام تفتح قائمة الدروس', (tester) async {
    await openMore(tester, accountOwner);
    expect(find.text('دليل الاستخدام'), findsOneWidget);
    await tester.tap(find.text('دليل الاستخدام'));
    await tester.pumpAndSettle();
    final lessons = TutorialCatalog.forApp(AppIdentity.admin);
    expect(find.text('أنهيت 0 من ${lessons.length}'), findsOneWidget);
    expect(find.text('جولة سريعة في التطبيق'), findsOneWidget);
  });

  appTest('عامل بلا صلاحيات يرى دليل الاستخدام أيضاً', (tester) async {
    await openMore(tester, accountBareWorker);
    expect(find.text('لا توجد أقسام متاحة'), findsOneWidget);
    expect(find.text('دليل الاستخدام'), findsOneWidget);
  });

  appTest('«؟» في تبويب التلاميذ يفتح درس التسجيل', (tester) async {
    await bootApp(
      tester,
      adminTabs,
      app: AppIdentity.admin,
      accounts: [accountOwner],
      pages: adminPages,
    );
    await loginWith(tester, accountOwner.email, accountOwner.password);
    await tester.tap(find.text('التلاميذ').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('شرح هذه الشاشة'));
    await tester.pumpAndSettle();
    expect(find.text('تسجيل تلميذ جديد'), findsOneWidget);
    expect(find.textContaining('الخطوة 1 من'), findsWidgets);
  });
}
