import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import 'date_key.dart';

/// سبب التعارض.
enum ConflictKind {
  /// نفس القاعة محجوزة في نفس الوقت.
  room('القاعة محجوزة'),

  /// نفس الأستاذ عنده حصة في نفس الوقت.
  teacher('الأستاذ مشغول');

  const ConflictKind(this.label);

  final String label;
}

/// تعارض مع مجموعة أخرى في القاعة أو الأستاذ.
class ScheduleConflict {
  const ScheduleConflict({
    required this.kind,
    required this.groupId,
    required this.groupNumber,
    required this.startMinutes,
    required this.endMinutes,
    this.roomId,
  });

  final ConflictKind kind;

  /// المجموعة التي تشغل الوقت.
  final String groupId;
  final int groupNumber;
  final int startMinutes;
  final int endMinutes;
  final String? roomId;

  /// رسالة واضحة للمستخدم.
  String get message =>
      '${kind.label}: المجموعة $groupNumber من '
      '${DateKey.formatMinutes(startMinutes)} إلى '
      '${DateKey.formatMinutes(endMinutes)}';
}

/// كشف تعارض الجدول: نفس القاعة أو نفس الأستاذ لا يُحجزان في نفس الوقت.
class ScheduleService {
  ScheduleService(this.db);

  final AppDatabase db;

  /// تعارضات خانة أسبوعية مقترحة مع الجداول الأسبوعية للمجموعات النشطة.
  ///
  /// [excludeGroupId] المجموعة التي يجري تعديلها (لا تتعارض مع نفسها).
  Future<List<ScheduleConflict>> slotConflicts({
    required int weekday,
    required int startMinutes,
    required int endMinutes,
    required String teacherId,
    String? roomId,
    String? excludeGroupId,
  }) async {
    _checkRange(startMinutes, endMinutes);
    final occupied = await _slotOccupancy(
      weekday: weekday,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      excludeGroupId: excludeGroupId,
    );
    return _conflicts(occupied, roomId: roomId, teacherId: teacherId);
  }

  /// تعارضات حصة مقترحة في تاريخ محدد.
  ///
  /// تُفحص الحصص المبرمجة في ذلك التاريخ (غير الملغاة)، وكذلك الخانات
  /// الأسبوعية للمجموعات التي لم تُبرمج حصتها لذلك اليوم بعد.
  /// [excludeSessionId] الحصة التي يجري نقلها.
  Future<List<ScheduleConflict>> dateConflicts({
    required String date,
    required int startMinutes,
    required int endMinutes,
    required String teacherId,
    String? roomId,
    String? excludeSessionId,
  }) async {
    _checkRange(startMinutes, endMinutes);
    final occupied = await _dateOccupancy(
      date: date,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      excludeSessionId: excludeSessionId,
    );
    return _conflicts(occupied, roomId: roomId, teacherId: teacherId);
  }

  /// القاعات المتاحة في تاريخ ووقت محددين، الأصغر سعةً أولاً.
  Future<List<RoomRow>> freeRoomsOnDate({
    required String date,
    required int startMinutes,
    required int endMinutes,
    String? excludeSessionId,
    int minCapacity = 0,
  }) async {
    _checkRange(startMinutes, endMinutes);
    final occupied = await _dateOccupancy(
      date: date,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      excludeSessionId: excludeSessionId,
    );
    return _freeRooms(occupied, minCapacity);
  }

  /// القاعات المتاحة لخانة أسبوعية، الأصغر سعةً أولاً.
  Future<List<RoomRow>> freeRoomsForSlot({
    required int weekday,
    required int startMinutes,
    required int endMinutes,
    String? excludeGroupId,
    int minCapacity = 0,
  }) async {
    _checkRange(startMinutes, endMinutes);
    final occupied = await _slotOccupancy(
      weekday: weekday,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      excludeGroupId: excludeGroupId,
    );
    return _freeRooms(occupied, minCapacity);
  }

  /// يقترح قاعة لحصة في تاريخ محدد: القاعة المفضّلة إن كانت متاحة، وإلا
  /// أصغر قاعة متاحة تسع [minCapacity]. يعيد `null` إن لم توجد قاعة.
  Future<RoomRow?> suggestRoom({
    required String date,
    required int startMinutes,
    required int endMinutes,
    String? preferredRoomId,
    String? excludeSessionId,
    int minCapacity = 0,
  }) async {
    final free = await freeRoomsOnDate(
      date: date,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      excludeSessionId: excludeSessionId,
      minCapacity: minCapacity,
    );
    if (free.isEmpty) return null;
    for (final room in free) {
      if (room.id == preferredRoomId) return room;
    }
    return free.first;
  }

  static void _checkRange(int start, int end) {
    if (start < 0 || end > 24 * 60 || end <= start) {
      throw ArgumentError('وقت غير صالح: من $start إلى $end');
    }
  }

  static List<ScheduleConflict> _conflicts(
    List<_Occupied> occupied, {
    required String? roomId,
    required String teacherId,
  }) {
    final conflicts = <ScheduleConflict>[];
    for (final item in occupied) {
      if (roomId != null && item.roomId == roomId) {
        conflicts.add(item.toConflict(ConflictKind.room));
      }
      if (item.teacherId == teacherId) {
        conflicts.add(item.toConflict(ConflictKind.teacher));
      }
    }
    return conflicts;
  }

