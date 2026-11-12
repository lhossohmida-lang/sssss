import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import 'dues_service.dart';

/// بند مستحق: دورة واحدة في مجموعة بما بقي منها.
class DueLine {
  const DueLine({
    required this.groupId,
    required this.groupNumber,
    required this.subjectName,
    required this.cycleNumber,
    required this.remaining,
  });

  final String groupId;
  final int groupNumber;
  final String subjectName;
  final int cycleNumber;
  final int remaining;

  String get label =>
      '$subjectName · المجموعة $groupNumber · الدورة $cycleNumber';
}

/// تلميذ عليه مستحقات، وبنودها الأقدم أولاً.
class DueStudent {
  const DueStudent({
    required this.studentId,
    required this.name,
    required this.parentPhone,
    required this.lines,
  });

  final String studentId;
  final String name;
  final String parentPhone;
  final List<DueLine> lines;

  /// مجموع ما عليه.
  int get total => lines.fold(0, (sum, l) => sum + l.remaining);

  /// أقدم دورة غير مسدَّدة (رقمها).
  int get oldestCycle =>
      lines.map((l) => l.cycleNumber).reduce((a, b) => a < b ? a : b);
}

/// تقرير المستحقات: من عليهم مال، الأكثر مبلغاً أولاً.
class DuesReport {
  const DuesReport(this.students);

  final List<DueStudent> students;

  bool get isEmpty => students.isEmpty;

  /// عدد التلاميذ.
  int get count => students.length;

  /// مجموع كل المستحقات.
  int get total => students.fold(0, (sum, s) => sum + s.total);
}

/// يبني تقرير المستحقات من الدورات غير المسدَّدة (باستعلام مجمّع واحد)
/// مع أسماء التلاميذ والمجموعات.
class DuesReports {
  DuesReports(this.db, this.dues);

  final AppDatabase db;
  final DuesService dues;

  /// التقرير، ويتحدث مع كل تغيّر في الدفعات أو الانتساب أو الأرصدة.
  Stream<DuesReport> watch({String? groupId, String query = ''}) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            db.payments,
            db.groupStudents,
            db.studentCredits,
            db.groups,
            db.students,
          },
        )
        .watch()
        .asyncMap((_) => load(groupId: groupId, query: query));
  }

  /// [groupId] يحصر في مجموعة، و[query] يبحث في اسم التلميذ وهاتف وليّه.
  Future<DuesReport> load({String? groupId, String query = ''}) async {
    final due = await dues.cycleDues(groupId: groupId, unpaidOnly: true);
    if (due.isEmpty) return const DuesReport([]);

    final studentIds = {for (final d in due) d.studentId}.toList();
    final groupIds = {for (final d in due) d.groupId}.toList();
    final students = await _students(studentIds);
    final groups = await _groups(groupIds);

    final lines = <String, List<DueLine>>{};
    for (final d in due) {
      final g = groups[d.groupId];
      if (g == null) continue;
      lines
          .putIfAbsent(d.studentId, () => [])
          .add(
            DueLine(
              groupId: d.groupId,
              groupNumber: g.number,
              subjectName: g.subject,
              cycleNumber: d.cycleNumber,
              remaining: d.remaining,
            ),
          );
    }

    final needle = query.trim();
    final result = <DueStudent>[];
    for (final entry in lines.entries) {
      final s = students[entry.key];
      if (s == null) continue;
      if (needle.isNotEmpty &&
          !s.name.contains(needle) &&
          !s.phone.contains(needle)) {
        continue;
      }
      final sorted = [...entry.value]
        ..sort((a, b) {
          final byCycle = a.cycleNumber.compareTo(b.cycleNumber);
          return byCycle != 0
              ? byCycle
              : a.groupNumber.compareTo(b.groupNumber);
        });
      result.add(
        DueStudent(
          studentId: entry.key,
          name: s.name,
          parentPhone: s.phone,
          lines: sorted,
        ),
      );
    }
    result.sort((a, b) {
      final byTotal = b.total.compareTo(a.total);
      return byTotal != 0 ? byTotal : a.name.compareTo(b.name);
    });
    return DuesReport(result);
  }

  Future<Map<String, ({String name, String phone})>> _students(
    List<String> ids,
  ) async {
    final rows = await (db.select(
      db.students,
    )..where((s) => s.id.isIn(ids) & s.deletedAt.isNull())).get();
    return {
      for (final s in rows)
        s.id: (name: '${s.firstName} ${s.lastName}', phone: s.parentPhone),
    };
  }

  Future<Map<String, ({String subject, int number})>> _groups(
    List<String> ids,
  ) async {
    final marks = List.filled(ids.length, '?').join(', ');
    final rows = await db
        .customSelect(
          'SELECT g.id, g.number, sub.name AS subject FROM groups g '
          'JOIN subjects sub ON sub.id = g.subject_id '
          'WHERE g.id IN ($marks) AND g.deleted_at IS NULL',
          variables: [for (final id in ids) Variable<String>(id)],
          readsFrom: {db.groups, db.subjects},
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('id'): (
          subject: row.read<String>('subject'),
          number: row.read<int>('number'),
        ),
    };
  }
}
