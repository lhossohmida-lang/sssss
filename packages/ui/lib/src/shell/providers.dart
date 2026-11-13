import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_chat/school_chat.dart';
import 'package:school_core/school_core.dart';

import 'push_notifications.dart';
import 'session_closer.dart';

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

/// واجهة تمرير مسارات إشعارات FCM إلى الموجّه بعد إنشائه.
final Provider<ValueNotifier<void Function(String)?>>
pushNavigationHandlerProvider = Provider((ref) {
  final handler = ValueNotifier<void Function(String)?>(null);
  ref.onDispose(handler.dispose);
  return handler;
});

/// يربط رمز FCM بالحساب الحالي ويتعامل مع فتح الإشعار.
final Provider<PushNotificationCoordinator> pushNotificationsProvider =
    Provider((ref) {
      final runtime = ref.watch(runtimeProvider);
      final navigator = ref.watch(pushNavigationHandlerProvider);
      final coordinator = PushNotificationCoordinator(
        installationStore: runtime.pushInstallationStore,
        isLocalMode: runtime.isLocalMode,
        signOutAction: runtime.auth.signOut,
        navigate: (path) {
          navigator.value?.call(path);
        },
      );
      ref.listen(sessionProvider, (_, next) {
        unawaited(coordinator.updateSession(next.value));
      });
      unawaited(coordinator.updateSession(runtime.auth.current));
      ref.onDispose(() => unawaited(coordinator.dispose()));
      return coordinator;
    });

/// خدمة المحادثات المقيّدة بالجلسة الحالية.
final Provider<ChatService> chatServiceProvider = Provider.autoDispose((ref) {
  final session = ref.watch(sessionProvider).value;
  if (session == null) {
    throw StateError('خدمة المحادثات تتطلب جلسة مسجّلة');
  }
  final runtime = ref.watch(runtimeProvider);
  return ChatService(
    runtime.db,
    runtime.writer,
    ChatPrincipal.fromSession(session),
  );
});

/// الغرف الظاهرة للمستخدم الحالي.
final chatRoomsProvider = StreamProvider.autoDispose
    .family<List<ChatRoomListItem>, int>(
      (ref, limit) => ref.watch(chatServiceProvider).watchRooms(limit: limit),
    );

/// غرفة واحدة مع إعادة تحقق العضوية خلال البث.
final chatRoomProvider = StreamProvider.autoDispose
    .family<ChatRoomRow?, String>(
      (ref, roomId) => ref.watch(chatServiceProvider).watchRoom(roomId),
    );

/// عضوية الحساب الحالي وحالة كتمه للغرفة.
final chatMembershipProvider = StreamProvider.autoDispose
    .family<ChatMemberRow?, String>(
      (ref, roomId) => ref.watch(chatServiceProvider).watchMyMembership(roomId),
    );

/// أسماء أعضاء غرفة ظاهرة للمشرفين لإدارة العضويات ونسبة الرسائل لأصحابها.
final chatRoomMembersProvider = FutureProvider.autoDispose
    .family<List<ChatRoomMemberItem>, String>(
      (ref, roomId) => ref.watch(chatServiceProvider).roomMembers(roomId),
    );

typedef ChatMessagesKey = ({String roomId, int limit});

/// أحدث الرسائل، بحد أقصى 50 رسالة.
final chatMessagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessageRow>, ChatMessagesKey>(
      (ref, key) => ref
          .watch(chatServiceProvider)
          .watchLatestMessages(key.roomId, limit: key.limit),
    );

typedef ChatContactSearchKey = ({String query, int limit});

/// جهات الاتصال التي يسمح السياق الحالي بمراسلتها.
final chatContactsProvider = FutureProvider.autoDispose
    .family<List<ChatContact>, ChatContactSearchKey>(
      (ref, key) => ref
          .watch(chatServiceProvider)
          .privateContacts(query: key.query, limit: key.limit),
    );

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

/// إجمالي المحادثات غير المقروءة في تطبيقي الأستاذ والوليّ.
final StreamProvider<int> chatUnreadCountProvider =
    StreamProvider.autoDispose<int>((ref) {
      return ref
          .watch(chatServiceProvider)
          .watchRooms()
          .map(
            (rooms) => rooms.fold(0, (total, room) => total + room.unreadCount),
          );
    });

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

