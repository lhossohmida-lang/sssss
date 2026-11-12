import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late DuesService dues;
  late StudentService service;

  const month = '2026-11';

  setUp(() async {
    env = TestEnv();
    dues = DuesService(env.db, env.writer);
    service = StudentService(env.db, env.writer, dues);
    await env.subject();
    await env.subject(id: 'sub2', price: 2500);
    await env.teacher();
    await env.group();
    await env.group(id: 'g2', subjectId: 'sub2');
    await env.db.customStatement(
      "UPDATE groups SET number = 2 WHERE id = 'g2'",
    );
    await env.student();
  });
  tearDown(() => env.close());

  Future<void> session(String id, {String groupId = 'g1'}) => env.db
      .into(env.db.sessions)
      .insert(
        SessionsCompanion.insert(
          id: id,
          createdAt: 1,
          updatedAt: 1,
          groupId: groupId,
          cycleNumber: 1,
          sessionNumber: const Value(1),
          date: '2026-11-0${id.codeUnitAt(id.length - 1) % 9 + 1}',
          startMinutes: 600 + id.hashCode % 50,
          endMinutes: 690,
        ),
      );

  Future<void> attend(String sessionId, String status) => env.db
      .into(env.db.attendance)
      .insert(
        AttendanceCompanion.insert(
          id: 'a-$sessionId',
          createdAt: 1,
          updatedAt: 1,
          sessionId: sessionId,
          studentId: 's1',
          status: status,
          method: 'manual',
        ),
      );

  Future<StudentProfile?> load() => service.load('s1', month: month);

  group('الملف', () {
    test('تلميذ بلا مجموعات ولا مستحقات', () async {
      final p = (await load())!;
      expect(p.fullName, 'تلميذ s1');
      expect(p.levelName, isNull);
      expect(p.parent, isNull);
      expect(p.enrolments, isEmpty);
      expect(p.waiting, isEmpty);
      expect(p.totalRemaining, 0);
    });

    test('تلميذ مجهول أو محذوف: null', () async {
      expect(await service.load('missing', month: month), isNull);
      await service.remove('s1');
      expect(await load(), isNull);
    });

    test('المجموعات بأسمائها وحضورها ومستحقاتها', () async {
      await env.enroll(id: 'e1', studentId: 's1', price: 2000);
      await env.enroll(
        id: 'e2',
        groupId: 'g2',
        studentId: 's1',
        price: 2500,
        discountType: 'percent',
        discountValue: 20,
      );
      for (final id in ['x1', 'x2', 'x3', 'x4']) {
        await session(id);
      }
      await attend('x1', 'present');
      await attend('x2', 'present');
      await attend('x3', 'absent');
      await attend('x4', 'excused');

      final p = (await load())!;
      expect(p.enrolments, hasLength(2));
      final first = p.enrolments.first;
      expect(first.subjectName, 'رياضيات');
      expect(first.groupNumber, 1);
      expect(first.teacherName, 'الأستاذ t1');
      expect(first.present, 2);
      expect(first.absent, 1);
      expect(first.excused, 1);
      expect(first.netPrice, 2000);
      expect(first.remaining, 2000);
      final second = p.enrolments.last;
      expect(second.groupNumber, 2);
      expect(second.netPrice, 2000);
      expect(second.present, 0);
      expect(p.cyclesRemaining, 4000);
    });

    test('الدفع ينقص الباقي', () async {
      await env.enroll(id: 'e1', studentId: 's1', price: 2000);
      await dues.recordMonthPayment(
        studentId: 's1',
        groupId: 'g1',
        cycleNumber: 1,
        amount: 1500,
        receivedBy: 'u1',
        receiptNumber: 'A-000001',
      );
      expect((await load())!.enrolments.single.remaining, 500);
    });

    test('حقوق التسجيل والنقل في المجموع', () async {
      await dues.ensureRegistrationFee(
        studentId: 's1',
        periodKey: '2026-2027',
        amount: 1500,
      );
      await dues.ensureRegistrationFee(
        studentId: 's1',
        periodKey: '2025-2026',
        amount: 1000,
      );
      await dues.payRegistrationFee(
        studentId: 's1',
        periodKey: '2025-2026',
        amount: 1000,
        receivedBy: 'u1',
        receiptNumber: 'A-000002',
      );
      await service.update(
        's1',
        firstName: 'تلميذ',
        lastName: 's1',
        levelId: null,
        usesTransport: true,
        transportPrice: 1200,
      );
      final p = (await load())!;
      expect(p.registrationFeeRemaining, 1500);
      expect(p.transportRemaining, 1200);
      expect(p.totalRemaining, 2700);
    });

    test('من غادر المجموعة لا تظهر في ملفه', () async {
      await env.enroll(id: 'e1', studentId: 's1');
      expect(await service.leaveGroup('s1', 'g1'), isTrue);
      expect(await service.leaveGroup('s1', 'g1'), isFalse);
      expect((await load())!.enrolments, isEmpty);
      final row = await env.db.select(env.db.groupStudents).getSingle();
      expect(row.leftAt, isNotNull);
      expect(row.deletedAt, isNull);
    });

    test('قوائم الانتظار وإزالتها', () async {
      final enrolments = EnrolmentService(
        env.db,
        env.writer,
        dues,
        CycleService(env.db, env.writer),
      );
      await enrolments.addToWaiting(studentId: 's1', subjectId: 'sub2');
      final p = (await load())!;
      expect(p.waiting.single.subjectName, 'رياضيات');
      expect(await service.leaveWaiting(p.waiting.single.entryId), isTrue);
      expect((await load())!.waiting, isEmpty);
    });

    test('المستوى والوليّ', () async {
      await env.db
          .into(env.db.levels)
          .insert(
            LevelsCompanion.insert(
              id: 'lv',
              createdAt: 1,
              updatedAt: 1,
              name: '3 متوسط',
              stage: 'middle',
              sortOrder: 203,
            ),
          );
      await env.db
          .into(env.db.parents)
          .insert(
            ParentsCompanion.insert(
              id: 'p1',
              createdAt: 1,
              updatedAt: 1,
              phone: '0550123456',
              email: '0550123456@school.local',
              name: const Value('علي'),
            ),
          );
      await env.db.customStatement(
        "UPDATE students SET level_id = 'lv', parent_account_id = 'p1' "
        "WHERE id = 's1'",
      );
      final p = (await load())!;
      expect(p.levelName, '3 متوسط');
      expect(p.parent?.name, 'علي');
    });

    test('watch يتحدث مع التغييرات', () async {
      final seen = <int>[];
      final sub = service
          .watch('s1', month: month)
          .listen((p) => seen.add(p?.enrolments.length ?? -1));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await env.enroll(id: 'e1', studentId: 's1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await service.remove('s1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();
      expect(seen.first, 0);
      expect(seen, contains(1));
      expect(seen.last, -1);
    });
  });

  group('التعديل', () {
    test('يغيّر الاسم والمستوى والنقل', () async {
      expect(
        await service.update(
          's1',
          firstName: ' أحمد ',
          lastName: ' علي ',
          levelId: null,
          usesTransport: true,
          transportPrice: 1200,
        ),
        isTrue,
      );
      final s = (await load())!.student;
      expect(s.firstName, 'أحمد');
      expect(s.lastName, 'علي');
      expect(s.usesTransport, isTrue);
      expect(s.transportPrice, 1200);
      await service.update(
        's1',
        firstName: 'أحمد',
        lastName: 'علي',
        levelId: null,
        usesTransport: false,
        transportPrice: 900,
      );
      final off = (await load())!.student;
      expect(off.usesTransport, isFalse);
      expect(off.transportPrice, 0);
    });

    test('بيانات غير صالحة أو تلميذ مجهول', () async {
      await expectLater(
        service.update(
          's1',
          firstName: '',
          lastName: ' ',
          levelId: null,
          usesTransport: true,
          transportPrice: 0,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys,
            'keys',
            containsAll([
              StudentService.fieldFirstName,
              StudentService.fieldLastName,
              StudentService.fieldTransport,
            ]),
          ),
        ),
      );
      expect(
        await service.update(
          'missing',
          firstName: 'أ',
          lastName: 'ب',
          levelId: null,
          usesTransport: false,
          transportPrice: 0,
        ),
        isFalse,
      );
    });
  });

  group('الحذف', () {
    test('ناعم: يغادر مجموعاته وقوائمه وتبقى سجلاته', () async {
      await env.enroll(id: 'e1', studentId: 's1');
      await EnrolmentService(
        env.db,
        env.writer,
        dues,
        CycleService(env.db, env.writer),
      ).addToWaiting(studentId: 's1', subjectId: 'sub2');
      await dues.recordMonthPayment(
        studentId: 's1',
        groupId: 'g1',
        cycleNumber: 1,
        amount: 1000,
        receivedBy: 'u1',
        receiptNumber: 'A-000003',
      );
      expect(await service.remove('s1'), isTrue);
      expect(await service.remove('s1'), isFalse);

      final student = await env.db.select(env.db.students).getSingle();
      expect(student.deletedAt, isNotNull);
      final enrolment = await env.db.select(env.db.groupStudents).getSingle();
      expect(enrolment.leftAt, isNotNull);
      final entry = await env.db.select(env.db.waitingEntries).getSingle();
      expect(entry.deletedAt, isNotNull);
      // المدفوعات باقية.
      expect(await env.db.select(env.db.payments).get(), hasLength(1));
    });

    test('الكتابة عبر SyncWriter', () async {
      await service.remove('s1');
      final outbox = await env.db.select(env.db.outbox).get();
      expect(outbox.any((o) => o.targetTable == 'students'), isTrue);
    });
  });
}
