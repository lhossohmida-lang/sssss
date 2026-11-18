import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'date_key.dart';
import 'enums.dart';
import 'stable_id.dart';

/// حصة كانت ستُبرمج من الجدول الأسبوعي للمجموعة ولم تُكتب بعد.
class ScheduledOccurrence {
  const ScheduledOccurrence({
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    this.roomId,
  });

  /// التاريخ `YYYY-MM-DD`.
  final String date;
  final int startMinutes;
  final int endMinutes;
  final String? roomId;

  String get key => '$date|$startMinutes';
}

/// قواعد الدورة: «الشهر» دورة من `sessions_per_cycle` حصة.
///
/// - الحصة الملغاة لا تُحسب ولا رقم لها.
/// - التعويضية والمضافة تُحسبان مثل العادية.
/// - الدورة تكتمل عندما يبلغ عدد الحصص المحسوبة المُغلقة حدّ الدورة،
///   وما بقي من حصص مبرمجة لم تُغلق ينتقل إلى الدورة التالية.
class CycleService {
  CycleService(this.db, this.writer);

  final AppDatabase db;
  final SyncWriter writer;

  /// أقصى عدد أيام يُبحث فيها عن خانات لإكمال برمجة الدورة.
  static const int _maxDaysAhead = 400;

  /// حصص دورة مرتبة زمنياً (دون المحذوفة).
  Future<List<SessionRow>> cycleSessions(String groupId, int cycleNumber) {
    final query = db.select(db.sessions)
      ..where(
        (s) =>
            s.groupId.equals(groupId) &
            s.cycleNumber.equals(cycleNumber) &
            s.deletedAt.isNull(),
      )
      ..orderBy([
        (s) => OrderingTerm(expression: s.date),
        (s) => OrderingTerm(expression: s.startMinutes),
      ]);
    return query.get();
  }

  /// عدد الحصص المحسوبة في الدورة؛ مع [closedOnly] تُعدّ المُغلقة فقط.
  Future<int> countedSessions(
    String groupId,
    int cycleNumber, {
    bool closedOnly = false,
  }) async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM sessions '
          'WHERE group_id = ? AND cycle_number = ? AND deleted_at IS NULL '
          "AND status <> 'cancelled'"
          '${closedOnly ? ' AND closed_at IS NOT NULL' : ''}',
          variables: [Variable<String>(groupId), Variable<int>(cycleNumber)],
          readsFrom: {db.sessions},
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// يعيد ترقيم حصص الدورة: 1، 2، 3… للمحسوبة بالترتيب الزمني،
  /// ولا رقم للملغاة. لا يكتب إلا ما تغيّر.
  Future<void> renumber(String groupId, int cycleNumber) {
    return db.transaction(() async {
      final sessions = await cycleSessions(groupId, cycleNumber);
      var next = 1;
      for (final session in sessions) {
        final counts = SessionStatus.fromCode(session.status).countsInCycle;
        final number = counts ? next++ : null;
        if (session.sessionNumber != number) {
          await _save(session.copyWith(sessionNumber: Value(number)));
        }
      }
    });
  }

  /// يبرمج من الجدول الأسبوعي ما ينقص الدورة الحالية حتى تبلغ حدّها،
  /// ابتداءً من [fromDate] أو من اليوم التالي لآخر حصة مبرمجة، أيهما أبعد.
  /// مع `continueAfterLast: false` يبدأ من [fromDate] نفسه ويملأ ما فيه من فراغ
  /// (لإعادة برمجة الدورة من تاريخ أول حصة).
  ///
  /// يعيد الحصص الجديدة. لا ينشئ شيئاً إن لم يكن للمجموعة جدول أسبوعي.
  Future<List<SessionRow>> topUp(
    String groupId, {
    required String fromDate,
    bool continueAfterLast = true,
  }) {
    return db.transaction(() async {
      final group = await _group(groupId);
      final cycle = group.currentCycleNumber;
      final missing =
          group.sessionsPerCycle - await countedSessions(groupId, cycle);
      if (missing <= 0) return const <SessionRow>[];

      var day = fromDate;
      if (continueAfterLast) {
        final existing = await cycleSessions(groupId, cycle);
        if (existing.isNotEmpty) {
          final afterLast = DateKey.next(existing.last.date);
          if (afterLast.compareTo(day) > 0) day = afterLast;
        }
      }

      final planned = await _occurrences(group, day, missing, const {});
      if (planned.isEmpty) return const <SessionRow>[];
      final created = <SessionRow>[];
      for (final occurrence in planned) {
        final stamp = writer.now();
        final session = SessionRow(
          id: StableId.session(
            groupId,
            occurrence.date,
            occurrence.startMinutes,
          ),
          createdAt: stamp,
          updatedAt: stamp,
          groupId: groupId,
          cycleNumber: cycle,
          date: occurrence.date,
          startMinutes: occurrence.startMinutes,
          endMinutes: occurrence.endMinutes,
          roomId: occurrence.roomId,
          status: SessionStatus.normal.code,
        );
        await _save(session);
        created.add(session);
      }
      await renumber(groupId, cycle);
      return created;
    });
  }

