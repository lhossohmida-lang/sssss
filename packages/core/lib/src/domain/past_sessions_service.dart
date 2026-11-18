import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'attendance_service.dart';
import 'catalog_service.dart';
import 'cycle_service.dart';
import 'date_key.dart';
import 'enums.dart';
import 'schedule_service.dart';

/// نقل حصة قادمة إلى تاريخ آخر بوقتها نفسه ([PastSessionsService.record]).
class SessionMove {
  const SessionMove({
    required this.fromDate,
    required this.startMinutes,
    required this.toDate,
  });

  /// تاريخ الحصة المبرمجة `YYYY-MM-DD`.
  final String fromDate;

  /// بداية الحصة؛ يبقى وقتها كما هو.
  final int startMinutes;

  /// التاريخ الجديد `YYYY-MM-DD`: اليوم أو بعده.
  final String toDate;

  String get fromKey => '$fromDate|$startMinutes';
}

/// حصة في «الحصص المقررة» للدورة الحالية: تاريخها ووقتها.
class PlannedSession {
  const PlannedSession({
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    this.held = false,
  });

  /// التاريخ `YYYY-MM-DD`.
  final String date;
  final int startMinutes;
  final int endMinutes;

  /// انعقدت وأُغلقت وسُجّل حضورها من قبل.
  final bool held;

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

  /// عدد الحصص القادمة التي نقصت من الدورة لتبقى بحجمها (حصص الدورة ثابتة).
  final int removedUpcoming;
}

/// «الحصص المقررة» للدورة الحالية من تاريخ أول حصة: حصص الدورة كلها بعددها وتواريخها
/// من الجدول الأسبوعي، ماضيةً وقادمة.
class CyclePlan {
  const CyclePlan({
    required this.from,
    required this.cycleSize,
    required this.capacity,
    required this.fixed,
    required this.past,
    required this.upcoming,
  });

  /// تاريخ أول حصة الذي بُني عليه المخطط (`YYYY-MM-DD`).
  final String from;

  /// عدد حصص الدورة.
  final int cycleSize;

  /// أقصى عدد حصص ماضية يمكن تسجيلها الآن.
  final int capacity;

  /// حصص قائمة لا تمسّها إعادة البرمجة: المنعقدة المسجَّلة ([PlannedSession.held])،
  /// وما فيه حضور، والتعويضية والمضافة.
  final List<PlannedSession> fixed;

  /// حصص قبل اليوم، من [from]، يُسجَّل حضور ما انعقد منها ويُترك ما لم ينعقد.
  final List<PlannedSession> past;

  /// الحصص القادمة التي ستُبرمج من الجدول، بأكثر ما تحتمله الدورة؛ يؤخذ منها بقدر ما
  /// يبقى لها بعد الحصص الثابتة والماضية المحدَّدة.
  final List<PlannedSession> upcoming;
}

/// حصص الدورة الحالية مصنّفة بحسب جواز إعادة برمجتها.
class _CycleState {
  _CycleState({
    required this.fixed,
    required this.deletable,
    required this.taken,
  });

  /// المحسوبة التي لا تُمَسّ: المغلقة، وما فيه حضور، وغير العادية. بالترتيب الزمني.
  final List<SessionRow> fixed;

  /// العادية غير المغلقة التي لا حضور فيها: تُسجَّل إن حُدِّدت، وتُحذف وتُبرمج من جديد
  /// إن لم تُحدَّد. بالترتيب الزمني.
  final List<SessionRow> deletable;

  /// مفاتيح (`تاريخ|بداية`) كل حصص المجموعة الحية التي تبقى حيث هي.
  final Set<String> taken;

  Set<String> get deletableIds => {for (final s in deletable) s.id};

  int get held => fixed.where((s) => s.closedAt != null).length;

  String? get earliestHeld {
    for (final session in fixed) {
      if (session.closedAt != null) return session.date;
    }
    return null;
  }
}

