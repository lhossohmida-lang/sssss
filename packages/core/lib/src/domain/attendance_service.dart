import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'catalog_service.dart';
import 'cycle_service.dart';
import 'date_key.dart';
import 'dues_service.dart';
import 'enums.dart';
import 'payout_service.dart';
import 'stable_id.dart';

/// حصة في قائمة يوم، مع عدّادات حضورها.
class DaySession {
  const DaySession({
    required this.session,
    required this.groupNumber,
    required this.subjectName,
    required this.teacherName,
    required this.students,
    required this.present,
    required this.absent,
    required this.excused,
    this.roomName,
  });

  final SessionRow session;
  final int groupNumber;
  final String subjectName;
  final String teacherName;
  final String? roomName;

  /// عدد تلاميذ المجموعة المنتسبين لهذه الحصة.
  final int students;
  final int present;
  final int absent;
  final int excused;

  String get id => session.id;
  bool get cancelled => session.status == SessionStatus.cancelled.code;
  bool get closed => session.closedAt != null;

  /// عدد من لم يُسجَّل لهم شيء بعد.
  int get unmarked => students - present - absent - excused;
}

/// تلميذ في ورقة حضور حصة.
class RosterStudent {
  const RosterStudent({
    required this.studentId,
    required this.name,
    this.status,
    this.method,
  });

  final String studentId;
  final String name;

  /// حالته المسجَّلة، و`null` إن لم يُسجَّل شيء.
  final AttendanceStatus? status;
  final AttendanceMethod? method;
}

/// ورقة حضور حصة: بياناتها وتلاميذها بحالاتهم.
class SessionRoster {
  const SessionRoster({
    required this.session,
    required this.groupNumber,
    required this.subjectName,
    required this.teacherName,
    required this.students,
  });

  final SessionRow session;
  final int groupNumber;
  final String subjectName;
  final String teacherName;
  final List<RosterStudent> students;

  bool get cancelled => session.status == SessionStatus.cancelled.code;
  bool get closed => session.closedAt != null;

  int count(AttendanceStatus status) =>
      students.where((s) => s.status == status).length;

  int get unmarked => students.where((s) => s.status == null).length;
}

/// الحضور اليدوي لتلاميذ الحصص، والتغييب التلقائي عند نهايتها.
///
/// «غائب برخصة» يمنحها المدير أو العامل المخوَّل فقط (قرار 44)؛ الخدمة
/// تشترط ذلك صراحةً بوسيط `canExcuse` حتى لا يتجاوزه تطبيق الأستاذ.
class AttendanceService {
  AttendanceService(this.db, this.writer, this.cycles, this.dues);

  final AppDatabase db;
  final SyncWriter writer;
  final CycleService cycles;
  final DuesService dues;

  late final PayoutService _payouts = PayoutService(db, writer, dues);

  // ---------------------------------------------------------------------------
  // القراءة
  // ---------------------------------------------------------------------------

