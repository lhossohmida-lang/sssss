import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import 'date_key.dart';

/// حال حصة في كشف تلميذ.
enum ChildSessionState {
  present('حضر'),
  absent('غاب'),
  excused('غاب برخصة'),
  cancelled('أُلغيت'),

  /// لم يحن وقتها بعد.
  upcoming('قادمة'),

  /// انتهى وقتها ولم يُسجَّل حضور بعد.
  pending('لم يُسجَّل');

  const ChildSessionState(this.label);

  final String label;

  /// هل تُحسب في حضوره وغيابه؟
  bool get counted => this == present || this == absent || this == excused;
}

/// حصة من حصص مجموعة التلميذ وحاله فيها.
class ChildSession {
  const ChildSession({
    required this.sessionId,
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    required this.state,
  });

  final String sessionId;
  final String date;
  final int startMinutes;
  final int endMinutes;
  final ChildSessionState state;

  /// يوم الشهر (1..31).
  int get day => int.parse(date.substring(8));
}

/// عدّادات حضوره في مجموعة خلال شهر.
class ChildAttendanceSummary {
  const ChildAttendanceSummary({
    required this.present,
    required this.absent,
    required this.excused,
  });

  final int present;
  final int absent;
  final int excused;

  int get total => present + absent + excused;
}

/// كشف حضور تلميذ في مجموعة (مادة) لشهر، حصة بحصة، ليراه وليّه.
class ChildAttendanceService {
  ChildAttendanceService(this.db, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase db;
  final DateTime Function() _now;

  /// كشف الشهر [month] (`YYYY-MM`)، ويتحدث مع كل تغيير في الحصص أو الحضور.
  Stream<List<ChildSession>> watchMonth(
    String studentId,
    String groupId,
    String month,
  ) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {db.sessions, db.attendance, db.groupStudents},
        )
        .watch()
        .asyncMap((_) => sessions(studentId, groupId, month));
  }

  /// حصص المجموعة في [month] مرتبة بالتاريخ والوقت، بحال التلميذ في كل منها.
  ///
  /// الحصة التي لا سجل حضور له فيها تُعدّ من كشفه إن وقعت في فترة انتسابه
  /// (من انضمامه إلى مغادرته)، فلا تظهر له حصص سبقت انضمامه.
  Future<List<ChildSession>> sessions(
    String studentId,
    String groupId,
    String month,
  ) async {
    final enrolment =
        await (db.select(db.groupStudents)
              ..where(
                (e) =>
                    e.studentId.equals(studentId) &
                    e.groupId.equals(groupId) &
                    e.deletedAt.isNull(),
              )
              ..orderBy([(e) => OrderingTerm.desc(e.joinedAt)])
              ..limit(1))
            .getSingleOrNull();
    if (enrolment == null) return const [];
    final joined = _dateOf(enrolment.joinedAt);
    final left = enrolment.leftAt == null ? null : _dateOf(enrolment.leftAt!);

    final rows = await db
        .customSelect(
          'SELECT se.id, se.date, se.start_minutes, se.end_minutes, '
          'se.status AS session_status, se.closed_at, '
          'a.status AS attendance_status FROM sessions se '
          'LEFT JOIN attendance a ON a.session_id = se.id '
          'AND a.student_id = ? AND a.deleted_at IS NULL '
          'WHERE se.group_id = ? AND se.deleted_at IS NULL '
          'AND se.date >= ? AND se.date < ? '
          'ORDER BY se.date, se.start_minutes, se.id',
          variables: [
            Variable<String>(studentId),
            Variable<String>(groupId),
            Variable<String>('$month-01'),
            Variable<String>('${DateKey.shiftMonth(month, 1)}-01'),
          ],
          readsFrom: {db.sessions, db.attendance},
        )
        .get();

    final now = _now();
    final today = DateKey.of(now);
    final minutes = DateKey.minutesOf(now);
    final result = <ChildSession>[];
    for (final row in rows) {
      final date = row.read<String>('date');
      final end = row.read<int>('end_minutes');
      final marked = row.read<String?>('attendance_status');
      final cancelled = row.read<String>('session_status') == 'cancelled';
      if (marked == null) {
        // خارج فترة انتسابه: ليست من كشفه.
        if (date.compareTo(joined) < 0) continue;
        if (left != null && date.compareTo(left) > 0) continue;
      }
      final ChildSessionState state;
      if (cancelled) {
        state = ChildSessionState.cancelled;
      } else if (marked != null) {
        state = switch (marked) {
          'present' => ChildSessionState.present,
          'excused' => ChildSessionState.excused,
          _ => ChildSessionState.absent,
        };
      } else if (date.compareTo(today) > 0 ||
          (date == today &&
              end > minutes &&
              row.read<int?>('closed_at') == null)) {
        state = ChildSessionState.upcoming;
      } else {
        state = ChildSessionState.pending;
      }
      result.add(
        ChildSession(
          sessionId: row.read<String>('id'),
          date: date,
          startMinutes: row.read<int>('start_minutes'),
          endMinutes: end,
          state: state,
        ),
      );
    }
    return result;
  }

  /// عدّادات [sessions] (الحاضر والغائب والغائب برخصة).
  static ChildAttendanceSummary summarize(List<ChildSession> sessions) {
    var present = 0;
    var absent = 0;
    var excused = 0;
    for (final s in sessions) {
      switch (s.state) {
        case ChildSessionState.present:
          present++;
        case ChildSessionState.absent:
          absent++;
        case ChildSessionState.excused:
          excused++;
        case ChildSessionState.cancelled ||
            ChildSessionState.upcoming ||
            ChildSessionState.pending:
          break;
      }
    }
    return ChildAttendanceSummary(
      present: present,
      absent: absent,
      excused: excused,
    );
  }

  static String _dateOf(int millis) => DateKey.of(
    DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal(),
  );
}