/// «الحصص المقررة» للدورة الحالية وتسجيل ما انعقد منها قبل أن تبدأ المدرسة باستعمال
/// النظام.
///
/// حصص الدورة دائماً بعددها (`sessions_per_cycle`) وبتواريخها من الجدول الأسبوعي ابتداءً
/// من تاريخ أول حصة. المدرسة التي تبدأ والدورة في منتصفها لها حصص مضت وحضور لم
/// يُسجَّل؛ بدونه يخطئ حساب نصيب الأستاذ وتقدّم الدورة. هذه الخدمة تقترح الحصص الماضية
/// من تاريخ أول حصة، وتُنشئ ما انعقد منها مغلقاً بترتيبه الزمني داخل الدورة الحالية مع
/// حضور تلاميذه، ثم تعيد برمجة القادمة من الجدول لتبقى الدورة بعددها. وتغيير تاريخ
/// أول حصة إلى ما بعد اليوم يُعيد برمجة الدورة كلها من ذلك التاريخ.
///
/// قيود مقصودة:
/// - لا تُسجَّل إلا حصص قبل اليوم (حصص اليوم تُغلق وتُسجَّل من شاشة الحضور).
/// - تبقى حصة واحدة على الأقل في الدورة لتُغلق تلقائياً، فلا تكتمل الدورة هنا
///   (اكتمالها يُنشئ خلاص الأستاذ ويرسل رسائل لأولياء التلاميذ).
/// - الحصص المنعقدة المغلقة وما فيه حضور والتعويضية والمضافة لا تُحذف عند إعادة البرمجة.
/// - لا رسائل غياب ولا تنبيهات: هذه حصص مضت.
///
/// تغيير تاريخ حصة قادمة ([SessionMove]): تُنقل بوقتها إلى اليوم أو ما بعده بعد فحص تعارضها
/// مع أستاذها وقاعتها وحصص الفوج. تُلغى في موعدها وتحلّ محلها حصة تعويضية في الموعد
/// الجديد ([CycleService.moveSession])، فلا تُعيد إعادةُ البرمجة اللاحقة الحصةَ إلى موعدها
/// الأصلي، ولا ما مضى أو انعقد يُنقل.
class PastSessionsService {
  PastSessionsService(this.db, this.writer, this.cycles, this.attendance);

  final AppDatabase db;
  final SyncWriter writer;
  final CycleService cycles;
  final AttendanceService attendance;

  late final ScheduleService _schedule = ScheduleService(db);

  /// حقل أخطاء نقل الحصص.
  static const String fieldMoves = 'moves';

  /// أقصى عدد أيام يُبحث فيها عن حصص ماضية من الجدول.
  static const int _maxDays = 200;

  /// تاريخ أول حصة في الدورة الحالية: أقدم حصة محسوبة فيها (منعقدة أو مبرمجة)، أو
  /// اليوم إن لم تكن فيها حصص.
  Future<String> firstDate(String groupId, {required DateTime now}) async {
    final group = await _activeGroup(groupId);
    final sessions = await cycles.cycleSessions(
      groupId,
      group.currentCycleNumber,
    );
    for (final session in sessions) {
      if (session.status != SessionStatus.cancelled.code) return session.date;
    }
    return DateKey.of(now);
  }

