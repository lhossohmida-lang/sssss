import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late CycleService cycles;
  late GroupService groups;
  late DuesService dues;
  late EnrolmentService enrolments;
  late AttendanceService attendance;
  late WaitingGroupService waiting;

  // 2026-11-07 سبت.
  const saturday = GroupSlotInput(
    weekday: 6,
    startMinutes: 600,
    endMinutes: 690,
  );

  setUp(() async {
    env = TestEnv();
    cycles = CycleService(env.db, env.writer);
    groups = GroupService(env.db, env.writer, ScheduleService(env.db), cycles);
    dues = DuesService(env.db, env.writer);
    enrolments = EnrolmentService(env.db, env.writer, dues, cycles);
    attendance = AttendanceService(env.db, env.writer, cycles, dues);
    waiting = WaitingGroupService(env.db, env.writer);
    await env.subject();
    await env.teacher(rate: 1200);
    await env.room();
    await env.db
        .into(env.db.teacherSubjects)
        .insert(
          TeacherSubjectsCompanion.insert(
            teacherId: 't1',
            subjectId: 'sub',
            updatedAt: 1,
          ),
        );
    for (final id in ['s1', 's2', 's3', 's4']) {
      await env.student(id: id);
    }
    // حساب صاحب المدرسة: رقم دخوله هو هاتف المدير الذي تصله رسائل النظام.
    await env.db
        .into(env.db.userAccounts)
        .insert(
          UserAccountsCompanion.insert(
            id: 'owner',
            createdAt: 1,
            updatedAt: 1,
            email: '0555123456@school.local',
            role: 'owner',
          ),
        );
  });
  tearDown(() => env.close());

  Future<GroupRow> waitingGroup({int target = 3}) => groups.createWaiting(
    subjectId: 'sub',
    teacherId: 't1',
    monthlyPrice: 2500,
    ratePerStudent: 1200,
    waitingTarget: target,
  );

  group('الأفواج المنتظِرة', () {
    test('تُنشأ بلا جدول ولا حصص، بعدد مطلوب وسعر ونصيب', () async {
      final g = await waitingGroup();
      expect(g.waitingTarget, 3);
      expect(g.monthlyPrice, 2500);
      expect(g.ratePerStudent, 1200);
      expect(g.isReview, isFalse);
      expect(await groups.slotsOf(g.id), isEmpty);
      expect(await env.db.select(env.db.sessions).get(), isEmpty);
      final items = await waiting.list();
      expect(items.single.target, 3);
      expect(items.single.studentCount, 0);
      expect(items.single.isReady, isFalse);
      expect(items.single.missing, 3);
    });

    test('العدد المطلوب من 1 إلى 500', () async {
      for (final bad in [0, -2, 501]) {
        await expectLater(
          waitingGroup(target: bad),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.errors.keys,
              'حقول',
              contains(GroupService.fieldWaitingTarget),
            ),
          ),
        );
      }
      expect(await env.db.select(env.db.groups).get(), isEmpty);
    });

    test(
      'عند بلوغ العدد: إشعار للمدير ورسالة إلى هاتفه مرة واحدة فقط',
      () async {
        final g = await waitingGroup();
        await enrolments.enrol(studentId: 's1', groupId: g.id);
        await enrolments.enrol(studentId: 's2', groupId: g.id);
        expect(await env.db.select(env.db.notifications).get(), isEmpty);
        expect(await env.db.select(env.db.smsQueue).get(), isEmpty);

        await enrolments.enrol(studentId: 's3', groupId: g.id);
        final notes = await env.db.select(env.db.notifications).get();
        expect(notes, hasLength(1));
        expect(notes.single.kind, WaitingGroupService.notifyReady);
        expect(notes.single.userId, 'owner');
        expect(notes.single.entityId, g.id);
        expect(notes.single.body, contains('3 من 3'));
        final sms = await env.db.select(env.db.smsQueue).get();
        expect(sms, hasLength(1));
        expect(sms.single.kind, SmsTemplateKeys.groupReady);
        expect(sms.single.phone, PhoneNumbers.toInternational('0555123456'));
        expect(sms.single.message, contains('اكتمل'));
        expect(sms.single.message, contains('تاريخ أول حصة'));

        // تلميذ رابع بعد التنبيه لا ينبّه من جديد.
        await enrolments.enrol(studentId: 's4', groupId: g.id);
        expect(await env.db.select(env.db.notifications).get(), hasLength(1));
        expect(await env.db.select(env.db.smsQueue).get(), hasLength(1));
        expect((await waiting.list()).single.isReady, isTrue);
        final row = await (env.db.select(
          env.db.groups,
        )..where((x) => x.id.equals(g.id))).getSingle();
        expect(row.startAlertedAt, isNotNull);
      },
    );

    test('إيقاف نوع الرسالة يُبقي الإشعار ويمنع الرسالة', () async {
      await SmsKindPolicy(
        env.db,
        env.writer,
      ).setEnabled(SmsTemplateKeys.groupReady, enabled: false);
      final g = await waitingGroup(target: 1);
      await enrolments.enrol(studentId: 's1', groupId: g.id);
      expect(await env.db.select(env.db.notifications).get(), hasLength(1));
      expect(await env.db.select(env.db.smsQueue).get(), isEmpty);
    });

    test('فوج عادي لا يُنبَّه، ولا فوج بدأ', () async {
      await env.group(id: 'normal', rate: 1000, price: 2000);
      await enrolments.enrol(studentId: 's1', groupId: 'normal');
      expect(await env.db.select(env.db.notifications).get(), isEmpty);
    });

    test(
      'تحديد تاريخ أول حصة: يحفظ الجدول ويولّد الحصص ويخبر الأولياء',
      () async {
        final g = await waitingGroup(target: 2);
        await enrolments.enrol(studentId: 's1', groupId: g.id);
        await enrolments.enrol(studentId: 's2', groupId: g.id);
        await env.db.delete(env.db.smsQueue).go();

        final started = await groups.startWaiting(
          g.id,
          slots: const [saturday],
          startDate: '2026-11-07',
          today: '2026-11-05',
        );
        expect(started, isTrue);
        final sessions = await (env.db.select(
          env.db.sessions,
        )..orderBy([(s) => OrderingTerm.asc(s.date)])).get();
        expect(sessions, hasLength(8));
        expect(sessions.first.date, '2026-11-07');
        expect((await groups.slotsOf(g.id)), hasLength(1));
        // بدأ الفوج فلم يعد منتظِراً.
        expect(await waiting.list(), isEmpty);
        // الوليّ نفسه لتلميذين: رسالة واحدة بالموعد.
        final sms = await env.db.select(env.db.smsQueue).get();
        expect(sms, hasLength(1));
        expect(sms.single.kind, SmsTemplateKeys.groupStarted);
        expect(sms.single.message, contains('2026-11-07'));
        expect(sms.single.message, contains('السبت'));
      },
    );

    test('لا يبدأ فوج بدأ، ولا في الماضي، ولا بجدول متعارض', () async {
      final g = await waitingGroup();
      await expectLater(
        groups.startWaiting(
          g.id,
          slots: const [saturday],
          startDate: '2026-11-01',
          today: '2026-11-05',
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys,
            'حقول',
            contains(GroupService.fieldFirstDate),
          ),
        ),
      );
      await expectLater(
        groups.startWaiting(
          g.id,
          slots: const [],
          startDate: '2026-11-07',
          today: '2026-11-05',
        ),
        throwsA(isA<ValidationException>()),
      );
      await groups.startWaiting(
        g.id,
        slots: const [saturday],
        startDate: '2026-11-07',
        today: '2026-11-05',
      );
      await expectLater(
        groups.startWaiting(
          g.id,
          slots: const [saturday],
          startDate: '2026-11-14',
          today: '2026-11-05',
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys,
            'حقول',
            contains(GroupService.fieldGroup),
          ),
        ),
      );
      // فوج عادي ليس منتظِراً.
      await env.group(id: 'normal', rate: 1000, price: 2000);
      expect(
        await groups.startWaiting(
          'normal',
          slots: const [saturday],
          startDate: '2026-11-07',
          today: '2026-11-05',
        ),
        isFalse,
      );
    });

    test('تعديل فوج منتظِر بلا جدول لا يبدأه', () async {
      final g = await waitingGroup();
      final ok = await groups.update(
        g.id,
        teacherId: 't1',
        roomId: 'r1',
        slots: const [],
        today: '2026-11-05',
        requireSlots: false,
      );
      expect(ok, isTrue);
      expect(await env.db.select(env.db.sessions).get(), isEmpty);
      expect((await waiting.list()).single.group.roomId, 'r1');
    });

    test('اللوحة تعدّ المنتظِرة والمكتملة', () async {
      final g = await waitingGroup(target: 1);
      await waitingGroup(target: 5);
      await enrolments.enrol(studentId: 's1', groupId: g.id);
      final stats = await DashboardQueries(
        env.db,
        env.writer,
      ).load(now: DateTime(2026, 11, 14, 10));
      expect(stats.waitingGroups, 2);
      expect(stats.waitingGroupsReady, 1);
    });
  });

  group('حصة المراجعة', () {
    Future<GroupRow> review({String date = '2026-11-20'}) =>
        groups.createReview(
          subjectId: 'sub',
          teacherId: 't1',
          roomId: 'r1',
          date: date,
          startMinutes: 600,
          endMinutes: 780,
          fee: 500,
          teacherAmount: 300,
          today: '2026-11-14',
        );

    test('فوج من حصة واحدة بثمن ونصيب، بلا جدول أسبوعي', () async {
      final r = await review();
      expect(r.isReview, isTrue);
      expect(r.sessionsPerCycle, 1);
      expect(r.monthlyPrice, 500);
      expect(r.ratePerStudent, 300);
      expect(await groups.slotsOf(r.id), isEmpty);
      final sessions = await env.db.select(env.db.sessions).get();
      expect(sessions, hasLength(1));
      expect(sessions.single.date, '2026-11-20');
      expect(sessions.single.startMinutes, 600);
      expect(sessions.single.endMinutes, 780);
      expect(await groups.firstSessionId(r.id), sessions.single.id);
    });

    test('تاريخ في الماضي وثمن غير صالح يُرفضان برسالتيهما', () async {
      await expectLater(
        review(date: '2026-11-01'),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys,
            'حقول',
            contains(GroupService.fieldDate),
          ),
        ),
      );
      await expectLater(
        groups.createReview(
          subjectId: 'sub',
          teacherId: 't1',
          date: '2026-11-20',
          startMinutes: 600,
          endMinutes: 780,
          fee: 0,
          teacherAmount: 300,
          today: '2026-11-14',
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors[GroupService.fieldPrice],
            'ثمن',
            'أدخل ثمن الحصة',
          ),
        ),
      );
    });

    test('تُؤرشف بعد انتهاء حصتها فلا تبقى بين الأفواج النشطة', () async {
      final r = await review();
      await attendance.closeDueSessions(DateTime(2026, 11, 20, 14));
      final row = await (env.db.select(
        env.db.groups,
      )..where((g) => g.id.equals(r.id))).getSingle();
      expect(row.archivedAt, isNotNull);
      expect(await groups.watchAll().first, isEmpty);
    });
  });

  group('الأفواج لا تتداخل بعد التغيير', () {
    test('فوج منتظِر وفوج عادي في المادة نفسها يُرقَّمان تباعاً', () async {
      final a = await waitingGroup();
      final b = await groups.create(
        subjectId: 'sub',
        teacherId: 't1',
        monthlyPrice: 2000,
        ratePerStudent: 1000,
        slots: const [saturday],
        startDate: '2026-11-07',
      );
      expect([a.number, b.number], [1, 2]);
    });
  });
}
