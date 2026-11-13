import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/testing.dart';
import 'package:teacher/teacher_tabs.dart';

const teacher = TestAccount(
  id: 'u-teacher',
  email: 'teacher@school.local',
  password: 'teacher-pass-1',
  role: UserRole.teacher,
  entityId: 't1',
  displayName: 'الأستاذ كمال',
);

const parent = TestAccount(
  id: 'u-parent',
  email: 'parent@school.local',
  password: 'parent-pass-1',
  role: UserRole.parent,
  entityId: 'p1',
);

void main() {
  appTest('يفتح بالعربية ومن اليمين إلى اليسار على شاشة الدخول', (
    tester,
  ) async {
    await bootApp(
      tester,
      teacherTabs,
      app: AppIdentity.teacher,
      accounts: [teacher],
    );
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('الأستاذ'), findsOneWidget);
    final context = tester.element(find.text('تسجيل الدخول'));
    expect(Directionality.of(context), TextDirection.rtl);
  });

  appTest('الأستاذ يدخل ويرى تبويباته', (tester) async {
    await bootApp(
      tester,
      teacherTabs,
      app: AppIdentity.teacher,
      accounts: [teacher],
    );
    await loginWith(tester, teacher.email, teacher.password);
    for (final label in ['الرئيسية', 'مجموعاتي', 'طلباتي', 'خلاصي', 'حسابي']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  appTest('مدخل المحادثات يفتح صندوق رسائل الأستاذ', (tester) async {
    await bootApp(
      tester,
      teacherTabs,
      app: AppIdentity.teacher,
      accounts: [teacher],
      pages: teacherPages,
    );
    await loginWith(tester, teacher.email, teacher.password);
    await tester.tap(find.byTooltip('المحادثات'));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد محادثات بعد'), findsOneWidget);
  });

  appTest('حساب الوليّ لا يدخل تطبيق الأستاذ', (tester) async {
    final runtime = await bootApp(
      tester,
      teacherTabs,
      app: AppIdentity.teacher,
      accounts: [parent],
    );
    await loginWith(tester, parent.email, parent.password);
    expect(find.textContaining('لا يدخل من تطبيق الأستاذ'), findsOneWidget);
    expect(runtime.auth.current, isNull);
  });
}
