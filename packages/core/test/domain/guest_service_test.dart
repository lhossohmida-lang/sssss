import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late CycleService cycles;
  late GroupService groups;
  late DuesService dues;
  late PaymentService payments;
  late EnrolmentService enrolments;
  late AttendanceService attendance;
  late GuestService guests;
  late ScanService scanner;
  late PayoutService payouts;
  late GroupRow review;
  late String sessionId;

  final now = DateTime(2026, 11, 14, 10);

  setUp(() async {
    env = TestEnv();
    cycles = CycleService(env.db, env.writer);
    groups = GroupService(env.db, env.writer, ScheduleService(env.db), cycles);
    dues = DuesService(env.db, env.writer);
    payments = PaymentService(
      env.db,
      env.writer,
      dues,
      DeviceInfoStore(env.db, random: Random(7)),
    );
    enrolments = EnrolmentService(env.db, env.writer, dues, cycles);
    attendance = AttendanceService(env.db, env.writer, cycles, dues);
    guests = GuestService(env.db, env.writer, payments);
    scanner = ScanService(env.db, env.writer, cycles, dues);
    payouts = PayoutService(env.db, env.writer, dues);
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
    await env.student(id: 's1');
    await env.student(id: 's2');
    // فوج عادي فيه s1، وحصة مراجعة لا تلاميذ منتسبين فيها.
    await env.group(id: 'regular', rate: 1200, price: 2000);
    await env.enroll(id: 'e1', groupId: 'regular', studentId: 's1');
    review = await groups.createReview(
      subjectId: 'sub',
      teacherId: 't1',
      roomId: 'r1',
      date: '2026-11-20',
      startMinutes: 600,
      endMinutes: 780,
      fee: 500,
      teacherAmount: 300,
      today: '2026-11-14',
    );
    sessionId = (await groups.firstSessionId(review.id))!;
  });
  tearDown(() => env.close());

  Future<SessionGuestItem> oneTime({
    String name = 'أحمد بن علي',
    String phone = '0551112233',
    int paid = 500,
  }) => guests.addOneTime(
    sessionId: sessionId,
    name: name,
    phone: phone,
    price: 500,
    teacherAmount: 300,
    paidNow: paid,
  );

  group('تلميذ لمرة واحدة', () {
    test('سجل مخفي وتذكرة ووصل ورقمه في دليل الهواتف', () async {
      final g = await oneTime();
      expect(g.singleUse, isTrue);
      expect(g.ticketCode, startsWith('G-'));
      expect(QrCodes.parse(g.ticketCode!)?.kind, QrOwnerKind.guest);
      expect(g.price, 500);
      expect(g.teacherAmount, 300);
      expect(g.isPaid, isTrue);

      final student = await (env.db.select(
        env.db.students,
      )..where((s) => s.id.equals(g.studentId))).getSingle();
      expect(student.singleUse, isTrue);
      expect(student.firstName, 'أحمد');
      expect(student.lastName, 'بن علي');
      expect(student.parentPhone, '0551112233');

      final paid = await env.db.select(env.db.payments).get();
      expect(paid, hasLength(1));
      expect(paid.single.type, PaymentType.session.code);
      expect(paid.single.amount, 500);
      expect(paid.single.studentId, g.studentId);
      expect(paid.single.groupId, review.id);
      expect(paid.single.periodKey, sessionId);
      expect(paid.single.receiptNumber, isNotEmpty);

      final contacts = await env.db.select(env.db.contacts).get();
      expect(contacts, hasLength(1));
      expect(contacts.single.phone, '0551112233');
      expect(contacts.single.source, ContactService.sourceOneTime);

      // مخفي من القائمة العادية وعدّاد التلاميذ.
      final page = await StudentQueries(env.db).watchPage().first;
      expect(page.items.map((i) => i.id), unorderedEquals(['s1', 's2']));
      final stats = await DashboardQueries(env.db, env.writer).load(now: now);
      expect(stats.students, 2);
    });

    test('بلا هاتف لا يُسجَّل في الدليل، والدفع الجزئي يبقى باقياً', () async {
      final g = await oneTime(phone: '', paid: 200);
      expect(g.remaining, 300);
      expect(g.isPaid, isFalse);
      expect(await env.db.select(env.db.contacts).get(), isEmpty);
      // الباقي يظهر في «ما يُدفع» ويُسدَّد بوصل ثانٍ.
      final items = await payments.payables(g.studentId, now: now);
      final item = items.singleWhere((i) => i.type == PaymentType.session);
      expect(item.total, 500);
      expect(item.paid, 200);
      expect(item.periodKey, sessionId);
      expect(item.label, contains('الفوج'));
      await payments.record(
        studentId: g.studentId,
        type: PaymentType.session,
        amount: 300,
        groupId: item.groupId,
        cycleNumber: item.cycleNumber,
        periodKey: item.periodKey,
      );
      expect((await guests.guests(sessionId)).single.isPaid, isTrue);
      expect(
        (await payments.payables(
          g.studentId,
          now: now,
        )).where((i) => i.type == PaymentType.session),
        isEmpty,
      );
      // لا يُدفع أكثر من الباقي.
      await expectLater(
        payments.record(
          studentId: g.studentId,
          type: PaymentType.session,
          amount: 10,
          periodKey: sessionId,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('بيانات غير صالحة: أخطاء بالحقول ولا شيء يُكتب', () async {
      await expectLater(
        guests.addOneTime(
          sessionId: sessionId,
          name: ' ',
          phone: '123',
          price: 15,
          teacherAmount: 5,
          paidNow: 600,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys.toSet(),
            'حقول',
            containsAll([
              GuestService.fieldName,
              GuestService.fieldPhone,
              GuestService.fieldPrice,
              GuestService.fieldTeacherAmount,
            ]),
          ),
        ),
      );
      await expectLater(
        guests.addOneTime(
          sessionId: sessionId,
          name: 'س',
          price: 500,
          teacherAmount: 300,
          paidNow: 600,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys,
            'حقول',
            contains(GuestService.fieldPaid),
          ),
        ),
      );
      expect(await env.db.select(env.db.sessionGuests).get(), isEmpty);
      expect(await env.db.select(env.db.payments).get(), isEmpty);
    });

    test('حصة انتهت أو أُلغيت لا تقبل ضيوفاً', () async {
      await attendance.closeDueSessions(DateTime(2026, 11, 20, 14));
      await expectLater(
        oneTime(),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors[GuestService.fieldSession],
            'سبب',
            'انتهت هذه الحصة',
          ),
        ),
      );
    });

    test(
      'الاقتراح: ثمن حصة المراجعة كاملاً، وحصة من دورة الفوج العادي',
      () async {
        final forReview = await guests.suggest(sessionId);
        expect(forReview.price, 500);
        expect(forReview.teacherAmount, 300);
        await cycles.addSession(
          groupId: 'regular',
          date: '2026-11-21',
          startMinutes: 600,
          endMinutes: 690,
          status: SessionStatus.normal,
        );
        final regularSession = (await env.db.select(env.db.sessions).get())
            .firstWhere((s) => s.groupId == 'regular');
        final forRegular = await guests.suggest(regularSession.id);
        expect(forRegular.price, 250); // 2000 ÷ 8 حصص.
        expect(forRegular.teacherAmount, 150); // 1200 ÷ 8.
      },
    );
  });

  group('تلميذ مسجَّل في فوج آخر', () {
    test('يدخل برمزه العادي بلا تذكرة، ولا يُضاف مرتين', () async {
      final g = await guests.addStudent(
        sessionId: sessionId,
        studentId: 's1',
        price: 0,
        teacherAmount: 300,
      );
      expect(g.singleUse, isFalse);
      expect(g.ticketCode, isNull);
      expect(g.isPaid, isTrue, reason: 'ثمن صفر: لا باقي');
      await expectLater(
        guests.addStudent(
          sessionId: sessionId,
          studentId: 's1',
          price: 0,
          teacherAmount: 300,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors[GuestService.fieldStudent],
            'سبب',
            'مضاف إلى هذه الحصة من قبل',
          ),
        ),
      );
    });

    test('منتسب إلى فوج الحصة نفسه لا يكون ضيفها', () async {
      await cycles.addSession(
        groupId: 'regular',
        date: '2026-11-21',
        startMinutes: 600,
        endMinutes: 690,
        status: SessionStatus.normal,
      );
      final regular = (await env.db.select(env.db.sessions).get()).firstWhere(
        (s) => s.groupId == 'regular',
      );
      await expectLater(
        guests.addStudent(
          sessionId: regular.id,
          studentId: 's1',
          price: 100,
          teacherAmount: 50,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors[GuestService.fieldStudent],
            'سبب',
            'التلميذ منتسب إلى فوج هذه الحصة',
          ),
        ),
      );
      // وتلميذ مجهول.
      await expectLater(
        guests.addStudent(
          sessionId: sessionId,
          studentId: 'nope',
          price: 0,
          teacherAmount: 0,
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('الحذف', () {
    test('ضيف لم يحضر ولم يدفع يُحذف مع سجله المخفي', () async {
      final g = await oneTime(paid: 0);
      expect(await guests.remove(g.id), isTrue);
      expect(await guests.guests(sessionId), isEmpty);
      final student = await (env.db.select(
        env.db.students,
      )..where((s) => s.id.equals(g.studentId))).getSingle();
      expect(student.deletedAt, isNotNull);
      expect(await guests.remove(g.id), isFalse, reason: 'محذوف أصلاً');
    });

    test('ضيف دفع لا يُحذف', () async {
      final g = await oneTime();
      expect(await guests.remove(g.id), isFalse);
      expect(await guests.guests(sessionId), hasLength(1));
    });

    test('ضيف حضر لا يُحذف', () async {
      final g = await guests.addStudent(
        sessionId: sessionId,
        studentId: 's1',
        price: 0,
        teacherAmount: 300,
      );
      await attendance.mark(
        sessionId: sessionId,
        studentId: 's1',
        status: AttendanceStatus.present,
      );
      expect(await guests.remove(g.id), isFalse);
    });
  });

  group('ورقة الحضور', () {
    test('تعرض الضيوف بوسمهم، ويُسجَّل حضورهم يدوياً', () async {
      final g = await oneTime();
      await guests.addStudent(
        sessionId: sessionId,
        studentId: 's1',
        price: 0,
        teacherAmount: 300,
      );
      var roster = (await attendance.roster(sessionId))!;
      expect(roster.students, hasLength(2));
      expect(roster.students.every((s) => s.guest), isTrue);
      expect(roster.unmarked, 2);

      await attendance.mark(
        sessionId: sessionId,
        studentId: g.studentId,
        status: AttendanceStatus.present,
      );
      roster = (await attendance.roster(sessionId))!;
      expect(roster.count(AttendanceStatus.present), 1);
      expect(
        (await guests.guests(sessionId))
            .firstWhere((x) => x.id == g.id)
            .present,
        isTrue,
      );
    });

    test('غياب الضيف لا يُسجَّل تلقائياً عند إغلاق الحصة', () async {
      await oneTime();
      await attendance.closeDueSessions(DateTime(2026, 11, 20, 14));
      expect(await env.db.select(env.db.attendance).get(), isEmpty);
    });
  });

  group('تذكرة الدخول', () {
    final session = DateTime(2026, 11, 20, 9, 45);

    test('تُمسح فيُسجَّل الحضور، وتُستعمل مرة واحدة', () async {
      final g = await oneTime();
      await scanner.loadIndex();
      final first = await scanner.scan(g.ticketCode!, now: session);
      expect(first.outcome, ScanOutcome.guestOk);
      expect(first.owner?.name, 'أحمد بن علي');
      expect(first.groupNumber, review.number);
      final row = await env.db.select(env.db.attendance).getSingle();
      expect(row.studentId, g.studentId);
      expect(row.status, AttendanceStatus.present.code);
      expect(row.method, AttendanceMethod.qr.code);
      final guest = (await env.db.select(env.db.sessionGuests).getSingle());
      expect(guest.usedAt, isNotNull);

      final second = await scanner.scan(
        g.ticketCode!,
        now: session.add(const Duration(minutes: 1)),
      );
      expect(second.outcome, ScanOutcome.guestUsed);
      expect(await env.db.select(env.db.attendance).get(), hasLength(1));
    });

    test('ضيف لم يدفع: يُسجَّل حضوره بتنبيه', () async {
      final g = await oneTime(paid: 0);
      await scanner.loadIndex();
      final result = await scanner.scan(g.ticketCode!, now: session);
      expect(result.outcome, ScanOutcome.guestDues);
      expect(await env.db.select(env.db.attendance).get(), hasLength(1));
    });

    test('لا تصلح في يوم آخر ولا خارج وقت الحصة', () async {
      final g = await oneTime();
      await scanner.loadIndex();
      expect(
        (await scanner.scan(
          g.ticketCode!,
          now: DateTime(2026, 11, 19, 9, 45),
        )).outcome,
        ScanOutcome.guestInvalid,
      );
      expect(
        (await scanner.scan(
          g.ticketCode!,
          now: DateTime(2026, 11, 20, 8, 0),
        )).outcome,
        ScanOutcome.guestInvalid,
        reason: 'قبل الهامش',
      );
      expect(
        (await scanner.scan(
          g.ticketCode!,
          now: DateTime(2026, 11, 20, 14, 0),
        )).outcome,
        ScanOutcome.guestInvalid,
        reason: 'بعد النهاية',
      );
      expect(await env.db.select(env.db.attendance).get(), isEmpty);
      // لم تُستعمل بعد فتصلح في وقتها.
      expect(
        (await scanner.scan(g.ticketCode!, now: session)).outcome,
        ScanOutcome.guestOk,
      );
    });

    test(
      'تلميذ مسجَّل ضيف يدخل برمزه العادي فيُسجَّل حضوره مرة واحدة',
      () async {
        await guests.addStudent(
          sessionId: sessionId,
          studentId: 's1',
          price: 0,
          teacherAmount: 300,
        );
        await scanner.loadIndex();
        final first = await scanner.scan('S-s1', now: session);
        expect(first.outcome, ScanOutcome.guestOk);
        expect(first.groupNumber, review.number);
        final row = await env.db.select(env.db.attendance).getSingle();
        expect(row.studentId, 's1');
        expect(row.sessionId, sessionId);
        expect(row.method, AttendanceMethod.qr.code);
        expect(
          (await env.db.select(env.db.sessionGuests).getSingle()).usedAt,
          isNotNull,
        );
        final again = await scanner.scan(
          'S-s1',
          now: session.add(const Duration(minutes: 1)),
        );
        expect(again.outcome, ScanOutcome.studentAlreadyPresent);
        expect(await env.db.select(env.db.attendance).get(), hasLength(1));
      },
    );

    test('تلميذ مسجَّل غير ضيف على حصة اليوم: «لا حصة له الآن»', () async {
      await scanner.loadIndex();
      expect(
        (await scanner.scan('S-s2', now: session)).outcome,
        ScanOutcome.studentNoSession,
      );
    });

    test('تلميذ مسجَّل ضيف لم يدفع ثمناً: يُسجَّل حضوره بتنبيه', () async {
      await guests.addStudent(
        sessionId: sessionId,
        studentId: 's2',
        price: 200,
        teacherAmount: 100,
      );
      await scanner.loadIndex();
      expect(
        (await scanner.scan('S-s2', now: session)).outcome,
        ScanOutcome.guestDues,
      );
    });

    test('ضيف حذفت تذكرته يعاد «رمز غير معروف»', () async {
      final g = await oneTime(paid: 0);
      await guests.remove(g.id);
      await scanner.loadIndex();
      expect(
        (await scanner.scan(g.ticketCode!, now: session)).outcome,
        ScanOutcome.unknown,
      );
    });
  });

  group('نصيب الأستاذ من الضيوف', () {
    Future<void> markPresent(String studentId) => attendance.mark(
      sessionId: sessionId,
      studentId: studentId,
      status: AttendanceStatus.present,
    );

    test('يأخذ مبلغه عن الضيف الحاضر الدافع كاملاً', () async {
      final g = await oneTime();
      await markPresent(g.studentId);
      final payout = await payouts.compute(review.id, 1);
      final line = payout.lines.single;
      expect(line.studentId, g.studentId);
      expect(line.attended, 1);
      expect(line.earned, 300);
      expect(line.full, 300);
      expect(payout.earned, 300);
    });

    test('بقدر ما دُفع من ثمن الحصة، والباقي معلّق ثم يُفرَج عنه', () async {
      final g = await oneTime(paid: 250);
      await markPresent(g.studentId);
      var payout = await payouts.compute(review.id, 1);
      expect(payout.lines.single.earned, 150);
      expect(payout.lines.single.full, 300);
      expect(payout.pending, 150);

      // يكتمل الدفع: تظهر بقية نصيب الأستاذ في الخلاصة.
      await payments.record(
        studentId: g.studentId,
        type: PaymentType.session,
        amount: 250,
        groupId: review.id,
        cycleNumber: 1,
        periodKey: sessionId,
      );
      payout = await payouts.compute(review.id, 1);
      expect(payout.lines.single.earned, 300);
    });

    test('الغائب لا يأخذ عنه الأستاذ شيئاً', () async {
      final g = await oneTime();
      await attendance.mark(
        sessionId: sessionId,
        studentId: g.studentId,
        status: AttendanceStatus.absent,
      );
      final payout = await payouts.compute(review.id, 1);
      expect(payout.lines.single.earned, 0);
      expect(payout.lines.single.attended, 0);
    });

    test('تلميذ مسجَّل بثمن صفر: الأستاذ يأخذ مبلغه من مال المدرسة', () async {
      await guests.addStudent(
        sessionId: sessionId,
        studentId: 's1',
        price: 0,
        teacherAmount: 300,
      );
      await markPresent('s1');
      final payout = await payouts.compute(review.id, 1);
      expect(payout.lines.single.studentId, 's1');
      expect(payout.lines.single.earned, 300);
    });

    test('خلاص الحصة بعد إغلاقها يشمل الضيوف ويُنشأ مرة واحدة', () async {
      final g = await oneTime();
      await markPresent(g.studentId);
      await attendance.closeDueSessions(DateTime(2026, 11, 20, 14));
      final saved = await env.db.select(env.db.teacherPayouts).get();
      expect(saved, hasLength(1));
      expect(saved.single.amount, 300);
      expect(saved.single.groupId, review.id);
      final lines = PayoutService.linesOf(saved.single);
      expect(lines.single.studentId, g.studentId);
    });

    test('الإفراج عن النصيب المعلّق بعد تسديد ضيف متأخر', () async {
      final g = await oneTime(paid: 0);
      await markPresent(g.studentId);
      await attendance.closeDueSessions(DateTime(2026, 11, 20, 14));
      expect(
        (await env.db.select(env.db.teacherPayouts).getSingle()).amount,
        0,
      );
      await payments.record(
        studentId: g.studentId,
        type: PaymentType.session,
        amount: 500,
        groupId: review.id,
        cycleNumber: 1,
        periodKey: sessionId,
      );
      final all = await env.db.select(env.db.teacherPayouts).get();
      expect(all.fold<int>(0, (sum, p) => sum + p.amount), 300);
      expect(all.any((p) => p.kind == PayoutService.kindRelease), isTrue);
    });
  });

  group('ضيف في حصة فوج عادي', () {
    test('يُحسب نصيبه ضمن دورة الفوج دون أن يُحسب منتسباً', () async {
      for (var i = 0; i < 8; i++) {
        await cycles.addSession(
          groupId: 'regular',
          date: '2026-11-${(21 + i).toString().padLeft(2, '0')}',
          startMinutes: 600,
          endMinutes: 690,
          status: SessionStatus.normal,
        );
      }
      final regular = (await env.db.select(env.db.sessions).get())
          .firstWhere((s) => s.groupId == 'regular')
          .id;
      final g = await guests.addOneTime(
        sessionId: regular,
        name: 'زائر',
        price: 250,
        teacherAmount: 150,
        paidNow: 250,
      );
      await attendance.mark(
        sessionId: regular,
        studentId: g.studentId,
        status: AttendanceStatus.present,
      );
      final payout = await payouts.compute('regular', 1);
      final guestLine = payout.lines.firstWhere(
        (l) => l.studentId == g.studentId,
      );
      expect(guestLine.earned, 150);
      // المنتسب s1 لم يحضر فلا نصيب له، والضيف لم يُحسب بنسبة حصص الدورة.
      expect(payout.lines.firstWhere((l) => l.studentId == 's1').earned, 0);
      expect(payout.lines, hasLength(2));
      // لا يظهر بين تلاميذ الفوج في قائمة المنتسبين.
      final enrolled = await (env.db.select(
        env.db.groupStudents,
      )..where((e) => e.studentId.equals(g.studentId))).get();
      expect(enrolled, isEmpty);
      expect(enrolments, isNotNull);
    });
  });
}