  /// «الحصص المقررة» للدورة الحالية بدءاً من أول حصة [from]، دون كتابة شيء.
  Future<CyclePlan> plan(
    String groupId, {
    required String from,
    required DateTime now,
  }) async {
    final group = await _activeGroup(groupId);
    _checkDate(from, field: 'first_date');
    final today = DateKey.of(now);
    final size = group.sessionsPerCycle;
    final state = await _cycleState(group);
    final slots = await _slots(groupId);

    // الحصص العادية الماضية التي برمجها النظام ولم تُسجَّل ولا حضور فيها تُعرض لتُسجَّل
    // أو تُترك، مع خانات الجدول التي لا حصة فيها من أول حصة إلى أمس.
    final past = <String, PlannedSession>{};
    for (final session in state.deletable) {
      if (session.date.compareTo(today) < 0 &&
          session.date.compareTo(from) >= 0) {
        past['${session.date}|${session.startMinutes}'] = PlannedSession(
          date: session.date,
          startMinutes: session.startMinutes,
          endMinutes: session.endMinutes,
        );
      }
    }
    var day = from;
    for (var i = 0; i < _maxDays && day.compareTo(today) < 0; i++) {
      final weekday = DateKey.weekday(day);
      for (final slot in slots.where((s) => s.weekday == weekday)) {
        final key = '$day|${slot.startMinutes}';
        if (state.taken.contains(key) || past.containsKey(key)) continue;
        past[key] = PlannedSession(
          date: day,
          startMinutes: slot.startMinutes,
          endMinutes: slot.endMinutes,
        );
      }
      day = DateKey.next(day);
    }
    final pastRows = past.values.toList()..sort(_byTime);

    final upcoming = await cycles.occurrences(
      groupId,
      fromDate: from.compareTo(today) > 0 ? from : today,
      count: size - state.fixed.length,
      ignore: state.deletableIds,
    );
    final room = size - 1 - state.held;
    return CyclePlan(
      from: from,
      cycleSize: size,
      capacity: room < 0 ? 0 : room,
      fixed: [
        for (final s in state.fixed)
          PlannedSession(
            date: s.date,
            startMinutes: s.startMinutes,
            endMinutes: s.endMinutes,
            held: s.closedAt != null,
          ),
      ],
      past: pastRows.take(size).toList(),
      upcoming: [
        for (final o in upcoming)
          PlannedSession(
            date: o.date,
            startMinutes: o.startMinutes,
            endMinutes: o.endMinutes,
          ),
      ],
    );
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

  /// يسجّل [sessions] في الدورة الحالية مغلقةً بحضور تلاميذها ثم يعيد برمجة ما بقي
  /// منها من الجدول لتبقى الدورة بعددها. كله أو لا شيء.
  ///
  /// [firstDate] تاريخ أول حصة في الدورة: ما قبله من الحصص العادية غير المسجَّلة يُحذف،
  /// وإن كان بعد اليوم بُرمجت الدورة كلها منه. بدونه تُبرمج القادمة من اليوم. ومع
  /// [firstDate] تجوز قائمة [sessions] فارغة (إعادة برمجة فقط).
  ///
  /// [moves] حصص قادمة تُنقل بعد إعادة البرمجة إلى تواريخ أخرى بوقتها (انظر [SessionMove])،
  /// بترتيبها: ما يُنقل إلى موعد أخلاه نقلٌ سابق يأتي بعده.
  ///
  /// [canExcuse] إذن تسجيل «غائب برخصة» (للمدير أو العامل المخوَّل فقط، قرار 44).
  Future<PastSessionsResult> record(
    String groupId,
    List<PastSessionInput> sessions, {
    required DateTime now,
    bool canExcuse = false,
    String? firstDate,
    List<SessionMove> moves = const [],
  }) async {
    if (sessions.isEmpty && firstDate == null && moves.isEmpty) {
      throw ValidationException.field('sessions', 'اختر حصة واحدة على الأقل');
    }
    final today = DateKey.of(now);
    if (firstDate != null) _checkDate(firstDate, field: 'first_date');
    _checkMoves(moves, today: today);
    final seen = <String>{};
    for (final input in sessions) {
      _checkDate(input.date);
      if (input.date.compareTo(today) >= 0) {
        throw ValidationException.field(
          'sessions',
          'الحصص السابقة قبل اليوم فقط؛ حصص اليوم تُسجَّل من شاشة الحضور',
        );
      }
      if (firstDate != null && input.date.compareTo(firstDate) < 0) {
        throw ValidationException.field(
          'sessions',
          'حصة قبل تاريخ أول حصة في الدورة: ${input.date}',
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
      final size = group.sessionsPerCycle;
      final state = await _cycleState(group);
      final earliestHeld = state.earliestHeld;
      if (firstDate != null &&
          earliestHeld != null &&
          firstDate.compareTo(earliestHeld) > 0) {
        throw ValidationException.field(
          'first_date',
          'أول حصة لا تكون بعد حصة انعقدت وسُجّلت ($earliestHeld)',
        );
      }
      if (sessions.isNotEmpty) {
        final allowed = size - 1 - state.held;
        if (sessions.length > allowed) {
          throw ValidationException.field(
            'sessions',
            allowed <= 0
                ? 'لا يمكن تسجيل حصص سابقة: الدورة تكاد تكتمل'
                : 'يمكن تسجيل $allowed حصة سابقة على الأكثر '
                      '(حصص الدورة $size)',
          );
        }
        if (state.fixed.length + sessions.length > size) {
          throw ValidationException.field(
            'sessions',
            'حصص الدورة ($size) لا تتسع لما سُجّل وللحصص الثابتة فيها '
                '(${state.fixed.length})',
          );
        }
      }

      final roster = {for (final s in await this.roster(groupId)) s.studentId};
      final reusable = {
        for (final s in state.deletable) '${s.date}|${s.startMinutes}': s,
      };
      for (final input in sessions) {
        for (final studentId in input.marks.keys) {
          if (!roster.contains(studentId)) {
            throw ValidationException.field(
              'attendance',
              'تلميذ ليس منتسباً إلى هذا الفوج في دورته الحالية',
            );
          }
        }
        final key = '${input.date}|${input.startMinutes}';
        if (!reusable.containsKey(key) &&
            await _slotTaken(groupId, input.date, input.startMinutes)) {
          throw ValidationException.field(
            'sessions',
            'حصة هذا الفوج في ${input.date} '
                '${DateKey.formatMinutes(input.startMinutes)} مسجَّلة من قبل',
          );
        }
      }

      var marks = 0;
      final reused = <String>{};
      final ordered = [...sessions]
        ..sort((a, b) {
          final byDate = a.date.compareTo(b.date);
          return byDate != 0
              ? byDate
              : a.startMinutes.compareTo(b.startMinutes);
        });
      for (final input in ordered) {
        // حصة برمجها النظام ولم تُسجَّل تُغلق نفسها، وغيرها يُنشأ مغلقاً.
        final scheduled = reusable['${input.date}|${input.startMinutes}'];
        final SessionRow session;
        if (scheduled != null) {
          session = scheduled;
          reused.add(scheduled.id);
        } else {
          session = await cycles.addSession(
            groupId: groupId,
            date: input.date,
            startMinutes: input.startMinutes,
            endMinutes: input.endMinutes,
            status: SessionStatus.normal,
          );
        }
        await cycles.closeSession(session.id);
        for (final entry in input.marks.entries) {
          await attendance.writeHistorical(session, entry.key, entry.value);
          marks++;
        }
      }

      // ما لم يُحدَّد من الحصص المبرمجة (ماضية لم تنعقد، أو قادمة) يُحذف ثم تُبرمج القادمة
      // من الجدول من جديد: من اليوم، أو من أول حصة إن كانت بعد اليوم.
      var deletedUpcoming = 0;
      for (final session in state.deletable) {
        if (reused.contains(session.id)) continue;
        await writer.softDelete(db.sessions, key: {'id': session.id});
        if (session.date.compareTo(today) >= 0) deletedUpcoming++;
      }
      await cycles.renumber(groupId, cycle);
      final created = await cycles.topUp(
        groupId,
        fromDate: firstDate != null && firstDate.compareTo(today) > 0
            ? firstDate
            : today,
        continueAfterLast: false,
      );
      await _applyMoves(group, moves, now: now);
      final removed = deletedUpcoming - created.length;
      return PastSessionsResult(
        sessions: sessions.length,
        marks: marks,
        removedUpcoming: removed < 0 ? 0 : removed,
      );
    });
  }

  /// فحص النقل قبل أي كتابة: تواريخ صالحة، والوجهة اليوم أو بعده، ولا تكرار.
  static void _checkMoves(List<SessionMove> moves, {required String today}) {
    final from = <String>{};
    final to = <String>{};
    for (final move in moves) {
      _checkDate(move.fromDate, field: fieldMoves);
      _checkDate(move.toDate, field: fieldMoves);
      if (move.startMinutes < 0 || move.startMinutes >= 24 * 60) {
        throw ValidationException.field(fieldMoves, 'وقت الحصة غير صالح');
      }
      if (move.fromDate.compareTo(today) < 0) {
        throw ValidationException.field(
          fieldMoves,
          'حصة ${move.fromDate} مضى موعدها فلا تُنقل',
        );
      }
      if (move.toDate.compareTo(today) < 0) {
        throw ValidationException.field(
          fieldMoves,
          'تُنقل الحصة إلى اليوم أو ما بعده، لا إلى تاريخ مضى (${move.toDate})',
        );
      }
      if (move.toDate == move.fromDate) {
        throw ValidationException.field(
          fieldMoves,
          'اختر تاريخاً مختلفاً عن تاريخ الحصة (${move.fromDate})',
        );
      }
      if (!from.add(move.fromKey)) {
        throw ValidationException.field(
          fieldMoves,
          'حصة ${move.fromDate} مذكورة في أكثر من نقل',
        );
      }
      if (!to.add('${move.toDate}|${move.startMinutes}')) {
        throw ValidationException.field(
          fieldMoves,
          'حصتان تُنقلان إلى الموعد نفسه: ${move.toDate}',
        );
      }
    }
  }

  /// ينقل الحصص القادمة بترتيبها، وأي رفض يُلغي العملية كلها (داخل معاملة [record]).
  Future<void> _applyMoves(
    GroupRow group,
    List<SessionMove> moves, {
    required DateTime now,
  }) async {
    final today = DateKey.of(now);
    final minutes = DateKey.minutesOf(now);
    for (final move in moves) {
      final session = await _liveSession(
        group.id,
        move.fromDate,
        move.startMinutes,
      );
      if (session == null ||
          session.status == SessionStatus.cancelled.code ||
          session.cycleNumber != group.currentCycleNumber) {
        throw ValidationException.field(
          fieldMoves,
          'لا حصة قادمة للفوج يوم ${move.fromDate} لنقلها',
        );
      }
      if (move.toDate == today && session.endMinutes <= minutes) {
        throw ValidationException.field(
          fieldMoves,
          'انتهى وقت هذه الحصة اليوم؛ اختر يوماً بعد اليوم',
        );
      }
      final conflicts = await _schedule.dateConflicts(
        date: move.toDate,
        startMinutes: session.startMinutes,
        endMinutes: session.endMinutes,
        teacherId: group.teacherId,
        roomId: session.roomId ?? group.roomId,
        excludeSessionId: session.id,
      );
      if (conflicts.isNotEmpty) {
        throw ValidationException.field(
          fieldMoves,
          'تعارض في ${move.toDate}: ${conflicts.map((c) => c.message).join('، ')}',
        );
      }
      try {
        await cycles.moveSession(session.id, toDate: move.toDate);
      } on StateError catch (e) {
        throw ValidationException.field(fieldMoves, e.message);
      }
    }
  }

  Future<SessionRow?> _liveSession(String groupId, String date, int start) =>
      (db.select(db.sessions)..where(
            (s) =>
                s.groupId.equals(groupId) &
                s.date.equals(date) &
                s.startMinutes.equals(start) &
                s.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  /// حصص الدورة الحالية مصنّفة: ثابتة (لا تُمَسّ) أو قابلة لإعادة البرمجة.
  Future<_CycleState> _cycleState(GroupRow group) async {
    final all =
        await (db.select(db.sessions)
              ..where((s) => s.groupId.equals(group.id) & s.deletedAt.isNull())
              ..orderBy([
                (s) => OrderingTerm(expression: s.date),
                (s) => OrderingTerm(expression: s.startMinutes),
              ]))
            .get();
    final marked = await db
        .customSelect(
          'SELECT DISTINCT a.session_id AS id FROM attendance a '
          'JOIN sessions s ON s.id = a.session_id '
          'WHERE s.group_id = ? AND a.deleted_at IS NULL',
          variables: [Variable<String>(group.id)],
          readsFrom: {db.attendance, db.sessions},
        )
        .get();
    final markedIds = {for (final row in marked) row.read<String>('id')};

    final fixed = <SessionRow>[];
    final deletable = <SessionRow>[];
    final taken = <String>{};
    for (final session in all) {
      final inCycle = session.cycleNumber == group.currentCycleNumber;
      final counted = session.status != SessionStatus.cancelled.code;
      final replannable =
          inCycle &&
          session.closedAt == null &&
          session.status == SessionStatus.normal.code &&
          !markedIds.contains(session.id);
      if (replannable) {
        deletable.add(session);
        continue;
      }
      taken.add('${session.date}|${session.startMinutes}');
      if (inCycle && counted) fixed.add(session);
    }
    return _CycleState(fixed: fixed, deletable: deletable, taken: taken);
  }

  Future<List<GroupSlotRow>> _slots(String groupId) =>
      (db.select(db.groupSlots)
            ..where((s) => s.groupId.equals(groupId) & s.deletedAt.isNull())
            ..orderBy([(s) => OrderingTerm(expression: s.startMinutes)]))
          .get();

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

  static int _byTime(PlannedSession a, PlannedSession b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.startMinutes.compareTo(b.startMinutes);
  }

  static void _checkDate(String value, {String field = 'sessions'}) {
    final valid = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);
    if (!valid || DateKey.of(DateKey.parse(value)) != value) {
      throw ValidationException.field(field, 'تاريخ غير صالح: $value');
    }
  }
}
