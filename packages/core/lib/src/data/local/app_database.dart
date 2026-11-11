import 'package:drift/drift.dart';

import 'tables/people_tables.dart';
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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