  /// أول [count] حصة من الجدول الأسبوعي ابتداءً من [fromDate] لا حصة قائمة فيها،
  /// بالترتيب الزمني، دون كتابة شيء. حصص [ignore] (معرّفاتها) تُعامَل كأنها
  /// محذوفة، لمعاينة ما سيُبرمج بعد حذفها.
  Future<List<ScheduledOccurrence>> occurrences(
    String groupId, {
    required String fromDate,
    required int count,
    Set<String> ignore = const {},
  }) async => _occurrences(await _group(groupId), fromDate, count, ignore);

  Future<List<ScheduledOccurrence>> _occurrences(
    GroupRow group,
    String fromDate,
    int count,
    Set<String> ignore,
  ) async {
    if (count <= 0) return const <ScheduledOccurrence>[];
    final slots =
        await (db.select(db.groupSlots)
              ..where((s) => s.groupId.equals(group.id) & s.deletedAt.isNull())
              ..orderBy([(s) => OrderingTerm(expression: s.startMinutes)]))
            .get();
    if (slots.isEmpty) return const <ScheduledOccurrence>[];

    final found = <ScheduledOccurrence>[];
    var day = fromDate;
    for (var i = 0; i < _maxDaysAhead && found.length < count; i++) {
      final weekday = DateKey.weekday(day);
      for (final slot in slots.where((s) => s.weekday == weekday)) {
        if (found.length >= count) break;
        if (await _slotTaken(group.id, day, slot.startMinutes, ignore)) {
          continue;
        }
        found.add(
          ScheduledOccurrence(
            date: day,
            startMinutes: slot.startMinutes,
            endMinutes: slot.endMinutes,
            roomId: slot.roomId ?? group.roomId,
          ),
        );
      }
      day = DateKey.next(day);
    }
    return found;
  }

  /// يضيف حصة (مضافة أو تعويضية أو عادية) إلى الدورة الحالية ويعيد الترقيم.
  Future<SessionRow> addSession({
    required String groupId,
    required String date,
    required int startMinutes,
    required int endMinutes,
    String? roomId,
    SessionStatus status = SessionStatus.added,
  }) {
    if (status == SessionStatus.cancelled) {
      throw ArgumentError.value(status, 'status', 'لا تُضاف حصة ملغاة');
    }
    if (endMinutes <= startMinutes) {
      throw ArgumentError('وقت النهاية يجب أن يكون بعد وقت البداية');
    }
    return db.transaction(() async {
      final group = await _group(groupId);
      final stamp = writer.now();
      final session = SessionRow(
        id: StableId.session(groupId, date, startMinutes),
        createdAt: stamp,
        updatedAt: stamp,
        groupId: groupId,
        cycleNumber: group.currentCycleNumber,
        date: date,
        startMinutes: startMinutes,
        endMinutes: endMinutes,
        roomId: roomId ?? group.roomId,
        status: status.code,
      );
      await _save(session);
      await renumber(groupId, group.currentCycleNumber);
      return _session(session.id);
    });
  }

  /// يلغي حصة: تخرج من حساب الدورة، ويُعاد الترقيم، وتُبرمج حصة بديلة
  /// في آخر الدورة من الجدول الأسبوعي.
  Future<void> cancelSession(String sessionId) {
    return db.transaction(() async {
      final session = await _session(sessionId);
      if (session.status == SessionStatus.cancelled.code) return;
      if (session.closedAt != null) {
        throw StateError('لا تُلغى حصة أُغلقت بعد انعقادها');
      }
      await _save(
        session.copyWith(
          status: SessionStatus.cancelled.code,
          sessionNumber: const Value(null),
        ),
      );
      await renumber(session.groupId, session.cycleNumber);
      final group = await _group(session.groupId);
      if (group.currentCycleNumber == session.cycleNumber) {
        await topUp(session.groupId, fromDate: DateKey.next(session.date));
      }
    });
  }

  /// يغلق الحصة بعد انعقادها. يعيد `false` إن كانت مغلقة أو ملغاة.
  Future<bool> closeSession(String sessionId) {
    return db.transaction(() async {
      final session = await _session(sessionId);
      if (session.closedAt != null ||
          session.status == SessionStatus.cancelled.code) {
        return false;
      }
      await _save(session.copyWith(closedAt: Value(writer.now())));
      return true;
    });
  }