  Future<List<RoomRow>> _freeRooms(
    List<_Occupied> occupied,
    int minCapacity,
  ) async {
    final busy = {
      for (final item in occupied)
        if (item.roomId != null) item.roomId!,
    };
    final rooms =
        await (db.select(db.rooms)
              ..where(
                (r) =>
                    r.deletedAt.isNull() &
                    r.capacity.isBiggerOrEqualValue(minCapacity),
              )
              ..orderBy([
                (r) => OrderingTerm(expression: r.capacity),
                (r) => OrderingTerm(expression: r.name),
              ]))
            .get();
    return [
      for (final room in rooms)
        if (!busy.contains(room.id)) room,
    ];
  }

  /// الخانات الأسبوعية للمجموعات النشطة المتقاطعة مع الوقت المطلوب.
  Future<List<_Occupied>> _slotOccupancy({
    required int weekday,
    required int startMinutes,
    required int endMinutes,
    String? excludeGroupId,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT g.id AS group_id, g.number, g.teacher_id, '
          'COALESCE(gs.room_id, g.room_id) AS room_id, '
          'gs.start_minutes, gs.end_minutes '
          'FROM group_slots gs JOIN groups g ON g.id = gs.group_id '
          'WHERE gs.weekday = ? AND gs.start_minutes < ? '
          'AND gs.end_minutes > ? AND gs.deleted_at IS NULL '
          'AND g.deleted_at IS NULL AND g.archived_at IS NULL '
          'AND g.id <> ?',
          variables: [
            Variable<int>(weekday),
            Variable<int>(endMinutes),
            Variable<int>(startMinutes),
            Variable<String>(excludeGroupId ?? ''),
          ],
          readsFrom: {db.groupSlots, db.groups},
        )
        .get();
    return rows.map(_Occupied.fromRow).toList();
  }

  /// ما يشغل الوقت في تاريخ محدد: الحصص المبرمجة، ثم الخانات الأسبوعية
  /// التي لم تُبرمج حصتها لذلك اليوم بعد.
  Future<List<_Occupied>> _dateOccupancy({
    required String date,
    required int startMinutes,
    required int endMinutes,
    String? excludeSessionId,
  }) async {
    final excludedGroup = excludeSessionId == null
        ? null
        : (await (db.select(
                db.sessions,
              )..where((s) => s.id.equals(excludeSessionId))).getSingleOrNull())
              ?.groupId;

    final sessionRows = await db
        .customSelect(
          'SELECT g.id AS group_id, g.number, g.teacher_id, '
          'COALESCE(s.room_id, g.room_id) AS room_id, '
          's.start_minutes, s.end_minutes '
          'FROM sessions s JOIN groups g ON g.id = s.group_id '
          'WHERE s.date = ? AND s.start_minutes < ? AND s.end_minutes > ? '
          "AND s.deleted_at IS NULL AND s.status <> 'cancelled' "
          'AND g.deleted_at IS NULL AND s.id <> ?',
          variables: [
            Variable<String>(date),
            Variable<int>(endMinutes),
            Variable<int>(startMinutes),
            Variable<String>(excludeSessionId ?? ''),
          ],
          readsFrom: {db.sessions, db.groups},
        )
        .get();

    final slotRows = await db
        .customSelect(
          'SELECT g.id AS group_id, g.number, g.teacher_id, '
          'COALESCE(gs.room_id, g.room_id) AS room_id, '
          'gs.start_minutes, gs.end_minutes '
          'FROM group_slots gs JOIN groups g ON g.id = gs.group_id '
          'WHERE gs.weekday = ? AND gs.start_minutes < ? '
          'AND gs.end_minutes > ? AND gs.deleted_at IS NULL '
          'AND g.deleted_at IS NULL AND g.archived_at IS NULL '
          'AND NOT EXISTS (SELECT 1 FROM sessions s '
          'WHERE s.group_id = gs.group_id AND s.date = ? '
          'AND s.start_minutes = gs.start_minutes)',
          variables: [
            Variable<int>(DateKey.weekday(date)),
            Variable<int>(endMinutes),
            Variable<int>(startMinutes),
            Variable<String>(date),
          ],
          readsFrom: {db.groupSlots, db.groups, db.sessions},
        )
        .get();

    return [
      ...sessionRows.map(_Occupied.fromRow),
      // خانة المجموعة التي تُنقل حصتها لا تتعارض مع نفسها.
      ...slotRows
          .map(_Occupied.fromRow)
          .where((item) => item.groupId != excludedGroup),
    ];
  }
}

class _Occupied {
  const _Occupied({
    required this.groupId,
    required this.groupNumber,
    required this.teacherId,
    required this.roomId,
    required this.startMinutes,
    required this.endMinutes,
  });

  factory _Occupied.fromRow(QueryRow row) => _Occupied(
    groupId: row.read<String>('group_id'),
    groupNumber: row.read<int>('number'),
    teacherId: row.read<String>('teacher_id'),
    roomId: row.read<String?>('room_id'),
    startMinutes: row.read<int>('start_minutes'),
    endMinutes: row.read<int>('end_minutes'),
  );

  final String groupId;
  final int groupNumber;
  final String teacherId;
  final String? roomId;
  final int startMinutes;
  final int endMinutes;

  ScheduleConflict toConflict(ConflictKind kind) => ScheduleConflict(
    kind: kind,
    groupId: groupId,
    groupNumber: groupNumber,
    startMinutes: startMinutes,
    endMinutes: endMinutes,
    roomId: roomId,
  );
}
