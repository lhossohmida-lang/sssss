import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

const _owner = TestAccount(
  id: 'u-owner',
  email: 'owner@school.local',
  password: 'owner-pass-1',
  role: UserRole.owner,
  displayName: 'المدير',
  mustChangePassword: false,
);

const _teacher = TestAccount(
  id: 'u-teacher',
  email: 'teacher@school.local',
  password: 'teacher-pass-1',
  role: UserRole.teacher,
  entityId: 't1',
  displayName: 'الأستاذ كمال',
  mustChangePassword: false,
);

final _tabs = [
  AppTab(
    path: '/home',
    destination: const ClayDestination(label: 'الرئيسية', icon: ClayIcons.home),
    builder: (_) => const Text('صفحة الرئيسية'),
  ),
  AppTab(
    path: '/students',
    destination: const ClayDestination(
      label: 'التلاميذ',
      icon: ClayIcons.students,
    ),
    builder: (_) => const Text('صفحة التلاميذ'),
  ),
  AppTab(
    path: '/more',
    destination: const ClayDestination(label: 'المزيد', icon: ClayIcons.more),
    builder: (_) => const Text('صفحة المزيد'),
  ),
  AppTab(
    path: '/account',
    destination: const ClayDestination(label: 'حسابي', icon: ClayIcons.parents),
    builder: (_) => const AccountScreen(),
  ),
];

Future<AppRuntime> open(
  WidgetTester tester, {
  TestAccount account = _owner,
  AppIdentity app = AppIdentity.admin,
  bool welcome = false,
}) async {
  final runtime = await bootApp(
    tester,
    _tabs,
    app: app,
    accounts: [account],
    tutorialWelcome: welcome,
  );
  await loginWith(tester, account.email, account.password);
  return runtime;
}

/// تفتح صفحة بمسارها كأن المستخدم تنقّل إليها.
Future<void> goTo(WidgetTester tester, String location) async {
  unawaited(
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push(location),
  );
  await tester.pumpAndSettle();
}

Future<TutorialState> stateOf(WidgetTester tester, AppRuntime runtime) => runDb(
  tester,
  () => TutorialProgress(DevicePreferences(runtime.db), 'u-owner').load(),
);

