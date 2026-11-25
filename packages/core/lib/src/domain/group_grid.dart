import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import 'date_key.dart';
import 'dues_service.dart';
import 'enums.dart';
import 'pricing.dart';

/// خلية في شبكة الحضور: حالة التلميذ في حصة، أو `null` إن لم تُسجَّل.
typedef GridCells = Map<String, AttendanceStatus>;

/// تلميذ في شبكة الدورة مع حالاته في حصصها.
class GridStudent {
  const GridStudent({
    required this.studentId,
    required this.name,
    required this.cells,
    required this.leftGroup,
    this.coveredSessions,
    this.creditSessions = 0,
    this.reviewSessionIds = const {},
  });

  final String studentId;
  final String name;

  /// عدد حصص الدورة التي يغطيها ما دفعه التلميذ (كلها إن كان معفى أو سعره صفر)؛ `null` إن لم تُحسب
  /// المدفوعات (تطبيق الأستاذ لا يقرأ المدفوعات) أو لم يكن ملزَماً بهذه الدورة.
  final int? coveredSessions;

  /// حصص من أول الدورة دُفعت في دورة سابقة (رصيد التحاق في منتصفها أو غياب برخصة): تظهر بالأزرق.
  final int creditSessions;

  /// هل حصة ترتيبها [index] مدفوعة من رصيد دورة سابقة؟
  bool creditAt(int index) => index < creditSessions;

  /// هل حصة ترتيبها [index] بين حصص الدورة المحسوبة (غير الملغاة، بالترتيب الزمني) مدفوعة؟ فمن
  /// دفع شهره تظهر حصصه كلها مدفوعة حتى قبل أن يحضرها. `null` إن لم تُحسب المدفوعات.
  bool? paidAt(int index) {
    final covered = coveredSessions;
    return covered == null ? null : index < covered;
  }

  /// معرّف الحصة ← حالة حضوره فيها.
  final GridCells cells;

  /// هل غادر المجموعة (يظهر لأن له حضوراً في هذه الدورة)؟
  final bool leftGroup;

  /// حصص المراجعة التي هو ضيف فيها: تُعدّ حصصاً من دورته، فتظهر بين حصصها بحسب تاريخها ويدخل حضورها
  /// في مجموعه (يظهر حضوره فيها في [cells]).
  final Set<String> reviewSessionIds;

  int count(AttendanceStatus status) =>
      cells.values.where((s) => s == status).length;

  /// عدد حصص [sessions] التي كانت حالته فيها [status] (حصص الدورة العامة دون حصص المراجعة).
  int countIn(Iterable<SessionRow> sessions, AttendanceStatus status) =>
      sessions.where((s) => cells[s.id] == status).length;

  /// عدد حصص المراجعة التي حضرها ضيفاً وكانت حالته فيها [status].
  int reviewCountIn(AttendanceStatus status) =>
      reviewSessionIds.where((id) => cells[id] == status).length;

  /// ما يُعدّ له من حصص الدورة: حصصها المحسوبة [counted] وحصص المراجعة التي هو ضيف فيها.
  int sessionsTotal(int counted) => counted + reviewSessionIds.length;

  /// عدد ما حضره من حصص دورته: حصصها العامة [sessions] وحصص المراجعة التي حضرها.
  int presentTotal(Iterable<SessionRow> sessions) =>
      countIn(sessions, AttendanceStatus.present) +
      reviewCountIn(AttendanceStatus.present);
}

/// شبكة حضور دورة: حصصها بالترتيب الزمني، وتلاميذها بحالاتهم فيها.
class GroupGrid {
  const GroupGrid({
    required this.group,
    required this.cycleNumber,
    required this.sessions,
    required this.students,
    this.reviewSessions = const [],
  });

  final GroupRow group;
  final int cycleNumber;

  /// حصص مراجعة (فوج من حصة واحدة في مادة هذا الفوج) حضرها تلاميذه ضيوفاً في أيام هذه الدورة (من أول
  /// حصة فيها حتى أول حصة في الدورة التالية، وللدورة الحالية بلا نهاية): تُعدّ حصصاً من دورتهم فتظهر
  /// بين حصصها بحسب تاريخها ويدخل حضورها في مجموعهم؛ ولا تدخل [countedSessions] لأنها لا تخص بقية
  /// تلاميذ الفوج ولا تغيّر عدد حصص دورته.
  final List<SessionRow> reviewSessions;

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
  /// [dues] يُمرَّر في تطبيق الإدارة وحده (المدفوعات لا تصل الأستاذ)، فتُحسب حصص كل تلميذ المدفوعة.
  GroupGridQueries(this.db, {this.dues});

  final AppDatabase db;
  final DuesService? dues;

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
            db.payments,
            db.studentCredits,
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

