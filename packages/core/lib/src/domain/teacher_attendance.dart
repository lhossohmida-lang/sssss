import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'date_key.dart';
import 'enums.dart';
import 'stable_id.dart';

/// حالة حضور الأستاذ لحصة.
enum TeacherSessionStatus {
  /// مسح دخوله لهذه الحصة.
  present('حضر'),

  /// انتهت الحصة (أو أُغلقت) ولم يحضرها.
  absent('لم يحضر'),

  /// لم تنتهِ الحصة بعد.
  pending('لم تنتهِ');

  const TeacherSessionStatus(this.label);
  final String label;
}

/// حصة في كشف الأستاذ.
class TeacherSessionRow {
  const TeacherSessionRow({
    required this.sessionId,
    required this.groupNumber,
    required this.subjectName,
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    required this.status,
    required this.lateMinutes,
    this.checkIn,
    this.checkOut,
  });

  final String sessionId;
  final int groupNumber;
  final String subjectName;
  final String date;
  final int startMinutes;
  final int endMinutes;
  final TeacherSessionStatus status;
  final int lateMinutes;
  final int? checkIn;
  final int? checkOut;

  String get groupLabel => 'المجموعة $groupNumber · $subjectName';
}

/// كشف شهر أستاذ.
class TeacherMonth {
  const TeacherMonth({
    required this.teacherId,
    required this.name,
    required this.sessions,
  });

  final String teacherId;
  final String name;

  /// حصص الشهر غير الملغاة بالترتيب الزمني.
  final List<TeacherSessionRow> sessions;

  int get attended =>
      sessions.where((s) => s.status == TeacherSessionStatus.present).length;

  int get missed =>
      sessions.where((s) => s.status == TeacherSessionStatus.absent).length;

  /// الحصص التي انتهت (حضرها أو غاب عنها).
  int get held => attended + missed;

  int get totalLateMinutes => sessions.fold(0, (sum, s) => sum + s.lateMinutes);
}

/// حصة لم يحضرها أستاذها (للتنبيه).
class MissedSession {
  const MissedSession({
    required this.sessionId,
    required this.teacherId,
    required this.teacherName,
    required this.groupNumber,
    required this.subjectName,
    required this.date,
    required this.startMinutes,
  });

  final String sessionId;
  final String teacherId;
  final String teacherName;
  final int groupNumber;
  final String subjectName;
  final String date;
  final int startMinutes;
}

