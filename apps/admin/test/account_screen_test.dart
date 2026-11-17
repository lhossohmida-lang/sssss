import 'package:admin/admin_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

const _owner = TestAccount(
  id: 'u-owner',
  email: 'owner@school.local',
  password: 'owner-pass-1',
  role: UserRole.owner,
  displayName: 'صاحب المدرسة',
  mustChangePassword: false,
);

const _bareWorker = TestAccount(
  id: 'u-worker',
  email: '0661234567@school.local',
  password: 'worker-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'عامل بلا صلاحيات',
  mustChangePassword: false,
  permissions: '{}',
);

Future<AppRuntime> openMore(WidgetTester tester, TestAccount account) async {
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
  return runtime;
}

Finder field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

void main() {
  appTest('«المزيد»: بطاقة حسابي أعلى القائمة وتفتح صفحة الحساب', (
    tester,
  ) async {
    await openMore(tester, _owner);
    expect(find.text('حسابي'), findsOneWidget);
    expect(find.text('صاحب المدرسة · صاحب المدرسة'), findsOneWidget);

    await tester.tap(find.text('حسابي'));
    await tester.pumpAndSettle();

    expect(find.text('رقم الدخول'), findsOneWidget);
    expect(find.text('owner@school.local'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'تغيير كلمة السر'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'تغيير رقم الدخول'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'خروج'), findsOneWidget);
  });

  appTest('تغيير رقم الدخول: أخطاء الحقول ثم النجاح ببيانات الرقم الجديد', (
    tester,
  ) async {
    final runtime = await openMore(tester, _owner);
    await tester.tap(find.text('حسابي'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'تغيير رقم الدخول'));
    await tester.pumpAndSettle();

    Future<void> submit(String phone, String password) async {
      await tester.enterText(field('رقم الهاتف الجديد'), phone);
      await tester.enterText(field('كلمة السر الحالية'), password);
      await tester.tap(find.widgetWithText(ClayButton, 'حفظ'));
      await tester.pumpAndSettle();
    }

    // حقول فارغة ثم رقم غير صالح.
    await submit('', '');
    expect(find.text('أدخل رقم الهاتف'), findsOneWidget);
    expect(find.text('أدخل كلمة السر الحالية'), findsOneWidget);
    await submit('12345', 'owner-pass-1');
    expect(find.textContaining('يبدأ بـ 05 أو 06 أو 07'), findsOneWidget);
    await submit('owner@school.com', 'owner-pass-1');
    expect(find.text('أدخل رقم هاتف لا بريداً إلكترونياً'), findsOneWidget);

    // كلمة السر الحالية خاطئة: الخطأ تحت حقلها والرقم لم يتغير.
    await submit('0550123456', 'wrong-pass-1');
    expect(find.text(AuthFailure.invalidCredentials.message), findsOneWidget);
    expect(runtime.auth.current?.email, 'owner@school.local');

    // النجاح: يُغلق الحوار، ويظهر الرقم الجديد، ويُسجَّل في الحساب.
    await submit('0550 12 34 56', 'owner-pass-1');
    expect(
      find.text('رقم الهاتف الجديد'),
      findsNothing,
      reason: 'الحوار أُغلق',
    );
    expect(
      find.text('تم تغيير رقم الدخول، استعمله في المرة القادمة'),
      findsOneWidget,
    );
    expect(find.text('0550123456'), findsOneWidget);
    expect(runtime.auth.current?.email, '0550123456@school.local');
    final row = await tester.runAsync(
      () => (runtime.db.select(
        runtime.db.userAccounts,
      )..where((t) => t.id.equals('u-owner'))).getSingle(),
    );
    expect(row!.email, '0550123456@school.local');
  });

  appTest('إلغاء الحوار لا يغيّر شيئاً', (tester) async {
    final runtime = await openMore(tester, _owner);
    await tester.tap(find.text('حسابي'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'تغيير رقم الدخول'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'إلغاء'));
    await tester.pumpAndSettle();
    expect(runtime.auth.current?.email, 'owner@school.local');
    expect(find.text('رقم الهاتف الجديد'), findsNothing);
  });

  appTest('عامل بلا صلاحيات: يرى حسابي ورسالة أن لا أقسام له', (tester) async {
    await openMore(tester, _bareWorker);
    expect(find.text('حسابي'), findsOneWidget);
    expect(find.text('لا توجد أقسام متاحة'), findsOneWidget);

    await tester.tap(find.text('حسابي'));
    await tester.pumpAndSettle();
    expect(find.text('0661234567'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'تغيير رقم الدخول'), findsOneWidget);
  });
}
