import 'package:admin/admin_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/testing.dart';

const owner = TestAccount(
  id: 'u-owner',
  email: 'owner@school.local',
  password: 'owner-pass-1',
  role: UserRole.owner,
  displayName: 'المدير',
);

const receptionist = TestAccount(
  id: 'u-worker',
  email: 'worker@school.local',
  password: 'worker-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'عامل الاستقبال',
  permissions: '{"students":["view","add"],"payments":["view"]}',
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
    await bootApp(tester, adminTabs, app: AppIdentity.admin, accounts: [owner]);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('الإدارة'), findsOneWidget);
    final context = tester.element(find.text('تسجيل الدخول'));
    expect(Directionality.of(context), TextDirection.rtl);
  });

  appTest('صاحب المدرسة يرى التبويبات الخمسة', (tester) async {
    final runtime = await bootApp(
      tester,
      adminTabs,
      app: AppIdentity.admin,
      accounts: [owner],
    );
    await loginWith(tester, owner.email, owner.password);
    expect(runtime.auth.current?.role, UserRole.owner);
    for (final label in [
      'الرئيسية',
      'التلاميذ',
      'المجموعات',
      'المدفوعات',
      'المزيد',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  appTest('العامل يرى ما صُرّح له فقط', (tester) async {
    await bootApp(
      tester,
      adminTabs,
      app: AppIdentity.admin,
      accounts: [receptionist],
    );
    await loginWith(tester, receptionist.email, receptionist.password);
    expect(find.text('التلاميذ'), findsWidgets);
    expect(find.text('المدفوعات'), findsWidgets);
    expect(find.text('المجموعات'), findsNothing);
  });

  appTest('حساب الأستاذ لا يدخل تطبيق الإدارة', (tester) async {
    final runtime = await bootApp(
      tester,
      adminTabs,
      app: AppIdentity.admin,
      accounts: [teacher],
    );
    await loginWith(tester, teacher.email, teacher.password);
    expect(find.textContaining('لا يدخل من تطبيق الإدارة'), findsOneWidget);
    expect(runtime.auth.current, isNull);
  });
}
