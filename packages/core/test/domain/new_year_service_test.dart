import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late NewYearService service;
  late GroupService groups;
  // «الآن»: 2026-11-14 الساعة 12:00.
  final now = DateTime(2026, 11, 14, 12);

  setUp(() async {
    env = TestEnv();
    groups = GroupService(
      env.db,
      env.writer,
      ScheduleService(env.db),
      CycleService(env.db, env.writer),
    );
    service = NewYearService(env.db, env.writer, groups, now: () => now);
    await env.subject();
    await env.teacher();
    await env.db
        .into(env.db.teacherSubjects)
        .insert(
          TeacherSubjectsCompanion.insert(
            teacherId: 't1',
            subjectId: 'sub',
            updatedAt: 1,
          ),
        );
    await env.group();
    await env.group(id: 'g2', number: 2);
    await env.group(id: 'g3', number: 3);
    await env.student();
    await env.student(id: 's2');
    await env.student(id: 's3');
    await env.enroll(id: 'e1', studentId: 's1');
    await env.enroll(id: 'e2', groupId: 'g2', studentId: 's1');
    await env.enroll(id: 'e3', studentId: 's2');
  });
  tearDown(() => env.close());

  Future<void> session(
    String id,
    String group,
    String date, {
    String status = 'normal',
    bool closed = false,
    int start = 600,
  }) => env.db
      .into(env.db.sessions)
      .insert(
        SessionsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          groupId: group,
          cycleNumber: 1,
          date: date,
          startMinutes: start,
          endMinutes: start + 90,
          status: Value(status),
          closedAt: Value(closed ? 5 : null),
        ),
      );

  group('المعاينة', () {
    test(
      'الأفواج النشطة والتلاميذ المنتسبون (دون تكرار) والحصص القادمة',
      () async {
        await session('past', 'g1', '2026-11-10');
        await session('doneToday', 'g1', '2026-11-14', start: 400);
        await session('later', 'g1', '2026-11-14', start: 840);
        await session('tomorrow', 'g2', '2026-11-15');
        await session('cancelled', 'g2', '2026-11-16', status: 'cancelled');
        await session('closed', 'g2', '2026-11-17', closed: true);
        final preview = await service.preview();
        expect(preview.activeGroups, 3);
        // s1 في مجموعتين وs2 في واحدة؛ s3 غير منتسب.
        expect(preview.enrolledStudents, 2);
        expect(preview.upcomingSessions, 2);
      },
    );

    test('المؤرشفة والمحذوفة ومن غادر لا تُحسب', () async {
      await groups.archive('g3');
      await env.writer.softDelete(env.db.groups, key: {'id': 'g2'});
      await env.db.customStatement(
        "UPDATE group_students SET left_at = 5 WHERE id = 'e3'",
      );
      final preview = await service.preview();
      expect(preview.activeGroups, 1);
      expect(preview.enrolledStudents, 1);
    });

    test('بلا أفواج: أصفار', () async {
      final empty = TestEnv();
      addTearDown(empty.close);
      final s = NewYearService(
        empty.db,
        empty.writer,
        GroupService(
          empty.db,
          empty.writer,
          ScheduleService(empty.db),
          CycleService(empty.db, empty.writer),
        ),
        now: () => now,
      );
      final preview = await s.preview();
      expect(preview.activeGroups, 0);
      expect(preview.enrolledStudents, 0);
      expect(preview.upcomingSessions, 0);
    });
  });

  group('التنفيذ', () {
    test('عبارة التأكيد شرط، وبدونها لا يُكتب شيء', () async {
      for (final wrong in ['', 'سنة', 'نعم', 'سنة  جديدة']) {
        await expectLater(
          service.start(confirmation: wrong),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.errors[NewYearService.fieldConfirm],
              'confirm',
              contains('سنة جديدة'),
            ),
          ),
        );
      }
      final active = await (env.db.select(
        env.db.groups,
      )..where((g) => g.archivedAt.isNull())).get();
      expect(active, hasLength(3));
      expect(await service.lastStartedAt(), isNull);
    });

    test('يؤرشف كل الأفواج النشطة ويعيد الأعداد', () async {
      env.time = 5000;
      final result = await service.start(confirmation: ' سنة جديدة ');
      expect(result.archivedGroups, 3);
      expect(result.retainedStudents, 2);
      // ساعة الاختبار تتقدم مع كل كتابة، فكل المجموعات بعد الوقت المحدد.
      expect(result.at, greaterThanOrEqualTo(5000));
      final rows = await env.db.select(env.db.groups).get();
      expect(
        rows.every((g) => g.archivedAt != null && g.archivedAt! >= 5000),
        isTrue,
      );
      expect((await groups.watchAll().first), isEmpty);
      expect((await groups.watchAll(archived: true).first), hasLength(3));
    });

    test(
      'التلاميذ وانتسابهم وحضورهم ومدفوعاتهم وخلاص الأستاذ تبقى كما هي',
      () async {
        await session('a', 'g1', '2026-11-10');
        await env.db
            .into(env.db.attendance)
            .insert(
              AttendanceCompanion.insert(
                id: 'at1',
                createdAt: 1,
                updatedAt: 1,
                sessionId: 'a',
                studentId: 's1',
                status: 'present',
                method: 'manual',
              ),
            );
        await env.db.customStatement(
          'INSERT INTO payments (id, created_at, updated_at, student_id, type, '
          'group_id, cycle_number, amount, received_by, receipt_number) VALUES '
          "('p1', 1, 1, 's1', 'month', 'g1', 1, 2000, 'u1', 'AAA-000001')",
        );
        final before = {
          'students': await env.db.select(env.db.students).get(),
          'enrol': await env.db.select(env.db.groupStudents).get(),
          'attendance': await env.db.select(env.db.attendance).get(),
          'payments': await env.db.select(env.db.payments).get(),
          'sessions': await env.db.select(env.db.sessions).get(),
        };
        await service.start(confirmation: NewYearService.confirmPhrase);
        expect(await env.db.select(env.db.students).get(), before['students']);
        expect(
          await env.db.select(env.db.groupStudents).get(),
          before['enrol'],
        );
        expect(
          await env.db.select(env.db.attendance).get(),
          before['attendance'],
        );
        expect(await env.db.select(env.db.payments).get(), before['payments']);
        expect(await env.db.select(env.db.sessions).get(), before['sessions']);
      },
    );

    test('المؤرشفة سلفاً لا يتغير وقت أرشفتها', () async {
      env.time = 2000;
      await groups.archive('g3');
      env.time = 9000;
      final result = await service.start(confirmation: 'سنة جديدة');
      expect(result.archivedGroups, 2);
      final g3 = await (env.db.select(
        env.db.groups,
      )..where((g) => g.id.equals('g3'))).getSingle();
      expect(g3.archivedAt, lessThan(9000));
    });

    test(
      'الكتابة عبر SyncWriter: سجل عمليات وطابور مزامنة ووقت آخر تنفيذ',
      () async {
        env.time = 7000;
        await service.start(confirmation: 'سنة جديدة');
        expect(await service.lastStartedAt(), greaterThanOrEqualTo(7000));
        final outbox = await env.db.select(env.db.outbox).get();
        expect(outbox.where((o) => o.targetTable == 'groups'), hasLength(3));
        expect(outbox.where((o) => o.targetTable == 'settings'), hasLength(1));
        final audit = await env.db.select(env.db.auditLog).get();
        expect(audit.where((a) => a.entity == 'groups'), hasLength(3));
      },
    );

    test('بلا أفواج نشطة: لا أرشفة لكن يُسجَّل التنفيذ', () async {
      await service.start(confirmation: 'سنة جديدة');
      env.time = 8000;
      final again = await service.start(confirmation: 'سنة جديدة');
      expect(again.archivedGroups, 0);
      expect(again.retainedStudents, 0);
      expect(await service.lastStartedAt(), greaterThanOrEqualTo(8000));
    });

    test('فوج جديد بعدها تأخذ رقماً بعد القديمة وتبقى نشطة', () async {
      await service.start(confirmation: 'سنة جديدة');
      final created = await groups.create(
        subjectId: 'sub',
        teacherId: 't1',
        slots: [
          const GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690),
        ],
        startDate: '2026-12-05',
      );
      expect(created.number, 4);
      expect((await groups.watchAll().first).single.id, created.id);
    });
  });
}
