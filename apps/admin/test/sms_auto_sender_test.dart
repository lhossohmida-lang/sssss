import 'package:admin/admin_tabs.dart';
import 'package:admin/screens/sms_auto_sender.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_sms/school_sms.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;

const smsOnly = TestAccount(
  id: 'u-sms-user',
  email: 'sms-user@school.local',
  password: 'sms-user-pass-1',
  role: UserRole.worker,
  entityId: 'w-sms-user',
  displayName: 'عامل الرسائل',
  permissions: '{"sms":["view","use"]}',
);

const smsViewOnly = TestAccount(
  id: 'u-sms-view',
  email: 'sms-view@school.local',
  password: 'sms-view-pass-1',
  role: UserRole.worker,
  entityId: 'w-sms-view',
  displayName: 'مشاهد الرسائل',
  permissions: '{"sms":["view"]}',
);

/// منصة إرسال وهمية: تحفظ ما أُرسل وتتحكم في منح الإذن.
class _FakeSmsPlatform implements SmsDispatchPlatform {
  bool granted = true;
  int permissionRequests = 0;
  final List<String> sent = [];

  @override
  Future<bool> requestPermissions() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<List<SmsSimCard>> availableSimCards() async => const [
    SmsSimCard(
      slotIndex: 0,
      subscriptionId: 1,
      displayName: 'SIM',
      carrierName: 'Carrier',
    ),
  ];

  @override
  Future<void> startForegroundService() async {}

  @override
  Future<void> stopForegroundService() async {}

  @override
  Future<void> send(SmsQueueRow message, {required int simSlotIndex}) async {
    sent.add(message.message);
  }
}

/// يشغّل تطبيق الإدارة كما في الإنتاج: المُرسِل التلقائي ملفوف حول التطبيق، ومنصة
/// الرسائل وهمية، ثم يدخل بالحساب.
Future<AppRuntime> bootWithSms(
  WidgetTester tester, {
  required TestAccount account,
  required SmsDispatchPlatform? platform,
  Future<void> Function(AppDatabase db)? seed,
}) async {
  final runtime = (await tester.runAsync(
    () => startTestRuntime(app: AppIdentity.admin, accounts: [account]),
  ))!;
  addTearDown(() async {
    await tester.runAsync(() async {
      await runtime.auth.dispose();
      await runtime.db.close();
    });
  });
  if (seed != null) await tester.runAsync(() => seed(runtime.db));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runtimeProvider.overrideWithValue(runtime),
        sessionCloserEnabledProvider.overrideWithValue(false),
        smsPlatformProvider.overrideWithValue(platform),
      ],
      child: SmsAutoSenderLifecycle(
        child: SchoolApp(tabs: adminTabs, pages: adminPages),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  await loginWith(tester, account.email, account.password);
  return runtime;
}

