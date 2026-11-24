import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_sms/school_sms.dart';
import 'package:school_ui/school_ui.dart';

/// ساعة الرسائل: الوقت الذي تُحسب به ساعات الهدوء (21:00–07:00) وموعد المؤجَّل. الوقت الحقيقي
/// دائماً في التطبيق، وتثبّتها الاختبارات حتى لا تتأثر بوقت تشغيلها من اليوم.
final Provider<DateTime Function()> smsClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// طابور الرسائل لهذه المدرسة: نسخة واحدة يتقاسمها الإرسال التلقائي وشاشة الرسائل.
final Provider<SmsQueueService> smsQueueServiceProvider =
    Provider<SmsQueueService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return SmsQueueService(
        runtime.db,
        runtime.writer,
        now: ref.watch(smsClockProvider),
      );
    });

/// منصة الإرسال على هذا الجهاز: Android فقط (فيه الشريحة)، وغيره `null`.
/// تستبدلها الاختبارات بمنصة وهمية.
final Provider<SmsDispatchPlatform?> smsPlatformProvider =
    Provider<SmsDispatchPlatform?>(
      (ref) => !kIsWeb && Platform.isAndroid ? AndroidSmsPlatform() : null,
    );

final Provider<SmsSenderDevice> smsSenderDeviceProvider =
    Provider<SmsSenderDevice>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return SmsSenderDevice(runtime.db, runtime.writer);
    });

/// معرّف جهاز الإرسال المعيَّن، أو `null` إن لم يُعيَّن أحد بعد.
final smsSenderDesignatedProvider = StreamProvider.autoDispose<String?>(
  (ref) => ref.watch(smsSenderDeviceProvider).watchDesignated(),
);

/// هل هذا الجهاز هو المعيَّن للإرسال؟
final smsIsSenderDeviceProvider = StreamProvider.autoDispose<bool>(
  (ref) => ref.watch(smsSenderDeviceProvider).watchIsThisDevice(),
);

/// الإرسال التلقائي على هذا الجهاز: يعمل على هاتف Android لمن يملك صلاحية استعمال
/// الرسائل، ولا يرسل منه إلا الجهاز المعيَّن (أول هاتف يفتح الإدارة بصلاحية الإعدادات
/// يصير هو المعيَّن إن لم يوجد). `null` على غير Android أو دون صلاحية.
final Provider<SmsAutoDispatcher?> smsAutoDispatcherProvider =
    Provider<SmsAutoDispatcher?>((ref) {
      final platform = ref.watch(smsPlatformProvider);
      if (platform == null) return null;
      final allowed = ref.watch(
        sessionProvider.select(
          (s) =>
              s.value?.can(PermissionModule.sms, PermissionAction.use) ?? false,
        ),
      );
      if (!allowed) return null;
      final canClaim = ref.watch(
        sessionProvider.select(
          (s) =>
              s.value?.can(PermissionModule.settings, PermissionAction.edit) ??
              false,
        ),
      );
      final runtime = ref.watch(runtimeProvider);
      final queue = ref.watch(smsQueueServiceProvider);
      final clock = ref.watch(smsClockProvider);
      final sender = ref.watch(smsSenderDeviceProvider);
      final preferences = DevicePreferences(runtime.db);
      final worker = SmsDispatchWorker(
        queue: queue,
        settings: SmsSettingsService(runtime.db, runtime.writer),
        platform: platform,
        now: clock,
        // لا نبقي الخدمة الأمامية ساعات في الانتظار: المُرسِل يستأنف بمؤقّت.
        maxScheduledWait: Duration.zero,
      );

      Future<bool> isSender() async {
        var mine = await sender.isThisDevice();
        if (!mine && canClaim) mine = await sender.claimIfUnassigned();
        if (mine &&
            await preferences.read(DevicePreferences.smsPermissionAskedKey) ==
                null) {
          // مرة واحدة في وقت هادئ بدل أن تظهر نافذة الإذن أثناء عمل المدير.
          await preferences.write(DevicePreferences.smsPermissionAskedKey, '1');
          await platform.requestPermissions();
        }
        return mine;
      }

      final dispatcher = SmsAutoDispatcher(
        pendingCounts: queue.watchPendingCount(),
        isSender: isSender,
        run: worker.start,
        stop: worker.stop,
        now: clock,
      )..start();
      ref.onDispose(dispatcher.dispose);
      return dispatcher;
    });

/// حالة الإرسال التلقائي لشاشة الرسائل.
final smsAutoStatusProvider = StreamProvider.autoDispose<SmsAutoStatus>((
  ref,
) async* {
  final dispatcher = ref.watch(smsAutoDispatcherProvider);
  if (dispatcher == null) {
    yield const SmsAutoStatus(SmsAutoState.stopped);
    return;
  }
  yield dispatcher.status;
  yield* dispatcher.statuses;
});

/// يشغّل الإرسال التلقائي مع التطبيق ويستأنفه كلما عاد إلى الواجهة.
class SmsAutoSenderLifecycle extends ConsumerStatefulWidget {
  const SmsAutoSenderLifecycle({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SmsAutoSenderLifecycle> createState() =>
      _SmsAutoSenderLifecycleState();
}

class _SmsAutoSenderLifecycleState extends ConsumerState<SmsAutoSenderLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(smsAutoDispatcherProvider)?.kick();
    }
  }

  @override
  Widget build(BuildContext context) {
    // المراقبة تبقى حيّة ما دام التطبيق مفتوحاً (ويعيد بناءها تغيّر الصلاحيات).
    ref.watch(smsAutoDispatcherProvider);
    return widget.child;
  }
}

