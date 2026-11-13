import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'catalog_service.dart';
import 'date_key.dart';

/// اختبار أو تقييم لمجموعة: عنوانه وتاريخه وما أُدخل من نتائجه.
class AssessmentSummary {
  const AssessmentSummary({
    required this.title,
    required this.date,
    required this.count,
    required this.average,
    required this.maxScore,
  });

  final String title;
  final String date;

  /// عدد النتائج المُدخلة.
  final int count;

  /// متوسط النتائج (بسلّمها).
  final double average;
  final double maxScore;
}

/// نتيجة تلميذ في اختبار (أو لم تُدخل بعد).
class GradeEntry {
  const GradeEntry({
    required this.studentId,
    required this.name,
    this.gradeId,
    this.score,
    this.note = '',
  });

  final String studentId;
  final String name;
  final String? gradeId;
  final double? score;
  final String note;
}

/// نتيجة تلميذ في اختبار كما يراها وليّه.
class ChildGrade {
  const ChildGrade({
    required this.id,
    required this.title,
    required this.date,
    required this.score,
    required this.maxScore,
    required this.note,
  });

  final String id;
  final String title;
  final String date;
  final double score;
  final double maxScore;
  final String note;

  /// العلامة منسوبة إلى 20 (سلّم المدارس الجزائرية) لتُقارن النتائج بسلالم
  /// مختلفة.
  double get outOf20 => score / maxScore * 20;
}

/// ما يُدخله الأستاذ لتلميذ: علامته (أو `null` لعدم الإدخال) وملاحظته.
typedef GradeInput = ({double? score, String note});

