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
    Contacts,
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
    SessionGuests,
    Attendance,
    TeacherAttendance,
    WorkerAttendance,
    SessionRequests,
    Payments,
    StudentCredits,
    RegistrationFees,
    TeacherPayouts,
    StaffDebts,
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
  int get schemaVersion => 6;

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
      // 4: ديون صاحب المدرسة لأساتذته وعماله وتسديدها.
      if (from < 4) {
        await m.createTable(staffDebts);
        await m.createIndex(idxStaffDebtsStaff);
        await m.createIndex(idxStaffDebtsDate);
        await m.createIndex(idxStaffDebtsUpdated);
      }
      // 5: سعر الشهر لكل فوج. الفوج القائم يأخذ سعر مادته ومبلغ أستاذه الحاليين فتصير لكل فوج قيمتاه
      // (ما يقرؤه الخادم بالترحيل 0010 نفسه، فتتفق الأجهزة دون مزامنة).
      if (from < 5) {
        await m.addColumn(groups, groups.monthlyPrice);
        await customStatement(
          'UPDATE groups SET monthly_price = COALESCE((SELECT s.monthly_price '
          'FROM subjects s WHERE s.id = groups.subject_id), 0) '
          'WHERE monthly_price = 0',
        );
        await customStatement(
          'UPDATE groups SET rate_per_student = (SELECT t.rate_per_student '
          'FROM teachers t WHERE t.id = groups.teacher_id) '
          'WHERE rate_per_student IS NULL',
        );
      }
      // 6: الأفواج المنتظِرة وحصص المراجعة، وما يأخذه الأستاذ عن كل تلميذ، والتلاميذ لمرة واحدة وضيوف
      // الحصص، ودليل الهواتف (الترحيل 0011 على الخادم).
      if (from < 6) {
        await m.addColumn(groups, groups.waitingTarget);
        await m.addColumn(groups, groups.startAlertedAt);
        await m.addColumn(groups, groups.isReview);
        await m.addColumn(groupStudents, groupStudents.teacherAmount);
        await m.addColumn(students, students.singleUse);
        await m.createTable(sessionGuests);
        await m.createIndex(idxSessionGuestsPair);
        await m.createIndex(idxSessionGuestsTicket);
        await m.createIndex(idxSessionGuestsStudent);
        await m.createIndex(idxSessionGuestsUpdated);
        await m.createTable(contacts);
        await m.createIndex(idxContactsPhone);
        await m.createIndex(idxContactsName);
        await m.createIndex(idxContactsUpdated);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
