import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_button.dart';
import '../clay/clay_container.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'providers.dart';

/// إعداد التحديث التلقائي من وقت البناء. يمرّره مسار الإصدار للبناء العام وحده؛ وغيابه (التطوير وبناء مدرسة
/// خاص) يعطّل التحديث التلقائي فلا يستبدل جهازٌ بناءَه الخاص بنسخة عامة.
abstract final class UpdateBuildConfig {
  /// وسم الإصدار المثبَّت، مثل `preview-7`.
  static const String release = String.fromEnvironment('APP_RELEASE');

  /// مستودع الإصدارات `المالك/المستودع`.
  static const String repo = String.fromEnvironment('UPDATE_REPO');
}

/// اسم ملف هذا التطبيق في الإصدار على النظام الحالي، أو `null` حيث لا تحديث تلقائي.
String? updateAssetName(AppIdentity app, {TargetPlatform? platform}) {
  final target = platform ?? defaultTargetPlatform;
  if (target == TargetPlatform.android) return 'school-${app.name}.apk';
  if (target == TargetPlatform.windows && app == AppIdentity.admin) {
    return 'school-admin-setup.exe';
  }
  return null;
}

/// Android: يفتح نافذة تثبيت النظام للملف المنزَّل (لا تثبيت صامتاً خارج المتجر؛ يوافق المستخدم).
class AndroidApkInstaller implements UpdateInstaller {
  const AndroidApkInstaller();

  @override
  Future<void> install(File file, UpdateRelease release) async {
    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    switch (result.type) {
      case ResultType.done:
        return;
      case ResultType.permissionDenied:
        throw const UpdateException(
          'اسمح لهذا التطبيق بتثبيت التطبيقات من إعدادات الهاتف ثم اضغط «تثبيت» من جديد',
        );
      case ResultType.fileNotFound:
        throw const UpdateException('ملف التحديث لم يعد موجوداً');
      case ResultType.noAppToOpen:
      case ResultType.error:
        throw const UpdateException('تعذّر فتح مثبّت النظام');
    }
  }
}

/// Windows: يشغّل مثبّت النسخة الجديدة صامتاً ثم يغلق التطبيق ليحلّ محلّه ويُعاد تشغيله (`/relaunch=1`).
class WindowsSetupInstaller implements UpdateInstaller {
  const WindowsSetupInstaller();

  @override
  Future<void> install(File file, UpdateRelease release) async {
    await Process.start(file.path, const [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
      '/relaunch=1',
    ], mode: ProcessStartMode.detached);
    // يُمهَل المثبّت لحظة ليبدأ قبل أن يغلق التطبيق نفسه.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    exit(0);
  }
}

/// هل الشبكة الحالية غير محدودة الاستهلاك (واي فاي أو كابل)؟ على Windows نعم دائماً.
Future<bool> unmeteredNetwork() async {
  if (defaultTargetPlatform != TargetPlatform.android) return true;
  try {
    final kinds = await Connectivity().checkConnectivity();
    return kinds.contains(ConnectivityResult.wifi) ||
        kinds.contains(ConnectivityResult.ethernet);
  } on Object {
    return false;
  }
}

/// متحكم التحديث التلقائي لهذا التطبيق، أو `null` إن كان معطّلاً (بناء تطوير/خاص أو نظام بلا تحديث).
final Provider<UpdateController?>
updateControllerProvider = Provider<UpdateController?>((ref) {
  final runtime = ref.watch(runtimeProvider);
  final asset = updateAssetName(runtime.app);
  if (asset == null ||
      UpdateBuildConfig.repo.isEmpty ||
      ReleaseVersion.tryParse(UpdateBuildConfig.release) == null) {
    return null;
  }
  final controller = UpdateController(
    currentTag: UpdateBuildConfig.release,
    source: GitHubUpdateSource(repo: UpdateBuildConfig.repo, assetName: asset),
    downloader: UpdateDownloader(
      directory: Directory(
        '${runtime.photosDirectory.parent.path}${Platform.pathSeparator}updates',
      ),
    ),
    installer: defaultTargetPlatform == TargetPlatform.windows
        ? const WindowsSetupInstaller()
        : const AndroidApkInstaller(),
    canDownloadAutomatically: unmeteredNetwork,
  )..start();
  ref.onDispose(controller.dispose);
  return controller;
});

String _megabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(0)} ميغابايت';

