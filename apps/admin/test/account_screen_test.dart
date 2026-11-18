import 'package:admin/admin_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

const accountOwner = TestAccount(
  id: 'u-owner',
  email: 'owner@school.local',
  password: 'owner-pass-1',
  role: UserRole.owner,
  displayName: 'صاحب المدرسة',
  mustChangePassword: false,
);

const accountBareWorker = TestAccount(
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

/// بوابة إعادة تعيين وهمية تسجّل كلمات السر وتُفشل عند الطلب.
class _Reset implements SchoolResetGateway {
  final List<String> passwords = [];
  SchoolResetException? failure;
  SchoolResetResult result = const SchoolResetResult(
    epoch: 'epoch-1',
    removedAccounts: 5,
  );

  @override
  Future<SchoolResetResult> reset({required String password}) async {
    passwords.add(password);
    if (failure != null) throw failure!;
    return result;
  }
}

Future<AppRuntime> openAccount(
  WidgetTester tester,
  TestAccount account, {
  SchoolResetGateway? reset,
}) async {
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: [account],
    pages: adminPages,
    schoolReset: reset,
  );
  await loginWith(tester, account.email, account.password);
  await tester.tap(find.text('المزيد').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('حسابي'));
  await tester.pumpAndSettle();
  return runtime;
}

