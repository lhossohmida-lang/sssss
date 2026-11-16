import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'attendance_service.dart';
import 'catalog_service.dart';
import 'cycle_service.dart';
import 'date_key.dart';
import 'enums.dart';

/// حصة سابقة يقترحها الجدول الأسبوعي للفوج (لم تُسجَّل بعد).
class PastSessionSuggestion {
  const PastSessionSuggestion({
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
  });

  /// التاريخ `YYYY-MM-DD`.
  final String date;
  final int startMinutes;
  final int endMinutes;

  String get key => '$date|$startMinutes';
}

/// حصة انعقدت قبل استعمال النظام، مع حالات تلاميذها.
class PastSessionInput {
  const PastSessionInput({
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    this.marks = const {},
  });

  final String date;
  final int startMinutes;
  final int endMinutes;

  /// معرّف التلميذ ← حالته. من لا يرد هنا لا يُسجَّل له شيء (لم يكن منتسباً بعد).
  final Map<String, AttendanceStatus> marks;
}

/// تلميذ منتسب إلى الفوج في دورته الحالية.
class PastRosterStudent {
  const PastRosterStudent({required this.studentId, required this.name});

  final String studentId;
  final String name;
}

/// ما سُجِّل فعلاً.
class PastSessionsResult {
  const PastSessionsResult({
    required this.sessions,
    required this.marks,
    required this.removedUpcoming,
  });

  /// عدد الحصص السابقة المسجَّلة.
  final int sessions;

  /// عدد خانات الحضور المسجَّلة.
  final int marks;

  /// عدد الحصص القادمة التي حُذفت من الدورة لتبقى بحجمها (حصص الدورة ثابتة).
  final int removedUpcoming;
}

/// تسجيل حصص الدورة الحالية التي انعقدت قبل أن تبدأ المدرسة باستعمال النظام.
///
/// المدرسة التي تبدأ والدورة في منتصفها لها حصص مضت وحضور لم يُسجَّل؛ بدونه يخطئ
/// حساب نصيب الأستاذ وتقدّم الدورة. هذه الخدمة تنشئ تلك الحصص مغلقة بترتيبها
/// الزمني داخل الدورة الحالية، وتسجّل حضور التلاميذ فيها، وتحذف من حصص الدورة
/// القادمة بقدر ما أُضيف حتى يبقى عدد حصصها كما هو.
///
/// قيود مقصودة:
/// - لا تُسجَّل إلا حصص قبل اليوم (حصص اليوم تُغلق وتُسجَّل من شاشة الحضور).
/// - تبقى حصة واحدة على الأقل في الدورة لتُغلق تلقائياً، فلا تكتمل الدورة هنا
///   (اكتمالها يُنشئ خلاص الأستاذ ويرسل رسائل لأولياء التلاميذ).
/// - لا رسائل غياب ولا تنبيهات: هذه حصص مضت.
class PastSessionsService {
  PastSessionsService(this.db, this.writer, this.cycles, this.attendance);

  final AppDatabase db;
  final SyncWriter writer;
  final CycleService cycles;
  final AttendanceService attendance;

  /// أقصى عدد أيام يُبحث فيها عن حصص من الجدول.
  static const int _maxDays = 200;

  /// عدد الحصص السابقة التي يمكن تسجيلها الآن في الدورة الحالية.
  Future<int> capacity(String groupId) async {
    final group = await _activeGroup(groupId);
    final held = await cycles.countedSessions(
      groupId,
      group.currentCycleNumber,
      closedOnly: true,
    );
    final room = group.sessionsPerCycle - 1 - held;
    return room < 0 ? 0 : room;
  }