/// شريط التحديث أعلى المحتوى: تنزيل جارٍ، أو نسخة جاهزة للتثبيت، أو نسخة تنتظر موافقة (شبكة بيانات).
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({this.controller, super.key});

  /// للاختبار؛ الافتراضي متحكم [updateControllerProvider].
  final UpdateController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = controller ?? ref.watch(updateControllerProvider);
    if (update == null) return const SizedBox.shrink();
    return ValueListenableBuilder<UpdateState>(
      valueListenable: update.state,
      builder: (context, state, _) => switch (state) {
        UpdateDownloading(:final release, :final fraction) => _Card(
          icon: Icons.downloading_rounded,
          title: 'جارٍ تنزيل النسخة الجديدة ${release.tag}',
          progress: fraction,
          detail: '${(fraction * 100).round()}٪',
        ),
        UpdateReady(:final release) => _Card(
          icon: Icons.system_update_rounded,
          title: 'نسخة جديدة (${release.tag}) جاهزة للتثبيت',
          detail: defaultTargetPlatform == TargetPlatform.windows
              ? 'سيُغلق التطبيق ثم يُفتح من جديد بعد التثبيت'
              : 'ستظهر نافذة تثبيت النظام للموافقة',
          actionLabel: 'تثبيت الآن',
          onAction: () => unawaited(update.install()),
        ),
        UpdateAvailable(:final release) => _Card(
          icon: Icons.cloud_download_rounded,
          title: 'نسخة جديدة (${release.tag}) متاحة',
          detail:
              'حجمها ${_megabytes(release.size)}؛ لن تُنزَّل عبر بيانات الهاتف دون موافقتك',
          actionLabel: 'تنزيل',
          onAction: () => unawaited(update.downloadNow()),
          dismissLabel: 'لاحقاً',
          onDismiss: update.dismiss,
        ),
        UpdateInstalling() => const _Card(
          icon: Icons.install_mobile_rounded,
          title: 'جارٍ بدء التثبيت…',
          progress: null,
          busy: true,
        ),
        UpdateFailed(:final message, release: != null) => _Card(
          icon: Icons.error_outline_rounded,
          title: message,
          error: true,
          actionLabel: 'إعادة المحاولة',
          // الملف المنزَّل سابقاً يُعاد استعماله فوراً، فالمحاولة الثانية تعيد «تثبيت الآن» عادةً.
          onAction: () => unawaited(update.downloadNow()),
          dismissLabel: 'إخفاء',
          onDismiss: update.dismiss,
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    this.detail,
    this.progress = -1,
    this.busy = false,
    this.error = false,
    this.actionLabel,
    this.onAction,
    this.dismissLabel,
    this.onDismiss,
  });

  final IconData icon;
  final String title;
  final String? detail;

  /// `-1` بلا شريط، `null` شريط غير محدد، وإلا نسبة من 0 إلى 1.
  final double? progress;
  final bool busy;
  final bool error;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? dismissLabel;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ClaySpacing.screenPadding,
        ClaySpacing.sm,
        ClaySpacing.screenPadding,
        0,
      ),
      child: ClayCard(
        flat: true,
        padding: const EdgeInsets.all(ClaySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(icon, color: error ? p.status.danger : p.accent),
                const SizedBox(width: ClaySpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleSmall),
                      if (detail != null) Text(detail!, style: text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            if (progress != -1 && !busy) ...[
              const SizedBox(height: ClaySpacing.sm),
              LinearProgressIndicator(value: progress),
            ],
            if (actionLabel != null || dismissLabel != null) ...[
              const SizedBox(height: ClaySpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (dismissLabel != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: ClaySpacing.sm,
                      ),
                      child: ClayButton(
                        label: dismissLabel!,
                        kind: ClayButtonKind.secondary,
                        onPressed: onDismiss,
                      ),
                    ),
                  if (actionLabel != null)
                    ClayButton(label: actionLabel!, onPressed: onAction),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// قسم «التحديث» في شاشة الحساب: النسخة الحالية وفحص يدوي.
class UpdateSection extends ConsumerWidget {
  const UpdateSection({this.controller, super.key});

  final UpdateController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = controller ?? ref.watch(updateControllerProvider);
    final text = Theme.of(context).textTheme;
    const tag = UpdateBuildConfig.release;
    if (update == null) {
      return Text(
        tag.isEmpty
            ? 'التحديث التلقائي غير مفعّل في هذا البناء'
            : 'الإصدار الحالي: $tag',
        style: text.bodySmall,
      );
    }
    return ValueListenableBuilder<UpdateState>(
      valueListenable: update.state,
      builder: (context, state, _) {
        final busy = state is UpdateChecking || state is UpdateDownloading;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الإصدار الحالي: ${update.currentTag}',
              style: text.bodyMedium,
            ),
            const SizedBox(height: ClaySpacing.xs),
            Text(_status(state), style: text.bodySmall),
            const SizedBox(height: ClaySpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ClayButton(
                label: 'التحقق من وجود تحديث',
                icon: Icons.refresh_rounded,
                kind: ClayButtonKind.secondary,
                loading: busy,
                onPressed: () => unawaited(update.checkNow(manual: true)),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _status(UpdateState state) => switch (state) {
    UpdateChecking() => 'جارٍ البحث عن تحديث…',
    UpdateUpToDate() => 'أنت على أحدث نسخة',
    UpdateAvailable(:final release) => 'نسخة جديدة متاحة: ${release.tag}',
    UpdateDownloading(:final release) => 'جارٍ تنزيل ${release.tag}…',
    UpdateReady(:final release) => 'نسخة جديدة جاهزة للتثبيت: ${release.tag}',
    UpdateInstalling() => 'جارٍ بدء التثبيت…',
    UpdateFailed(:final message) => message,
    UpdateIdle() => 'تُفحص النسخ الجديدة تلقائياً وتُنزَّل في الخلفية',
  };
}