/// ملفات المجموعات (نسخة محلية، سجل مزامَن، رفع لاحق). تُحفظ في مجلد
/// فرعي من مجلد صور التطبيق.
final Provider<GroupFileService> groupFileServiceProvider =
    Provider<GroupFileService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return GroupFileService(
        runtime.db,
        runtime.writer,
        directory: Directory(
          '${runtime.photosDirectory.path}${Platform.pathSeparator}'
          'group_files',
        ),
      );
    });

/// ملفات مجموعة، الأحدث أولاً، ولحظياً.
final groupFilesProvider = StreamProvider.autoDispose
    .family<List<GroupFileItem>, String>(
      (ref, groupId) => ref.watch(groupFileServiceProvider).watchFiles(groupId),
    );

/// خدمات المستحقات والانتساب والتسجيل (تطبيق الإدارة).
final Provider<DuesService> duesServiceProvider = Provider<DuesService>((ref) {
  final runtime = ref.watch(runtimeProvider);
  return DuesService(runtime.db, runtime.writer);
});

final Provider<EnrolmentService> enrolmentServiceProvider =
    Provider<EnrolmentService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return EnrolmentService(
        runtime.db,
        runtime.writer,
        ref.watch(duesServiceProvider),
        CycleService(runtime.db, runtime.writer),
      );
    });

final Provider<RegistrationService> registrationServiceProvider =
    Provider<RegistrationService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return RegistrationService(
        runtime.db,
        runtime.writer,
        accounts: ref.watch(accountServiceProvider),
        enrolments: ref.watch(enrolmentServiceProvider),
        dues: ref.watch(duesServiceProvider),
      );
    });

/// المجموعات النشطة لمادة (لاختيار المجموعة عند التسجيل).
final groupOptionsProvider = FutureProvider.autoDispose
    .family<List<GroupOption>, String>(
      (ref, subjectId) =>
          ref.watch(enrolmentServiceProvider).groupsForSubject(subjectId),
    );

/// أساتذة مادة (للأستاذ المفضّل في قائمة الانتظار).
final subjectTeachersProvider = FutureProvider.autoDispose
    .family<List<TeacherRow>, String>(
      (ref, subjectId) =>
          ref.watch(enrolmentServiceProvider).teachersOfSubject(subjectId),
    );

/// خطوط النقل الحية مرتبة بالاسم.
final StreamProvider<List<TransportLineRow>> transportLinesProvider =
    StreamProvider<List<TransportLineRow>>(
      (ref) => ref.watch(runtimeProvider).db.watchTransportLines(),
    );

/// خدمة ملف التلميذ.
final Provider<StudentService> studentServiceProvider =
    Provider<StudentService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return StudentService(
        runtime.db,
        runtime.writer,
        ref.watch(duesServiceProvider),
      );
    });

/// ملف تلميذ، ويتحدث مع كل تغيير؛ `null` إن حُذف أو لم يوجد.
final studentProfileProvider = StreamProvider.autoDispose
    .family<StudentProfile?, String>((ref, studentId) {
      final now = DateTime.now();
      final month =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}';
      return ref.watch(studentServiceProvider).watch(studentId, month: month);
    });

/// شعار المدرسة (ضغط وحفظ ورفع وجلب).
final Provider<LogoService> logoServiceProvider = Provider<LogoService>((ref) {
  final runtime = ref.watch(runtimeProvider);
  return LogoService(
    runtime.db,
    runtime.writer,
    directory: runtime.photosDirectory,
    files: runtime.fileStore,
  );
});

/// كشف تعارض الجدول وخدمة المجموعات وقائمتها الحية.
final Provider<ScheduleService> scheduleServiceProvider =
    Provider<ScheduleService>(
      (ref) => ScheduleService(ref.watch(runtimeProvider).db),
    );

final Provider<GroupService> groupServiceProvider = Provider<GroupService>((
  ref,
) {
  final runtime = ref.watch(runtimeProvider);
  return GroupService(
    runtime.db,
    runtime.writer,
    ref.watch(scheduleServiceProvider),
    CycleService(runtime.db, runtime.writer),
  );
});

/// المجموعات النشطة مع أساتذتها وموادها وجداولها.
final StreamProvider<List<GroupItem>> groupsProvider =
    StreamProvider<List<GroupItem>>(
      (ref) => ref.watch(groupServiceProvider).watchAll(),
    );