/// بطاقة تشرح للمدير ماذا يفعل الإرسال التلقائي الآن وما المطلوب منه إن توقف.
class SmsAutoStatusCard extends ConsumerWidget {
  const SmsAutoStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(smsPlatformProvider);
    final status =
        ref.watch(smsAutoStatusProvider).value ??
        const SmsAutoStatus(SmsAutoState.stopped);
    final designated = ref.watch(smsSenderDesignatedProvider);
    final hasSender = designated.value != null;
    final isSender = ref.watch(smsIsSenderDeviceProvider).value ?? false;
    final canClaim = ref.can(PermissionModule.settings, PermissionAction.edit);
    final dispatcher = ref.watch(smsAutoDispatcherProvider);
    final text = Theme.of(context).textTheme;

    final (ClayTone tone, String title, String? detail) = _describe(
      platform: platform != null,
      status: status,
      hasSender: hasSender,
      senderKnown: !designated.isLoading,
    );

    return ClayCard(
      flat: true,
      child: Padding(
        padding: const EdgeInsets.all(ClaySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: text.titleSmall)),
                ClayBadge(label: _badge(tone), tone: tone),
              ],
            ),
            if (detail != null) ...[
              const SizedBox(height: ClaySpacing.xs),
              Text(detail, style: text.bodySmall),
            ],
            if (dispatcher != null && isSender) ...[
              const SizedBox(height: ClaySpacing.md),
              ClayButton(
                label: status.state == SmsAutoState.blocked
                    ? 'إعادة المحاولة'
                    : 'أرسل الآن',
                icon: ClayIcons.sms,
                kind: ClayButtonKind.secondary,
                expand: true,
                onPressed: status.state == SmsAutoState.sending
                    ? null
                    : dispatcher.kick,
              ),
            ] else if (platform != null &&
                canClaim &&
                status.state == SmsAutoState.otherDevice) ...[
              const SizedBox(height: ClaySpacing.md),
              ClayButton(
                label: 'اجعل هذا الهاتف هو المرسل',
                icon: ClayIcons.sms,
                kind: ClayButtonKind.secondary,
                expand: true,
                onPressed: () async {
                  await ref.read(smsSenderDeviceProvider).claim();
                  ref.read(smsAutoDispatcherProvider)?.kick();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _badge(ClayTone tone) => switch (tone) {
    ClayTone.success => 'يعمل',
    ClayTone.danger => 'متوقف',
    ClayTone.warning => 'يحتاج انتباهك',
    _ => 'تلقائي',
  };

  static (ClayTone, String, String?) _describe({
    required bool platform,
    required SmsAutoStatus status,
    required bool hasSender,
    required bool senderKnown,
  }) {
    if (!platform) {
      if (senderKnown && !hasSender) {
        return (
          ClayTone.warning,
          'لا يوجد هاتف مُعيَّن لإرسال الرسائل',
          'افتح تطبيق الإدارة على هاتف Android فيه شريحة المدرسة '
              'ليبدأ الإرسال التلقائي. إلى ذلك الحين تنتظر الرسائل في الطابور.',
        );
      }
      return (
        ClayTone.info,
        'الرسائل تُرسل تلقائياً من هاتف الإدارة',
        'هذا الجهاز لا يرسل رسائل SMS؛ تظهر هنا حالة كل رسالة بعد إرسالها.',
      );
    }
    return switch (status.state) {
      SmsAutoState.idle => (
        ClayTone.success,
        'الإرسال التلقائي يعمل',
        'تُرسل أي رسالة جديدة فور إضافتها دون أن تضغط شيئاً. أبقِ التطبيق '
            'مفتوحاً أو في الخلفية، واستثنه من توفير البطارية.',
      ),
      SmsAutoState.sending => (
        ClayTone.info,
        'جارٍ إرسال الرسائل',
        'تُرسل واحدة بعد أخرى من شريحة هذا الهاتف.',
      ),
      SmsAutoState.waiting => (
        ClayTone.info,
        'رسائل مؤجلة حتى ${_time(status.until)}',
        'لا تُرسل رسائل بين الساعة 21:00 و07:00 لئلا تُزعج الأولياء؛ '
            'تُرسل تلقائياً عند الموعد.',
      ),
      SmsAutoState.otherDevice => (
        ClayTone.info,
        'هاتف إدارة آخر هو المرسل',
        'تُرسل الرسائل تلقائياً من ذلك الهاتف.',
      ),
      SmsAutoState.blocked => (
        ClayTone.danger,
        'توقف الإرسال التلقائي',
        status.message ?? 'تعذّر الإرسال',
      ),
      SmsAutoState.stopped => (
        ClayTone.neutral,
        'الإرسال التلقائي متوقف على هذا الجهاز',
        'يلزم صلاحية استعمال الرسائل لحسابك.',
      ),
    };
  }

  static String _time(DateTime? time) => time == null
      ? 'الصباح'
      : '${time.day}/${time.month} '
            '${time.hour.toString().padLeft(2, '0')}:'
            '${time.minute.toString().padLeft(2, '0')}';
}