void main() {
  appTest('الجولة الأولى لا تعترض الشاشات في الاختبارات الافتراضية', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('صفحة الرئيسية'), findsOneWidget);
    expect(find.text('جديد في التطبيق؟'), findsNothing);
  });

  appTest('بطاقة الجولة: «ليس الآن» تخفيها ولا تعود', (tester) async {
    final runtime = await open(tester, welcome: true);
    expect(find.text('جديد في التطبيق؟'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'ابدأ الجولة'), findsOneWidget);

    await tester.tap(find.widgetWithText(ClayButton, 'ليس الآن'));
    await tester.pumpAndSettle();
    expect(find.text('جديد في التطبيق؟'), findsNothing);
    expect((await stateOf(tester, runtime)).prompted, isTrue);

    // التنقل بين التبويبات لا يعيدها.
    await tester.tap(find.text('التلاميذ').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('الرئيسية').last);
    await tester.pumpAndSettle();
    expect(find.text('جديد في التطبيق؟'), findsNothing);
  });

  appTest('بطاقة الجولة: «ابدأ الجولة» تفتح الدرس الأول وتُسجَّل معروضة', (
    tester,
  ) async {
    final runtime = await open(tester, welcome: true);
    await tester.tap(find.widgetWithText(ClayButton, 'ابدأ الجولة'));
    await tester.pumpAndSettle();
    expect(find.text('جولة سريعة في التطبيق'), findsOneWidget);
    expect(find.textContaining('الخطوة 1 من'), findsWidgets);
    expect((await stateOf(tester, runtime)).prompted, isTrue);

    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('جديد في التطبيق؟'), findsNothing);
  });

  appTest('الدرس: التنقل بين الخطوات ثم «تم» يسجّله منتهياً', (tester) async {
    final runtime = await open(tester);
    await goTo(tester, HelpRoutes.lesson('students'));
    final steps = TutorialCatalog.find(AppIdentity.admin, 'students')!.steps;

    expect(find.text('تسجيل تلميذ جديد'), findsOneWidget);
    expect(find.text('الخطوة 1 من ${steps.length}'), findsOneWidget);
    expect(find.text(steps[0].title), findsOneWidget);
    expect(find.text(steps[0].body), findsOneWidget);
    expect(
      tester
          .widget<ClayButton>(find.widgetWithText(ClayButton, 'السابق'))
          .onPressed,
      isNull,
      reason: 'لا خطوة قبل الأولى',
    );

    await tester.tap(find.widgetWithText(ClayButton, 'التالي'));
    await tester.pumpAndSettle();
    expect(find.text('الخطوة 2 من ${steps.length}'), findsOneWidget);
    expect(find.text(steps[1].title), findsOneWidget);

    await tester.tap(find.widgetWithText(ClayButton, 'السابق'));
    await tester.pumpAndSettle();
    expect(find.text(steps[0].title), findsOneWidget);

    for (var i = 1; i < steps.length; i++) {
      await tester.tap(find.widgetWithText(ClayButton, 'التالي'));
      await tester.pumpAndSettle();
    }
    expect(find.text(steps.last.title), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'التالي'), findsNothing);
    expect(
      (await stateOf(tester, runtime)).isDone('students'),
      isFalse,
      reason: 'لم يُنهِ بعد',
    );

    await tester.tap(find.widgetWithText(ClayButton, 'تم'));
    await tester.pumpAndSettle();
    expect(find.text('تسجيل تلميذ جديد'), findsNothing, reason: 'عاد للخلف');
    expect((await stateOf(tester, runtime)).isDone('students'), isTrue);
  });

  appTest('دليل الاستخدام: دروس الإدارة وتقدّم المنتهي منها', (tester) async {
    final runtime = await open(tester);
    final lessons = TutorialCatalog.forApp(AppIdentity.admin);
    await goTo(tester, HelpRoutes.list);

    expect(find.text('دليل الاستخدام'), findsOneWidget);
    expect(find.text('أنهيت 0 من ${lessons.length}'), findsOneWidget);
    expect(find.text(lessons.first.title), findsOneWidget);
    expect(find.text('تم'), findsNothing);

    await runDb(
      tester,
      () => TutorialProgress(
        DevicePreferences(runtime.db),
        'u-owner',
      ).markDone(lessons.first.id),
    );
    await tester.pumpAndSettle();
    expect(find.text('أنهيت 1 من ${lessons.length}'), findsOneWidget);
    expect(find.text('تم'), findsOneWidget);

    await tester.tap(find.text(lessons.first.title));
    await tester.pumpAndSettle();
    expect(find.text('الخطوة 1 من ${lessons.first.steps.length}'), findsOne);
  });

  appTest('تطبيق الأستاذ يعرض دروس الأستاذ لا دروس الإدارة', (tester) async {
    await open(tester, account: _teacher, app: AppIdentity.teacher);
    await goTo(tester, HelpRoutes.list);
    expect(find.text('طلب تغيير موعد أو إلغاء حصة'), findsOneWidget);
    expect(find.text('إنشاء فوج مع تلاميذه'), findsNothing);
  });

  appTest('درس غير موجود: رسالة لا انهيار', (tester) async {
    await open(tester);
    await goTo(tester, HelpRoutes.lesson('zzz'));
    expect(find.text('هذا الدرس غير موجود'), findsOneWidget);
  });

  appTest('زر «؟»: يفتح درس التبويب الحالي', (tester) async {
    await open(tester);
    // الرئيسية: الجولة السريعة.
    await tester.tap(find.byTooltip('شرح هذه الشاشة'));
    await tester.pumpAndSettle();
    expect(find.text('جولة سريعة في التطبيق'), findsOneWidget);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();

    // التلاميذ: درس التسجيل.
    await tester.tap(find.text('التلاميذ').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('شرح هذه الشاشة'));
    await tester.pumpAndSettle();
    expect(find.text('تسجيل تلميذ جديد'), findsOneWidget);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();

    // المزيد: قائمة الدروس كلها.
    await tester.tap(find.text('المزيد').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('شرح هذه الشاشة'));
    await tester.pumpAndSettle();
    expect(find.text('دليل الاستخدام'), findsOneWidget);
    expect(find.textContaining('أنهيت 0 من'), findsOneWidget);
  });

  appTest('«حسابي»: زر دليل الاستخدام يفتح القائمة', (tester) async {
    await open(tester);
    await tester.tap(find.text('حسابي').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'دليل الاستخدام'));
    await tester.pumpAndSettle();
    expect(find.textContaining('أنهيت 0 من'), findsOneWidget);
  });
}