  /// حصص يوم [date] (غير المحذوفة، وفيها الملغاة) بعدّاداتها، وتتحدث لحظياً.
  Stream<List<DaySession>> watchDay(String date) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            db.sessions,
            db.attendance,
            db.groups,
            db.groupStudents,
            db.subjects,
            db.teachers,
            db.rooms,
          },
        )
        .watch()
        .asyncMap((_) => day(date));
  }

  Future<List<DaySession>> day(String date) async {
    final rows = await db
        .customSelect(
          'SELECT se.id AS session_id, g.number, sub.name AS subject, '
          't.name AS teacher, r.name AS room, '
          '(SELECT COUNT(*) FROM group_students gs WHERE gs.group_id = g.id '
          'AND gs.deleted_at IS NULL AND gs.left_at IS NULL '
          'AND gs.joined_at_cycle_number <= se.cycle_number) AS students, '
          "COALESCE(SUM(a.status = 'present'), 0) AS present, "
          "COALESCE(SUM(a.status = 'absent'), 0) AS absent, "
          "COALESCE(SUM(a.status = 'excused'), 0) AS excused "
          'FROM sessions se '
          'JOIN groups g ON g.id = se.group_id '
          'JOIN subjects sub ON sub.id = g.subject_id '
          'JOIN teachers t ON t.id = g.teacher_id '
          'LEFT JOIN rooms r ON r.id = COALESCE(se.room_id, g.room_id) '
          'LEFT JOIN attendance a ON a.session_id = se.id '
          'AND a.deleted_at IS NULL '
          'WHERE se.date = ? AND se.deleted_at IS NULL AND g.deleted_at IS NULL '
          'GROUP BY se.id ORDER BY se.start_minutes, g.number',
          variables: [Variable<String>(date)],
          readsFrom: {
            db.sessions,
            db.attendance,
            db.groups,
            db.groupStudents,
            db.subjects,
            db.teachers,
            db.rooms,
          },
        )
        .get();
    if (rows.isEmpty) return const [];
    final sessions = {
      for (final s in await (db.select(
        db.sessions,
      )..where((s) => s.date.equals(date) & s.deletedAt.isNull())).get())
        s.id: s,
    };
    return [
      for (final row in rows)
        DaySession(
          session: sessions[row.read<String>('session_id')]!,
          groupNumber: row.read<int>('number'),
          subjectName: row.read<String>('subject'),
          teacherName: row.read<String>('teacher'),
          roomName: row.read<String?>('room'),
          students: row.read<int>('students'),
          present: row.read<int>('present'),
          absent: row.read<int>('absent'),
          excused: row.read<int>('excused'),
        ),
    ];
  }

  /// ورقة حضور الحصة، وتتحدث لحظياً. `null` إن لم توجد الحصة.
  Stream<SessionRoster?> watchRoster(String sessionId) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            db.sessions,
            db.attendance,
            db.groupStudents,
            db.students,
            db.groups,
          },
        )
        .watch()
        .asyncMap((_) => roster(sessionId));
  }

  Future<SessionRoster?> roster(String sessionId) async {
    final session =
        await (db.select(db.sessions)
              ..where((s) => s.id.equals(sessionId) & s.deletedAt.isNull()))
            .getSingleOrNull();
    if (session == null) return null;
    final info = await db
        .customSelect(
          'SELECT g.number, sub.name AS subject, t.name AS teacher '
          'FROM groups g JOIN subjects sub ON sub.id = g.subject_id '
          'JOIN teachers t ON t.id = g.teacher_id WHERE g.id = ?',
          variables: [Variable<String>(session.groupId)],
          readsFrom: {db.groups, db.subjects, db.teachers},
        )
        .getSingle();

    // المنتسبون الحاليون لهذه الدورة، ومن سُجّل له حضور فيها وإن غادر.
    final rows = await db
        .customSelect(
          'SELECT s.id, s.first_name, s.last_name, a.status, a.method '
          'FROM students s '
          'LEFT JOIN attendance a ON a.student_id = s.id AND a.session_id = ? '
          'AND a.deleted_at IS NULL '
          'WHERE s.deleted_at IS NULL AND (a.id IS NOT NULL OR EXISTS ('
          'SELECT 1 FROM group_students gs WHERE gs.student_id = s.id '
          'AND gs.group_id = ? AND gs.deleted_at IS NULL '
          'AND gs.left_at IS NULL AND gs.joined_at_cycle_number <= ?)) '
          'ORDER BY s.last_name, s.first_name, s.id',
          variables: [
            Variable<String>(sessionId),
            Variable<String>(session.groupId),
            Variable<int>(session.cycleNumber),
          ],
          readsFrom: {db.students, db.attendance, db.groupStudents},
        )
        .get();
    return SessionRoster(
      session: session,
      groupNumber: info.read<int>('number'),
      subjectName: info.read<String>('subject'),
      teacherName: info.read<String>('teacher'),
      students: [
        for (final row in rows)
          RosterStudent(
            studentId: row.read<String>('id'),
            name:
                '${row.read<String>('first_name')} '
                '${row.read<String>('last_name')}',
            status: row.read<String?>('status') == null
                ? null
                : AttendanceStatus.fromCode(row.read<String>('status')),
            method: row.read<String?>('method') == null
                ? null
                : AttendanceMethod.fromCode(row.read<String>('method')),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // الكتابة
  // ---------------------------------------------------------------------------

  /// يسجّل حالة [studentId] في [sessionId] يدوياً (أو يغيّرها).
  ///
  /// يسمح بالتصحيح بعد إغلاق الحصة (كتحويل غياب تلقائي إلى «برخصة»). رصيد
  /// الغياب برخصة يُنشأ أو يُحذف تبعاً للحالة.
  Future<void> mark({
    required String sessionId,
    required String studentId,
    required AttendanceStatus status,
    bool canExcuse = false,
  }) async {
    if (status == AttendanceStatus.excused && !canExcuse) {
      throw ValidationException.field(
        'attendance',
        'تسجيل «غائب برخصة» للمدير أو العامل المخوَّل فقط',
      );
    }
    await db.transaction(() async {
      final session = await _openSession(sessionId);
      if (!await _inRoster(session, studentId)) {
        throw ValidationException.field(
          'attendance',
          'التلميذ ليس في هذه الحصة',
        );
      }
      await _write(session, studentId, status);
    });
  }

  /// يمسح تسجيل التلميذ في حصة لم تُغلق (تراجعاً عن خطأ).
  Future<void> clear({required String sessionId, required String studentId}) {
    return db.transaction(() async {
      final session = await _openSession(sessionId);
      if (session.closedAt != null) {
        throw ValidationException.field(
          'attendance',
          'الحصة مغلقة: غيّر الحالة بدل مسحها',
        );
      }
      await writer.softDelete(
        db.attendance,
        key: {'id': StableId.attendance(sessionId, studentId)},
      );
      await dues.syncExcusedCredit(sessionId: sessionId, studentId: studentId);
    });
  }

  /// يسجّل حاضراً كل من لم يُسجَّل له شيء بعد. يعيد عددهم.
  Future<int> markAllPresent(String sessionId) {
    return db.transaction(() async {
      final session = await _openSession(sessionId);
      final pending = await _unmarked(session);
      for (final studentId in pending) {
        await _write(session, studentId, AttendanceStatus.present);
      }
      return pending.length;
    });
  }

  /// يغلق الحصص المنتهية ([now] بعد نهايتها) ولم تُغلق: يسجّل غائباً كل من لم
  /// يُسجَّل له شيء، ثم يغلق الحصة، ثم يكمل الدورة إن اكتملت بها.
  ///
  /// الحصص تُعالج بالترتيب الزمني، لتنتقل الدورة سليمة. يعيد عدد الحصص
  /// المغلقة. آمن عند التكرار.
  Future<int> closeDueSessions(DateTime now) async {
    final today = DateKey.of(now);
    final minutes = DateKey.minutesOf(now);
    final due = await db
        .customSelect(
          'SELECT se.id FROM sessions se JOIN groups g ON g.id = se.group_id '
          'WHERE se.deleted_at IS NULL AND se.closed_at IS NULL '
          "AND se.status <> 'cancelled' AND g.deleted_at IS NULL "
          'AND g.archived_at IS NULL '
          'AND (se.date < ? OR (se.date = ? AND se.end_minutes <= ?)) '
          'ORDER BY se.date, se.start_minutes, se.id',
          variables: [
            Variable<String>(today),
            Variable<String>(today),
            Variable<int>(minutes),
          ],
          readsFrom: {db.sessions, db.groups},
        )
        .get();
    var closed = 0;
    for (final row in due) {
      final id = row.read<String>('id');
      final done = await db.transaction(() async {
        final session = await (db.select(
          db.sessions,
        )..where((s) => s.id.equals(id))).getSingle();
        // قد تُغلق أو تُلغى أثناء معالجة سابقتها (إكمال الدورة ينقل الحصص).
        if (session.closedAt != null ||
            session.status == SessionStatus.cancelled.code) {
          return false;
        }
        for (final studentId in await _unmarked(session)) {
          await _write(session, studentId, AttendanceStatus.absent);
        }
        await cycles.closeSession(id);
        final finished = await cycles.completeCycleIfDone(
          session.groupId,
          fromDate: DateKey.next(session.date),
        );
        // اكتمال الدورة يُنشئ خلاص الأستاذ عنها بما دُفع حتى الآن.
        if (finished != null) {
          await _payouts.createCyclePayout(session.groupId, finished);
        }
        return true;
      });
      if (done) closed++;
    }
    return closed;
  }

  // ---------------------------------------------------------------------------
  // داخلي
  // ---------------------------------------------------------------------------

  Future<SessionRow> _openSession(String sessionId) async {
    final session =
        await (db.select(db.sessions)
              ..where((s) => s.id.equals(sessionId) & s.deletedAt.isNull()))
            .getSingleOrNull();
    if (session == null) {
      throw ValidationException.field('attendance', 'الحصة غير موجودة');
    }
    if (session.status == SessionStatus.cancelled.code) {
      throw ValidationException.field('attendance', 'الحصة ملغاة');
    }
    return session;
  }

  Future<bool> _inRoster(SessionRow session, String studentId) async {
    final row = await db
        .customSelect(
          'SELECT 1 FROM group_students gs WHERE gs.student_id = ? '
          'AND gs.group_id = ? AND gs.deleted_at IS NULL '
          'AND gs.left_at IS NULL AND gs.joined_at_cycle_number <= ? '
          'UNION SELECT 1 FROM attendance a WHERE a.student_id = ? '
          'AND a.session_id = ? AND a.deleted_at IS NULL LIMIT 1',
          variables: [
            Variable<String>(studentId),
            Variable<String>(session.groupId),
            Variable<int>(session.cycleNumber),
            Variable<String>(studentId),
            Variable<String>(session.id),
          ],
          readsFrom: {db.groupStudents, db.attendance},
        )
        .getSingleOrNull();
    return row != null;
  }

  /// المنتسبون لهذه الحصة ولا تسجيل لهم.
  Future<List<String>> _unmarked(SessionRow session) async {
    final rows = await db
        .customSelect(
          'SELECT gs.student_id FROM group_students gs '
          'JOIN students s ON s.id = gs.student_id AND s.deleted_at IS NULL '
          'WHERE gs.group_id = ? AND gs.deleted_at IS NULL '
          'AND gs.left_at IS NULL AND gs.joined_at_cycle_number <= ? '
          'AND NOT EXISTS (SELECT 1 FROM attendance a '
          'WHERE a.session_id = ? AND a.student_id = gs.student_id '
          'AND a.deleted_at IS NULL) ORDER BY gs.student_id',
          variables: [
            Variable<String>(session.groupId),
            Variable<int>(session.cycleNumber),
            Variable<String>(session.id),
          ],
          readsFrom: {db.groupStudents, db.students, db.attendance},
        )
        .get();
    return [for (final r in rows) r.read<String>('student_id')];
  }

  Future<void> _write(
    SessionRow session,
    String studentId,
    AttendanceStatus status,
  ) async {
    final id = StableId.attendance(session.id, studentId);
    final existing = await (db.select(
      db.attendance,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
    if (existing != null &&
        existing.deletedAt == null &&
        existing.status == status.code) {
      return;
    }
    final stamp = writer.now();
    final row = existing == null
        ? AttendanceRow(
            id: id,
            createdAt: stamp,
            updatedAt: stamp,
            sessionId: session.id,
            studentId: studentId,
            status: status.code,
            method: AttendanceMethod.manual.code,
          )
        : existing.copyWith(
            status: status.code,
            method: AttendanceMethod.manual.code,
            deletedAt: const Value(null),
          );
    await writer.save(db.attendance, row, key: {'id': id});
    await dues.syncExcusedCredit(sessionId: session.id, studentId: studentId);
  }
}
