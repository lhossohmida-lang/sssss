import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'catalog_service.dart';
import 'cycle_service.dart';
import 'dues_service.dart';
import 'enums.dart';
import 'stable_id.dart';

/// مجموعة تُعرض للاختيار عند التسجيل: أستاذها وعدد تلاميذها.
class GroupOption {
  const GroupOption({
    required this.group,
    required this.teacherName,
    required this.studentCount,
  });

  final GroupRow group;
  final String teacherName;
  final int studentCount;

  String get id => group.id;

  /// الاسم الظاهر، مثل «المجموعة 2 · الأستاذ كمال».
  String get label => 'المجموعة ${group.number} · $teacherName';
}

/// انتساب التلاميذ إلى المجموعات وقوائم الانتظار.
class EnrolmentService {
  EnrolmentService(this.db, this.writer, this.dues, this.cycles);

  final AppDatabase db;
  final SyncWriter writer;
  final DuesService dues;
  final CycleService cycles;

  static const String fieldPrice = 'price';
  static const String fieldDiscount = 'discount';
  static const String fieldGroup = 'group';

  /// أخطاء السعر والتخفيض: اسم الحقل ← الرسالة. فارغة إن كانا سليمين.
  static Map<String, String> priceErrors({
    required int price,
    required DiscountType discountType,
    required int discountValue,
  }) {
    final errors = <String, String>{};
    if (price < 0) {
      errors[fieldPrice] = 'السعر لا يكون سالباً';
    } else if (price % 10 != 0) {
      errors[fieldPrice] = 'السعر من مضاعفات 10 دج';
    }
    switch (discountType) {
      case DiscountType.none || DiscountType.exempt:
        break;
      case DiscountType.percent:
        if (discountValue < 1 || discountValue > 100) {
          errors[fieldDiscount] = 'النسبة من 1 إلى 100';
        }
      case DiscountType.fixed:
        if (discountValue < 10 || discountValue % 10 != 0) {
          errors[fieldDiscount] = 'مبلغ التخفيض من مضاعفات 10 دج';
        } else if (discountValue > price) {
          errors[fieldDiscount] = 'التخفيض أكبر من السعر';
        }
    }
    return errors;
  }

  /// المجموعات النشطة لمادة، مرتبة برقمها.
  Future<List<GroupOption>> groupsForSubject(String subjectId) async {
    final rows = await db
        .customSelect(
          'SELECT g.*, t.name AS teacher_name, '
          '(SELECT COUNT(*) FROM group_students gs WHERE gs.group_id = g.id '
          'AND gs.deleted_at IS NULL AND gs.left_at IS NULL) AS student_count '
          'FROM groups g JOIN teachers t ON t.id = g.teacher_id '
          'WHERE g.subject_id = ? AND g.deleted_at IS NULL '
          'AND g.archived_at IS NULL ORDER BY g.number',
          variables: [Variable<String>(subjectId)],
          readsFrom: {db.groups, db.teachers, db.groupStudents},
        )
        .get();
    return [
      for (final row in rows)
        GroupOption(
          group: db.groups.map(row.data),
          teacherName: row.read<String>('teacher_name'),
          studentCount: row.read<int>('student_count'),
        ),
    ];
  }

  /// أساتذة المادة الأحياء، مرتبين بالاسم.
  Future<List<TeacherRow>> teachersOfSubject(String subjectId) async {
    final rows = await db
        .customSelect(
          'SELECT t.* FROM teachers t '
          'JOIN teacher_subjects ts ON ts.teacher_id = t.id '
          'WHERE ts.subject_id = ? AND ts.deleted_at IS NULL '
          'AND t.deleted_at IS NULL ORDER BY t.name',
          variables: [Variable<String>(subjectId)],
          readsFrom: {db.teachers, db.teacherSubjects},
        )
        .get();
    return [for (final row in rows) db.teachers.map(row.data)];
  }