  /// حصص الجدول الأسبوعي من [from] حتى أمس ممّا لا حصة مسجَّلة له، بالترتيب الزمني.
  Future<List<PastSessionSuggestion>> suggest(
    String groupId, {
    required String from,
    required DateTime now,
  }) async {
    await _activeGroup(groupId);
    _checkDate(from);
    final today = DateKey.of(now);
    final slots =
        await (db.select(db.groupSlots)
              ..where((s) => s.groupId.equals(groupId) & s.deletedAt.isNull())
              ..orderBy([(s) => OrderingTerm(expression: s.startMinutes)]))
            .get();
    final found = <PastSessionSuggestion>[];
    if (slots.isEmpty) return found;
    var day = from;
    for (var i = 0; i < _maxDays && day.compareTo(today) < 0; i++) {
      final weekday = DateKey.weekday(day);
      for (final slot in slots.where((s) => s.weekday == weekday)) {
        if (await _slotTaken(groupId, day, slot.startMinutes)) continue;
        found.add(
          PastSessionSuggestion(
            date: day,
            startMinutes: slot.startMinutes,
            endMinutes: slot.endMinutes,
          ),
        );
      }
      day = DateKey.next(day);
    }
    return found;
  }

  /// تلاميذ الفوج المنتسبون في دورته الحالية (من يُسجَّل حضورهم)، بالاسم.
  Future<List<PastRosterStudent>> roster(String groupId) async {
    final group = await _activeGroup(groupId);
    final rows = await db
        .customSelect(
          'SELECT s.id, s.first_name, s.last_name FROM students s '
          'JOIN group_students gs ON gs.student_id = s.id '
          'WHERE gs.group_id = ? AND gs.deleted_at IS NULL '
          'AND gs.left_at IS NULL AND s.deleted_at IS NULL '
          'AND gs.joined_at_cycle_number <= ? '
          'ORDER BY s.last_name, s.first_name, s.id',
          variables: [
            Variable<String>(groupId),
            Variable<int>(group.currentCycleNumber),
          ],
          readsFrom: {db.students, db.groupStudents},
        )
        .get();
    return [
      for (final row in rows)
        PastRosterStudent(
          studentId: row.read<String>('id'),
          name:
              '${row.read<String>('first_name')} ${row.read<String>('last_name')}',
        ),
    ];
  }

  /// يسجّل [sessions] في الدورة الحالية مغلقةً بحضور تلاميذها. كله أو لا شيء.
  ///
  /// [canExcuse] إذن تسجيل «غائب برخصة» (للمدير أو العامل المخوَّل فقط، قرار 44).
  Future<PastSessionsResult> record(
    String groupId,
    List<PastSessionInput> sessions, {
    required DateTime now,
    bool canExcuse = false,
  }) async {
    if (sessions.isEmpty) {
      throw ValidationException.field('sessions', 'اختر حصة واحدة على الأقل');
    }
    final today = DateKey.of(now);
    final seen = <String>{};
    for (final input in sessions) {
      _checkDate(input.date);
      if (input.date.compareTo(today) >= 0) {
        throw ValidationException.field(
          'sessions',
          'الحصص السابقة قبل اليوم فقط؛ حصص اليوم تُسجَّل من شاشة الحضور',
        );
      }
      if (input.endMinutes <= input.startMinutes ||
          input.startMinutes < 0 ||
          input.endMinutes > 24 * 60) {
        throw ValidationException.field(
          'sessions',
          'وقت نهاية الحصة يجب أن يكون بعد بدايتها',
        );
      }
      if (!seen.add('${input.date}|${input.startMinutes}')) {
        throw ValidationException.field(
          'sessions',
          'حصتان في اليوم والوقت نفسيهما: ${input.date}',
        );
      }
      if (!canExcuse &&
          input.marks.values.any((s) => s == AttendanceStatus.excused)) {
        throw ValidationException.field(
          'attendance',
          'تسجيل «غائب برخصة» للمدير أو العامل المخوَّل فقط',
        );
      }
    }

    return db.transaction(() async {
      final group = await _activeGroup(groupId);
      final cycle = group.currentCycleNumber;
      final held = await cycles.countedSessions(
        groupId,
        cycle,
        closedOnly: true,
      );
      final allowed = group.sessionsPerCycle - 1 - held;
      if (sessions.length > allowed) {
        throw ValidationException.field(
          'sessions',
          allowed <= 0
              ? 'لا يمكن تسجيل حصص سابقة: الدورة تكاد تكتمل'
              : 'يمكن تسجيل $allowed حصة سابقة على الأكثر '
                    '(حصص الدورة ${group.sessionsPerCycle})',
        );
      }
      final roster = {for (final s in await this.roster(groupId)) s.studentId};
      for (final input in sessions) {
        for (final studentId in input.marks.keys) {
          if (!roster.contains(studentId)) {
            throw ValidationException.field(
              'attendance',
              'تلميذ ليس منتسباً إلى هذا الفوج في دورته الحالية',
            );
          }
        }
        if (await _slotTaken(groupId, input.date, input.startMinutes)) {
          throw ValidationException.field(
            'sessions',
            'حصة هذا الفوج في ${input.date} '
                '${DateKey.formatMinutes(input.startMinutes)} مسجَّلة من قبل',
          );
        }
      }

      var marks = 0;
      final ordered = [...sessions]
        ..sort((a, b) {
          final byDate = a.date.compareTo(b.date);
          return byDate != 0
              ? byDate
              : a.startMinutes.compareTo(b.startMinutes);
        });
      for (final input in ordered) {
        final session = await cycles.addSession(
          groupId: groupId,
          date: input.date,
          startMinutes: input.startMinutes,
          endMinutes: input.endMinutes,
          status: SessionStatus.normal,
        );
        await cycles.closeSession(session.id);
        for (final entry in input.marks.entries) {
          await attendance.writeHistorical(session, entry.key, entry.value);
          marks++;
        }
      }

      final removed = await _trimUpcoming(group);
      await cycles.renumber(groupId, cycle);
      return PastSessionsResult(
        sessions: sessions.length,
        marks: marks,
        removedUpcoming: removed,
      );
    });
  }

