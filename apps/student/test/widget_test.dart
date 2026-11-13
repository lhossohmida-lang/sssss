import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/testing.dart';
import 'package:student/student_tabs.dart';

const parent = TestAccount(
  id: 'u-parent',
  email: 'parent@school.local',
  password: 'parent-pass-1',
  role: UserRole.parent,
  entityId: 'p1',
  displayName: 'ولي التلميذ',
);

const teacher = TestAccount(
  id: 'u-teacher',
  email: 'teacher@school.local',
  password: 'teacher-pass-1',
  role: UserRole.teacher,
  entityId: 't1',
);

void main() {
  appTest('يفتح بالعربية ومن اليمين إلى اليسار على شاشة الدخول', (
    tester,
  ) async {
    await bootApp(
      tester,
      studentTabs,
      app: AppIdentity.student,
      accounts: [parent],
    );
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('وليّ التلميذ'), findsOneWidget);
    final context = tester.element(find.text('تسجيل الدخول'));
    expect(Directionality.of(context), TextDirection.rtl);
  });

  appTest('الوليّ يدخل ويرى تبويباته', (tester) async {
    await bootApp(
      tester,
      studentTabs,
      app: AppIdentity.student,
      accounts: [parent],
    );
    await loginWith(tester, parent.email, parent.password);
    for (final label in [
      'الرئيسية',
      'الحضور',
      'الجدول',
      'المدفوعات',
      'حسابي',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  appTest('مدخل المحادثات يفتح صندوق رسائل الوليّ', (tester) async {
    await bootApp(
      tester,
      studentTabs,
      app: AppIdentity.student,
      accounts: [parent],
      pages: studentPages,
    );
    await loginWith(tester, parent.email, parent.password);
    await tester.tap(find.byTooltip('المحادثات'));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد محادثات بعد'), findsOneWidget);
  });

  appTest('حساب الأستاذ لا يدخل تطبيق الوليّ', (tester) async {
    final runtime = await bootApp(
      tester,
      studentTabs,
      app: AppIdentity.student,
      accounts: [teacher],
    );
    await loginWith(tester, teacher.email, teacher.password);
    expect(
      find.textContaining('لا يدخل من تطبيق وليّ التلميذ'),
      findsOneWidget,
    );
    expect(runtime.auth.current, isNull);
  });
}
