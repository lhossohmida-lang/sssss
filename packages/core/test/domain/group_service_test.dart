import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

var _created = 0;

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
    test('فوج بجدولها وحصص دورتها الأولى مرقّمة', () async {
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

    test('أرقام الأفواج متسلسلة', () async {
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

    test('قاعة الخانة تتقدم على قاعة الفوج', () async {
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

    test('إنشاء فوج يخبر أولياء منتظري المادة بموعدها', () async {
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

    test('تعارض القاعة مع فوج آخر', () async {
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

    test('تعارض الأستاذ مع فوجه الأخرى', () async {
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

    test('تعارض عند التعديل يُرفض، والفوج لا تتعارض مع نفسها', () async {
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

    test('فوج مجهولة', () async {
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

  group('الحذف', () {
    Future<int> live(String table, String groupId) async {
      final row = await env.db
          .customSelect(
            'SELECT COUNT(*) AS c FROM $table '
            'WHERE group_id = ? AND deleted_at IS NULL',
            variables: [Variable<String>(groupId)],
          )
          .getSingle();
      return row.read<int>('c');
    }

    test(
      'يحذف فوجاً لم يبدأ مع جدوله وحصصه وانتساب تلاميذه ويبقى التلميذ',
      () async {
        final g = await create();
        await env.student();
        await env.enroll(id: 'e1', groupId: g.id, studentId: 's1');
        expect(await live('sessions', g.id), 8);

        expect(await service.delete(g.id), isTrue);

        expect(await service.watchAll().first, isEmpty);
        expect(await service.slotsOf(g.id), isEmpty);
        expect(await live('group_slots', g.id), 0);
        expect(await live('sessions', g.id), 0);
        expect(await live('group_students', g.id), 0);
        final students = await (env.db.select(
          env.db.students,
        )..where((s) => s.deletedAt.isNull())).get();
        expect(students.map((s) => s.id), ['s1']);
        final row = await (env.db.select(
          env.db.groups,
        )..where((x) => x.id.equals(g.id))).getSingle();
        expect(row.deletedAt, isNotNull);
      },
    );

    test('فوج غير موجود أو محذوف سلفاً', () async {
      final g = await create();
      expect(await service.delete('missing'), isFalse);
      expect(await service.delete(g.id), isTrue);
      expect(await service.delete(g.id), isFalse);
    });

    test('بعد الحذف تتحرر القاعة والأستاذ والوقت لفوج جديد', () async {
      final g = await create();
      await service.delete(g.id);
      final again = await create();
      expect(again.id, isNot(g.id));
      expect(await live('sessions', again.id), 8);
    });

    test('لا يُحذف فوج له مدفوعات بل يُؤرشف', () async {
      final g = await create();
      await env.student();
      await env.db
          .into(env.db.payments)
          .insert(
            PaymentsCompanion.insert(
              id: 'p1',
              createdAt: 1,
              updatedAt: 1,
              studentId: 's1',
              type: 'month',
              amount: 2000,
              receivedBy: 'u1',
              receiptNumber: 'A-000001',
              groupId: Value(g.id),
            ),
          );
      await expectLater(
        service.delete(g.id),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.toString(),
            'الرسالة',
            allOf(contains('مدفوعات'), contains('أرشفه')),
          ),
        ),
      );
      expect(await live('sessions', g.id), 8, reason: 'لا شيء حُذف');
      expect((await service.watchAll().first).single.id, g.id);
    });

    test('لا يُحذف فوج انعقدت حصة منه ولا فوج فيه حضور', () async {
      final g = await create();
      await env.student();
      final first = (await sessions(g.id)).first;
      await cycles.closeSession(first.id);
      await expectLater(
        service.delete(g.id),
        throwsA(isA<ValidationException>()),
      );

      final other = await create(
        teacher: 't2',
        slots: const [slotTue],
        room: 'r2',
      );
      final marked = (await sessions(other.id)).first;
      await env.db
          .into(env.db.attendance)
          .insert(
            AttendanceCompanion.insert(
              id: 'a1',
              createdAt: 1,
              updatedAt: 1,
              sessionId: marked.id,
              studentId: 's1',
              status: 'present',
              method: 'manual',
            ),
          );
      await expectLater(
        service.delete(other.id),
        throwsA(isA<ValidationException>()),
      );
      expect(await live('sessions', other.id), 8);
    });

    test('لا يُحذف فوج له خلاص أستاذ أو رصيد أو نتيجة', () async {
      final g = await create();
      await env.student();
      Future<void> expectBlocked(String reason) async {
        await expectLater(
          service.delete(g.id),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.toString(),
              'الرسالة',
              contains(reason),
            ),
          ),
          reason: reason,
        );
      }

      await env.db
          .into(env.db.teacherPayouts)
          .insert(
            TeacherPayoutsCompanion.insert(
              id: 'po1',
              createdAt: 1,
              updatedAt: 1,
              teacherId: 't1',
              groupId: g.id,
              cycleNumber: 1,
              amount: 1000,
            ),
          );
      await expectBlocked('خلاص أساتذة');
      await env.db.customStatement('UPDATE teacher_payouts SET deleted_at = 5');

      await env.db
          .into(env.db.studentCredits)
          .insert(
            StudentCreditsCompanion.insert(
              id: 'c1',
              createdAt: 1,
              updatedAt: 1,
              studentId: 's1',
              groupId: g.id,
              amount: 500,
              reason: 'manual',
              sourceCycleNumber: 1,
              targetCycleNumber: 2,
            ),
          );
      await expectBlocked('أرصدة');
      await env.db.customStatement('UPDATE student_credits SET deleted_at = 5');

      await env.db
          .into(env.db.grades)
          .insert(
            GradesCompanion.insert(
              id: 'gr1',
              createdAt: 1,
              updatedAt: 1,
              studentId: 's1',
              groupId: g.id,
              title: 'اختبار',
              score: 15,
              date: '2026-11-10',
            ),
          );
      await expectBlocked('نتائج');
      await env.db.customStatement('UPDATE grades SET deleted_at = 5');

      // بزوال المانع كلها يجوز الحذف.
      expect(await service.delete(g.id), isTrue);
    });
  });

  group('الترقيم لكل مادة وسنة', () {
    Future<void> level(String id, String name, int order) => env.db
        .into(env.db.levels)
        .insert(
          LevelsCompanion.insert(
            id: id,
            createdAt: 1,
            updatedAt: 1,
            name: name,
            stage: EducationStage.secondary.code,
            sortOrder: order,
          ),
        );

    Future<void> subject(String id, String name, {String? levelId}) => env.db
        .into(env.db.subjects)
        .insert(
          SubjectsCompanion.insert(
            id: id,
            createdAt: 1,
            updatedAt: 1,
            name: name,
            monthlyPrice: const Value(2000),
            levelId: Value(levelId),
          ),
        );

    Future<GroupRow> createFor(String subjectId, {String slotDay = 'sat'}) =>
        service.create(
          subjectId: subjectId,
          teacherId: 't1',
          roomId: null,
          // خانة بوقت فريد لكل فوج حتى لا يتعارض الأستاذ مع نفسه.
          slots: [
            GroupSlotInput(
              weekday: saturday,
              startMinutes: 600 + 120 * _created++,
              endMinutes: 690 + 120 * (_created - 1),
            ),
          ],
          startDate: start,
        );

    setUp(() async {
      _created = 0;
      await level('l3', '3 ثانوي', 3);
      await level('l2', '2 ثانوي', 2);
      await subject('math3', 'رياضيات', levelId: 'l3');
      await subject('math2', 'رياضيات', levelId: 'l2');
      await subject('phys3', 'فيزياء', levelId: 'l3');
      for (final id in ['math3', 'math2', 'phys3']) {
        await env.db
            .into(env.db.teacherSubjects)
            .insert(
              TeacherSubjectsCompanion.insert(
                teacherId: 't1',
                subjectId: id,
                updatedAt: 1,
              ),
            );
      }
    });

    test('كل مادة وسنة تبدأ من فوج 1 وتتابع بعدها', () async {
      expect((await createFor('math3')).number, 1);
      expect((await createFor('math3')).number, 2);
      expect((await createFor('math2')).number, 1, reason: 'سنة أخرى');
      expect((await createFor('phys3')).number, 1, reason: 'مادة أخرى');
      expect((await createFor('math3')).number, 3);
    });

    test('مادتان باسم واحد وسنة واحدة مقطع واحد', () async {
      await subject('math3b', 'رياضيات ', levelId: 'l3');
      await env.db
          .into(env.db.teacherSubjects)
          .insert(
            TeacherSubjectsCompanion.insert(
              teacherId: 't1',
              subjectId: 'math3b',
              updatedAt: 1,
            ),
          );
      expect((await createFor('math3')).number, 1);
      expect((await createFor('math3b')).number, 2);
    });

    test('المؤرشف يُحسب فلا يتكرر رقمه، والمحذوف لا يُحسب', () async {
      final first = await createFor('math3');
      await createFor('math3');
      await service.archive(first.id);
      final third = await createFor('math3');
      expect(third.number, 3, reason: 'المؤرشف 1 يُحسب مع 2');
      expect(await service.delete(third.id), isTrue);
      expect(
        (await createFor('math3')).number,
        3,
        reason: 'الفوج 3 حُذف فيُعاد رقمه',
      );
    });

    test('الأفواج تحمل مستواها: الوسم بالسنة ومفتاح المقطع', () async {
      await createFor('math3');
      await createFor('math2');
      final items = await service.watchAll().first;
      final math3 = items.singleWhere((i) => i.levelId == 'l3');
      expect(math3.subjectName, 'رياضيات (3 ثانوي)');
      expect(math3.baseSubjectName, 'رياضيات');
      expect(math3.levelName, '3 ثانوي');
      final math2 = items.singleWhere((i) => i.levelId == 'l2');
      expect(math2.scope, isNot(math3.scope));
      expect(math2.scope, GroupService.scopeKey(' رياضيات', 'l2'));
    });

    test('مادة عامة بلا سنة: اسمها كما هو ومقطعها بلا مستوى', () async {
      final general = await service.create(
        subjectId: 'sub',
        teacherId: 't1',
        roomId: null,
        slots: const [slotTue],
        startDate: start,
      );
      expect(general.number, 1);
      final item = (await service.watchAll().first).single;
      expect(item.subjectName, 'رياضيات');
      expect(item.levelId, isNull);
      expect(item.levelName, isNull);
    });

    GroupsCompanion raw(String id, int number, String subjectId, int created) =>
        GroupsCompanion.insert(
          id: id,
          createdAt: created,
          updatedAt: created,
          number: number,
          subjectId: subjectId,
          teacherId: 't1',
        );

    test('إعادة الترقيم: كل مقطع من 1 بترتيب رقمه الحالي', () async {
      final db = env.db;
      // ترقيم عالمي قديم: رياضيات 3: 1،5،9؛ رياضيات 2: 2،7؛ فيزياء 3: 3.
      for (final (id, number, subject) in [
        ('a', 1, 'math3'),
        ('b', 2, 'math2'),
        ('c', 3, 'phys3'),
        ('d', 5, 'math3'),
        ('e', 7, 'math2'),
        ('f', 9, 'math3'),
      ]) {
        await db.into(db.groups).insert(raw(id, number, subject, number));
      }
      expect(await service.normalizeNumbers(), 5);
      Future<List<int>> numbers(String subject) async => [
        for (final g
            in await (db.select(db.groups)
                  ..where((g) => g.subjectId.equals(subject))
                  ..orderBy([(g) => OrderingTerm(expression: g.createdAt)]))
                .get())
          g.number,
      ];
      expect(await numbers('math3'), [1, 2, 3]);
      expect(await numbers('math2'), [1, 2]);
      expect(await numbers('phys3'), [1]);
      expect(await service.normalizeNumbers(), 0, reason: 'لا تغيير ثانية');
    });

    test(
      'رقم مكرر يُفضّ بترتيب الإنشاء، والفجوة تُسدّ، والمحذوف خارجها',
      () async {
        final db = env.db;
        await db.into(db.groups).insert(raw('x1', 3, 'math3', 10));
        await db.into(db.groups).insert(raw('x2', 3, 'math3', 20));
        await db.into(db.groups).insert(raw('x3', 3, 'math3', 30));
        await db.into(db.groups).insert(raw('gone', 1, 'math3', 5));
        await db.customStatement(
          "UPDATE groups SET deleted_at = 9 WHERE id = 'gone'",
        );
        expect(await service.normalizeNumbers(), 2);
        final rows = await (db.select(
          db.groups,
        )..where((g) => g.deletedAt.isNull())).get();
        expect(
          {for (final g in rows) g.id: g.number},
          {'x1': 1, 'x2': 2, 'x3': 3},
        );
      },
    );

    test('إعادة الترقيم تدخل طابور المزامنة', () async {
      final db = env.db;
      await db.into(db.groups).insert(raw('p', 4, 'math3', 1));
      await db.delete(db.outbox).go();
      await service.normalizeNumbers();
      final pending = await (db.select(
        db.outbox,
      )..where((o) => o.targetTable.equals('groups'))).get();
      expect(pending, hasLength(1));
    });
  });
}
