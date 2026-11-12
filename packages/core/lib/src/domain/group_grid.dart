import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import 'enums.dart';

/// خلية في شبكة الحضور: حالة التلميذ في حصة، أو `null` إن لم تُسجَّل.
typedef GridCells = Map<String, AttendanceStatus>;

/// تلميذ في شبكة الدورة مع حالاته في حصصها.
class GridStudent {
  const GridStudent({
    required this.studentId,
    required this.name,
    required this.cells,
    required this.leftGroup,
  });

  final String studentId;
  final String name;

  /// معرّف الحصة ← حالة حضوره فيها.
  final GridCells cells;

  /// هل غادر المجموعة (يظهر لأن له حضوراً في هذه الدورة)؟
  final bool leftGroup;

  int count(AttendanceStatus status) =>
      cells.values.where((s) => s == status).length;
}

/// شبكة حضور دورة: حصصها بالترتيب الزمني، وتلاميذها بحالاتهم فيها.
class GroupGrid {
  const GroupGrid({
    required this.group,
    required this.cycleNumber,
    required this.sessions,
    required this.students,
  });

  final GroupRow group;
  final int cycleNumber;

  /// حصص الدورة بالترتيب الزمني، وفيها الملغاة (تُعرض باهتة).
  final List<SessionRow> sessions;
  final List<GridStudent> students;

  /// هل هذه الدورة الحالية للمجموعة؟
  bool get isCurrent => cycleNumber == group.currentCycleNumber;

  /// الحصص المحسوبة (غير الملغاة).
  int get countedSessions => sessions
      .where((s) => SessionStatus.fromCode(s.status).countsInCycle)
      .length;

  /// الحصص المنعقدة (المُغلقة المحسوبة).
  int get heldSessions => sessions
      .where(
        (s) =>
            SessionStatus.fromCode(s.status).countsInCycle &&
            s.closedAt != null,
      )
      .length;
}

/// استعلام شبكة الحضور لدورة من دورات مجموعة، باستعلامات مجمّعة لا لكل خلية.
class GroupGridQueries {
  GroupGridQueries(this.db);

  final AppDatabase db;

  /// الشبكة، وتتحدث مع كل تغيّر في الحصص أو الحضور أو الانتساب. يعيد `null`
  /// إن لم توجد المجموعة. [cycleNumber] الافتراضي هو الدورة الحالية.
  Stream<GroupGrid?> watch(String groupId, {int? cycleNumber}) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            db.groups,
            db.sessions,
            db.attendance,
            db.groupStudents,
            db.students,
          },
        )
        .watch()
        .asyncMap((_) => load(groupId, cycleNumber: cycleNumber));
  }

  Future<GroupGrid?> load(String groupId, {int? cycleNumber}) async {
    final group =
        await (db.select(db.groups)
              ..where((g) => g.id.equals(groupId) & g.deletedAt.isNull()))
            .getSingleOrNull();
    if (group == null) return null;
    final cycle = cycleNumber ?? group.currentCycleNumber;

    final sessions =
        await (db.select(db.sessions)
              ..where(
                (s) =>
                    s.groupId.equals(groupId) &
                    s.cycleNumber.equals(cycle) &
                    s.deletedAt.isNull(),
              )
              ..orderBy([
                (s) => OrderingTerm(expression: s.date),
                (s) => OrderingTerm(expression: s.startMinutes),
              ]))
            .get();

    // التلاميذ: من انتسب حتى هذه الدورة، ومن غادر وله حضور فيها.
    final studentRows = await db
        .customSelect(
          'SELECT s.id, s.first_name, s.last_name, gs.left_at FROM students s '
          'JOIN group_students gs ON gs.student_id = s.id '
          'WHERE gs.group_id = ? AND gs.deleted_at IS NULL '
          'AND s.deleted_at IS NULL AND gs.joined_at_cycle_number <= ? '
          'AND (gs.left_at IS NULL OR EXISTS ('
          'SELECT 1 FROM attendance a JOIN sessions se ON se.id = a.session_id '
          'WHERE a.student_id = s.id AND se.group_id = gs.group_id '
          'AND se.cycle_number = ? AND a.deleted_at IS NULL)) '
          'ORDER BY s.last_name, s.first_name, s.id',
          variables: [
            Variable<String>(groupId),
            Variable<int>(cycle),
            Variable<int>(cycle),
          ],
          readsFrom: {
            db.students,
            db.groupStudents,
            db.attendance,
            db.sessions,
          },
        )
        .get();

    final attendanceRows = await db
        .customSelect(
          'SELECT a.session_id, a.student_id, a.status FROM attendance a '
          'JOIN sessions se ON se.id = a.session_id '
          'WHERE se.group_id = ? AND se.cycle_number = ? '
          'AND se.deleted_at IS NULL AND a.deleted_at IS NULL',
          variables: [Variable<String>(groupId), Variable<int>(cycle)],
          readsFrom: {db.attendance, db.sessions},
        )
        .get();
    final byStudent = <String, GridCells>{};
    for (final row in attendanceRows) {
      byStudent.putIfAbsent(row.read<String>('student_id'), () => {})[row
          .read<String>('session_id')] = AttendanceStatus.fromCode(
        row.read<String>('status'),
      );
    }

    return GroupGrid(
      group: group,
      cycleNumber: cycle,
      sessions: sessions,
      students: [
        for (final row in studentRows)
          GridStudent(
            studentId: row.read<String>('id'),
            name:
                '${row.read<String>('first_name')} '
                '${row.read<String>('last_name')}',
            cells: byStudent[row.read<String>('id')] ?? const {},
            leftGroup: row.read<int?>('left_at') != null,
          ),
      ],
    );
  }
}