/// شبكة حضور دورة من دورات مجموعة (الدورة الحالية إن لم تُحدَّد).
typedef GroupGridKey = ({String groupId, int? cycle});

final groupGridProvider = StreamProvider.autoDispose
    .family<GroupGrid?, GroupGridKey>(
      (ref, key) =>
          GroupGridQueries(ref.watch(runtimeProvider).db)
              .watch(key.groupId, cycleNumber: key.cycle),
    );

/// معلومات مجموعة واحدة (للعنوان وأزرار الشاشة).
final groupItemProvider = Provider.autoDispose.family<GroupItem?, String>((
  ref,
  groupId,
) {
  final groups = ref.watch(groupsProvider).value ?? const <GroupItem>[];
  return groups.where((g) => g.id == groupId).firstOrNull;
});

/// الحضور اليدوي والتغييب التلقائي (تطبيق الإدارة).
final Provider<AttendanceService> attendanceServiceProvider =
    Provider<AttendanceService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return AttendanceService(
        runtime.db,
        runtime.writer,
        CycleService(runtime.db, runtime.writer),
        ref.watch(duesServiceProvider),
      );
    });

/// حصص يوم (مفتاحه `YYYY-MM-DD`) بعدّادات حضورها.
final daySessionsProvider = StreamProvider.autoDispose
    .family<List<DaySession>, String>(
      (ref, date) => ref.watch(attendanceServiceProvider).watchDay(date),
    );

/// ورقة حضور حصة.
final sessionRosterProvider = StreamProvider.autoDispose
    .family<SessionRoster?, String>(
      (ref, sessionId) =>
          ref.watch(attendanceServiceProvider).watchRoster(sessionId),
    );

/// هل تعمل مهمة التغييب التلقائي؟ تعطّلها الاختبارات التي لا تريد مؤقتاً
/// في الخلفية.
final Provider<bool> sessionCloserEnabledProvider = Provider<bool>(
  (ref) => true,
);

/// مهمة الخلفية: تغلق الحصص المنتهية وتغيّب من لم يُسجَّل (تطبيق الإدارة،
/// لمن يملك صلاحية الحضور أو الماسح فقط).
final Provider<void> sessionCloserProvider = Provider<void>((ref) {
  if (!ref.watch(sessionCloserEnabledProvider)) return;
  final runtime = ref.watch(runtimeProvider);
  if (runtime.app != AppIdentity.admin) return;
  final eligible = ref.watch(
    sessionProvider.select((s) {
      final session = s.value;
      if (session == null || !session.allowsApp(AppIdentity.admin)) {
        return false;
      }
      return session.policy.canAnyOf(PermissionModule.attendance) ||
          session.policy.canAnyOf(PermissionModule.scanner);
    }),
  );
  if (!eligible) return;
  final closer = SessionCloser(ref.watch(attendanceServiceProvider))..start();
  ref.onDispose(closer.dispose);
});

/// الجدول الأسبوعي الثابت لكل المجموعات النشطة.
final StreamProvider<WeeklySchedule> weeklyScheduleProvider =
    StreamProvider.autoDispose<WeeklySchedule>(
      (ref) => WeeklyScheduleQueries(ref.watch(runtimeProvider).db).watch(),
    );

/// قوائم الانتظار (تطبيق الإدارة).
final Provider<WaitingService> waitingServiceProvider =
    Provider<WaitingService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return WaitingService(runtime.db, runtime.writer);
    });

final StreamProvider<List<WaitingListItem>> waitingListsProvider =
    StreamProvider.autoDispose<List<WaitingListItem>>(
      (ref) => ref.watch(waitingServiceProvider).watchLists(),
    );

/// قائمة انتظار واحدة (`null` إن لم يبقَ فيها منتظر).
final waitingListProvider = StreamProvider.autoDispose
    .family<WaitingListItem?, String>(
      (ref, listId) => ref.watch(waitingServiceProvider).watchList(listId),
    );

/// منتظرو قائمة، الأقدم أولاً.
final waitingStudentsProvider = StreamProvider.autoDispose
    .family<List<WaitingStudent>, String>(
      (ref, listId) => ref.watch(waitingServiceProvider).watchStudents(listId),
    );

