import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'date_key.dart';
import 'enums.dart';
import 'stable_id.dart';

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
  ///
  /// يعيد الحصص الجديدة. لا ينشئ شيئاً إن لم يكن للمجموعة جدول أسبوعي.
  Future<List<SessionRow>> topUp(String groupId, {required String fromDate}) {
    return db.transaction(() async {
      final group = await _group(groupId);
      final cycle = group.currentCycleNumber;
      final missing =
          group.sessionsPerCycle - await countedSessions(groupId, cycle);
      if (missing <= 0) return const <SessionRow>[];

      final slots =
          await (db.select(db.groupSlots)
                ..where((s) => s.groupId.equals(groupId) & s.deletedAt.isNull())
                ..orderBy([(s) => OrderingTerm(expression: s.startMinutes)]))
              .get();
      if (slots.isEmpty) return const <SessionRow>[];

      final existing = await cycleSessions(groupId, cycle);
      var day = fromDate;
      if (existing.isNotEmpty) {
        final afterLast = DateKey.next(existing.last.date);
        if (afterLast.compareTo(day) > 0) day = afterLast;
      }

      final created = <SessionRow>[];
      for (var i = 0; i < _maxDaysAhead && created.length < missing; i++) {
        final weekday = DateKey.weekday(day);
        for (final slot in slots.where((s) => s.weekday == weekday)) {
          if (created.length >= missing) break;
          if (await _slotTaken(groupId, day, slot.startMinutes)) continue;
          final stamp = writer.now();
          final session = SessionRow(
            id: StableId.session(groupId, day, slot.startMinutes),
            createdAt: stamp,
            updatedAt: stamp,
            groupId: groupId,
            cycleNumber: cycle,
            date: day,
            startMinutes: slot.startMinutes,
            endMinutes: slot.endMinutes,
            roomId: slot.roomId ?? group.roomId,
            status: SessionStatus.normal.code,
          );
          await _save(session);
          created.add(session);
        }
        day = DateKey.next(day);
      }
      await renumber(groupId, cycle);
      return created;
    });
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

  Future<GroupRow> _group(String id) =>
      (db.select(db.groups)..where((g) => g.id.equals(id))).getSingle();

  Future<SessionRow> _session(String id) =>
      (db.select(db.sessions)..where((s) => s.id.equals(id))).getSingle();

  Future<void> _save(SessionRow session) =>
      writer.save(db.sessions, session, key: {'id': session.id});
}
