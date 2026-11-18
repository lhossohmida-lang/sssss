import 'package:drift/drift.dart';

import 'people_tables.dart';
import 'sync_columns.dart';

/// المجموعات. «الشهر» = دورة من [sessionsPerCycle] حصة وليس شهر التقويم.
@DataClassName('GroupRow')
@TableIndex(name: 'idx_groups_number', columns: {#number})
@TableIndex(name: 'idx_groups_subject', columns: {#subjectId})
@TableIndex(name: 'idx_groups_teacher', columns: {#teacherId})
@TableIndex(name: 'idx_groups_room', columns: {#roomId})
@TableIndex(name: 'idx_groups_updated', columns: {#updatedAt})
class Groups extends Table with SyncColumns {
  IntColumn get number => integer()();

  TextColumn get subjectId => text().references(Subjects, #id)();

  TextColumn get teacherId => text().references(Teachers, #id)();

  /// القاعة الافتراضية للمجموعة.
  TextColumn get roomId => text().nullable().references(Rooms, #id)();

  IntColumn get sessionsPerCycle => integer().withDefault(const Constant(8))();

  IntColumn get currentCycleNumber =>
      integer().withDefault(const Constant(1))();

  /// سعر الشهر (الدورة) الذي يدفعه كل تلميذ في هذه المجموعة بالدينار، قبل التخفيض. يُعيَّن عند
  /// إنشاء الفوج فقط، وبه يُنسب التلاميذ إليه (فسعر مادة المستوى المتوسط غير سعر الابتدائي).
  /// `0` لفوج أُنشئ قبل هذا الحقل ولم يُملأ بعد: يؤخذ سعر مادته (انظر `EnrolmentService.priceOfGroup`).
  IntColumn get monthlyPrice => integer().withDefault(const Constant(0))();

  /// مبلغ الأستاذ لكل تلميذ في هذه المجموعة؛ يُعيَّن عند إنشاء الفوج فقط. `null` لفوج قديم يعني
  /// قيمة الأستاذ الافتراضية.
  IntColumn get ratePerStudent => integer().nullable()();

  /// وقت الأرشفة عند «سنة جديدة»؛ `null` يعني أن المجموعة نشطة.
  IntColumn get archivedAt => integer().nullable()();

  /// فوج منتظِر: له تلاميذ ولا موعد لأول حصة بعد، ينتظر أن يبلغ عدد تلاميذه هذا العدد (يحدده المدير
  /// عند إنشائه). عند بلوغه يُنبَّه المدير في التطبيق وبرسالة SMS ليحدد تاريخ أول حصة. `null` فوج عادي.
  IntColumn get waitingTarget => integer().nullable()();

  /// وقت تنبيه المدير باكتمال الفوج المنتظِر (مرة واحدة)؛ `null` لم يُنبَّه بعد.
  IntColumn get startAlertedAt => integer().nullable()();

  /// حصة مراجعة: فوج من حصة واحدة، يحضرها من يدفع ثمنها وحدها (تلاميذ لمرة واحدة أو تلاميذ فوج آخر).
  BoolColumn get isReview => boolean().withDefault(const Constant(false))();
}

/// الجدول الأسبوعي الثابت للمجموعة: خانة لكل يوم تدرس فيه.
@DataClassName('GroupSlotRow')
@TableIndex(name: 'idx_group_slots_group', columns: {#groupId})
@TableIndex(name: 'idx_group_slots_day', columns: {#weekday, #startMinutes})
@TableIndex(name: 'idx_group_slots_room', columns: {#roomId, #weekday})
@TableIndex(name: 'idx_group_slots_updated', columns: {#updatedAt})
class GroupSlots extends Table with SyncColumns {
  TextColumn get groupId => text().references(Groups, #id)();

  /// 1 = الاثنين … 7 = الأحد (ترقيم `DateTime.weekday`).
  IntColumn get weekday => integer()();

  IntColumn get startMinutes => integer()();

  IntColumn get endMinutes => integer()();

  TextColumn get roomId => text().nullable().references(Rooms, #id)();
}

/// انتساب تلميذ إلى مجموعة مع سعره وتخفيضه.
@DataClassName('GroupStudentRow')
@TableIndex(
  name: 'idx_group_students_pair',
  columns: {#groupId, #studentId},
  unique: true,
)
@TableIndex(name: 'idx_group_students_student', columns: {#studentId})
@TableIndex(name: 'idx_group_students_updated', columns: {#updatedAt})
class GroupStudents extends Table with SyncColumns {
  TextColumn get groupId => text().references(Groups, #id)();

  TextColumn get studentId => text().references(Students, #id)();

  IntColumn get joinedAt => integer()();

  /// رقم الدورة التي التحق فيها.
  IntColumn get joinedAtCycleNumber =>
      integer().withDefault(const Constant(1))();

  /// رقم أول حصة يحضرها في دورة الالتحاق (1 = من بداية الدورة).
  IntColumn get joinedAtSessionNumber =>
      integer().withDefault(const Constant(1))();

  /// سعر الشهر لهذا التلميذ في هذه المجموعة قبل التخفيض.
  IntColumn get monthlyPrice => integer()();

  /// `none` / `percent` / `fixed` / `exempt`.
  TextColumn get discountType => text().withDefault(const Constant('none'))();

  /// النسبة (0–100) أو المبلغ بالدينار حسب [discountType].
  IntColumn get discountValue => integer().withDefault(const Constant(0))();

  /// وقت مغادرة المجموعة؛ `null` يعني أنه ما زال فيها.
  IntColumn get leftAt => integer().nullable()();

  /// ما يأخذه الأستاذ عن هذا التلميذ في الدورة بالدينار، يُعيَّن عند انتسابه. `null` يعني مبلغ
  /// الفوج كاملاً (فالتخفيض أو الإعفاء على حساب المدرسة). أقل منه يعني أن الأستاذ يتحمل من
  /// التخفيض، وصفر أن المدرسة تأخذ كل حصة الأستاذ عنه.
  IntColumn get teacherAmount => integer().nullable()();
}

/// قائمة انتظار لكل (مادة + مستوى).
@DataClassName('WaitingListRow')
@TableIndex(name: 'idx_waiting_lists_subject', columns: {#subjectId, #levelId})
@TableIndex(name: 'idx_waiting_lists_updated', columns: {#updatedAt})
class WaitingLists extends Table with SyncColumns {
  TextColumn get subjectId => text().references(Subjects, #id)();

  TextColumn get levelId => text().nullable().references(Levels, #id)();

  TextColumn get preferredTeacherId =>
      text().nullable().references(Teachers, #id)();

  /// الحد الذي يُنبَّه المدير عند بلوغه.
  IntColumn get threshold => integer().withDefault(const Constant(10))();

  /// آخر مرة أُرسل فيها تنبيه بلوغ الحد (لمنع التكرار).
  IntColumn get thresholdNotifiedAt => integer().nullable()();
}

/// تلميذ في قائمة انتظار.
@DataClassName('WaitingEntryRow')
@TableIndex(
  name: 'idx_waiting_entries_pair',
  columns: {#waitingListId, #studentId},
  unique: true,
)
@TableIndex(name: 'idx_waiting_entries_student', columns: {#studentId})
@TableIndex(name: 'idx_waiting_entries_updated', columns: {#updatedAt})
class WaitingEntries extends Table with SyncColumns {
  TextColumn get waitingListId => text().references(WaitingLists, #id)();

  TextColumn get studentId => text().references(Students, #id)();

  IntColumn get addedAt => integer()();
}

/// الحصص.
@DataClassName('SessionRow')
@TableIndex(name: 'idx_sessions_group_cycle', columns: {#groupId, #cycleNumber})
@TableIndex(name: 'idx_sessions_date', columns: {#date, #startMinutes})
@TableIndex(name: 'idx_sessions_room_date', columns: {#roomId, #date})
@TableIndex(
  name: 'idx_sessions_group_slot',
  columns: {#groupId, #date, #startMinutes},
  unique: true,
)
@TableIndex(name: 'idx_sessions_updated', columns: {#updatedAt})
class Sessions extends Table with SyncColumns {
  TextColumn get groupId => text().references(Groups, #id)();

  IntColumn get cycleNumber => integer()();

  /// ترتيب الحصة داخل الدورة؛ `null` للحصة الملغاة لأنها لا تُحسب.
  IntColumn get sessionNumber => integer().nullable()();

  /// التاريخ بصيغة `YYYY-MM-DD`.
  TextColumn get date => text()();

  IntColumn get startMinutes => integer()();

  IntColumn get endMinutes => integer()();

  TextColumn get roomId => text().nullable().references(Rooms, #id)();

  /// `normal` / `cancelled` / `makeup` / `added`.
  TextColumn get status => text().withDefault(const Constant('normal'))();

  /// وقت إغلاق الحصة: تغييب من لم يمسح وتجهيز سجل الحضور.
  IntColumn get closedAt => integer().nullable()();
}

/// حضور التلاميذ.
@DataClassName('AttendanceRow')
@TableIndex(
  name: 'idx_attendance_pair',
  columns: {#sessionId, #studentId},
  unique: true,
)
@TableIndex(name: 'idx_attendance_student', columns: {#studentId, #status})
@TableIndex(name: 'idx_attendance_updated', columns: {#updatedAt})
class Attendance extends Table with SyncColumns {
  TextColumn get sessionId => text().references(Sessions, #id)();

  TextColumn get studentId => text().references(Students, #id)();

  /// `present` / `absent` / `excused`.
  TextColumn get status => text()();

  IntColumn get scannedAt => integer().nullable()();

  /// `qr` / `manual`.
  TextColumn get method => text()();
}

/// ضيوف الحصة: تلميذ يحضر حصة واحدة ويدفع ثمنها وحدها، سواء كان «تلميذاً لمرة واحدة» لا ينتسب إلى فوج
/// أو تلميذاً منتسباً إلى فوج آخر (كحصة مراجعة). لكل ضيف سعر لهذه الحصة ومبلغ للأستاذ عنها، وتذكرة
/// QR تُستعمل مرة واحدة لتلميذ لمرة واحدة.
@DataClassName('SessionGuestRow')
@TableIndex(
  name: 'idx_session_guests_pair',
  columns: {#sessionId, #studentId},
  unique: true,
)
@TableIndex(
  name: 'idx_session_guests_ticket',
  columns: {#ticketCode},
  unique: true,
)
@TableIndex(name: 'idx_session_guests_student', columns: {#studentId})
@TableIndex(name: 'idx_session_guests_updated', columns: {#updatedAt})
class SessionGuests extends Table with SyncColumns {
  TextColumn get sessionId => text().references(Sessions, #id)();

  TextColumn get studentId => text().references(Students, #id)();

  /// سعر هذه الحصة لهذا الضيف بالدينار.
  IntColumn get price => integer().withDefault(const Constant(0))();

  /// ما يأخذه الأستاذ عن هذا الضيف بالدينار.
  IntColumn get teacherAmount => integer().withDefault(const Constant(0))();

  /// رمز تذكرة QR لمرة واحدة (`G-...`)؛ `null` لضيف منتسب يدخل برمزه العادي.
  TextColumn get ticketCode => text().nullable()();

  /// وقت استعمال التذكرة (مسحها عند الدخول)؛ `null` لم تُستعمل بعد.
  IntColumn get usedAt => integer().nullable()();
}

/// حضور الأساتذة. [sessionId] فارغ عند «حضور عام» دون حصة.
@DataClassName('TeacherAttendanceRow')
@TableIndex(
  name: 'idx_teacher_attendance_teacher',
  columns: {#teacherId, #date},
)
@TableIndex(name: 'idx_teacher_attendance_session', columns: {#sessionId})
@TableIndex(name: 'idx_teacher_attendance_updated', columns: {#updatedAt})
class TeacherAttendance extends Table with SyncColumns {
  TextColumn get teacherId => text().references(Teachers, #id)();

  TextColumn get sessionId => text().nullable().references(Sessions, #id)();

  TextColumn get date => text()();

  IntColumn get checkIn => integer().nullable()();

  IntColumn get checkOut => integer().nullable()();

  IntColumn get lateMinutes => integer().withDefault(const Constant(0))();
}

/// حضور العمال: سجل واحد لكل عامل في اليوم.
@DataClassName('WorkerAttendanceRow')
@TableIndex(
  name: 'idx_worker_attendance_day',
  columns: {#workerId, #date},
  unique: true,
)
@TableIndex(name: 'idx_worker_attendance_date', columns: {#date})
@TableIndex(name: 'idx_worker_attendance_updated', columns: {#updatedAt})
class WorkerAttendance extends Table with SyncColumns {
  TextColumn get workerId => text().references(Workers, #id)();

  TextColumn get date => text()();

  IntColumn get checkIn => integer().nullable()();

  IntColumn get checkOut => integer().nullable()();

  /// دقائق التأخر للعرض فقط؛ لا أثر مالي لها.
  IntColumn get lateMinutes => integer().withDefault(const Constant(0))();

  /// تعديل المدير اليدوي لليوم: `off` / `half` / `full`، أو `null` دون تعديل.
  TextColumn get overrideKind => text().nullable()();
}

/// طلبات الأستاذ لتغيير الحصص.
@DataClassName('SessionRequestRow')
@TableIndex(name: 'idx_session_requests_status', columns: {#status, #createdAt})
@TableIndex(name: 'idx_session_requests_teacher', columns: {#teacherId})
@TableIndex(name: 'idx_session_requests_group', columns: {#groupId})
@TableIndex(name: 'idx_session_requests_updated', columns: {#updatedAt})
class SessionRequests extends Table with SyncColumns {
  TextColumn get teacherId => text().references(Teachers, #id)();

  TextColumn get groupId => text().references(Groups, #id)();

  /// `reschedule` / `add` / `advance` / `cancel`.
  TextColumn get type => text()();

  /// الحصة المعنية؛ فارغ عند «إضافة حصة».
  TextColumn get sessionId => text().nullable().references(Sessions, #id)();

  TextColumn get newDate => text().nullable()();

  IntColumn get newStartMinutes => integer().nullable()();

  IntColumn get newEndMinutes => integer().nullable()();

  TextColumn get newRoomId => text().nullable().references(Rooms, #id)();

  TextColumn get reason => text().withDefault(const Constant(''))();

  /// `pending` / `approved` / `rejected`.
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// معرّف من راجع الطلب.
  TextColumn get reviewedBy => text().nullable()();

  IntColumn get reviewedAt => integer().nullable()();

  TextColumn get adminNote => text().withDefault(const Constant(''))();
}