/// منطق ماسح المدخل بإعدادات المدرسة (الهامش والمهلة وحد المستحقات).
///
/// يُبنى من جديد عند تغيّر الإعدادات؛ وفهرس الرموز يحمّله من يفتح الماسح.
final Provider<ScanService> scanServiceProvider =
    Provider.autoDispose<ScanService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      final settings = ref.watch(schoolSettingsProvider).value;
      return ScanService(
        runtime.db,
        runtime.writer,
        CycleService(runtime.db, runtime.writer),
        ref.watch(duesServiceProvider),
        config: settings == null
            ? const ScanConfig()
            : ScanConfig(
                marginMinutes: settings.scanMarginMinutes,
                graceMinutes: settings.graceMinutes,
                duesGraceSessions: settings.duesSessionThreshold,
              ),
      );
    });

/// المسحات الحديثة القادمة من أي جهاز (شاشة المدخل).
final Provider<RecentScanFeed> recentScanFeedProvider =
    Provider.autoDispose<RecentScanFeed>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return RecentScanFeed(runtime.db, ref.watch(duesServiceProvider));
    });

/// المدفوعات وتسجيلها بوصل مرقَّم (تطبيق الإدارة).
final Provider<PaymentService> paymentServiceProvider =
    Provider<PaymentService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return PaymentService(
        runtime.db,
        runtime.writer,
        ref.watch(duesServiceProvider),
        DeviceInfoStore(runtime.db),
      );
    });

typedef PaymentPageKey = ({String query, PaymentType? type, int limit});

/// صفحة من قائمة المدفوعات للبحث والنوع والحد.
final paymentPageProvider = StreamProvider.autoDispose
    .family<PaymentPage, PaymentPageKey>(
      (ref, key) => ref
          .watch(paymentServiceProvider)
          .watchPayments(query: key.query, type: key.type, limit: key.limit),
    );

/// مجموع ما استُلم اليوم.
final StreamProvider<int> receivedTodayProvider =
    StreamProvider.autoDispose<int>(
      (ref) =>
          ref.watch(paymentServiceProvider).watchReceivedOn(DateTime.now()),
    );

/// ما يمكن لتلميذ دفعه الآن؛ يُعاد حسابه بعد كل دفعة.
final payablesProvider = FutureProvider.autoDispose
    .family<List<PayableItem>, String>(
      (ref, studentId) => ref
          .watch(paymentServiceProvider)
          .payables(studentId, now: DateTime.now()),
    );

/// دفعة بتفاصيلها (شاشة الوصل).
final paymentDetailProvider = FutureProvider.autoDispose
    .family<PaymentDetail?, String>(
      (ref, id) => ref.watch(paymentServiceProvider).detail(id),
    );

/// تقرير المستحقات (تطبيق الإدارة).
final Provider<DuesReports> duesReportsProvider = Provider<DuesReports>((ref) {
  final runtime = ref.watch(runtimeProvider);
  return DuesReports(runtime.db, ref.watch(duesServiceProvider));
});

typedef DuesReportKey = ({String? groupId, String query});

/// من عليهم مستحقات، بمجموعة وبحث اختياريين.
final duesReportProvider = StreamProvider.autoDispose
    .family<DuesReport, DuesReportKey>(
      (ref, key) => ref
          .watch(duesReportsProvider)
          .watch(groupId: key.groupId, query: key.query),
    );

/// حقوق التسجيل: فتراتها وتقريرها (تطبيق الإدارة).
final Provider<RegistrationFeeReports> feeReportsProvider =
    Provider<RegistrationFeeReports>(
      (ref) => RegistrationFeeReports(ref.watch(runtimeProvider).db),
    );

final FutureProvider<List<String>> feePeriodsProvider =
    FutureProvider.autoDispose<List<String>>(
      (ref) => ref.watch(feeReportsProvider).periods(),
    );

typedef FeeReportKey = ({String period, bool unpaidOnly, String query});

final feeReportProvider = StreamProvider.autoDispose
    .family<FeeReport, FeeReportKey>(
      (ref, key) => ref
          .watch(feeReportsProvider)
          .watch(
            periodKey: key.period,
            unpaidOnly: key.unpaidOnly,
            query: key.query,
          ),
    );

