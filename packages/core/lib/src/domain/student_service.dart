import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'catalog_service.dart';
import 'dues_service.dart';
import 'enums.dart';
import 'pricing.dart';

/// مجموعة ينتسب إليها التلميذ، مع حضوره فيها وما بقي عليه.
class EnrolmentInfo {
  const EnrolmentInfo({
    required this.enrolment,
    required this.groupNumber,
    required this.subjectName,
    required this.teacherName,
    required this.present,
    required this.absent,
    required this.excused,
    required this.remaining,
  });

  final GroupStudentRow enrolment;
  final int groupNumber;
  final String subjectName;
  final String teacherName;

  /// عدد حصصه حاضراً، غائباً، وغائباً برخصة في هذه المجموعة.
  final int present;
  final int absent;
  final int excused;

  /// مجموع ما لم يدفعه من دورات هذه المجموعة.
  final int remaining;

  String get groupId => enrolment.groupId;

  /// سعر الدورة بعد التخفيض.
  int get netPrice => Pricing.netPrice(
    price: enrolment.monthlyPrice,
    discountType: DiscountType.fromCode(enrolment.discountType),
    discountValue: enrolment.discountValue,
  );
}

/// قائمة انتظار ينتظر فيها التلميذ.
class WaitingInfo {
  const WaitingInfo({
    required this.entryId,
    required this.subjectName,
    this.levelName,
  });

  final String entryId;
  final String subjectName;
  final String? levelName;
}

/// ملف التلميذ كاملاً كما يُعرض في شاشته.
class StudentProfile {
  const StudentProfile({
    required this.student,
    required this.levelName,
    required this.parent,
    required this.enrolments,
    required this.waiting,
    required this.registrationFeeRemaining,
    required this.transportRemaining,
  });

  final StudentRow student;
  final String? levelName;
  final ParentRow? parent;
  final List<EnrolmentInfo> enrolments;
  final List<WaitingInfo> waiting;

  /// الباقي من حقوق التسجيل في كل الفترات.
  final int registrationFeeRemaining;

  /// الباقي من نقل الشهر الحالي.
  final int transportRemaining;

  String get fullName => '${student.firstName} ${student.lastName}';

  /// مجموع ما بقي من دورات كل المجموعات.
  int get cyclesRemaining => enrolments.fold(0, (sum, e) => sum + e.remaining);

  /// مجموع كل ما عليه.
  int get totalRemaining =>
      cyclesRemaining + registrationFeeRemaining + transportRemaining;
}

/// ملف التلميذ: قراءته كاملاً، وتعديل بياناته، ومغادرة المجموعات، وحذفه.
class StudentService {
  StudentService(this.db, this.writer, this.dues);

  final AppDatabase db;
  final SyncWriter writer;
  final DuesService dues;

  static const String fieldFirstName = 'first_name';
  static const String fieldLastName = 'last_name';
  static const String fieldTransport = 'transport';

