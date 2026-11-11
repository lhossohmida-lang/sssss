import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';

/// وقت التشغيل (قاعدة، مصادقة، مزامنة). يُمرَّر في `main` عبر
/// `ProviderScope(overrides: [runtimeProvider.overrideWithValue(runtime)])`.
final Provider<AppRuntime> runtimeProvider = Provider<AppRuntime>(
  (ref) => throw StateError('runtimeProvider لم يُمرَّر في ProviderScope'),
);

/// الجلسة الحالية؛ `null` دون تسجيل دخول.
final StreamProvider<AuthSession?> sessionProvider =
    StreamProvider<AuthSession?>((ref) async* {
      final auth = ref.watch(runtimeProvider).auth;
      yield auth.current;
      yield* auth.changes;
    });

/// اسم المدرسة من الإعدادات؛ فارغ إن لم يُحدَّد بعد.
final StreamProvider<String> schoolNameProvider = StreamProvider<String>(
  (ref) => ref.watch(runtimeProvider).db.watchSetting(SettingKeys.schoolName),
);

/// عدد الإشعارات غير المقروءة للمستخدم الحالي.
final StreamProvider<int> unreadCountProvider = StreamProvider.autoDispose<int>(
  (ref) {
    final accountId = ref.watch(
      sessionProvider.select((s) => s.value?.accountId),
    );
    if (accountId == null) return Stream.value(0);
    return ref
        .watch(runtimeProvider)
        .db
        .watchUnreadNotificationCount(accountId);
  },
);

/// إشعارات المستخدم الحالي، الأحدث أولاً (آخر 200).
final StreamProvider<List<NotificationRow>> notificationsProvider =
    StreamProvider.autoDispose<List<NotificationRow>>((ref) {
      final accountId = ref.watch(
        sessionProvider.select((s) => s.value?.accountId),
      );
      if (accountId == null) return Stream.value(const []);
      return ref.watch(runtimeProvider).db.watchNotifications(accountId);
    });

/// هل يحتاج الجهاز إلى إنشاء حساب صاحب المدرسة؟ (الوضع المحلي دون حسابات)
final FutureProvider<bool> needsOwnerSetupProvider =
    FutureProvider.autoDispose<bool>((ref) async {
      final local = ref.watch(runtimeProvider).localGateway;
      if (local == null) return false;
      return local.hasNoAccounts();
    });

/// خدمة إعدادات المدرسة.
final Provider<SettingsService> settingsServiceProvider =
    Provider<SettingsService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return SettingsService(runtime.db, runtime.writer);
    });

/// خدمة المستويات الدراسية.
final Provider<LevelService> levelServiceProvider = Provider<LevelService>((
  ref,
) {
  final runtime = ref.watch(runtimeProvider);
  return LevelService(runtime.db, runtime.writer);
});

/// إعدادات المدرسة، وتتحدث مع كل تغيير (حتى القادم من جهاز آخر).
final StreamProvider<SchoolSettings> schoolSettingsProvider =
    StreamProvider<SchoolSettings>(
      (ref) => ref.watch(settingsServiceProvider).watch(),
    );

/// المستويات الدراسية الحية مرتبة.
final StreamProvider<List<LevelRow>> levelsProvider =
    StreamProvider<List<LevelRow>>(
      (ref) => ref.watch(levelServiceProvider).watchAll(),
    );