/// خلاص الأساتذة (تطبيق الإدارة).
final Provider<PayoutService> payoutServiceProvider = Provider<PayoutService>((
  ref,
) {
  final runtime = ref.watch(runtimeProvider);
  return PayoutService(
    runtime.db,
    runtime.writer,
    ref.watch(duesServiceProvider),
  );
});

final Provider<PayoutQueries> payoutQueriesProvider = Provider<PayoutQueries>(
  (ref) => PayoutQueries(
    ref.watch(runtimeProvider).db,
    ref.watch(payoutServiceProvider),
  ),
);

typedef PayoutKey = ({PayoutStatus status, String? teacherId});

final payoutsProvider = StreamProvider.autoDispose
    .family<List<PayoutItem>, PayoutKey>(
      (ref, key) => ref
          .watch(payoutQueriesProvider)
          .watch(status: key.status, teacherId: key.teacherId),
    );

/// ملخص الخلاصات (لأستاذ أو للكل).
final payoutSummaryProvider = StreamProvider.autoDispose
    .family<PayoutSummary, String?>(
      (ref, teacherId) =>
          ref.watch(payoutQueriesProvider).watchSummary(teacherId: teacherId),
    );

/// تفصيل خلاص؛ يُعاد حسابه بعد التسليم.
final payoutDetailProvider = FutureProvider.autoDispose
    .family<PayoutDetail?, String>(
      (ref, id) => ref.watch(payoutQueriesProvider).detail(id),
    );

/// أساتذة المدرسة للاختيار في المرشِّحات (قراءة خفيفة بلا خدمة الحسابات).
final StreamProvider<List<TeacherRow>> teacherOptionsProvider =
    StreamProvider.autoDispose<List<TeacherRow>>(
      (ref) => ref.watch(runtimeProvider).db.watchTeachers(),
    );

/// خدمة العمال وقائمتهم الحية.
final Provider<WorkerService> workerServiceProvider = Provider<WorkerService>((
  ref,
) {
  final runtime = ref.watch(runtimeProvider);
  return WorkerService(
    runtime.db,
    runtime.writer,
    ref.watch(accountServiceProvider),
  );
});

final StreamProvider<List<WorkerItem>> workersProvider =
    StreamProvider<List<WorkerItem>>(
      (ref) => ref.watch(workerServiceProvider).watchAll(),
    );

/// أجور العمال وكشف حضورهم الشهري.
final Provider<WageService> wageServiceProvider = Provider<WageService>((ref) {
  final runtime = ref.watch(runtimeProvider);
  return WageService(runtime.db, runtime.writer);
});

/// كشف شهر (`YYYY-MM`) لكل العمال.
final workerSheetProvider = StreamProvider.autoDispose
    .family<List<WorkerMonthSummary>, String>(
      (ref, month) => ref.watch(wageServiceProvider).watchSheet(month),
    );

/// كشف حضور الأساتذة والحصص التي لم يحضرها أستاذها.
final Provider<TeacherAttendanceQueries> teacherAttendanceProvider =
    Provider<TeacherAttendanceQueries>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return TeacherAttendanceQueries(runtime.db, runtime.writer);
    });

/// كشف شهر (`YYYY-MM`) لكل الأساتذة.
final teacherSheetProvider = StreamProvider.autoDispose
    .family<List<TeacherMonth>, String>(
      (ref, month) => ref.watch(teacherAttendanceProvider).watchSheet(month),
    );

/// حصص لم يحضرها أستاذها منذ [since] (مفتاح تاريخ).
final missedSessionsProvider = StreamProvider.autoDispose
    .family<List<MissedSession>, String>(
      (ref, since) =>
          ref.watch(teacherAttendanceProvider).watchMissed(since: since),
    );

/// أرقام لوحة التحكم.
final StreamProvider<DashboardStats> dashboardProvider =
    StreamProvider.autoDispose<DashboardStats>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return DashboardQueries(runtime.db, runtime.writer).watch();
    });

/// معرّف الأستاذ صاحب الجلسة (تطبيق الأستاذ)، أو `null`.
final Provider<String?> myTeacherIdProvider = Provider<String?>(
  (ref) => ref.watch(
    sessionProvider.select(
      (s) => s.value?.role == UserRole.teacher ? s.value?.entityId : null,
    ),
  ),
);

