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

/// خدمة المواد، وقائمتها الحية مع أسماء المستويات.
final Provider<SubjectService> subjectServiceProvider =
    Provider<SubjectService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return SubjectService(runtime.db, runtime.writer);
    });

final StreamProvider<List<SubjectItem>> subjectsProvider =
    StreamProvider<List<SubjectItem>>(
      (ref) => ref.watch(subjectServiceProvider).watchAll(),
    );

/// خدمة القاعات، وقائمتها الحية.
final Provider<RoomService> roomServiceProvider = Provider<RoomService>((ref) {
  final runtime = ref.watch(runtimeProvider);
  return RoomService(runtime.db, runtime.writer);
});

final StreamProvider<List<RoomRow>> roomsProvider =
    StreamProvider<List<RoomRow>>(
      (ref) => ref.watch(roomServiceProvider).watchAll(),
    );

/// هل يملك المستخدم الحالي [action] على [module]؟ يعيد بناء الودجت عند تغيّر
/// الصلاحية فقط (`select`)، لا مع كل تغيّر في الجلسة.
extension AccessRef on WidgetRef {
  bool can(PermissionModule module, PermissionAction action) => watch(
    sessionProvider.select((s) => s.value?.can(module, action) ?? false),
  );
}

/// منشئ حسابات الدخول (تطبيق الإدارة فقط). يرمي إن لم يكن متاحاً في هذا
/// التطبيق أو دون خادم مهيّأ.
final Provider<AccountService> accountServiceProvider =
    Provider<AccountService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      final provisioner = runtime.provisioner;
      if (provisioner == null) {
        throw StateError('إنشاء الحسابات غير متاح في هذا التطبيق');
      }
      return AccountService(runtime.db, runtime.writer, provisioner);
    });

/// خدمة الأساتذة وقائمتهم الحية.
final Provider<TeacherService> teacherServiceProvider =
    Provider<TeacherService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return TeacherService(
        runtime.db,
        runtime.writer,
        ref.watch(accountServiceProvider),
      );
    });

final StreamProvider<List<TeacherItem>> teachersProvider =
    StreamProvider<List<TeacherItem>>(
      (ref) => ref.watch(teacherServiceProvider).watchAll(),
    );

/// استعلامات قائمة التلاميذ.
final Provider<StudentQueries> studentQueriesProvider =
    Provider<StudentQueries>(
      (ref) => StudentQueries(ref.watch(runtimeProvider).db),
    );

/// مفتاح صفحة التلاميذ: نص البحث وعدد ما يُحمَّل.
typedef StudentPageKey = ({String query, int limit});

/// صفحة من التلاميذ مطابقة للبحث، وتتحدث مع كل تغيير.
final studentPageProvider = StreamProvider.family<StudentPage, StudentPageKey>(
  (ref, key) => ref
      .watch(studentQueriesProvider)
      .watchPage(query: key.query, limit: key.limit),
);

/// حفظ صور التلاميذ والأساتذة (ضغط، تخزين محلي، رفع لاحق).
final Provider<PhotoService> photoServiceProvider = Provider<PhotoService>((
  ref,
) {
  final runtime = ref.watch(runtimeProvider);
  return PhotoService(
    runtime.db,
    runtime.writer,
    directory: runtime.photosDirectory,
  );
});
