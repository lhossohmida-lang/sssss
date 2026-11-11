import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:school_core/school_core.dart';

/// قاعدة في الذاكرة مع كاتب بوقت ومعرّفات محسومة، لتبسيط الاختبارات.
class TestEnv {
  TestEnv() : db = AppDatabase(NativeDatabase.memory()) {
    writer = SyncWriter(
      db,
      actor: () => const Actor(userId: 'u1', userName: 'المدير'),
      clock: () => time,
      idGenerator: () => 'id-${++_ids}',
    );
  }

  final AppDatabase db;
  late final SyncWriter writer;
  int time = 1000;
  int _ids = 0;

  Future<void> close() => db.close();

  Future<void> subject({String id = 'sub', int price = 2000}) => db
      .into(db.subjects)
      .insert(
        SubjectsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          name: 'رياضيات',
          monthlyPrice: Value(price),
        ),
      );

  Future<void> teacher({String id = 't1', int rate = 1000}) => db
      .into(db.teachers)
      .insert(
        TeachersCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          name: 'الأستاذ $id',
          phone: '0770000000',
          email: '$id@school.local',
          qrCode: 'T-$id',
          ratePerStudent: Value(rate),
        ),
      );

  Future<void> room({String id = 'r1'}) => db
      .into(db.rooms)
      .insert(
        RoomsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          name: 'القاعة $id',
        ),
      );

  Future<void> student({String id = 's1'}) => db
      .into(db.students)
      .insert(
        StudentsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          firstName: 'تلميذ',
          lastName: id,
          parentPhone: '0550123456',
          qrCode: 'S-$id',
        ),
      );

  Future<void> group({
    String id = 'g1',
    String teacherId = 't1',
    String subjectId = 'sub',
    String? roomId,
    int sessionsPerCycle = 8,
    int? rate,
  }) => db
      .into(db.groups)
      .insert(
        GroupsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          number: 1,
          subjectId: subjectId,
          teacherId: teacherId,
          roomId: Value(roomId),
          sessionsPerCycle: Value(sessionsPerCycle),
          ratePerStudent: Value(rate),
        ),
      );

  /// خانة أسبوعية: [weekday] من 1 (الاثنين) إلى 7 (الأحد).
  Future<void> slot({
    required String id,
    String groupId = 'g1',
    required int weekday,
    int start = 600,
    int end = 690,
    String? roomId,
  }) => db
      .into(db.groupSlots)
      .insert(
        GroupSlotsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          groupId: groupId,
          weekday: weekday,
          startMinutes: start,
          endMinutes: end,
          roomId: Value(roomId),
        ),
      );

  Future<void> enroll({
    required String id,
    String groupId = 'g1',
    required String studentId,
    int price = 2000,
    String discountType = 'none',
    int discountValue = 0,
    int joinedCycle = 1,
    int joinedSession = 1,
  }) => db
      .into(db.groupStudents)
      .insert(
        GroupStudentsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          groupId: groupId,
          studentId: studentId,
          joinedAt: 1,
          monthlyPrice: price,
          discountType: Value(discountType),
          discountValue: Value(discountValue),
          joinedAtCycleNumber: Value(joinedCycle),
          joinedAtSessionNumber: Value(joinedSession),
        ),
      );
}