/// مجموعات الأستاذ غير المؤرشفة (تطبيق الأستاذ).
final Provider<AsyncValue<List<GroupItem>>> myGroupsProvider =
    Provider.autoDispose<AsyncValue<List<GroupItem>>>((ref) {
      final me = ref.watch(myTeacherIdProvider);
      return ref
          .watch(groupsProvider)
          .whenData(
            (all) => [
              for (final g in all)
                if (g.group.teacherId == me) g,
            ],
          );
    });

/// حصص أستاذ في يوم (مفتاحه `YYYY-MM-DD`) بعدّادات حضورها.
final myDaySessionsProvider = StreamProvider.autoDispose
    .family<List<DaySession>, String>((ref, date) {
      final me = ref.watch(myTeacherIdProvider);
      if (me == null) return Stream.value(const <DaySession>[]);
      return ref.watch(attendanceServiceProvider).watchDay(date, teacherId: me);
    });

/// صف الأستاذ صاحب الجلسة (رمزه واسمه)، أو `null`.
final StreamProvider<TeacherRow?> myTeacherProvider =
    StreamProvider.autoDispose<TeacherRow?>((ref) {
      final me = ref.watch(myTeacherIdProvider);
      if (me == null) return Stream.value(null);
      return ref.watch(runtimeProvider).db.watchTeacher(me);
    });

/// طلبات الأستاذ لتغيير الحصص.
final Provider<RequestService> requestServiceProvider =
    Provider<RequestService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return RequestService(
        runtime.db,
        runtime.writer,
        ScheduleService(runtime.db),
        CycleService(runtime.db, runtime.writer),
      );
    });

/// طلبات الأستاذ صاحب الجلسة، الأحدث أولاً.
final StreamProvider<List<RequestItem>> myRequestsProvider =
    StreamProvider.autoDispose<List<RequestItem>>((ref) {
      final me = ref.watch(myTeacherIdProvider);
      if (me == null) return Stream.value(const <RequestItem>[]);
      return ref.watch(requestServiceProvider).watchMine(me);
    });

/// حصص مجموعة التي يمكن طلب تغييرها، من اليوم.
final openSessionsProvider = FutureProvider.autoDispose
    .family<List<SessionRow>, String>(
      (ref, groupId) => ref
          .watch(requestServiceProvider)
          .openSessions(groupId, fromDate: DateKey.of(DateTime.now())),
    );

/// طلبات الأساتذة في الإدارة، بحصرها بحالة (`null` للكل).
final allRequestsProvider = StreamProvider.autoDispose
    .family<List<RequestItem>, SessionRequestStatus?>(
      (ref, status) =>
          ref.watch(requestServiceProvider).watchAll(status: status),
    );

/// عدد الطلبات المعلّقة (شارة الإدارة).
final StreamProvider<int> pendingRequestsCountProvider =
    StreamProvider.autoDispose<int>(
      (ref) => ref.watch(requestServiceProvider).watchPendingCount(),
    );

/// طلب واحد بوصفه؛ يُعاد حسابه بعد البتّ فيه.
final requestItemProvider = FutureProvider.autoDispose
    .family<RequestItem?, String>(
      (ref, id) => ref.watch(requestServiceProvider).find(id),
    );

/// نتائج المجموعات (تطبيق الأستاذ).
final Provider<GradeService> gradeServiceProvider = Provider<GradeService>((
  ref,
) {
  final runtime = ref.watch(runtimeProvider);
  return GradeService(runtime.db, runtime.writer);
});

/// اختبارات مجموعة بمتوسطاتها.
final assessmentsProvider = StreamProvider.autoDispose
    .family<List<AssessmentSummary>, String>(
      (ref, groupId) =>
          ref.watch(gradeServiceProvider).watchAssessments(groupId),
    );

typedef AssessmentKey = ({String groupId, String title, String date});

/// تلاميذ اختبار بنتائجهم (فارغ العنوان لاختبار جديد).
final gradeEntriesProvider = FutureProvider.autoDispose
    .family<List<GradeEntry>, AssessmentKey>(
      (ref, key) => ref
          .watch(gradeServiceProvider)
          .entries(key.groupId, title: key.title, date: key.date),
    );

