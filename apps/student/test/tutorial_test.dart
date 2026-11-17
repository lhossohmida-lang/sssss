import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';
import 'package:student/student_tabs.dart';

import 'home_test.dart' hide main;

void main() {
  test('كل تبويب في تطبيق الوليّ له درس يشرحه', () {
    for (final tab in studentTabs) {
      expect(
        TutorialCatalog.forTab(AppIdentity.student, tab.path),
        isNotNull,
        reason: tab.path,
      );
    }
  });

  appTest('«؟» في «الجدول» يفتح درس الجدول الأسبوعي', (tester) async {
    await openParent(tester);
    await tester.tap(find.text('الجدول').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('شرح هذه الشاشة'));
    await tester.pumpAndSettle();
    expect(find.text('الجدول الأسبوعي'), findsWidgets);
    expect(find.textContaining('الخطوة 1 من'), findsWidgets);
  });

  appTest('«حسابي»: دليل الاستخدام بدروس الوليّ', (tester) async {
    await openParent(tester);
    await tester.tap(find.text('حسابي').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'دليل الاستخدام'));
    await tester.pumpAndSettle();
    final lessons = TutorialCatalog.forApp(AppIdentity.student);
    expect(find.text('أنهيت 0 من ${lessons.length}'), findsOneWidget);
    expect(find.text('جولة سريعة للوليّ'), findsOneWidget);
  });
}
