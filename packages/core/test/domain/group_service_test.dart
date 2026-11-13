import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late CycleService cycles;
  late GroupService service;

  // 2026-11-07 سبت، 2026-11-08 أحد، 2026-11-10 ثلاثاء.
  const start = '2026-11-07';
  const saturday = 6;
  const tuesday = 2;

  setUp(() async {
    env = TestEnv();
    cycles = CycleService(env.db, env.writer);
    service = GroupService(env.db, env.writer, ScheduleService(env.db), cycles);
    await env.subject();
    await env.subject(id: 'sub2', price: 2500);
    await env.teacher();
    await env.teacher(id: 't2');
    await env.room();
    await env.room(id: 'r2');
    for (final t in ['t1', 't2']) {
      await env.db
          .into(env.db.teacherSubjects)
          .insert(
            TeacherSubjectsCompanion.insert(
              teacherId: t,
              subjectId: 'sub',
              updatedAt: 1,
            ),
          );
    }
  });
  tearDown(() => env.close());

  const slotSat = GroupSlotInput(
    weekday: saturday,
    startMinutes: 600,
    endMinutes: 690,
  );
  const slotTue = GroupSlotInput(
    weekday: tuesday,
    startMinutes: 960,
    endMinutes: 1050,
  );

  Future<GroupRow> create({
    String teacher = 't1',
    String? room = 'r1',
    int cycle = 8,
    int? rate,
    List<GroupSlotInput> slots = const [slotSat, slotTue],
  }) => service.create(
    subjectId: 'sub',
    teacherId: teacher,
    roomId: room,
    sessionsPerCycle: cycle,
    ratePerStudent: rate,
    slots: slots,
    startDate: start,
  );

  Future<List<SessionRow>> sessions(String groupId) =>
      cycles.cycleSessions(groupId, 1);

  group('الإنشاء', () {
    test('مجموعة بجدولها وحصص دورتها الأولى مرقّمة', () async {
      final g = await create(rate: 900);
      expect(g.number, 1);
      expect(g.sessionsPerCycle, 8);
      expect(g.currentCycleNumber, 1);
      expect(g.ratePerStudent, 900);
      expect(g.roomId, 'r1');

      final slots = await service.slotsOf(g.id);
      expect(slots, hasLength(2));
      // السبت أولاً في الترتيب.
      expect(slots.first.weekday, saturday);

      final list = await sessions(g.id);
      expect(list, hasLength(8));
      expect(list.map((s) => s.sessionNumber), [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(list.first.date, '2026-11-07');
      expect(list[1].date, '2026-11-10');
      expect(list[2].date, '2026-11-14');
      for (final s in list) {
        expect(s.roomId, 'r1');
        expect(s.status, 'normal');
      }
    });

    test('أرقام المجموعات متسلسلة', () async {
      final a = await create();
      final b = await create(
        teacher: 't2',
        room: 'r2',
        slots: const [
          GroupSlotInput(weekday: 3, startMinutes: 600, endMinutes: 690),
        ],
      );
      expect(a.number, 1);
      expect(b.number, 2);
    });

    test('قاعة الخانة تتقدم على قاعة المجموعة', () async {
      final g = await create(
        slots: const [
          GroupSlotInput(
            weekday: saturday,
            startMinutes: 600,
            endMinutes: 690,
            roomId: 'r2',
          ),
        ],
      );
      expect((await sessions(g.id)).first.roomId, 'r2');
    });

    test('عدد حصص الدورة يحدد ما يُولَّد', () async {
      final g = await create(cycle: 4, slots: const [slotSat]);
      expect(await sessions(g.id), hasLength(4));
    });

    test('الكتابة عبر SyncWriter', () async {
      await create();
      final tables = (await env.db.select(env.db.outbox).get())
          .map((o) => o.targetTable)
          .toSet();
      expect(tables, containsAll(['groups', 'group_slots', 'sessions']));
    });

    test('إنشاء مجموعة يخبر أولياء منتظري المادة بموعدها', () async {
      await env.student();
      final enrolments = EnrolmentService(
        env.db,
        env.writer,
        DuesService(env.db, env.writer),
        cycles,
      );
      await enrolments.addToWaiting(studentId: 's1', subjectId: 'sub');

      final group = await create();

      final sms = await env.db.select(env.db.smsQueue).get();
      expect(sms, hasLength(1));
      expect(sms.single.kind, SmsTemplateKeys.groupCreated);
      expect(sms.single.phone, '+213550123456');
      expect(sms.single.message, contains('تلميذ s1'));
      expect(sms.single.message, contains('السبت 10:00–11:30'));
      expect(sms.single.eventKey, 'group_created:${group.id}:+213550123456');
    });
  });

  group('التحقق', () {
    Future<Map<String, String>> errorsFor({
      String subject = 'sub',
      String teacher = 't1',
      int cycle = 8,
      int? rate,
      List<GroupSlotInput> slots = const [slotSat],
      String? room = 'r1',
    }) => service.validate(
      subjectId: subject,
      teacherId: teacher,
      roomId: room,
      sessionsPerCycle: cycle,
      ratePerStudent: rate,
      slots: slots,
    );

    test('بيانات سليمة: لا أخطاء', () async {
      expect(await errorsFor(), isEmpty);
    });

    test('مادة أو أستاذ مجهولان، وأستاذ لا يدرّس المادة', () async {
      expect(
        (await errorsFor(subject: 'x')).keys,
        contains(GroupService.fieldSubject),
      );
      expect(
        (await errorsFor(teacher: 'x')).keys,
        contains(GroupService.fieldTeacher),
      );
      // t1 لا يدرّس sub2.
      final e = await errorsFor(subject: 'sub2');
      expect(e[GroupService.fieldTeacher], contains('لا يدرّس'));
    });

    test('حدود عدد الحصص والمبلغ', () async {
      expect(
        (await errorsFor(cycle: 0)).keys,
        contains(GroupService.fieldCycleSize),
      );
      expect(
        (await errorsFor(cycle: 32)).keys,
        contains(GroupService.fieldCycleSize),
      );
      expect(
        (await errorsFor(rate: -10)).keys,
        contains(GroupService.fieldRate),
      );
      expect(
        (await errorsFor(rate: 905)).keys,
        contains(GroupService.fieldRate),
      );
      expect(await errorsFor(rate: 0), isEmpty);
    });

    test('بلا خانات، وخانات غير صالحة', () async {
      expect((await errorsFor(slots: const [])).keys, [
        GroupService.fieldSlots,
      ]);
      final e = await errorsFor(
        slots: const [
          GroupSlotInput(weekday: 9, startMinutes: 600, endMinutes: 690),
          GroupSlotInput(weekday: 1, startMinutes: 700, endMinutes: 700),
          GroupSlotInput(weekday: 1, startMinutes: 600, endMinutes: 1500),
        ],
      );
      expect(e.keys, containsAll(['slot:0', 'slot:1', 'slot:2']));
    });

    test('خانتان متداخلتان في نفس اليوم، والمتلاصقتان مسموحتان', () async {
      final overlap = await errorsFor(
        slots: const [
          GroupSlotInput(weekday: saturday, startMinutes: 600, endMinutes: 690),
          GroupSlotInput(weekday: saturday, startMinutes: 660, endMinutes: 750),
        ],
      );
      expect(overlap['slot:1'], contains('تتداخل مع خانة 1'));
      expect(
        await errorsFor(
          slots: const [
            GroupSlotInput(
              weekday: saturday,
              startMinutes: 600,
              endMinutes: 690,
            ),
            GroupSlotInput(
              weekday: saturday,
              startMinutes: 690,
              endMinutes: 780,
            ),
          ],
        ),
        isEmpty,
      );
    });

    test('تعارض القاعة مع مجموعة أخرى', () async {
      await create();
      // أستاذ آخر في القاعة نفسها والوقت نفسه.
      final e = await errorsFor(teacher: 't2', slots: const [slotSat]);
      expect(e['slot:0'], contains('القاعة محجوزة'));
      // قاعة أخرى: لا تعارض.
      expect(
        await errorsFor(teacher: 't2', room: 'r2', slots: const [slotSat]),
        isEmpty,
      );
    });

    test('تعارض الأستاذ مع مجموعته الأخرى', () async {
      await create();
      final e = await errorsFor(room: 'r2', slots: const [slotSat]);
      expect(e['slot:0'], contains('الأستاذ'));
    });

    test('الإنشاء بتعارض يرمي ولا يكتب شيئاً', () async {
      await create();
      await expectLater(
        create(teacher: 't2', slots: const [slotSat]),
        throwsA(isA<ValidationException>()),
      );
      expect(await env.db.select(env.db.groups).get(), hasLength(1));
      expect(await env.db.select(env.db.groupSlots).get(), hasLength(2));
    });
  });

  group('التعديل', () {
    test('الأستاذ والقاعة والمبلغ دون مسّ الحصص إن بقي الجدول', () async {
      final g = await create();
      final before = (await sessions(g.id)).map((s) => s.id).toList();
      expect(
        await service.update(
          g.id,
          teacherId: 't2',
          roomId: 'r2',
          ratePerStudent: 1000,
          slots: const [slotSat, slotTue],
          today: start,
        ),
        isTrue,
      );
      final row = await (env.db.select(
        env.db.groups,
      )..where((x) => x.id.equals(g.id))).getSingle();
      expect(row.teacherId, 't2');
      expect(row.roomId, 'r2');
      expect(row.ratePerStudent, 1000);
      expect((await sessions(g.id)).map((s) => s.id), before);
    });

    test('تغيير الجدول يعيد توليد الحصص القادمة من الجديد', () async {
      final g = await create();
      const newSlot = GroupSlotInput(
        weekday: 3,
        startMinutes: 600,
        endMinutes: 690,
      );
      await service.update(
        g.id,
        teacherId: 't1',
        roomId: 'r1',
        slots: const [newSlot],
        today: start,
      );
      final slots = await service.slotsOf(g.id);
      expect(slots.single.weekday, 3);
      final list = await sessions(g.id);
      expect(list, hasLength(8));
      // كلها أربعاء (3).
      expect(list.map((s) => DateKey.weekday(s.date)).toSet(), {3});
      expect(list.map((s) => s.sessionNumber), [1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test('الحصص المنعقدة أو ذات الحضور تبقى عند تغيير الجدول', () async {
      final g = await create();
      final list = await sessions(g.id);
      // الأولى مغلقة، والثانية فيها حضور.
      await env.db.customStatement(
        "UPDATE sessions SET closed_at = 5 WHERE id = '${list[0].id}'",
      );
      await env.student();
      await env.db
          .into(env.db.attendance)
          .insert(
            AttendanceCompanion.insert(
              id: 'a1',
              createdAt: 1,
              updatedAt: 1,
              sessionId: list[1].id,
              studentId: 's1',
              status: 'present',
              method: 'manual',
            ),
          );
      await service.update(
        g.id,
        teacherId: 't1',
        roomId: 'r1',
        slots: const [
          GroupSlotInput(weekday: 3, startMinutes: 600, endMinutes: 690),
        ],
        today: start,
      );
      final after = await sessions(g.id);
      expect(after.map((s) => s.id), containsAll([list[0].id, list[1].id]));
      expect(after, hasLength(8));
    });

    test('تعارض عند التعديل يُرفض، والمجموعة لا تتعارض مع نفسها', () async {
      final a = await create();
      final b = await create(
        teacher: 't2',
        room: 'r2',
        slots: const [
          GroupSlotInput(weekday: 3, startMinutes: 600, endMinutes: 690),
        ],
      );
      await expectLater(
        service.update(
          b.id,
          teacherId: 't2',
          roomId: 'r1',
          slots: const [slotSat],
          today: start,
        ),
        throwsA(isA<ValidationException>()),
      );
      // إعادة حفظ جدولها نفسه لا تعدّ تعارضاً.
      expect(
        await service.update(
          a.id,
          teacherId: 't1',
          roomId: 'r1',
          slots: const [slotSat, slotTue],
          today: start,
        ),
        isTrue,
      );
    });

    test('مجموعة مجهولة', () async {
      expect(
        await service.update(
          'missing',
          teacherId: 't1',
          slots: const [slotSat],
          today: start,
        ),
        isFalse,
      );
    });
  });

  group('القائمة والأرشفة', () {
    test('تعرض بأسماء المادة والأستاذ والقاعة وعدد التلاميذ والجدول', () async {
      final g = await create();
      await env.student();
      await env.enroll(id: 'e1', groupId: g.id, studentId: 's1');
      final items = await service.watchAll().first;
      final item = items.single;
      expect(item.number, 1);
      expect(item.subjectName, 'رياضيات');
      expect(item.teacherName, 'الأستاذ t1');
      expect(item.roomName, 'القاعة r1');
      expect(item.studentCount, 1);
      expect(item.scheduleText, 'السبت 10:00–11:30، الثلاثاء 16:00–17:30');
    });

    test('الأرشفة تنقلها من النشطة إلى المؤرشفة', () async {
      final g = await create();
      expect(await service.archive(g.id), isTrue);
      expect(await service.archive(g.id), isFalse);
      expect(await service.archive('missing'), isFalse);
      expect(await service.watchAll().first, isEmpty);
      expect((await service.watchAll(archived: true).first).single.id, g.id);
    });

    test('ساعات الأرشفة تحرّر القاعة والأستاذ في كشف التعارض', () async {
      final g = await create();
      await service.archive(g.id);
      // نفس القاعة والأستاذ والوقت متاحة بعد الأرشفة.
      expect(
        await service.validate(
          subjectId: 'sub',
          teacherId: 't1',
          roomId: 'r1',
          sessionsPerCycle: 8,
          ratePerStudent: null,
          slots: const [slotSat],
        ),
        isEmpty,
      );
    });

    test('أسماء الأيام وترتيب العرض', () {
      expect(GroupService.weekdayName(6), 'السبت');
      expect(GroupService.weekdayName(5), 'الجمعة');
      expect(GroupService.displayWeekdays, [6, 7, 1, 2, 3, 4, 5]);
    });
  });
}