void resetTests() {
  const button = 'إعادة تعيين بيانات المصنع';
  const phrase = 'حذف كل البيانات';

  appTest('الزر لصاحب المدرسة على خادم وحده', (tester) async {
    await openAccount(tester, accountOwner, reset: _Reset());
    expect(find.widgetWithText(ClayButton, button), findsOneWidget);
  });

  appTest('لا زر لمن لا خادم له ولا للعامل', (tester) async {
    await openAccount(tester, accountOwner);
    expect(find.widgetWithText(ClayButton, button), findsNothing);
  });

  appTest('عامل مع خادم: لا زر', (tester) async {
    await openAccount(tester, accountBareWorker, reset: _Reset());
    expect(find.widgetWithText(ClayButton, button), findsNothing);
  });

  appTest('تحذير مفصّل أولاً، والإلغاء لا يفعل شيئاً', (tester) async {
    final gateway = _Reset();
    await openAccount(tester, accountOwner, reset: gateway);
    await tester.tap(find.widgetWithText(ClayButton, button));
    await tester.pumpAndSettle();
    expect(find.textContaining('ستُحذف مدرستك كلها نهائياً'), findsOneWidget);
    expect(find.textContaining('يبقى حسابك'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد حذف كل البيانات'), findsNothing);
    expect(gateway.passwords, isEmpty);
  });

  appTest('الحذف معطّل حتى كلمة السر والعبارة الصحيحة', (tester) async {
    final gateway = _Reset();
    await openAccount(tester, accountOwner, reset: gateway);
    await tester.tap(find.widgetWithText(ClayButton, button));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'متابعة'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد حذف كل البيانات'), findsOneWidget);

    bool enabled() =>
        tester
            .widget<ClayButton>(find.widgetWithText(ClayButton, phrase))
            .onPressed !=
        null;
    expect(enabled(), isFalse);
    await tester.enterText(field('كلمة سر صاحب المدرسة'), 'owner-pass-1');
    await tester.pump();
    expect(enabled(), isFalse, reason: 'العبارة ناقصة');
    await tester.enterText(field('اكتب «$phrase» للتأكيد'), 'حذف');
    await tester.pump();
    expect(enabled(), isFalse);
    await tester.enterText(field('اكتب «$phrase» للتأكيد'), '  $phrase ');
    await tester.pump();
    expect(enabled(), isTrue, reason: 'المسافات الزائدة تُقصّ');
    await tester.enterText(field('كلمة سر صاحب المدرسة'), '');
    await tester.pump();
    expect(enabled(), isFalse, reason: 'بلا كلمة سر');
    expect(gateway.passwords, isEmpty);
  });

  appTest('كلمة سر خاطئة: خطأ عند حقلها ولا يُمسح شيء', (tester) async {
    final gateway = _Reset()
      ..failure = const SchoolResetException(
        SchoolResetFailure.wrongPassword,
        'كلمة السر غير صحيحة',
      );
    final runtime = await openAccount(tester, accountOwner, reset: gateway);
    await runDb(
      tester,
      () => runtime.writer.save(
        runtime.db.rooms,
        RoomsCompanion.insert(
          id: 'r1',
          createdAt: 0,
          updatedAt: 0,
          name: 'القاعة 1',
        ),
        key: {'id': 'r1'},
      ),
    );
    await tester.tap(find.widgetWithText(ClayButton, button));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'متابعة'));
    await tester.pumpAndSettle();
    await tester.enterText(field('كلمة سر صاحب المدرسة'), 'wrong-pass-1');
    await tester.enterText(field('اكتب «$phrase» للتأكيد'), phrase);
    await tester.pump();
    await tester.tap(find.widgetWithText(ClayButton, phrase));
    await tester.pumpAndSettle();

    expect(find.text('كلمة السر غير صحيحة'), findsOneWidget);
    expect(
      find.text('تأكيد حذف كل البيانات'),
      findsOneWidget,
      reason: 'الحوار مفتوح',
    );
    expect(gateway.passwords, ['wrong-pass-1']);
    final rooms = await runDb(
      tester,
      () => runtime.db.select(runtime.db.rooms).get(),
    );
    expect(rooms, hasLength(1), reason: 'لم يُمسح شيء');
  });

  appTest('النجاح: تُمسح بيانات الجهاز ويبقى المالك مسجَّلاً وتظهر النتيجة', (
    tester,
  ) async {
    final gateway = _Reset();
    final runtime = await openAccount(tester, accountOwner, reset: gateway);
    await runDb(
      tester,
      () => runtime.writer.save(
        runtime.db.rooms,
        RoomsCompanion.insert(
          id: 'r1',
          createdAt: 0,
          updatedAt: 0,
          name: 'القاعة 1',
        ),
        key: {'id': 'r1'},
      ),
    );
    await tester.tap(find.widgetWithText(ClayButton, button));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'متابعة'));
    await tester.pumpAndSettle();
    await tester.enterText(field('كلمة سر صاحب المدرسة'), 'owner-pass-1');
    await tester.enterText(field('اكتب «$phrase» للتأكيد'), phrase);
    await tester.pump();
    await tester.tap(find.widgetWithText(ClayButton, phrase));
    await tester.pumpAndSettle();

    expect(gateway.passwords, ['owner-pass-1']);
    expect(find.text('تمت إعادة تعيين المدرسة'), findsOneWidget);
    expect(find.textContaining('حُذف 5 من حسابات طاقمها'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'تم'));
    await tester.pumpAndSettle();

    final rooms = await runDb(
      tester,
      () => runtime.db.select(runtime.db.rooms).get(),
    );
    expect(rooms, isEmpty, reason: 'بيانات الجهاز مُسحت');
    expect(runtime.auth.current?.accountId, 'u-owner');
    expect(find.text('رقم الدخول'), findsOneWidget, reason: 'ما زال في حسابه');
    final epoch = await runDb(
      tester,
      () =>
          DevicePreferences(runtime.db).read(DevicePreferences.schoolEpochKey),
    );
    expect(epoch, 'epoch-1');
  });

  appTest('بقايا على الخادم: تُعرض وتُطلب إعادة التشغيل', (tester) async {
    final gateway = _Reset()
      ..result = const SchoolResetResult(
        epoch: 'epoch-2',
        removedAccounts: 2,
        authFailures: 1,
        storageFailures: 4,
      );
    await openAccount(tester, accountOwner, reset: gateway);
    await tester.tap(find.widgetWithText(ClayButton, button));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'متابعة'));
    await tester.pumpAndSettle();
    await tester.enterText(field('كلمة سر صاحب المدرسة'), 'owner-pass-1');
    await tester.enterText(field('اكتب «$phrase» للتأكيد'), phrase);
    await tester.pump();
    await tester.tap(find.widgetWithText(ClayButton, phrase));
    await tester.pumpAndSettle();
    expect(find.text('تمت الإعادة وبقيت بقايا'), findsOneWidget);
    expect(
      find.textContaining('1 من حسابات الدخول، 4 من الملفات'),
      findsOneWidget,
    );
  });
}

void main() {
  resetTests();

  appTest('«المزيد»: بطاقة حسابي أعلى القائمة وتفتح صفحة الحساب', (
    tester,
  ) async {
    await openMore(tester, accountOwner);
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
    final runtime = await openMore(tester, accountOwner);
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
    final runtime = await openMore(tester, accountOwner);
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
    await openMore(tester, accountBareWorker);
    expect(find.text('حسابي'), findsOneWidget);
    expect(find.text('لا توجد أقسام متاحة'), findsOneWidget);

    await tester.tap(find.text('حسابي'));
    await tester.pumpAndSettle();
    expect(find.text('0661234567'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'تغيير رقم الدخول'), findsOneWidget);
  });
}