/// حضور الأساتذة: كشف الشهر، والحصص التي لم يحضرها أستاذها، وتسجيل حضورهم
/// يدوياً عند نسيان المسح.
class TeacherAttendanceQueries {
  TeacherAttendanceQueries(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  Set<ResultSetImplementation<dynamic, dynamic>> get _tables => {
    db.sessions,
    db.groups,
    db.teachers,
    db.subjects,
    db.teacherAttendance,
  };

  /// كشف شهر [month] (`YYYY-MM`) لكل الأساتذة الذين لهم حصص فيه، ولحظياً.
  Stream<List<TeacherMonth>> watchSheet(String month) {
    return db
        .customSelect('SELECT 1', readsFrom: _tables)
        .watch()
        .asyncMap((_) => sheet(month, now: DateTime.now()));
  }

  Future<List<TeacherMonth>> sheet(
    String month, {
    required DateTime now,
  }) async {
    final rows = await _sessionRows(
      from: '$month-01',
      to: '$month-31',
      now: now,
    );
    final byTeacher = <String, List<_Row>>{};
    for (final row in rows) {
      byTeacher.putIfAbsent(row.teacherId, () => []).add(row);
    }
    final months = [
      for (final entry in byTeacher.entries)
        TeacherMonth(
          teacherId: entry.key,
          name: entry.value.first.teacherName,
          sessions: [for (final r in entry.value) r.session],
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return months;
  }

  /// حصص انتهت ولم يحضرها أستاذها منذ [since] (مفتاح تاريخ) حتى [now]،
  /// الأحدث أولاً، ولحظياً.
  Stream<List<MissedSession>> watchMissed({required String since}) {
    return db
        .customSelect('SELECT 1', readsFrom: _tables)
        .watch()
        .asyncMap((_) => missed(since: since, now: DateTime.now()));
  }

  Future<List<MissedSession>> missed({
    required String since,
    required DateTime now,
  }) async {
    final rows = await _sessionRows(from: since, to: '9999-12-31', now: now);
    return [
      for (final r in rows)
        if (r.session.status == TeacherSessionStatus.absent)
          MissedSession(
            sessionId: r.session.sessionId,
            teacherId: r.teacherId,
            teacherName: r.teacherName,
            groupNumber: r.session.groupNumber,
            subjectName: r.session.subjectName,
            date: r.session.date,
            startMinutes: r.session.startMinutes,
          ),
    ]..sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.startMinutes.compareTo(a.startMinutes);
    });
  }

  /// يسجّل حضور الأستاذ لحصة يدوياً (نسي المسح). يعيد `false` إن كان
  /// مسجَّلاً أصلاً أو الحصة غير موجودة أو ملغاة.
  Future<bool> markPresent(String sessionId) {
    return db.transaction(() async {
      final session =
          await (db.select(db.sessions)..where(
                (s) =>
                    s.id.equals(sessionId) &
                    s.deletedAt.isNull() &
                    s.status.equals(SessionStatus.cancelled.code).not(),
              ))
              .getSingleOrNull();
      if (session == null) return false;
      final group = await (db.select(
        db.groups,
      )..where((g) => g.id.equals(session.groupId))).getSingle();
      final id = StableId.teacherAttendance(group.teacherId, sessionId);
      final existing = await (db.select(
        db.teacherAttendance,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (existing != null &&
          existing.deletedAt == null &&
          existing.checkIn != null) {
        return false;
      }
      final stamp = writer.now();
      if (existing == null) {
        await writer.save(
          db.teacherAttendance,
          TeacherAttendanceRow(
            id: id,
            createdAt: stamp,
            updatedAt: stamp,
            teacherId: group.teacherId,
            sessionId: sessionId,
            date: session.date,
            checkIn: stamp,
            lateMinutes: 0,
          ),
          key: {'id': id},
        );
      } else {
        await writer.save(
          db.teacherAttendance,
          existing.copyWith(
            checkIn: Value(stamp),
            deletedAt: const Value(null),
          ),
          key: {'id': id},
        );
      }
      return true;
    });
  }

  Future<List<_Row>> _sessionRows({
    required String from,
    required String to,
    required DateTime now,
  }) async {
    final today = DateKey.of(now);
    final minutes = DateKey.minutesOf(now);
    final rows = await db
        .customSelect(
          'SELECT se.id, se.date, se.start_minutes, se.end_minutes, '
          'se.closed_at, g.number, sub.name AS subject, t.id AS teacher_id, '
          't.name AS teacher, ta.check_in, ta.check_out, ta.late_minutes '
          'FROM sessions se JOIN groups g ON g.id = se.group_id '
          'JOIN teachers t ON t.id = g.teacher_id '
          'JOIN subjects sub ON sub.id = g.subject_id '
          'LEFT JOIN teacher_attendance ta ON ta.session_id = se.id '
          'AND ta.teacher_id = g.teacher_id AND ta.deleted_at IS NULL '
          'WHERE se.date >= ? AND se.date <= ? AND se.deleted_at IS NULL '
          "AND se.status <> 'cancelled' AND g.deleted_at IS NULL "
          'AND t.deleted_at IS NULL '
          'ORDER BY se.date, se.start_minutes, g.number',
          variables: [Variable<String>(from), Variable<String>(to)],
          readsFrom: _tables,
        )
        .get();
    return [
      for (final row in rows)
        _Row(
          teacherId: row.read<String>('teacher_id'),
          teacherName: row.read<String>('teacher'),
          session: TeacherSessionRow(
            sessionId: row.read<String>('id'),
            groupNumber: row.read<int>('number'),
            subjectName: row.read<String>('subject'),
            date: row.read<String>('date'),
            startMinutes: row.read<int>('start_minutes'),
            endMinutes: row.read<int>('end_minutes'),
            lateMinutes: row.read<int?>('late_minutes') ?? 0,
            checkIn: row.read<int?>('check_in'),
            checkOut: row.read<int?>('check_out'),
            status: row.read<int?>('check_in') != null
                ? TeacherSessionStatus.present
                : (row.read<int?>('closed_at') != null ||
                          row.read<String>('date').compareTo(today) < 0 ||
                          (row.read<String>('date') == today &&
                              row.read<int>('end_minutes') <= minutes)
                      ? TeacherSessionStatus.absent
                      : TeacherSessionStatus.pending),
          ),
        ),
    ];
  }
}

class _Row {
  const _Row({
    required this.teacherId,
    required this.teacherName,
    required this.session,
  });

  final String teacherId;
  final String teacherName;
  final TeacherSessionRow session;
}
