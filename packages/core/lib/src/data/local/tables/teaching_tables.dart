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

  /// مبلغ الأستاذ لكل تلميذ في هذه المجموعة؛ `null` يعني قيمة الأستاذ الافتراضية.
  IntColumn get ratePerStudent => integer().nullable()();

  /// وقت الأرشفة عند «سنة جديدة»؛ `null` يعني أن المجموعة نشطة.
  IntColumn get archivedAt => integer().nullable()();
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