  /// ينسب التلميذ إلى المجموعة بسعره وتخفيضه.
  ///
  /// - دورة الالتحاق هي الدورة الحالية، وأول حصة له هي التالية لما انعقد
  ///   منها، فيُنشأ رصيد الحصص الفائتة (إجابة 49) إن التحق في منتصفها.
  /// - من غادر ثم عاد يُعاد انتسابه بنفس السجل.
  /// - يُزال من قائمة انتظار مادة المجموعة إن كان فيها.
  ///
  /// يرمي [ValidationException] إن كان منتسباً أصلاً، أو المجموعة مؤرشفة، أو
  /// السعر والتخفيض غير صالحين.
  Future<GroupStudentRow> enrol({
    required String studentId,
    required String groupId,
    required int monthlyPrice,
    DiscountType discountType = DiscountType.none,
    int discountValue = 0,
  }) {
    final errors = priceErrors(
      price: monthlyPrice,
      discountType: discountType,
      discountValue: discountValue,
    );
    if (errors.isNotEmpty) throw ValidationException(errors);

    return db.transaction(() async {
      final group = await (db.select(
        db.groups,
      )..where((g) => g.id.equals(groupId))).getSingleOrNull();
      if (group == null ||
          group.deletedAt != null ||
          group.archivedAt != null) {
        throw ValidationException.field(fieldGroup, 'المجموعة غير متاحة');
      }
      final id = StableId.groupStudent(groupId, studentId);
      final existing = await (db.select(
        db.groupStudents,
      )..where((e) => e.id.equals(id))).getSingleOrNull();
      if (existing != null &&
          existing.deletedAt == null &&
          existing.leftAt == null) {
        throw ValidationException.field(
          fieldGroup,
          'التلميذ منتسب إلى هذه المجموعة',
        );
      }
      final held = await cycles.countedSessions(
        groupId,
        group.currentCycleNumber,
        closedOnly: true,
      );
      final firstSession = held + 1 > group.sessionsPerCycle
          ? group.sessionsPerCycle
          : held + 1;
      final stamp = writer.now();
      await writer.save(
        db.groupStudents,
        GroupStudentsCompanion.insert(
          id: id,
          createdAt: stamp,
          updatedAt: stamp,
          groupId: groupId,
          studentId: studentId,
          joinedAt: stamp,
          joinedAtCycleNumber: Value(group.currentCycleNumber),
          joinedAtSessionNumber: Value(firstSession),
          monthlyPrice: monthlyPrice,
          discountType: Value(discountType.code),
          discountValue: Value(
            discountType == DiscountType.none ||
                    discountType == DiscountType.exempt
                ? 0
                : discountValue,
          ),
          leftAt: const Value(null),
          deletedAt: const Value(null),
        ),
        key: {'id': id},
      );
      await dues.createMidJoinCredit(studentId: studentId, groupId: groupId);
      await _leaveWaiting(studentId, group.subjectId);
      return (db.select(
        db.groupStudents,
      )..where((e) => e.id.equals(id))).getSingle();
    });
  }

  /// يضيف التلميذ إلى قائمة انتظار المادة في مستواه (تُنشأ القائمة إن لم
  /// توجد). يعيد معرّف القائمة. من كان فيها أصلاً لا يتكرر.
  Future<String> addToWaiting({
    required String studentId,
    required String subjectId,
    String? levelId,
    String? preferredTeacherId,
  }) {
    return db.transaction(() async {
      final listId = StableId.waitingList(subjectId, levelId);
      final list = await (db.select(
        db.waitingLists,
      )..where((l) => l.id.equals(listId))).getSingleOrNull();
      final stamp = writer.now();
      if (list == null || list.deletedAt != null) {
        await writer.save(
          db.waitingLists,
          WaitingListsCompanion.insert(
            id: listId,
            createdAt: stamp,
            updatedAt: stamp,
            subjectId: subjectId,
            levelId: Value(levelId),
            preferredTeacherId: Value(preferredTeacherId),
            deletedAt: const Value(null),
          ),
          key: {'id': listId},
        );
      } else if (list.preferredTeacherId == null &&
          preferredTeacherId != null) {
        await writer.patch(
          db.waitingLists,
          key: {'id': listId},
          values: {'preferred_teacher_id': preferredTeacherId},
        );
      }
      final entryId = StableId.waitingEntry(listId, studentId);
      final entry = await (db.select(
        db.waitingEntries,
      )..where((e) => e.id.equals(entryId))).getSingleOrNull();
      if (entry == null || entry.deletedAt != null) {
        await writer.save(
          db.waitingEntries,
          WaitingEntriesCompanion.insert(
            id: entryId,
            createdAt: stamp,
            updatedAt: stamp,
            waitingListId: listId,
            studentId: studentId,
            addedAt: stamp,
            deletedAt: const Value(null),
          ),
          key: {'id': entryId},
        );
      }
      return listId;
    });
  }

  /// يزيل التلميذ من قوائم انتظار المادة (بعد انتسابه إلى مجموعة فيها).
  Future<void> _leaveWaiting(String studentId, String subjectId) async {
    final rows = await db
        .customSelect(
          'SELECT e.id FROM waiting_entries e '
          'JOIN waiting_lists l ON l.id = e.waiting_list_id '
          'WHERE e.student_id = ? AND l.subject_id = ? '
          'AND e.deleted_at IS NULL',
          variables: [Variable<String>(studentId), Variable<String>(subjectId)],
          readsFrom: {db.waitingEntries, db.waitingLists},
        )
        .get();
    for (final row in rows) {
      await writer.softDelete(
        db.waitingEntries,
        key: {'id': row.read<String>('id')},
      );
    }
  }
}
