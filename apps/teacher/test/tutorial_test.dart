import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';
import 'package:teacher/teacher_tabs.dart';

import 'home_screens_test.dart' hide main;

void main() {
  test('كل تبويب في تطبيق الأستاذ له درس يشرحه', () {
    for (final tab in teacherTabs) {
      expect(
        TutorialCatalog.forTab(AppIdentity.teacher, tab.path),
        isNotNull,
        reason: tab.path,
      );
    }
  });

  appTest('«؟» في «طلباتي» يفتح درس طلب تغيير الموعد', (tester) async {
    await openTeacher(tester);
    await tester.tap(find.text('طلباتي').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('شرح هذه الشاشة'));
    await tester.pumpAndSettle();
    expect(find.text('طلب تغيير موعد أو إلغاء حصة'), findsOneWidget);
  });

  appTest('«؟» في «خلاصي» يفتح درس المستحقات', (tester) async {
    await openTeacher(tester);
    await tester.tap(find.text('خلاصي').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('شرح هذه الشاشة'));
    await tester.pumpAndSettle();
    expect(find.text('مستحقاتك'), findsOneWidget);
  });

  appTest('الشريط العلوي بأربعة أزرار لا يفيض على شاشة ضيقة', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    await openTeacher(tester);
    expect(find.byTooltip('شرح هذه الشاشة'), findsOneWidget);
    expect(find.byTooltip('المساعد'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('«حسابي»: دليل الاستخدام بدروس الأستاذ', (tester) async {
    await openTeacher(tester);
    await tester.tap(find.text('حسابي').last);
    // شاشة طويلة: بطاقة الحساب أعلى الصفحة تدفع الأزرار للأسفل.
    tester.view.physicalSize = const Size(420, 2600);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'دليل الاستخدام'));
    await tester.pumpAndSettle();
    final lessons = TutorialCatalog.forApp(AppIdentity.teacher);
    expect(find.text('أنهيت 0 من ${lessons.length}'), findsOneWidget);
    expect(find.text('جولة سريعة للأستاذ'), findsOneWidget);
    expect(find.text('إنشاء فوج مع تلاميذه'), findsNothing);
  });
}