  /// ملف التلميذ، ويتحدث مع كل تغيير في بياناته أو حضوره أو مدفوعاته.
  /// يعطي `null` إن لم يوجد أو حُذف. [month] شهر التقويم الحالي `YYYY-MM`.
  Stream<StudentProfile?> watch(String studentId, {required String month}) {
    // استعلام خفيف يراقب الجداول المعنية؛ عند أي تغيير يُعاد بناء الملف.
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            db.students,
            db.parents,
            db.levels,
            db.groupStudents,
            db.groups,
            db.subjects,
            db.teachers,
            db.waitingEntries,
            db.waitingLists,
            db.attendance,
            db.payments,
            db.studentCredits,
            db.registrationFees,
          },
        )
        .watch()
        .asyncMap((_) => load(studentId, month: month));
  }

  /// ملف التلميذ الآن؛ `null` إن لم يوجد أو حُذف.
  Future<StudentProfile?> load(
    String studentId, {
    required String month,
  }) async {
    final row = await db
        .customSelect(
          'SELECT s.*, l.name AS level_name FROM students s '
          'LEFT JOIN levels l ON l.id = s.level_id '
          'WHERE s.id = ? AND s.deleted_at IS NULL',
          variables: [Variable<String>(studentId)],
          readsFrom: {db.students, db.levels},
        )
        .getSingleOrNull();
    if (row == null) return null;
    final student = db.students.map(row.data);
    final parentId = student.parentAccountId;
    final parent = parentId == null
        ? null
        : await (db.select(
            db.parents,
          )..where((p) => p.id.equals(parentId))).getSingleOrNull();

    final unpaid = await dues.cycleDues(studentId: studentId, unpaidOnly: true);
    final remainingByGroup = <String, int>{};
    for (final due in unpaid) {
      remainingByGroup[due.groupId] =
          (remainingByGroup[due.groupId] ?? 0) + due.remaining;
    }

    // الحضور مجمَّع لكل مجموعة في استعلام واحد.
    final enrolmentRows = await db
        .customSelect(
          'SELECT gs.*, g.number AS group_number, sub.name AS subject_name, '
          't.name AS teacher_name, '
          "COALESCE(SUM(a.status = 'present'), 0) AS present, "
          "COALESCE(SUM(a.status = 'absent'), 0) AS absent, "
          "COALESCE(SUM(a.status = 'excused'), 0) AS excused "
          'FROM group_students gs '
          'JOIN groups g ON g.id = gs.group_id '
          'JOIN subjects sub ON sub.id = g.subject_id '
          'JOIN teachers t ON t.id = g.teacher_id '
          'LEFT JOIN sessions se ON se.group_id = gs.group_id '
          'AND se.deleted_at IS NULL '
          'LEFT JOIN attendance a ON a.session_id = se.id '
          'AND a.student_id = gs.student_id AND a.deleted_at IS NULL '
          'WHERE gs.student_id = ? AND gs.deleted_at IS NULL '
          'AND gs.left_at IS NULL '
          'GROUP BY gs.id ORDER BY sub.name, g.number',
          variables: [Variable<String>(studentId)],
          readsFrom: {
            db.groupStudents,
            db.groups,
            db.subjects,
            db.teachers,
            db.sessions,
            db.attendance,
          },
        )
        .get();

    final waitingRows = await db
        .customSelect(
          'SELECT e.id, sub.name AS subject_name, l.name AS level_name '
          'FROM waiting_entries e '
          'JOIN waiting_lists w ON w.id = e.waiting_list_id '
          'JOIN subjects sub ON sub.id = w.subject_id '
          'LEFT JOIN levels l ON l.id = w.level_id '
          'WHERE e.student_id = ? AND e.deleted_at IS NULL '
          'AND w.deleted_at IS NULL ORDER BY sub.name',
          variables: [Variable<String>(studentId)],
          readsFrom: {
            db.waitingEntries,
            db.waitingLists,
            db.subjects,
            db.levels,
          },
        )
        .get();

    final feeRow = await db
        .customSelect(
          'SELECT COALESCE(SUM(MAX(f.amount - COALESCE(('
          'SELECT SUM(p.amount) FROM payments p WHERE p.student_id = f.student_id '
          "AND p.type = 'registration' AND p.period_key = f.period_key "
          'AND p.deleted_at IS NULL), 0), 0)), 0) AS remaining '
          'FROM registration_fees f '
          'WHERE f.student_id = ? AND f.deleted_at IS NULL',
          variables: [Variable<String>(studentId)],
          readsFrom: {db.registrationFees, db.payments},
        )
        .getSingle();

    return StudentProfile(
      student: student,
      levelName: row.read<String?>('level_name'),
      parent: parent,
      enrolments: [
        for (final e in enrolmentRows)
          EnrolmentInfo(
            enrolment: db.groupStudents.map(e.data),
            groupNumber: e.read<int>('group_number'),
            subjectName: e.read<String>('subject_name'),
            teacherName: e.read<String>('teacher_name'),
            present: e.read<int>('present'),
            absent: e.read<int>('absent'),
            excused: e.read<int>('excused'),
            remaining: remainingByGroup[e.read<String>('group_id')] ?? 0,
          ),
      ],
      waiting: [
        for (final w in waitingRows)
          WaitingInfo(
            entryId: w.read<String>('id'),
            subjectName: w.read<String>('subject_name'),
            levelName: w.read<String?>('level_name'),
          ),
      ],
      registrationFeeRemaining: feeRow.read<int>('remaining'),
      transportRemaining: await dues.transportRemaining(
        studentId: studentId,
        month: month,
      ),
    );
  }

  /// يعدّل بيانات التلميذ. يعيد `false` إن لم يوجد. يرمي
  /// [ValidationException] إن كانت البيانات غير صالحة.
  Future<bool> update(
    String studentId, {
    required String firstName,
    required String lastName,
    required String? levelId,
    required bool usesTransport,
    required int transportPrice,
    String? transportLineId,
  }) async {
    final errors = <String, String>{};
    if (firstName.trim().isEmpty) errors[fieldFirstName] = 'أدخل الاسم';
    if (lastName.trim().isEmpty) errors[fieldLastName] = 'أدخل اللقب';
    if (usesTransport) {
      if (transportPrice <= 0) {
        errors[fieldTransport] = 'أدخل سعر النقل الشهري';
      } else if (transportPrice % 10 != 0) {
        errors[fieldTransport] = 'السعر من مضاعفات 10 دج';
      }
    }
    if (errors.isNotEmpty) throw ValidationException(errors);
    return writer.patch(
      db.students,
      key: {'id': studentId},
      values: {
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'level_id': levelId,
        'uses_transport': usesTransport ? 1 : 0,
        'transport_price': usesTransport ? transportPrice : 0,
        'transport_line_id': usesTransport ? transportLineId : null,
      },
    );
  }

  /// يسجّل مغادرة التلميذ للمجموعة. دوراته السابقة ومستحقاتها تبقى، ولا
  /// تُحسب عليه دورات تبدأ بعد مغادرته. يعيد `false` إن لم يكن منتسباً.
  Future<bool> leaveGroup(String studentId, String groupId) async {
    final enrolment =
        await (db.select(db.groupStudents)..where(
              (e) =>
                  e.studentId.equals(studentId) &
                  e.groupId.equals(groupId) &
                  e.deletedAt.isNull() &
                  e.leftAt.isNull(),
            ))
            .getSingleOrNull();
    if (enrolment == null) return false;
    return writer.patch(
      db.groupStudents,
      key: {'id': enrolment.id},
      values: {'left_at': writer.now()},
    );
  }

  /// يزيل التلميذ من قائمة انتظار.
  Future<bool> leaveWaiting(String entryId) =>
      writer.softDelete(db.waitingEntries, key: {'id': entryId});

  /// يحذف التلميذ حذفاً ناعماً: يغادر مجموعاته وقوائم انتظاره، وتبقى
  /// مدفوعاته وحضوره في السجلات. يعيد `false` إن لم يوجد أو كان محذوفاً.
  Future<bool> remove(String studentId) {
    return db.transaction(() async {
      final removed = await writer.softDelete(
        db.students,
        key: {'id': studentId},
      );
      if (!removed) return false;
      final stamp = writer.now();
      final enrolments =
          await (db.select(db.groupStudents)..where(
                (e) =>
                    e.studentId.equals(studentId) &
                    e.deletedAt.isNull() &
                    e.leftAt.isNull(),
              ))
              .get();
      for (final e in enrolments) {
        await writer.patch(
          db.groupStudents,
          key: {'id': e.id},
          values: {'left_at': stamp},
        );
      }
      final entries =
          await (db.select(db.waitingEntries)..where(
                (e) => e.studentId.equals(studentId) & e.deletedAt.isNull(),
              ))
              .get();
      for (final e in entries) {
        await writer.softDelete(db.waitingEntries, key: {'id': e.id});
      }
      return true;
    });
  }
}