    // حصص المراجعة التي حضرها تلاميذ الفوج ضيوفاً (في مادته)، وتقع في أيام هذه الدورة: من أول حصة فيها
    // حتى أول حصة في الدورة التالية (غير شاملة)، وللدورة الحالية بلا نهاية (فلا تضيع مراجعة تلي آخر
    // حصصها قبل أن تبدأ دورة جديدة).
    final reviewSessions = <SessionRow>[];
    final reviewGuests = <String, Set<String>>{};
    if (sessions.isNotEmpty) {
      final nextStart = await db
          .customSelect(
            'SELECT MIN(date) AS d FROM sessions WHERE group_id = ? '
            'AND cycle_number > ? AND deleted_at IS NULL',
            variables: [Variable<String>(groupId), Variable<int>(cycle)],
            readsFrom: {db.sessions},
          )
          .getSingle();
      final String? endExclusive =
          nextStart.read<String?>('d') ??
          (cycle == group.currentCycleNumber
              ? null
              : DateKey.of(
                  DateKey.parse(sessions.last.date)
                      .add(const Duration(days: 1)),
                ));
      final reviewRows = await db
          .customSelect(
            'SELECT DISTINCT se.id, se.date, se.start_minutes '
            'FROM session_guests sg '
            'JOIN sessions se ON se.id = sg.session_id AND se.deleted_at IS NULL '
            "AND se.status <> 'cancelled' "
            'JOIN groups rg ON rg.id = se.group_id AND rg.is_review = 1 '
            'AND rg.deleted_at IS NULL AND rg.subject_id = ? '
            'JOIN group_students gs ON gs.student_id = sg.student_id '
            'AND gs.group_id = ? AND gs.deleted_at IS NULL '
            'WHERE sg.deleted_at IS NULL AND se.date >= ? '
            '${endExclusive == null ? '' : 'AND se.date < ? '}'
            'ORDER BY se.date, se.start_minutes, se.id',
            variables: [
              Variable<String>(group.subjectId),
              Variable<String>(groupId),
              Variable<String>(sessions.first.date),
              if (endExclusive != null) Variable<String>(endExclusive),
            ],
            readsFrom: {
              db.sessionGuests,
              db.sessions,
              db.groups,
              db.groupStudents,
            },
          )
          .get();
      final reviewIds = [for (final row in reviewRows) row.read<String>('id')];
      if (reviewIds.isNotEmpty) {
        final marks = List.filled(reviewIds.length, '?').join(', ');
        final ids = [for (final id in reviewIds) Variable<String>(id)];
        final rows = await (db.select(
          db.sessions,
        )..where((s) => s.id.isIn(reviewIds))).get();
        final byId = {for (final row in rows) row.id: row};
        reviewSessions.addAll([
          for (final id in reviewIds)
            if (byId[id] != null) byId[id]!,
        ]);
        final guestRows = await db
            .customSelect(
              'SELECT sg.session_id, sg.student_id FROM session_guests sg '
              'WHERE sg.session_id IN ($marks) AND sg.deleted_at IS NULL',
              variables: ids,
              readsFrom: {db.sessionGuests},
            )
            .get();
        for (final row in guestRows) {
          reviewGuests
              .putIfAbsent(row.read<String>('student_id'), () => {})
              .add(row.read<String>('session_id'));
        }
        final reviewAttendance = await db
            .customSelect(
              'SELECT a.session_id, a.student_id, a.status FROM attendance a '
              'WHERE a.session_id IN ($marks) AND a.deleted_at IS NULL',
              variables: ids,
              readsFrom: {db.attendance},
            )
            .get();
        for (final row in reviewAttendance) {
          byStudent.putIfAbsent(row.read<String>('student_id'), () => {})[row
              .read<String>('session_id')] = AttendanceStatus.fromCode(
            row.read<String>('status'),
          );
        }
      }
    }

    final service = dues;
    final dueByStudent = <String, CycleDue>{
      if (service != null)
        for (final due in await service.cycleDues(
          groupId: groupId,
          cycleNumber: cycle,
        ))
          due.studentId: due,
    };

    return GroupGrid(
      group: group,
      cycleNumber: cycle,
      sessions: sessions,
      reviewSessions: reviewSessions,
      students: [
        for (final row in studentRows)
          GridStudent(
            studentId: row.read<String>('id'),
            name:
                '${row.read<String>('first_name')} '
                '${row.read<String>('last_name')}',
            cells: byStudent[row.read<String>('id')] ?? const {},
            leftGroup: row.read<int?>('left_at') != null,
            coveredSessions: dueByStudent[row.read<String>('id')]
                ?.coveredSessions(group.sessionsPerCycle),
            creditSessions:
                dueByStudent[row.read<String>('id')]?.creditSessions(
                  group.sessionsPerCycle,
                ) ??
                0,
            reviewSessionIds: reviewGuests[row.read<String>('id')] ?? const {},
          ),
      ],
    );
  }
}