/// النتائج والملاحظات: إدخال اختبار لكل تلاميذ المجموعة دفعة واحدة، وتعديله
/// وحذفه، وقراءة اختبارات المجموعة بمتوسطاتها.
class GradeService {
  GradeService(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  static const String fieldTitle = 'title';
  static const String fieldDate = 'date';
  static const String fieldMax = 'max';
  static const String fieldGroup = 'group';

  /// مفتاح خطأ علامة تلميذ.
  static String fieldScore(String studentId) => 'score:$studentId';

  static final RegExp _dateKey = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// اختبارات المجموعة الأحدث أولاً، ولحظياً.
  Stream<List<AssessmentSummary>> watchAssessments(String groupId) {
    return db
        .customSelect('SELECT 1', readsFrom: {db.grades})
        .watch()
        .asyncMap((_) => assessments(groupId));
  }

  Future<List<AssessmentSummary>> assessments(String groupId) async {
    final rows = await db
        .customSelect(
          'SELECT title, date, COUNT(*) AS n, AVG(score) AS avg, '
          'MAX(max_score) AS max FROM grades '
          'WHERE group_id = ? AND deleted_at IS NULL '
          'GROUP BY title, date ORDER BY date DESC, title',
          variables: [Variable<String>(groupId)],
          readsFrom: {db.grades},
        )
        .get();
    return [
      for (final row in rows)
        AssessmentSummary(
          title: row.read<String>('title'),
          date: row.read<String>('date'),
          count: row.read<int>('n'),
          average: row.read<double>('avg'),
          maxScore: row.read<double>('max'),
        ),
    ];
  }

  /// تلاميذ المجموعة الحاليون مع نتائجهم في الاختبار [title] بتاريخ [date]
  /// (فارغة إن لم تُدخل). من غادر المجموعة وله نتيجة يبقى ظاهراً.
  Future<List<GradeEntry>> entries(
    String groupId, {
    required String title,
    required String date,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT s.id, s.first_name, s.last_name, g.id AS grade_id, '
          'g.score, g.note FROM students s '
          'LEFT JOIN grades g ON g.student_id = s.id AND g.group_id = ? '
          'AND g.title = ? AND g.date = ? AND g.deleted_at IS NULL '
          'WHERE s.deleted_at IS NULL AND (g.id IS NOT NULL OR EXISTS ('
          'SELECT 1 FROM group_students gs WHERE gs.student_id = s.id '
          'AND gs.group_id = ? AND gs.deleted_at IS NULL '
          'AND gs.left_at IS NULL)) '
          'ORDER BY s.last_name, s.first_name, s.id',
          variables: [
            Variable<String>(groupId),
            Variable<String>(title),
            Variable<String>(date),
            Variable<String>(groupId),
          ],
          readsFrom: {db.students, db.grades, db.groupStudents},
        )
        .get();
    return [
      for (final row in rows)
        GradeEntry(
          studentId: row.read<String>('id'),
          name:
              '${row.read<String>('first_name')} '
              '${row.read<String>('last_name')}',
          gradeId: row.read<String?>('grade_id'),
          score: row.read<double?>('score'),
          note: row.read<String?>('note') ?? '',
        ),
    ];
  }

  /// يحفظ اختباراً لمجموعة: لكل تلميذ علامته وملاحظته. من لم تُدخل علامته
  /// لا نتيجة له (وتُحذف إن كانت مدخلة من قبل). يعيد عدد النتائج المحفوظة.
  ///
  /// [teacherId] يشترط أن تكون المجموعة له (تطبيق الأستاذ). [originalTitle]
  /// و[originalDate] لاختبار يُعاد تسميته أو تأريخه: تُنقل نتائجه القديمة.
  Future<int> saveAssessment({
    required String groupId,
    required String title,
    required String date,
    required Map<String, GradeInput> results,
    double maxScore = 20,
    String? teacherId,
    String? originalTitle,
    String? originalDate,
  }) async {
    final errors = <String, String>{};
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) errors[fieldTitle] = 'أدخل عنوان الاختبار';
    if (!_dateKey.hasMatch(date)) errors[fieldDate] = 'اختر التاريخ';
    if (maxScore <= 0 || maxScore > 1000) {
      errors[fieldMax] = 'السلّم موجب ولا يزيد عن 1000';
    }
    for (final entry in results.entries) {
      final score = entry.value.score;
      if (score != null && (score < 0 || score > maxScore)) {
        errors[fieldScore(entry.key)] = 'العلامة بين 0 و${_fmt(maxScore)}';
      }
    }
    if (errors.isNotEmpty) throw ValidationException(errors);

    return db.transaction(() async {
      final group =
          await (db.select(db.groups)
                ..where((g) => g.id.equals(groupId) & g.deletedAt.isNull()))
              .getSingleOrNull();
      if (group == null ||
          (teacherId != null && group.teacherId != teacherId)) {
        throw ValidationException.field(
          fieldGroup,
          'هذه المجموعة ليست من مجموعاتك',
        );
      }
      final fromTitle = originalTitle ?? cleanTitle;
      final fromDate = originalDate ?? date;
      var saved = 0;
      for (final entry in results.entries) {
        final existing =
            await (db.select(db.grades)..where(
                  (g) =>
                      g.groupId.equals(groupId) &
                      g.studentId.equals(entry.key) &
                      g.title.equals(fromTitle) &
                      g.date.equals(fromDate) &
                      g.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        final score = entry.value.score;
        if (score == null) {
          if (existing != null) {
            await writer.softDelete(db.grades, key: {'id': existing.id});
          }
          continue;
        }
        final stamp = writer.now();
        final row = GradeRow(
          id: existing?.id ?? writer.newId(),
          createdAt: existing?.createdAt ?? stamp,
          updatedAt: stamp,
          studentId: entry.key,
          groupId: groupId,
          title: cleanTitle,
          score: score,
          maxScore: maxScore,
          note: entry.value.note.trim(),
          date: date,
        );
        await writer.save(db.grades, row, key: {'id': row.id});
        saved++;
      }
      return saved;
    });
  }

  /// يحذف اختباراً بكل نتائجه (حذف ناعم). يعيد عدد ما حُذف.
  Future<int> deleteAssessment(
    String groupId, {
    required String title,
    required String date,
    String? teacherId,
  }) {
    return db.transaction(() async {
      final group = await (db.select(
        db.groups,
      )..where((g) => g.id.equals(groupId))).getSingleOrNull();
      if (group == null ||
          (teacherId != null && group.teacherId != teacherId)) {
        throw ValidationException.field(
          fieldGroup,
          'هذه المجموعة ليست من مجموعاتك',
        );
      }
      final rows =
          await (db.select(db.grades)..where(
                (g) =>
                    g.groupId.equals(groupId) &
                    g.title.equals(title) &
                    g.date.equals(date) &
                    g.deletedAt.isNull(),
              ))
              .get();
      for (final row in rows) {
        await writer.softDelete(db.grades, key: {'id': row.id});
      }
      return rows.length;
    });
  }

  /// نتائج تلميذ في مجموعة، الأحدث أولاً، ولحظياً.
  Stream<List<ChildGrade>> watchForStudent(String studentId, String groupId) {
    return db
        .customSelect('SELECT 1', readsFrom: {db.grades})
        .watch()
        .asyncMap((_) => forStudent(studentId, groupId));
  }

  Future<List<ChildGrade>> forStudent(String studentId, String groupId) async {
    final rows =
        await (db.select(db.grades)
              ..where(
                (g) =>
                    g.studentId.equals(studentId) &
                    g.groupId.equals(groupId) &
                    g.deletedAt.isNull(),
              )
              ..orderBy([
                (g) => OrderingTerm.desc(g.date),
                (g) => OrderingTerm.asc(g.title),
                (g) => OrderingTerm.asc(g.id),
              ]))
            .get();
    return [
      for (final g in rows)
        ChildGrade(
          id: g.id,
          title: g.title,
          date: g.date,
          score: g.score,
          maxScore: g.maxScore,
          note: g.note,
        ),
    ];
  }

  /// متوسط [grades] منسوباً إلى 20، أو `null` إن لم توجد نتائج.
  static double? averageOutOf20(List<ChildGrade> grades) {
    if (grades.isEmpty) return null;
    return grades.fold<double>(0, (sum, g) => sum + g.outOf20) / grades.length;
  }

  /// «15.5» أو «20» بلا كسر زائد.
  static String _fmt(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value';

  /// تنسيق علامة للعرض.
  static String format(double value) => _fmt(value);

  /// اليوم بمفتاحه (للتاريخ الافتراضي).
  static String today() => DateKey.of(DateTime.now());
}