  /// ينقل حصة قادمة إلى [toDate] بوقتها وقاعتها نفسيهما، ويعيد الحصة الجديدة.
  ///
  /// تُلغى الحصة في موعدها القديم (فيبقى محجوزاً بها ولا يُعاد برمجته من الجدول) وتُضاف في
  /// الموعد الجديد حصة تعويضية في الدورة نفسها، فيبقى عدد حصص الدورة كما هو ولا تُبرمج
  /// حصة بديلة. موعد قديم ملغى بالنقل يصلح وجهةً لنقل لاحق. يرمي [StateError] برسالة عربية
  /// إن كانت الحصة ملغاة أو أُغلقت أو سُجّل حضورها، أو كان [toDate] تاريخها نفسه، أو كان
  /// للفوج حصة قائمة في الموعد الجديد.
  Future<SessionRow> moveSession(String sessionId, {required String toDate}) {
    return db.transaction(() async {
      final session = await _session(sessionId);
      if (session.status == SessionStatus.cancelled.code) {
        throw StateError('لا تُنقل حصة ملغاة');
      }
      if (session.closedAt != null || await _hasAttendance(sessionId)) {
        throw StateError('لا تُنقل حصة انعقدت أو سُجّل حضورها');
      }
      if (toDate == session.date) {
        throw StateError('اختر تاريخاً مختلفاً عن تاريخ الحصة');
      }
      if (!await _slotFree(session.groupId, toDate, session.startMinutes)) {
        throw StateError(
          'للفوج حصة يوم $toDate على '
          '${DateKey.formatMinutes(session.startMinutes)} من قبل',
        );
      }
      await _save(
        session.copyWith(
          status: SessionStatus.cancelled.code,
          sessionNumber: const Value(null),
        ),
      );
      final stamp = writer.now();
      final moved = SessionRow(
        id: StableId.session(session.groupId, toDate, session.startMinutes),
        createdAt: stamp,
        updatedAt: stamp,
        groupId: session.groupId,
        cycleNumber: session.cycleNumber,
        date: toDate,
        startMinutes: session.startMinutes,
        endMinutes: session.endMinutes,
        roomId: session.roomId,
        status: SessionStatus.makeup.code,
      );
      await _save(moved);
      await renumber(session.groupId, session.cycleNumber);
      return _session(moved.id);
    });
  }

  /// هل اكتملت الدورة الحالية للمجموعة؟
  Future<bool> isCurrentCycleComplete(String groupId) async {
    final group = await _group(groupId);
    final closed = await countedSessions(
      groupId,
      group.currentCycleNumber,
      closedOnly: true,
    );
    return closed >= group.sessionsPerCycle;
  }

  /// إن اكتملت الدورة الحالية: ينقل ما بقي من حصصها غير المغلقة إلى الدورة
  /// التالية، يبدأ الدورة الجديدة، ويبرمج حصصها من [fromDate].
  ///
  /// يعيد رقم الدورة التي اكتملت، أو `null` إن لم تكتمل بعد.
  Future<int?> completeCycleIfDone(String groupId, {required String fromDate}) {
    return db.transaction(() async {
      if (!await isCurrentCycleComplete(groupId)) return null;
      final group = await _group(groupId);
      final finished = group.currentCycleNumber;
      final next = finished + 1;

      for (final session in await cycleSessions(groupId, finished)) {
        if (session.closedAt == null) {
          await _save(session.copyWith(cycleNumber: next));
        }
      }
      await writer.save(
        db.groups,
        group.copyWith(currentCycleNumber: next),
        key: {'id': group.id},
        action: 'cycle_complete',
      );
      await renumber(groupId, finished);
      await renumber(groupId, next);
      await topUp(groupId, fromDate: fromDate);
      return finished;
    });
  }

  Future<bool> _slotTaken(
    String groupId,
    String date,
    int start, [
    Set<String> ignore = const {},
  ]) async {
    final row = await db
        .customSelect(
          'SELECT id FROM sessions WHERE group_id = ? AND date = ? '
          'AND start_minutes = ? AND deleted_at IS NULL LIMIT 1',
          variables: [
            Variable<String>(groupId),
            Variable<String>(date),
            Variable<int>(start),
          ],
          readsFrom: {db.sessions},
        )
        .getSingleOrNull();
    return row != null && !ignore.contains(row.read<String>('id'));
  }

  /// هل موعد الحصة خالٍ؟ الحصة الملغاة لا تحجز موعدها لحصة جديدة.
  Future<bool> _slotFree(String groupId, String date, int start) async {
    final row = await db
        .customSelect(
          'SELECT id FROM sessions WHERE group_id = ? AND date = ? '
          'AND start_minutes = ? AND deleted_at IS NULL '
          "AND status <> 'cancelled' LIMIT 1",
          variables: [
            Variable<String>(groupId),
            Variable<String>(date),
            Variable<int>(start),
          ],
          readsFrom: {db.sessions},
        )
        .getSingleOrNull();
    return row == null;
  }

  Future<bool> _hasAttendance(String sessionId) async {
    final row = await db
        .customSelect(
          'SELECT 1 FROM attendance WHERE session_id = ? '
          'AND deleted_at IS NULL LIMIT 1',
          variables: [Variable<String>(sessionId)],
          readsFrom: {db.attendance},
        )
        .getSingleOrNull();
    return row != null;
  }

  Future<GroupRow> _group(String id) =>
      (db.select(db.groups)..where((g) => g.id.equals(id))).getSingle();

  Future<SessionRow> _session(String id) =>
      (db.select(db.sessions)..where((s) => s.id.equals(id))).getSingle();

  Future<void> _save(SessionRow session) =>
      writer.save(db.sessions, session, key: {'id': session.id});
}
