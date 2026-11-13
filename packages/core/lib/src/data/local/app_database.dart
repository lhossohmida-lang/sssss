import 'package:drift/drift.dart';

import 'tables/finance_tables.dart';
import 'tables/messaging_tables.dart';
import 'tables/people_tables.dart';
import 'tables/system_tables.dart';
import 'tables/teaching_tables.dart';

part 'app_database.g.dart';

/// القاعدة المحلية (SQLite). كل شاشة تقرأ منها أولاً ولا تنتظر الشبكة.
@DriftDatabase(
  tables: [
    Settings,
    Levels,
    TransportLines,
    Parents,
    Students,
    Subjects,
    Rooms,
    Teachers,
    TeacherSubjects,
    Workers,
    Groups,
    GroupSlots,
    GroupStudents,
    WaitingLists,
    WaitingEntries,
    Sessions,
    Attendance,
    TeacherAttendance,
    WorkerAttendance,
    SessionRequests,
    Payments,
    StudentCredits,
    RegistrationFees,
    TeacherPayouts,
    ExpenseCategories,
    Expenses,
    SmsQueue,
    SmsTemplates,
    ChatRooms,
    ChatMembers,
    ChatMessages,
    Grades,
    GroupFiles,
    Notifications,
    UserAccounts,
    AuditLog,
    Outbox,
    SyncState,
    DeviceSession,
    LocalCredentials,
    DeviceInfo,
    UploadQueue,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // 2: بيانات الجهاز المحلية (بادئة الوصولات).
      if (from < 2) await m.createTable(deviceInfo);
      // 3: ربط رسائل الأحداث بمصدرها لمنع التكرار وإلغاء المؤجل منها.
      if (from < 3) {
        await m.addColumn(smsQueue, smsQueue.eventKey);
        await m.createIndex(idxSmsQueueEventKey);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