  /// يحذف من آخر حصص الدورة القادمة ما زاد عن حجمها بعد إضافة الحصص السابقة.
  Future<int> _trimUpcoming(GroupRow group) async {
    final counted = await cycles.countedSessions(
      group.id,
      group.currentCycleNumber,
    );
    final surplus = counted - group.sessionsPerCycle;
    if (surplus <= 0) return 0;
    final upcoming =
        await (db.select(db.sessions)
              ..where(
                (s) =>
                    s.groupId.equals(group.id) &
                    s.cycleNumber.equals(group.currentCycleNumber) &
                    s.deletedAt.isNull() &
                    s.closedAt.isNull() &
                    s.status.isNotValue(SessionStatus.cancelled.code),
              )
              ..orderBy([
                (s) => OrderingTerm.desc(s.date),
                (s) => OrderingTerm.desc(s.startMinutes),
              ])
              ..limit(surplus))
            .get();
    for (final session in upcoming) {
      final marked = await db
          .customSelect(
            'SELECT 1 FROM attendance WHERE session_id = ? '
            'AND deleted_at IS NULL LIMIT 1',
            variables: [Variable<String>(session.id)],
            readsFrom: {db.attendance},
          )
          .getSingleOrNull();
      if (marked != null) {
        throw ValidationException.field(
          'sessions',
          'لا يمكن حذف حصة قادمة سُجّل فيها حضور (${session.date})',
        );
      }
      await writer.softDelete(db.sessions, key: {'id': session.id});
    }
    return upcoming.length;
  }

  Future<GroupRow> _activeGroup(String groupId) async {
    final group =
        await (db.select(db.groups)..where(
              (g) =>
                  g.id.equals(groupId) &
                  g.deletedAt.isNull() &
                  g.archivedAt.isNull(),
            ))
            .getSingleOrNull();
    if (group == null) {
      throw ValidationException.field('group', 'الفوج غير موجود أو مؤرشف');
    }
    return group;
  }

  Future<bool> _slotTaken(String groupId, String date, int start) async {
    final row = await db
        .customSelect(
          'SELECT 1 FROM sessions WHERE group_id = ? AND date = ? '
          'AND start_minutes = ? AND deleted_at IS NULL LIMIT 1',
          variables: [
            Variable<String>(groupId),
            Variable<String>(date),
            Variable<int>(start),
          ],
          readsFrom: {db.sessions},
        )
        .getSingleOrNull();
    return row != null;
  }

  static void _checkDate(String value) {
    final valid = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
    if (!valid || DateKey.of(DateKey.parse(value)) != value) {
      throw ValidationException.field('sessions', 'تاريخ غير صالح: $value');
    }
  }
}
