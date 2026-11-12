import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import 'date_key.dart';

/// حصة قادمة لتلميذ: موعدها الفعلي (بعد أي تغيير وافقت عليه الإدارة).
class UpcomingSession {
  const UpcomingSession({
    required this.sessionId,
    required this.groupId,
    required this.groupNumber,
    required this.subjectName,
    required this.teacherName,
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    required this.cancelled,
    this.roomName,
  });

  final String sessionId;
  final String groupId;
  final int groupNumber;
  final String subjectName;
  final String teacherName;
  final String date;
  final int startMinutes;
  final int endMinutes;

  /// هل أُلغيت (لتُعرض مشطوبة فيعرف الوليّ أنها لن تُعقد)؟
  final bool cancelled;
  final String? roomName;

  String get timeText =>
      '${DateKey.formatMinutes(startMinutes)} - '
      '${DateKey.formatMinutes(endMinutes)}';
}

/// الحصص القادمة لتلميذ في مجموعاته الحالية.
class ChildScheduleQueries {
  ChildScheduleQueries(this.db, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase db;
  final DateTime Function() _now;

  /// أول [limit] حصة قادمة، ولحظياً.
  Stream<List<UpcomingSession>> watchUpcoming(
    String studentId, {
    int limit = 10,
  }) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            db.sessions,
            db.groups,
            db.groupStudents,
            db.rooms,
            db.subjects,
            db.teachers,
          },
        )
        .watch()
        .asyncMap((_) => upcoming(studentId, limit: limit));
  }

  /// الحصص من الآن فصاعداً بترتيب موعدها: حصص اليوم التي لم ينتهِ وقتها وما
  /// بعدها، لمجموعات ينتسب إليها التلميذ حالياً. الملغاة تُدرج وتُعلَّم.
  Future<List<UpcomingSession>> upcoming(
    String studentId, {
    int limit = 10,
  }) async {
    final now = _now();
    final today = DateKey.of(now);
    final minutes = DateKey.minutesOf(now);
    final rows = await db
        .customSelect(
          'SELECT se.id, se.group_id, se.date, se.start_minutes, '
          'se.end_minutes, se.status, g.number, sub.name AS subject, '
          't.name AS teacher, r.name AS room FROM sessions se '
          'JOIN groups g ON g.id = se.group_id '
          'JOIN subjects sub ON sub.id = g.subject_id '
          'JOIN teachers t ON t.id = g.teacher_id '
          'LEFT JOIN rooms r ON r.id = COALESCE(se.room_id, g.room_id) '
          'AND r.deleted_at IS NULL '
          'WHERE se.deleted_at IS NULL AND g.deleted_at IS NULL '
          'AND g.archived_at IS NULL AND se.closed_at IS NULL '
          'AND se.group_id IN (SELECT en.group_id FROM group_students en '
          'WHERE en.student_id = ? AND en.deleted_at IS NULL '
          'AND en.left_at IS NULL) '
          'AND (se.date > ? OR (se.date = ? AND se.end_minutes > ?)) '
          'ORDER BY se.date, se.start_minutes, g.number, se.id LIMIT ?',
          variables: [
            Variable<String>(studentId),
            Variable<String>(today),
            Variable<String>(today),
            Variable<int>(minutes),
            Variable<int>(limit),
          ],
          readsFrom: {
            db.sessions,
            db.groups,
            db.groupStudents,
            db.rooms,
            db.subjects,
            db.teachers,
          },
        )
        .get();
    return [
      for (final row in rows)
        UpcomingSession(
          sessionId: row.read<String>('id'),
          groupId: row.read<String>('group_id'),
          groupNumber: row.read<int>('number'),
          subjectName: row.read<String>('subject'),
          teacherName: row.read<String>('teacher'),
          date: row.read<String>('date'),
          startMinutes: row.read<int>('start_minutes'),
          endMinutes: row.read<int>('end_minutes'),
          cancelled: row.read<String>('status') == 'cancelled',
          roomName: row.read<String?>('room'),
        ),
    ];
  }
}
