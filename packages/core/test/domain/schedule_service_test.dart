import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late ScheduleService schedule;

  // 2026-11-14 يوم سبت (weekday = 6).
  const saturday = '2026-11-14';

  setUp(() async {
    env = TestEnv();
    schedule = ScheduleService(env.db);
    await env.subject();
    await env.teacher(id: 't1');
    await env.teacher(id: 't2');
    await env.room(id: 'r1');
    await env.room(id: 'r2');
    // المجموعة 1: الأستاذ t1، القاعة r1، السبت 10:00–11:30.
    await env.group(id: 'g1', teacherId: 't1', roomId: 'r1');
    await env.slot(id: 'sl1', groupId: 'g1', weekday: 6, start: 600, end: 690);
  });

  tearDown(() => env.close());

  Future<List<ConflictKind>> slot({
    int start = 600,
    int end = 690,
    String teacher = 't2',
    String? room = 'r2',
    int weekday = 6,
    String? exclude,
  }) async {
    final found = await schedule.slotConflicts(
      weekday: weekday,
      startMinutes: start,
      endMinutes: end,
      teacherId: teacher,
      roomId: room,
      excludeGroupId: exclude,
    );
    return found.map((c) => c.kind).toList();
  }

  Future<void> session(
    String id, {
    String groupId = 'g1',
    String date = saturday,
    int start = 600,
    int end = 690,
    String? roomId,
    String status = 'normal',
  }) => env.db
      .into(env.db.sessions)
      .insert(
        SessionsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          groupId: groupId,
          cycleNumber: 1,
          date: date,
          startMinutes: start,
          endMinutes: end,
          roomId: Value(roomId),
          status: Value(status),
        ),
      );

  group('الجدول الأسبوعي', () {
    test('نفس القاعة في نفس الوقت تعارض', () async {
      expect(await slot(room: 'r1'), [ConflictKind.room]);
    });

    test('نفس الأستاذ في نفس الوقت تعارض ولو في قاعة أخرى', () async {
      expect(await slot(teacher: 't1'), [ConflictKind.teacher]);
    });

    test('نفس القاعة ونفس الأستاذ: تعارضان', () async {
      expect(await slot(teacher: 't1', room: 'r1'), [
        ConflictKind.room,
        ConflictKind.teacher,
      ]);
    });

    test('قاعة أخرى وأستاذ آخر: لا تعارض', () async {
      expect(await slot(), isEmpty);
    });

    test('التقاطع الجزئي تعارض، والتلاصق ليس تعارضاً', () async {
      expect(await slot(room: 'r1', start: 660, end: 750), [ConflictKind.room]);
      expect(await slot(room: 'r1', start: 540, end: 601), [ConflictKind.room]);
      expect(await slot(room: 'r1', start: 620, end: 640), [ConflictKind.room]);
      expect(await slot(room: 'r1', start: 690, end: 780), isEmpty);
      expect(await slot(room: 'r1', start: 510, end: 600), isEmpty);
    });

    test('يوم آخر لا تعارض', () async {
      expect(await slot(room: 'r1', teacher: 't1', weekday: 2), isEmpty);
    });

    test('المجموعة لا تتعارض مع نفسها عند التعديل', () async {
      expect(await slot(room: 'r1', teacher: 't1', exclude: 'g1'), isEmpty);
    });

    test('المجموعة المؤرشفة أو المحذوفة لا تحجز شيئاً', () async {
      await (env.db.update(env.db.groups)..where((g) => g.id.equals('g1')))
          .write(const GroupsCompanion(archivedAt: Value(5)));
      expect(await slot(room: 'r1', teacher: 't1'), isEmpty);
    });

    test('قاعة الخانة تغلب القاعة الافتراضية للمجموعة', () async {
      await (env.db.update(env.db.groupSlots)..where((s) => s.id.equals('sl1')))
          .write(const GroupSlotsCompanion(roomId: Value('r2')));
      expect(await slot(room: 'r1'), isEmpty);
      expect(await slot(room: 'r2'), [ConflictKind.room]);
    });

    test('رسالة التعارض واضحة', () async {
      final conflict = (await schedule.slotConflicts(
        weekday: 6,
        startMinutes: 600,
        endMinutes: 690,
        teacherId: 't2',
        roomId: 'r1',
      )).single;
      expect(conflict.message, 'القاعة محجوزة: المجموعة 1 من 10:00 إلى 11:30');
      expect(conflict.groupId, 'g1');
    });

    test('الوقت غير الصالح يُرفض', () async {
      expect(() => slot(start: 700, end: 600), throwsArgumentError);
      expect(() => slot(start: 600, end: 600), throwsArgumentError);
      expect(() => slot(start: -5, end: 60), throwsArgumentError);
      expect(() => slot(start: 600, end: 2000), throwsArgumentError);
    });
  });

  group('تاريخ محدد', () {
    Future<List<ConflictKind>> onDate({
      String date = saturday,
      int start = 600,
      int end = 690,
      String teacher = 't2',
      String? room = 'r2',
      String? excludeSession,
    }) async {
      final found = await schedule.dateConflicts(
        date: date,
        startMinutes: start,
        endMinutes: end,
        teacherId: teacher,
        roomId: room,
        excludeSessionId: excludeSession,
      );
      return found.map((c) => c.kind).toList();
    }

    test('الخانة الأسبوعية تحجز اليوم حتى قبل برمجة حصته', () async {
      expect(await onDate(room: 'r1'), [ConflictKind.room]);
      expect(await onDate(teacher: 't1'), [ConflictKind.teacher]);
    });

    test('الحصة المبرمجة تُحسب مرة واحدة لا مرتين', () async {
      await session('se1');
      expect(await onDate(room: 'r1'), [ConflictKind.room]);
    });

    test('الحصة الملغاة تحرّر القاعة والأستاذ', () async {
      await session('se1', status: 'cancelled');
      expect(await onDate(room: 'r1', teacher: 't1'), isEmpty);
    });

    test('حصة مضافة خارج الجدول الأسبوعي تحجز وقتها', () async {
      await session('se-added', date: '2026-11-16', start: 900, end: 990);
      expect(
        await onDate(date: '2026-11-16', start: 930, end: 1000, room: 'r1'),
        [ConflictKind.room],
      );
      expect(
        await onDate(date: '2026-11-16', start: 990, end: 1050, room: 'r1'),
        isEmpty,
      );
    });

    test('الحصة المنقولة لا تتعارض مع نفسها ولا مع خانة مجموعتها', () async {
      await session('se1');
      expect(
        await onDate(room: 'r1', teacher: 't1', excludeSession: 'se1'),
        isEmpty,
      );
      // نقلها إلى سبت قادم لم تُبرمج حصته بعد: خانة مجموعتها لا تمنعها.
      expect(
        await onDate(
          date: '2026-11-21',
          room: 'r1',
          teacher: 't1',
          excludeSession: 'se1',
        ),
        isEmpty,
      );
    });

    test('قاعة الحصة تغلب قاعة المجموعة', () async {
      await session('se1', roomId: 'r2');
      expect(await onDate(room: 'r1'), isEmpty);
      expect(await onDate(room: 'r2'), [ConflictKind.room]);
    });
  });

  group('اقتراح قاعة', () {
    setUp(() async {
      await (env.db.update(env.db.rooms)..where((r) => r.id.equals('r1')))
          .write(const RoomsCompanion(capacity: Value(30)));
      await (env.db.update(env.db.rooms)..where((r) => r.id.equals('r2')))
          .write(const RoomsCompanion(capacity: Value(15)));
    });

    Future<RoomRow?> suggest({String? preferred, int capacity = 0}) =>
        schedule.suggestRoom(
          date: saturday,
          startMinutes: 600,
          endMinutes: 690,
          preferredRoomId: preferred,
          minCapacity: capacity,
        );

    test('القاعة المشغولة لا تُقترح', () async {
      final free = await schedule.freeRoomsOnDate(
        date: saturday,
        startMinutes: 600,
        endMinutes: 690,
      );
      expect(free.map((r) => r.id), ['r2']);
      expect((await suggest(preferred: 'r1'))?.id, 'r2');
    });

    test('القاعة المفضّلة تُقترح إن كانت متاحة', () async {
      await env.room(id: 'r3');
      expect((await suggest(preferred: 'r3'))?.id, 'r3');
    });

    test('أصغر قاعة تسع العدد المطلوب', () async {
      final free = await schedule.freeRoomsOnDate(
        date: '2026-11-16',
        startMinutes: 600,
        endMinutes: 690,
      );
      expect(free.map((r) => r.id), ['r2', 'r1']);
      final big = await schedule.suggestRoom(
        date: '2026-11-16',
        startMinutes: 600,
        endMinutes: 690,
        minCapacity: 20,
      );
      expect(big?.id, 'r1');
    });

    test('لا قاعة متاحة: يعيد null', () async {
      expect(await suggest(capacity: 20), isNull);
    });

    test('القاعات المتاحة لخانة أسبوعية', () async {
      final free = await schedule.freeRoomsForSlot(
        weekday: 6,
        startMinutes: 630,
        endMinutes: 720,
      );
      expect(free.map((r) => r.id), ['r2']);
      final editing = await schedule.freeRoomsForSlot(
        weekday: 6,
        startMinutes: 630,
        endMinutes: 720,
        excludeGroupId: 'g1',
      );
      expect(editing.map((r) => r.id), ['r2', 'r1']);
    });

    test('القاعة المحذوفة لا تُقترح', () async {
      await env.writer.softDelete(env.db.rooms, key: const {'id': 'r2'});
      expect(await suggest(), isNull);
    });
  });
}