/// معرّف الوليّ صاحب الجلسة (تطبيق الوليّ)، أو `null`.
final Provider<String?> myParentIdProvider = Provider<String?>(
  (ref) => ref.watch(
    sessionProvider.select(
      (s) => s.value?.role == UserRole.parent ? s.value?.entityId : null,
    ),
  ),
);

/// أبناء الوليّ مرتبين بالاسم، ولحظياً.
final StreamProvider<List<StudentRow>> childrenProvider =
    StreamProvider.autoDispose<List<StudentRow>>((ref) {
      final me = ref.watch(myParentIdProvider);
      if (me == null) return Stream.value(const <StudentRow>[]);
      return ref.watch(runtimeProvider).db.watchChildren(me);
    });

/// الابن الذي اختاره الوليّ في مبدّل الأبناء (يشترك فيه كل تبويب).
class SelectedChild extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String studentId) => state = studentId;
}

final NotifierProvider<SelectedChild, String?> selectedChildIdProvider =
    NotifierProvider<SelectedChild, String?>(SelectedChild.new);

/// الابن المعروض الآن: المختار إن كان من أبناء الوليّ، وإلا أولهم؛ و`null`
/// إن لم يكن له أبناء بعد.
final Provider<StudentRow?> selectedChildProvider =
    Provider.autoDispose<StudentRow?>((ref) {
      final children = ref.watch(childrenProvider).value ?? const [];
      if (children.isEmpty) return null;
      final id = ref.watch(selectedChildIdProvider);
      for (final child in children) {
        if (child.id == id) return child;
      }
      return children.first;
    });

/// كشف حضور التلميذ في مجموعاته (تطبيق الوليّ).
final Provider<ChildAttendanceService> childAttendanceServiceProvider =
    Provider<ChildAttendanceService>(
      (ref) => ChildAttendanceService(ref.watch(runtimeProvider).db),
    );

/// ما يحدّد كشفاً: التلميذ والمجموعة والشهر `YYYY-MM`.
typedef ChildMonthKey = ({String studentId, String groupId, String month});

/// حصص مجموعة لتلميذ في شهر بحاله في كل منها، ولحظياً.
final childMonthProvider = StreamProvider.autoDispose
    .family<List<ChildSession>, ChildMonthKey>(
      (ref, key) => ref
          .watch(childAttendanceServiceProvider)
          .watchMonth(key.studentId, key.groupId, key.month),
    );

/// الحصص القادمة لتلميذ (أول 10) بمواعيدها الفعلية، ولحظياً.
final childUpcomingProvider = StreamProvider.autoDispose
    .family<List<UpcomingSession>, String>(
      (ref, studentId) =>
          ChildScheduleQueries(ref.watch(runtimeProvider).db)
              .watchUpcoming(studentId),
    );

/// الجدول الأسبوعي لمجموعات تلميذ، ولحظياً.
final childWeeklyProvider = StreamProvider.autoDispose
    .family<WeeklySchedule, String>(
      (ref, studentId) =>
          WeeklyScheduleQueries(ref.watch(runtimeProvider).db)
              .watch(studentId: studentId),
    );

typedef ChildPaymentsKey = ({String studentId, int limit});

/// دفعات تلميذ، الأحدث أولاً، ولحظياً (كشف الوليّ).
final childPaymentsProvider = StreamProvider.autoDispose
    .family<PaymentPage, ChildPaymentsKey>(
      (ref, key) => ref
          .watch(paymentServiceProvider)
          .watchPayments(studentId: key.studentId, limit: key.limit),
    );

/// ما يحدّد نتائج تلميذ: هو ومجموعته.
typedef ChildGradesKey = ({String studentId, String groupId});

/// نتائج تلميذ في مجموعة، الأحدث أولاً، ولحظياً (كشف الوليّ).
final childGradesProvider = StreamProvider.autoDispose
    .family<List<ChildGrade>, ChildGradesKey>(
      (ref, key) => ref
          .watch(gradeServiceProvider)
          .watchForStudent(key.studentId, key.groupId),
    );

/// صف الوليّ صاحب الجلسة (هاتفه)، أو `null`.
final StreamProvider<ParentRow?> myParentProvider =
    StreamProvider.autoDispose<ParentRow?>((ref) {
      final me = ref.watch(myParentIdProvider);
      if (me == null) return Stream.value(null);
      return ref.watch(runtimeProvider).db.watchParent(me);
    });
