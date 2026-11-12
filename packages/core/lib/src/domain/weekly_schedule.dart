import 'package:drift/drift.dart' show Variable;

import '../data/local/app_database.dart';
import 'date_key.dart';
import 'group_service.dart';

/// خانة في الجدول الأسبوعي: حصة ثابتة لمجموعة في يوم من الأسبوع.
class ScheduleEntry {
  const ScheduleEntry({
    required this.groupId,
    required this.groupNumber,
    required this.subjectName,
    required this.teacherId,
    required this.teacherName,
    required this.weekday,
    required this.startMinutes,
    required this.endMinutes,
    this.roomId,
    this.roomName,
  });

  final String groupId;
  final int groupNumber;
  final String subjectName;
  final String teacherId;
  final String teacherName;

  /// 1 = الاثنين … 7 = الأحد.
  final int weekday;
  final int startMinutes;
  final int endMinutes;

  /// قاعة الخانة، وإلا الافتراضية للمجموعة، و`null` إن لم تُحدَّد.
  final String? roomId;
  final String? roomName;

  String get timeText =>
      '${DateKey.formatMinutes(startMinutes)}–'
      '${DateKey.formatMinutes(endMinutes)}';

  /// وصف الخانة لقارئ الشاشة والعرض.
  String get label =>
      'المجموعة $groupNumber · $subjectName · '
      '${GroupService.weekdayName(weekday)} $timeText';
}

/// محور الجدول: القاعة أو الأستاذ.
enum ScheduleAxis {
  room('حسب القاعة'),
  teacher('حسب الأستاذ');

  const ScheduleAxis(this.label);
  final String label;
}

/// جدول مورد واحد (قاعة أو أستاذ) خلال الأسبوع.
class ResourceSchedule {
  const ResourceSchedule({
    required this.id,
    required this.name,
    required this.entries,
  });

  /// معرّف القاعة أو الأستاذ، و`null` لخانات «بلا قاعة».
  final String? id;
  final String name;

  /// الخانات مرتبة باليوم (السبت أولاً) ثم ببداية الحصة.
  final List<ScheduleEntry> entries;

  List<ScheduleEntry> on(int weekday) => [
    for (final e in entries)
      if (e.weekday == weekday) e,
  ];
}

/// الجدول الأسبوعي لكل المجموعات النشطة.
class WeeklySchedule {
  const WeeklySchedule(this.entries);

  final List<ScheduleEntry> entries;

  bool get isEmpty => entries.isEmpty;

  /// بداية أول حصة (بالدقائق)، أو 8:00 إن لم توجد خانات.
  int get firstMinute => entries.isEmpty
      ? 480
      : entries.map((e) => e.startMinutes).reduce((a, b) => a < b ? a : b);

  /// نهاية آخر حصة (بالدقائق)، أو 18:00 إن لم توجد خانات.
  int get lastMinute => entries.isEmpty
      ? 1080
      : entries.map((e) => e.endMinutes).reduce((a, b) => a > b ? a : b);

  /// جدول كل مورد على [axis]، مرتبة بأسمائها؛ «بلا قاعة» آخراً.
  List<ResourceSchedule> by(ScheduleAxis axis) {
    final groups = <String?, List<ScheduleEntry>>{};
    final names = <String?, String>{};
    for (final e in entries) {
      final id = axis == ScheduleAxis.room ? e.roomId : e.teacherId;
      groups.putIfAbsent(id, () => []).add(e);
      names[id] = axis == ScheduleAxis.room
          ? (e.roomName ?? 'بلا قاعة')
          : e.teacherName;
    }
    final result = [
      for (final id in groups.keys)
        ResourceSchedule(
          id: id,
          name: names[id]!,
          entries: _sorted(groups[id]!),
        ),
    ];
    result.sort((a, b) {
      if (a.id == null) return b.id == null ? 0 : 1;
      if (b.id == null) return -1;
      return a.name.compareTo(b.name);
    });
    return result;
  }

  static List<ScheduleEntry> _sorted(List<ScheduleEntry> list) {
    int dayIndex(int weekday) => GroupService.displayWeekdays.indexOf(weekday);
    return [...list]..sort((a, b) {
      final day = dayIndex(a.weekday).compareTo(dayIndex(b.weekday));
      if (day != 0) return day;
      final start = a.startMinutes.compareTo(b.startMinutes);
      return start != 0 ? start : a.groupNumber.compareTo(b.groupNumber);
    });
  }
}

/// استعلام الجدول الأسبوعي من الخانات الثابتة للمجموعات النشطة.
class WeeklyScheduleQueries {
  WeeklyScheduleQueries(this.db);

  final AppDatabase db;

  /// الجدول، ويتحدث مع كل تغيّر في المجموعات أو خاناتها أو القاعات.
  ///
  /// بـ [studentId] يقتصر على مجموعات ينتسب إليها هذا التلميذ حالياً (جدول
  /// الوليّ لابنه).
  Stream<WeeklySchedule> watch({String? studentId}) {
    return db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            db.groupSlots,
            db.groups,
            db.rooms,
            db.subjects,
            db.teachers,
            db.groupStudents,
          },
        )
        .watch()
        .asyncMap((_) => load(studentId: studentId));
  }

  Future<WeeklySchedule> load({String? studentId}) async {
    final rows = await db
        .customSelect(
          'SELECT gs.weekday, gs.start_minutes, gs.end_minutes, '
          'g.id AS group_id, g.number, sub.name AS subject, '
          't.id AS teacher_id, t.name AS teacher, '
          'r.id AS room_id, r.name AS room '
          'FROM group_slots gs JOIN groups g ON g.id = gs.group_id '
          'JOIN subjects sub ON sub.id = g.subject_id '
          'JOIN teachers t ON t.id = g.teacher_id '
          'LEFT JOIN rooms r ON r.id = COALESCE(gs.room_id, g.room_id) '
          'AND r.deleted_at IS NULL '
          'WHERE gs.deleted_at IS NULL AND g.deleted_at IS NULL '
          'AND g.archived_at IS NULL '
          '${studentId == null ? '' : 'AND gs.group_id IN (SELECT en.group_id '
                    'FROM group_students en WHERE en.student_id = ? '
                    'AND en.deleted_at IS NULL AND en.left_at IS NULL) '}'
          'ORDER BY gs.weekday, gs.start_minutes, g.number',
          variables: [if (studentId != null) Variable<String>(studentId)],
          readsFrom: {
            db.groupSlots,
            db.groups,
            db.rooms,
            db.subjects,
            db.teachers,
            db.groupStudents,
          },
        )
        .get();
    return WeeklySchedule([
      for (final row in rows)
        ScheduleEntry(
          groupId: row.read<String>('group_id'),
          groupNumber: row.read<int>('number'),
          subjectName: row.read<String>('subject'),
          teacherId: row.read<String>('teacher_id'),
          teacherName: row.read<String>('teacher'),
          weekday: row.read<int>('weekday'),
          startMinutes: row.read<int>('start_minutes'),
          endMinutes: row.read<int>('end_minutes'),
          roomId: row.read<String?>('room_id'),
          roomName: row.read<String?>('room'),
        ),
    ]);
  }
}