/// يدفع إطارات كافية ليكمل الإرسال التلقائي سلسلته (قراءات وكتابات قاعدة).
Future<void> letItSend(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> enqueue(
  WidgetTester tester,
  AppRuntime runtime,
  String phone,
  String message,
) => runDb(
  tester,
  () => SmsQueueService(
    runtime.db,
    runtime.writer,
    now: () => DateTime(2026, 11, 17, 10),
  ).enqueue(phone: phone, message: message),
);

void main() {
  appTest('رسالة تُضاف إلى الطابور فتُرسل وحدها من هاتف المالك', (
    tester,
  ) async {
    final platform = _FakeSmsPlatform();
    final runtime = await bootWithSms(
      tester,
      account: owner,
      platform: platform,
    );
    await letItSend(tester);

    // أول هاتف يفتح الإدارة بصلاحية الإعدادات يصير المرسل دون سؤال.
    final sender = SmsSenderDevice(runtime.db, runtime.writer);
    expect(await runDb(tester, sender.isThisDevice), isTrue);
    expect(platform.permissionRequests, 1, reason: 'طلب الإذن مرة هادئة');

    await enqueue(tester, runtime, '0550123456', 'وصل الدفع رقم 1');
    await enqueue(tester, runtime, '0550123457', 'غياب التلميذ');
    await letItSend(tester);

    expect(platform.sent, ['وصل الدفع رقم 1', 'غياب التلميذ']);
    final rows = await runDb(
      tester,
      () => runtime.db.select(runtime.db.smsQueue).get(),
    );
    expect(rows.map((row) => row.status).toSet(), {SmsStatus.sent.code});
  });

  appTest('هاتف آخر معيَّن للإرسال: هذا الهاتف لا يرسل ويشرح ذلك', (
    tester,
  ) async {
    final platform = _FakeSmsPlatform();
    final runtime = await bootWithSms(
      tester,
      account: owner,
      platform: platform,
      seed: (db) async {
        await db
            .into(db.settings)
            .insert(
              SettingsCompanion.insert(
                key: SettingKeys.smsSenderDevice,
                value: 'phone-of-the-school',
                updatedAt: 1,
              ),
            );
      },
    );
    await letItSend(tester);
    await enqueue(tester, runtime, '0550123456', 'رسالة');
    await letItSend(tester);

    expect(platform.sent, isEmpty);
    await openMoreEntry(tester, 'الرسائل القصيرة');
    await letItSend(tester);
    expect(find.text('هاتف إدارة آخر هو المرسل'), findsOneWidget);

    // المالك يقرر أن هذا الهاتف هو المرسل: تُرسل الرسالة العالقة فوراً.
    await tester.tap(
      find.widgetWithText(ClayButton, 'اجعل هذا الهاتف هو المرسل'),
    );
    await letItSend(tester);
    expect(platform.sent, ['رسالة']);
  });

  appTest('نقص إذن الرسائل: بطاقة تشرح السبب وزر يعيد المحاولة', (
    tester,
  ) async {
    final platform = _FakeSmsPlatform()..granted = false;
    final runtime = await bootWithSms(
      tester,
      account: owner,
      platform: platform,
    );
    await enqueue(tester, runtime, '0550123456', 'رسالة');
    await letItSend(tester);
    expect(platform.sent, isEmpty);

    await openMoreEntry(tester, 'الرسائل القصيرة');
    await letItSend(tester);
    expect(find.text('توقف الإرسال التلقائي'), findsOneWidget);
    expect(find.textContaining('السماح بإرسال الرسائل'), findsWidgets);

    platform.granted = true;
    await tester.tap(find.widgetWithText(ClayButton, 'إعادة المحاولة'));
    await letItSend(tester);
    expect(platform.sent, ['رسالة']);
    expect(find.text('الإرسال التلقائي يعمل'), findsOneWidget);
  });

  appTest('من يملك عرض الرسائل فقط لا يرسل ولا يعيّن نفسه مرسلاً', (
    tester,
  ) async {
    final platform = _FakeSmsPlatform();
    final runtime = await bootWithSms(
      tester,
      account: smsViewOnly,
      platform: platform,
    );
    await enqueue(tester, runtime, '0550123456', 'رسالة');
    await letItSend(tester);

    expect(platform.sent, isEmpty);
    expect(platform.permissionRequests, 0);
    expect(
      await runDb(
        tester,
        () => SmsSenderDevice(runtime.db, runtime.writer).designated(),
      ),
      isNull,
    );
  });

  appTest(
    'عامل بصلاحية الاستعمال دون الإعدادات: يرسل إن عُيِّن ولا يعيّن نفسه',
    (tester) async {
      final platform = _FakeSmsPlatform();
      final runtime = await bootWithSms(
        tester,
        account: smsOnly,
        platform: platform,
      );
      await enqueue(tester, runtime, '0550123456', 'رسالة');
      await letItSend(tester);
      expect(platform.sent, isEmpty, reason: 'لا مرسل معيَّن بعد');

      // المالك عيّن هذا الهاتف (يصل الإعداد بالمزامنة).
      await runDb(tester, () async {
        await SmsSenderDevice(runtime.db, runtime.writer).claim();
      });
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SchoolApp)),
      );
      container.read(smsAutoDispatcherProvider)!.kick();
      await letItSend(tester);
      expect(platform.sent, ['رسالة']);
    },
  );

  appTest('الحاسوب لا يرسل: البطاقة تطلب هاتف Android إن لم يوجد مرسل', (
    tester,
  ) async {
    await bootWithSms(tester, account: owner, platform: null);
    await openMoreEntry(tester, 'الرسائل القصيرة');
    await letItSend(tester);
    expect(find.text('لا يوجد هاتف مُعيَّن لإرسال الرسائل'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'أرسل الآن'), findsNothing);
  });

  appTest('الحاسوب مع مرسل معيَّن: يشرح أن الرسائل تُرسل من الهاتف', (
    tester,
  ) async {
    await bootWithSms(
      tester,
      account: owner,
      platform: null,
      seed: (db) async {
        await db
            .into(db.settings)
            .insert(
              SettingsCompanion.insert(
                key: SettingKeys.smsSenderDevice,
                value: 'phone-of-the-school',
                updatedAt: 1,
              ),
            );
      },
    );
    await openMoreEntry(tester, 'الرسائل القصيرة');
    await letItSend(tester);
    expect(find.text('الرسائل تُرسل تلقائياً من هاتف الإدارة'), findsOneWidget);
  });
}
