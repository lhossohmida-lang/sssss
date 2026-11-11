import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';

const owner = TestAccount(
  id: 'u-owner',
  email: 'owner@school.local',
  password: 'owner-pass-1',
  role: UserRole.owner,
  displayName: 'المدير',
);

const newWorker = TestAccount(
  id: 'u-worker',
  email: 'worker@school.local',
  password: 'temp-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'عامل الاستقبال',
  mustChangePassword: true,
  permissions: '{"students":["view"],"scanner":["use"]}',
);

final tabs = [
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
    requires: PermissionModule.students,
    builder: (_) => const Text('صفحة التلاميذ'),
  ),
  AppTab(
    path: '/payments',
    destination: const ClayDestination(
      label: 'المدفوعات',
      icon: ClayIcons.payments,
    ),
    requires: PermissionModule.payments,
    builder: (_) => const Text('صفحة المدفوعات'),
  ),
];

/// يشغّل التطبيق على وقت تشغيل اختباري. التطبيق يبدأ بشاشة البداية.
Future<AppRuntime> boot(
  WidgetTester tester, {
  List<TestAccount> accounts = const [owner],
  AppIdentity app = AppIdentity.admin,
  bool signedIn = false,
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final runtime = (await tester.runAsync(
    () => startTestRuntime(app: app, accounts: accounts),
  ))!;
  if (signedIn) {
    await tester.runAsync(
      () => runtime.auth.signIn(
        email: accounts.first.email,
        password: accounts.first.password,
      ),
    );
  }
  addTearDown(() async {
    await tester.runAsync(() async {
      await runtime.auth.dispose();
      await runtime.db.close();
    });
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [runtimeProvider.overrideWithValue(runtime)],
      child: SchoolApp(tabs: tabs),
    ),
  );
  return runtime;
}

/// يشغّل اختبار واجهة ثم يفكّ الشجرة ويُفرغ مؤقتات drift المعلّقة (فتح
/// استعلام متدفق يترك مؤقتاً صفرياً عند إغلاقه) قبل أن يتحقق الإطار منها.
void shellTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

/// يتجاوز شاشة البداية.
Future<void> passSplash(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> fillField(WidgetTester tester, String label, String text) async {
  final field = find.ancestor(
    of: find.text(label),
    matching: find.byType(Column),
  );
  await tester.enterText(
    find.descendant(of: field.first, matching: find.byType(TextField)),
    text,
  );
}

Future<void> tapButton(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(ClayButton, label));
  await tester.pumpAndSettle();
}

void main() {
  group('شاشة البداية', () {
    shellTest('تعرض اسم التطبيق واسم المدرسة ثم تنتقل إلى الدخول', (
      tester,
    ) async {
      final runtime = await boot(tester);
      await tester.runAsync(
        () => runtime.writer.db
            .into(runtime.db.settings)
            .insert(
              SettingsCompanion.insert(
                key: SettingKeys.schoolName,
                value: 'مدرسة النجاح',
                updatedAt: 1,
              ),
            ),
      );
      await tester.pump();
      expect(find.text('الإدارة'), findsOneWidget);
      expect(find.text('مدرسة النجاح'), findsOneWidget);
      await passSplash(tester);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
    });

    shellTest('الواجهة عربية من اليمين إلى اليسار', (tester) async {
      await boot(tester);
      await passSplash(tester);
      final context = tester.element(find.text('تسجيل الدخول'));
      expect(Directionality.of(context), TextDirection.rtl);
    });
  });

  group('تسجيل الدخول', () {
    shellTest('حقول فارغة: أخطاء بالعربية دون اتصال', (tester) async {
      await boot(tester);
      await passSplash(tester);
      await tapButton(tester, 'دخول');
      expect(find.text('أدخل البريد'), findsOneWidget);
      expect(find.text('أدخل كلمة السر'), findsOneWidget);
    });

    shellTest('كلمة سر خاطئة: رسالة واضحة وبقاء في الشاشة', (tester) async {
      await boot(tester);
      await passSplash(tester);
      await fillField(tester, 'البريد', 'owner@school.local');
      await fillField(tester, 'كلمة السر', 'wrong-password');
      await tapButton(tester, 'دخول');
      expect(find.text('البريد أو كلمة السر غير صحيحة'), findsOneWidget);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
    });

    shellTest('دخول صحيح ينقل إلى أول تبويب', (tester) async {
      final runtime = await boot(tester);
      await passSplash(tester);
      await fillField(tester, 'البريد', 'owner@school.local');
      await fillField(tester, 'كلمة السر', 'owner-pass-1');
      await tapButton(tester, 'دخول');
      expect(runtime.auth.current?.role, UserRole.owner);
      expect(find.text('صفحة الرئيسية'), findsOneWidget);
      expect(find.text('تسجيل الدخول'), findsNothing);
    });

    shellTest('الجلسة المحفوظة تتجاوز الدخول', (tester) async {
      await boot(tester, signedIn: true);
      await passSplash(tester);
      expect(find.text('صفحة الرئيسية'), findsOneWidget);
    });

    shellTest('إظهار كلمة السر وإخفاؤها', (tester) async {
      await boot(tester);
      await passSplash(tester);
      TextField password() => tester.widget<TextField>(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('كلمة السر'),
                matching: find.byType(Column),
              )
              .first,
          matching: find.byType(TextField),
        ),
      );
      expect(password().obscureText, isTrue);
      await tester.tap(find.byTooltip('إظهار كلمة السر'));
      await tester.pump();
      expect(password().obscureText, isFalse);
    });
  });

  group('تغيير كلمة السر عند أول دخول', () {
    shellTest('الدخول بكلمة مؤقتة يفرض شاشة التغيير ثم يفتح التطبيق', (
      tester,
    ) async {
      final runtime = await boot(tester, accounts: [newWorker]);
      await passSplash(tester);
      await fillField(tester, 'البريد', 'worker@school.local');
      await fillField(tester, 'كلمة السر', 'temp-pass-1');
      await tapButton(tester, 'دخول');
      expect(find.text('اختر كلمة سر جديدة'), findsOneWidget);
      expect(find.text('صفحة الرئيسية'), findsNothing);

      // قصيرة ثم غير متطابقة.
      await fillField(tester, 'كلمة السر الجديدة', 'short');
      await fillField(tester, 'تأكيد كلمة السر', 'short');
      await tapButton(tester, 'حفظ ومتابعة');
      expect(find.textContaining('8 رموز على الأقل'), findsWidgets);
      await fillField(tester, 'كلمة السر الجديدة', 'long-enough-1');
      await fillField(tester, 'تأكيد كلمة السر', 'different-1');
      await tapButton(tester, 'حفظ ومتابعة');
      expect(find.text('كلمتا السر غير متطابقتين'), findsOneWidget);

      await fillField(tester, 'تأكيد كلمة السر', 'long-enough-1');
      await tapButton(tester, 'حفظ ومتابعة');
      expect(runtime.auth.current?.mustChangePassword, isFalse);
      expect(find.text('صفحة الرئيسية'), findsOneWidget);
    });

    shellTest('لا يمكن تجاوزها برابط مباشر', (tester) async {
      final runtime = await boot(tester, accounts: [newWorker], signedIn: true);
      await passSplash(tester);
      expect(find.text('اختر كلمة سر جديدة'), findsOneWidget);
      expect(runtime.auth.isReady, isFalse);
    });

    shellTest('زر الخروج يعيد إلى الدخول', (tester) async {
      await boot(tester, accounts: [newWorker], signedIn: true);
      await passSplash(tester);
      await tapButton(tester, 'خروج');
      expect(find.text('تسجيل الدخول'), findsOneWidget);
    });
  });

  group('هيكل التنقل', () {
    shellTest('صاحب المدرسة يرى كل التبويبات', (tester) async {
      await boot(tester, signedIn: true);
      await passSplash(tester);
      for (final label in ['الرئيسية', 'التلاميذ', 'المدفوعات']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });

    shellTest('العامل يرى التبويبات المصرَّح بها فقط', (tester) async {
      const worker = TestAccount(
        id: 'u-w2',
        email: 'w2@school.local',
        password: 'worker-pass-1',
        role: UserRole.worker,
        entityId: 'w2',
        displayName: 'عامل',
        permissions: '{"students":["view"]}',
      );
      await boot(tester, accounts: [worker], signedIn: true);
      await passSplash(tester);
      expect(find.text('التلاميذ'), findsWidgets);
      expect(find.text('المدفوعات'), findsNothing);
    });

    shellTest('التنقل بين التبويبات يبدّل الصفحة', (tester) async {
      await boot(tester, signedIn: true);
      await passSplash(tester);
      await tester.tap(find.text('التلاميذ').last);
      await tester.pumpAndSettle();
      expect(find.text('صفحة التلاميذ'), findsOneWidget);
      await tester.tap(find.text('المدفوعات').last);
      await tester.pumpAndSettle();
      expect(find.text('صفحة المدفوعات'), findsOneWidget);
    });

    shellTest('الخروج يعيد إلى الدخول ويمحو الجلسة', (tester) async {
      final runtime = await boot(tester, signedIn: true);
      await passSplash(tester);
      await tester.runAsync(runtime.auth.signOut);
      await tester.pumpAndSettle();
      expect(find.text('تسجيل الدخول'), findsOneWidget);
    });

    shellTest('على شاشة عريضة تظهر القائمة الجانبية باسم المستخدم', (
      tester,
    ) async {
      await boot(tester, signedIn: true);
      tester.view.physicalSize = const Size(1280, 800);
      await passSplash(tester);
      expect(find.byType(ClaySidebar), findsOneWidget);
      expect(find.text('المدير'), findsWidgets);
      expect(find.byType(ClayBottomNav), findsNothing);
    });
  });

  group('الإشعارات', () {
    Future<void> notify(
      WidgetTester tester,
      AppRuntime runtime,
      String id,
      String title, {
      int? readAt,
      String user = 'u-owner',
    }) => tester.runAsync(
      () => runtime.db
          .into(runtime.db.notifications)
          .insert(
            NotificationsCompanion.insert(
              id: id,
              // وقت محلي ثابت فلا يتأثر الاختبار بمنطقة جهاز التشغيل.
              createdAt: DateTime(2026, 11, 10, 12, 30).millisecondsSinceEpoch,
              updatedAt: 1,
              userId: user,
              title: title,
              body: 'تفاصيل $title',
              kind: 'test',
              readAt: Value(readAt),
            ),
          ),
    );

    shellTest('الجرس يعرض عدد غير المقروء', (tester) async {
      final runtime = await boot(tester, signedIn: true);
      await notify(tester, runtime, 'n1', 'طلب جديد');
      await notify(tester, runtime, 'n2', 'قديم', readAt: 5);
      await notify(tester, runtime, 'n3', 'لغيره', user: 'someone-else');
      await passSplash(tester);
      expect(find.byTooltip('الإشعارات (1 غير مقروءة)'), findsOneWidget);
    });

    shellTest('القائمة والتعليم كمقروء', (tester) async {
      final runtime = await boot(tester, signedIn: true);
      await notify(tester, runtime, 'n1', 'طلب جديد');
      await passSplash(tester);
      await tester.tap(find.byTooltip('الإشعارات (1 غير مقروءة)'));
      await tester.pumpAndSettle();
      expect(find.text('طلب جديد'), findsOneWidget);
      expect(find.text('10/11/2026 12:30'), findsOneWidget);

      await tester.tap(find.text('طلب جديد'));
      await tester.pumpAndSettle();
      final row = await tester.runAsync(
        () => (runtime.db.select(
          runtime.db.notifications,
        )..where((t) => t.id.equals('n1'))).getSingle(),
      );
      expect(row!.readAt, isNotNull);
      // التعليم مسجَّل في سجل العمليات وطابور المزامنة.
      final queued = await tester.runAsync(
        () => runtime.db.select(runtime.db.outbox).get(),
      );
      expect(queued!.any((o) => o.targetTable == 'notifications'), isTrue);
    });

    shellTest('لا إشعارات: حالة فارغة، والرجوع إلى الرئيسية', (tester) async {
      await boot(tester, signedIn: true);
      await passSplash(tester);
      await tester.tap(find.byTooltip('الإشعارات'));
      await tester.pumpAndSettle();
      expect(find.text('لا توجد إشعارات'), findsOneWidget);
      await tester.tap(find.byTooltip('رجوع'));
      await tester.pumpAndSettle();
      expect(find.text('صفحة الرئيسية'), findsOneWidget);
    });
  });

  group('الوضع المحلي (إعداد أول مرة)', () {
    shellTest('جهاز بلا حسابات: إنشاء حساب صاحب المدرسة ثم الدخول', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final runtime = (await tester.runAsync(
        () => startTestRuntime(localMode: true),
      ))!;
      addTearDown(() async {
        await tester.runAsync(() async {
          await runtime.auth.dispose();
          await runtime.db.close();
        });
      });
      expect(runtime.isLocalMode, isTrue);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [runtimeProvider.overrideWithValue(runtime)],
          child: SchoolApp(tabs: tabs),
        ),
      );
      await passSplash(tester);
      await tester.pumpAndSettle();
      expect(find.text('إعداد أول مرة'), findsOneWidget);
      expect(find.text('وضع محلي: دون خادم'), findsOneWidget);

      await fillField(tester, 'اسمك', 'مدير المدرسة');
      await fillField(tester, 'البريد', 'owner@school.com');
      await fillField(tester, 'كلمة السر', 'owner-pass-1');
      await fillField(tester, 'تأكيد كلمة السر', 'owner-pass-1');
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(ClayButton, 'إنشاء الحساب'));
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      await tester.pumpAndSettle();
      expect(runtime.auth.current?.role, UserRole.owner);
      expect(find.text('صفحة الرئيسية'), findsOneWidget);
    });
  });
}
