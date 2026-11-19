import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';

import '../support/fixtures.dart';

typedef PhoneLevel = (String?, String?);

void main() {
  late TestEnv env;
  late CycleService cycles;
  late DuesService dues;
  late PaymentService payments;
  late EnrolmentService enrolments;
  late AttendanceService attendance;
  late PayoutService payouts;

  setUp(() async {
    env = TestEnv();
    cycles = CycleService(env.db, env.writer);
    dues = DuesService(env.db, env.writer);
    payments = PaymentService(
      env.db,
      env.writer,
      dues,
      DeviceInfoStore(env.db, random: Random(7)),
    );
    enrolments = EnrolmentService(env.db, env.writer, dues, cycles);
    attendance = AttendanceService(env.db, env.writer, cycles, dues);
    payouts = PayoutService(env.db, env.writer, dues);
    await env.subject();
    await env.teacher(rate: 1200);
    await env.group(id: 'g1', rate: 1200, price: 2000);
    for (final id in ['s1', 's2', 's3', 's4']) {
      await env.student(id: id);
    }
  });
  tearDown(() => env.close());

  group('دليل الهواتف', () {
    late ContactService contacts;
    setUp(() => contacts = ContactService(env.db, env.writer));

    test('يسجّل جوالاً وثابتاً بصيغ موحَّدة', () async {
      final a = await contacts.add(
        name: ' مهتم ',
        phone: '0551 11 22 33',
        note: 'اتصل بعد شهر',
        followUpDate: '2026-12-15',
      );
      expect(a.name, 'مهتم');
      expect(a.phone, '0551112233');
      expect(a.followUpDate, '2026-12-15');
      expect(a.source, ContactService.sourceManual);
      final b = await contacts.add(phone: '021 23 45 67');
      expect(b.phone, '021234567', reason: 'هاتف ثابت بأرقام فقط');
      expect(b.name, isEmpty);
    });

    test('رقم أو تاريخ غير صالح: أخطاء بالحقول', () async {
      for (final bad in ['', 'abc', '12', '055']) {
        await expectLater(
          contacts.add(phone: bad),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.errors.keys,
              'حقول',
              contains(ContactService.fieldPhone),
            ),
          ),
          reason: bad,
        );
      }
      await expectLater(
        contacts.add(phone: '0551112233', followUpDate: '2026-13-45'),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys,
            'حقول',
            contains(ContactService.fieldFollowUp),
          ),
        ),
      );
      expect(await env.db.select(env.db.contacts).get(), isEmpty);
    });

    test('تعديل وحذف ناعم وبحث بالاسم أو الرقم أو الملاحظة', () async {
      final a = await contacts.add(
        name: 'سمير',
        phone: '0551112233',
        note: 'رياضيات',
      );
      await contacts.add(name: 'ليلى', phone: '0660000001', note: 'فيزياء');
      expect(await contacts.watchAll().first, hasLength(2));
      expect(
        (await contacts.watchAll(query: 'فيزياء').first).single.name,
        'ليلى',
      );
      expect(
        (await contacts.watchAll(query: '0551').first).single.name,
        'سمير',
      );
      expect(
        await contacts.update(
          a.id,
          name: 'سمير بن علي',
          phone: '0551112244',
          followUpDate: '2026-12-01',
        ),
        isTrue,
      );
      final row = await (env.db.select(
        env.db.contacts,
      )..where((c) => c.id.equals(a.id))).getSingle();
      expect(row.name, 'سمير بن علي');
      expect(row.phone, '0551112244');
      expect(row.followUpDate, '2026-12-01');
      expect(await contacts.remove(a.id), isTrue);
      expect(await contacts.watchAll().first, hasLength(1));
      expect(await contacts.update('nope', phone: '0551112233'), isFalse);
    });

    test('«أضف إن لم يوجد» لا يكرر الاسم والرقم نفسيهما', () async {
      expect(
        await contacts.addIfMissing(name: 'زائر', phone: '0551112233'),
        isNotNull,
      );
      expect(
        await contacts.addIfMissing(name: 'زائر', phone: '0551112233'),
        isNull,
      );
      expect(
        await contacts.addIfMissing(name: 'غيره', phone: '0551112233'),
        isNotNull,
      );
    });

    test(
      'أرقام التلاميذ للقراءة: المسجَّلون بأرقامهم دون تلاميذ المرة الواحدة',
      () async {
        await env.db.customStatement(
          "UPDATE students SET single_use = 1 WHERE id = 's2'",
        );
        await env.db.customStatement(
          "UPDATE students SET parent_phone = '' WHERE id = 's3'",
        );
        final phones = await contacts.watchStudentPhones().first;
        expect(phones.map((p) => p.studentId), unorderedEquals(['s1', 's4']));
        expect(
          (await contacts.watchStudentPhones(query: 's4').first)
              .single
              .studentId,
          's4',
        );
      },
    );
  });

  group('دليل الهواتف: السنة الدراسية', () {
    late ContactService contacts;
    setUp(() async {
      contacts = ContactService(env.db, env.writer);
      for (final (id, name, order) in [
        ('lv2', '2 ثانوي', 302),
        ('lv3', '3 ثانوي', 303),
      ]) {
        await env.db
            .into(env.db.levels)
            .insert(
              LevelsCompanion.insert(
                id: id,
                createdAt: 1,
                updatedAt: 1,
                name: name,
                stage: 'secondary',
                sortOrder: order,
              ),
            );
      }
    });

    test('الرقم يحمل سنة اختيارية تُحفظ وتُعدَّل وتُمسح', () async {
      final a = await contacts.add(phone: '0551112233', levelId: 'lv3');
      final none = await contacts.add(phone: '0551112244');
      expect(a.levelId, 'lv3');
      expect(none.levelId, isNull);
      expect(
        await contacts.update(a.id, phone: '0551112233', levelId: 'lv2'),
        isTrue,
      );
      expect(
        (await contacts.watchAll().first)
            .firstWhere((c) => c.id == a.id)
            .levelId,
        'lv2',
      );
      // تعديل دون سنة يمسحها (الحقل اختياري).
      await contacts.update(a.id, phone: '0551112233');
      expect(
        (await contacts.watchAll().first)
            .firstWhere((c) => c.id == a.id)
            .levelId,
        isNull,
      );
    });

    test('أرقام التلاميذ تحمل سنة كل تلميذ واسمها', () async {
      await env.db.customStatement(
        "UPDATE students SET level_id = 'lv3' WHERE id IN ('s1', 's2')",
      );
      await env.db.customStatement(
        "UPDATE students SET level_id = 'lv2' WHERE id = 's3'",
      );
      final phones = await contacts.watchStudentPhones().first;
      PhoneLevel of(String id) {
        final p = phones.firstWhere((p) => p.studentId == id);
        return (p.levelId, p.levelName);
      }

      expect(of('s1'), ('lv3', '3 ثانوي'));
      expect(of('s3'), ('lv2', '2 ثانوي'));
      expect(of('s4'), (null, null), reason: 'بلا سنة');
    });
  });

  group('من يتحمّل التخفيض', () {
    test('نصيب الأستاذ حين يتحمل التخفيض', () {
      int amount(int net) => Pricing.teacherAmountWhenTeacherBears(
        rate: 1200,
        price: 2000,
        net: net,
      );
      expect(amount(2000), 1200, reason: 'بلا تخفيض');
      expect(amount(1500), 700);
      expect(amount(1000), 200);
      expect(amount(500), 0, reason: 'التخفيض أكبر من نصيبه');
      expect(amount(0), 0, reason: 'إعفاء كامل');
      expect(
        Pricing.teacherAmountFor(
          DiscountBearer.school,
          rate: 1200,
          price: 2000,
          net: 0,
        ),
        isNull,
      );
      expect(
        Pricing.teacherAmountFor(
          DiscountBearer.teacher,
          rate: 1200,
          price: 2000,
          net: 1000,
        ),
        200,
      );
      expect(
        Pricing.teacherAmountFor(
          DiscountBearer.custom,
          rate: 1200,
          price: 2000,
          net: 1000,
          custom: 500,
        ),
        500,
      );
    });

    Future<GroupStudentRow> enrol(
      String studentId, {
      DiscountType type = DiscountType.exempt,
      int value = 0,
      DiscountBearer bearer = DiscountBearer.school,
      int? custom,
    }) => enrolments.enrol(
      studentId: studentId,
      groupId: 'g1',
      discountType: type,
      discountValue: value,
      bearer: bearer,
      customTeacherAmount: custom,
    );

    test('المدرسة تتحمل (الأصل): الأستاذ يأخذ نصيبه كاملاً', () async {
      expect((await enrol('s1')).teacherAmount, isNull);
      expect(
        (await enrol(
          's2',
          type: DiscountType.percent,
          value: 50,
        )).teacherAmount,
        isNull,
      );
    });

    test(
      'الأستاذ يتحمل: يُخصم التخفيض من نصيبه، والإعفاء الكامل يسقطه',
      () async {
        expect(
          (await enrol('s1', bearer: DiscountBearer.teacher)).teacherAmount,
          0,
        );
        expect(
          (await enrol(
            's2',
            type: DiscountType.percent,
            value: 50,
            bearer: DiscountBearer.teacher,
          )).teacherAmount,
          200,
        );
        expect(
          (await enrol(
            's3',
            type: DiscountType.fixed,
            value: 300,
            bearer: DiscountBearer.teacher,
          )).teacherAmount,
          900,
        );
      },
    );

    test('مبلغ يحدده المدير: يُحفظ، ويساوي النصيب فيُعدّ الأصل', () async {
      expect(
        (await enrol(
          's1',
          bearer: DiscountBearer.custom,
          custom: 500,
        )).teacherAmount,
        500,
      );
      expect(
        (await enrol(
          's2',
          bearer: DiscountBearer.custom,
          custom: 1200,
        )).teacherAmount,
        isNull,
      );
    });

    test(
      'مبلغ الأستاذ لا يزيد عن نصيبه ومن مضاعفات 10 وإلزامي مع «مبلغ»',
      () async {
        for (final bad in [1300, 15, -10]) {
          await expectLater(
            enrol('s1', bearer: DiscountBearer.custom, custom: bad),
            throwsA(
              isA<ValidationException>().having(
                (e) => e.errors.keys,
                'حقول',
                contains(EnrolmentService.fieldTeacherAmount),
              ),
            ),
            reason: '$bad',
          );
        }
        await expectLater(
          enrol('s1', bearer: DiscountBearer.custom),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.errors.keys,
              'حقول',
              contains(EnrolmentService.fieldTeacherAmount),
            ),
          ),
        );
        expect(await env.db.select(env.db.groupStudents).get(), isEmpty);
      },
    );

    test('التسجيل الجديد يمرّر من يتحمل التخفيض إلى الانتساب', () async {
      const request = RegistrationRequest(
        firstName: 'جديد',
        lastName: 'تلميذ',
        parentName: 'وليّ',
        parentPhone: '0661234567',
        date: '2026-11-14',
        choices: [
          SubjectChoice(
            subjectId: 'sub',
            groupId: 'g1',
            discountType: DiscountType.exempt,
            bearer: DiscountBearer.teacher,
          ),
        ],
      );
      final provisioner = FakeAccountProvisioner();
      final registration = RegistrationService(
        env.db,
        env.writer,
        accounts: AccountService(env.db, env.writer, provisioner),
        enrolments: enrolments,
        dues: dues,
      );
      final result = await registration.register(
        request,
        settings: const SchoolSettings(),
      );
      final row = await (env.db.select(
        env.db.groupStudents,
      )..where((e) => e.studentId.equals(result.student.id))).getSingle();
      expect(row.discountType, 'exempt');
      expect(row.teacherAmount, 0);
    });

    test('الخلاص يأخذ المبلغ المعيَّن لكل تلميذ لا نصيب الفوج وحده', () async {
      await enrol('s1'); // تتحمل المدرسة: 1200.
      await enrol('s2', bearer: DiscountBearer.teacher); // 0.
      await enrol('s3', bearer: DiscountBearer.custom, custom: 500); // 500.
      for (var i = 0; i < 8; i++) {
        await cycles.addSession(
          groupId: 'g1',
          date: '2026-11-${(10 + i).toString().padLeft(2, '0')}',
          startMinutes: 600,
          endMinutes: 690,
          status: SessionStatus.normal,
        );
      }
      for (final session in await env.db.select(env.db.sessions).get()) {
        for (final id in ['s1', 's2', 's3']) {
          await attendance.mark(
            sessionId: session.id,
            studentId: id,
            status: AttendanceStatus.present,
          );
        }
      }
      final payout = await payouts.compute('g1', 1);
      int earned(String id) =>
          payout.lines.firstWhere((l) => l.studentId == id).earned;
      expect(earned('s1'), 1200);
      expect(earned('s2'), 0);
      expect(earned('s3'), 500);
      expect(payout.earned, 1700);
      expect(payout.ratePerStudent, 1200);
    });
  });

  group('إيقاف أنواع الرسائل', () {
    late SmsKindPolicy policy;
    setUp(() => policy = SmsKindPolicy(env.db, env.writer));

    test('الأصل أن كل شيء يُرسل، والإيقاف والتفعيل يُحفظان', () async {
      expect(await policy.disabled(), isEmpty);
      expect(await policy.isEnabled(SmsTemplateKeys.paymentReceipt), isTrue);
      await policy.setEnabled(SmsTemplateKeys.paymentReceipt, enabled: false);
      await policy.setEnabled(SmsTemplateKeys.attendanceAbsent, enabled: false);
      expect(await policy.disabled(), {
        SmsTemplateKeys.paymentReceipt,
        SmsTemplateKeys.attendanceAbsent,
      });
      expect(await policy.isEnabled(SmsTemplateKeys.paymentReceipt), isFalse);
      await policy.setEnabled(SmsTemplateKeys.paymentReceipt, enabled: true);
      expect(await policy.disabled(), {SmsTemplateKeys.attendanceAbsent});
      expect(await policy.watchDisabled().first, {
        SmsTemplateKeys.attendanceAbsent,
      });
    });

    test('نص تالف أو فارغ يعني لا شيء موقوفاً', () {
      expect(SmsKindPolicy.parse(null), isEmpty);
      expect(SmsKindPolicy.parse(''), isEmpty);
      expect(SmsKindPolicy.parse('ليس json'), isEmpty);
      expect(SmsKindPolicy.parse('{"a": 1}'), isEmpty);
      expect(SmsKindPolicy.parse('["a", 3, "", "b"]'), {'a', 'b'});
    });

    test(
      'وصل الدفع يُوضع في الطابور، وإذا أوقف المدير نوعه لا يُوضع',
      () async {
        await env.enroll(id: 'e1', studentId: 's1');
        Future<PaymentRow> pay(int amount) => payments.record(
          studentId: 's1',
          type: PaymentType.month,
          groupId: 'g1',
          cycleNumber: 1,
          amount: amount,
        );
        await pay(500);
        expect(await env.db.select(env.db.smsQueue).get(), hasLength(1));

        await policy.setEnabled(SmsTemplateKeys.paymentReceipt, enabled: false);
        await pay(500);
        expect(
          await env.db.select(env.db.smsQueue).get(),
          hasLength(1),
          reason: 'النوع موقوف',
        );

        await policy.setEnabled(SmsTemplateKeys.paymentReceipt, enabled: true);
        await pay(500);
        expect(await env.db.select(env.db.smsQueue).get(), hasLength(2));
      },
    );

    test(
      'بيانات حساب جديد: إيقاف نوعها يجعل «أُرسلت الرسالة» خاطئاً',
      () async {
        final accounts = AccountService(
          env.db,
          env.writer,
          FakeAccountProvisioner(),
        );
        final first = await accounts.create(
          role: UserRole.teacher,
          entityId: 't-x',
          displayName: 'أستاذ',
          phone: '0770000011',
        );
        expect(first.smsQueued, isTrue);
        await policy.setEnabled(SmsTemplateKeys.accountCreated, enabled: false);
        final second = await accounts.create(
          role: UserRole.teacher,
          entityId: 't-y',
          displayName: 'أستاذ آخر',
          phone: '0770000012',
        );
        expect(second.smsQueued, isFalse);
        expect(await env.db.select(env.db.smsQueue).get(), hasLength(1));
      },
    );
  });

  group('شبكة الحضور: حصص مدفوعة', () {
    test('عدد الحصص المغطاة بما دُفع', () async {
      // s1 دفع الشهر، s2 نصفه، s3 لم يدفع، s4 معفى.
      await env.enroll(id: 'e1', studentId: 's1');
      await env.enroll(id: 'e2', studentId: 's2');
      await env.enroll(id: 'e3', studentId: 's3');
      await env.enroll(id: 'e4', studentId: 's4', discountType: 'exempt');
      for (var i = 0; i < 8; i++) {
        await cycles.addSession(
          groupId: 'g1',
          date: '2026-11-${(10 + i).toString().padLeft(2, '0')}',
          startMinutes: 600,
          endMinutes: 690,
          status: SessionStatus.normal,
        );
      }
      Future<void> pay(String id, int amount) => payments.record(
        studentId: id,
        type: PaymentType.month,
        groupId: 'g1',
        cycleNumber: 1,
        amount: amount,
      );
      await pay('s1', 2000);
      await pay('s2', 1000);

      final grid = (await GroupGridQueries(env.db, dues: dues).load('g1'))!;
      GridStudent student(String id) =>
          grid.students.firstWhere((s) => s.studentId == id);
      expect(student('s1').coveredSessions, 8);
      expect(student('s2').coveredSessions, 4);
      expect(student('s3').coveredSessions, 0);
      expect(student('s4').coveredSessions, 8, reason: 'معفى');
      expect(student('s2').paidAt(3), isTrue);
      expect(student('s2').paidAt(4), isFalse);
      expect(student('s3').paidAt(0), isFalse);
      expect(student('s1').paidAt(7), isTrue);

      // دون خدمة المدفوعات (تطبيق الأستاذ) لا تُحسب المدفوعات.
      final plain = (await GroupGridQueries(env.db).load('g1'))!;
      expect(plain.students.every((s) => s.coveredSessions == null), isTrue);
      expect(plain.students.first.paidAt(0), isNull);
    });

    test('تلميذ لا مستحق له في الدورة المعروضة بلا تغطية', () async {
      await env.enroll(id: 'e1', studentId: 's1', joinedCycle: 2);
      await env.db.customStatement(
        'UPDATE groups SET current_cycle_number = 2 WHERE id = \'g1\'',
      );
      final grid = (await GroupGridQueries(
        env.db,
        dues: dues,
      ).load('g1', cycleNumber: 1))!;
      expect(grid.students, isEmpty, reason: 'لم يلتحق بعد بالدورة 1');
    });
  });

  group('شبكة الحضور: حصص المراجعة', () {
    Future<String> reviewSession({
      required String groupId,
      String subjectId = 'sub',
      String date = '2026-11-12',
    }) async {
      if (subjectId != 'sub') await env.subject(id: subjectId, price: 900);
      await env.group(
        id: groupId,
        number: 9,
        subjectId: subjectId,
        sessionsPerCycle: 1,
        rate: 300,
        price: 500,
      );
      await env.db.customStatement(
        "UPDATE groups SET is_review = 1 WHERE id = '$groupId'",
      );
      final session = await cycles.addSession(
        groupId: groupId,
        date: date,
        startMinutes: 600,
        endMinutes: 780,
        status: SessionStatus.normal,
      );
      return session.id;
    }

    Future<void> guest(String sessionId, String studentId) => env.db
        .into(env.db.sessionGuests)
        .insert(
          SessionGuestsCompanion.insert(
            id: 'sg-$sessionId-$studentId',
            createdAt: 1,
            updatedAt: 1,
            sessionId: sessionId,
            studentId: studentId,
          ),
        );

    Future<void> regularSessions() async {
      await env.enroll(id: 'e1', studentId: 's1');
      await env.enroll(id: 'e2', studentId: 's2');
      for (var i = 0; i < 8; i++) {
        await cycles.addSession(
          groupId: 'g1',
          date: '2026-11-${(10 + i).toString().padLeft(2, '0')}',
          startMinutes: 600,
          endMinutes: 690,
          status: SessionStatus.normal,
        );
      }
    }

    test(
      'حصة من دورة من حضرها ضيفاً: تُحسب في مجموعه ولا تدخل حصص الدورة العامة',
      () async {
        await regularSessions();
        final review = await reviewSession(groupId: 'rev');
        await guest(review, 's1');
        await attendance.mark(
          sessionId: review,
          studentId: 's1',
          status: AttendanceStatus.present,
        );
        final grid = (await GroupGridQueries(env.db).load('g1'))!;
        expect(grid.sessions, hasLength(8));
        expect(grid.countedSessions, 8);
        expect(grid.reviewSessions.map((s) => s.id), [review]);
        final s1 = grid.students.firstWhere((s) => s.studentId == 's1');
        final s2 = grid.students.firstWhere((s) => s.studentId == 's2');
        expect(s1.reviewSessionIds, {review});
        expect(s1.cells[review], AttendanceStatus.present);
        expect(s2.reviewSessionIds, isEmpty);
        expect(s2.cells.containsKey(review), isFalse);
        // حصص الدورة العامة لا تشملها، ومجموعه يشمل ما حضره منها.
        expect(s1.countIn(grid.sessions, AttendanceStatus.present), 0);
        expect(s1.reviewCountIn(AttendanceStatus.present), 1);
        expect(s1.count(AttendanceStatus.present), 1);
        expect(s1.presentTotal(grid.sessions), 1);
        expect(s1.sessionsTotal(grid.countedSessions), 9);
        expect(s2.presentTotal(grid.sessions), 0);
        expect(s2.sessionsTotal(grid.countedSessions), 8);
      },
    );

    test('ضيف لم يُسجَّل حضوره بعد: حصة من دورته بلا حالة', () async {
      await regularSessions();
      final review = await reviewSession(groupId: 'rev');
      await guest(review, 's2');
      final grid = (await GroupGridQueries(env.db).load('g1'))!;
      final s2 = grid.students.firstWhere((s) => s.studentId == 's2');
      expect(s2.reviewSessionIds, {review});
      expect(s2.cells[review], isNull);
      expect(s2.sessionsTotal(grid.countedSessions), 9);
      expect(s2.presentTotal(grid.sessions), 0);
    });

    test('مراجعة مادة أخرى أو بلا ضيوف منهم لا تظهر', () async {
      await regularSessions();
      final other = await reviewSession(
        groupId: 'rev-other',
        subjectId: 'sub2',
      );
      await guest(other, 's1');
      await reviewSession(groupId: 'rev-empty', date: '2026-11-13');
      final grid = (await GroupGridQueries(env.db).load('g1'))!;
      expect(grid.reviewSessions, isEmpty);
      expect(grid.students.every((s) => s.reviewSessionIds.isEmpty), isTrue);
    });

    test(
      'المراجعة تتبع الدورة التي يقع تاريخها فيها، وللدورة الحالية بلا نهاية',
      () async {
        await regularSessions(); // الدورة 1: من 10 إلى 17 نوفمبر.
        await env.db.customStatement(
          "UPDATE groups SET current_cycle_number = 2 WHERE id = 'g1'",
        );
        for (final day in ['24', '25']) {
          await cycles.addSession(
            groupId: 'g1',
            date: '2026-11-$day',
            startMinutes: 600,
            endMinutes: 690,
            status: SessionStatus.normal,
          );
        }
        // 20 نوفمبر بعد آخر حصص الدورة 1 وقبل الدورة 2، و2 ديسمبر بعد حصص الدورة 2 (الحالية)،
        // و5 نوفمبر قبل أول حصة في الدورتين.
        final between = await reviewSession(
          groupId: 'rev-a',
          date: '2026-11-20',
        );
        final later = await reviewSession(groupId: 'rev-b', date: '2026-12-02');
        final early = await reviewSession(groupId: 'rev-c', date: '2026-11-05');
        for (final id in [between, later, early]) {
          await guest(id, 's1');
        }
        final queries = GroupGridQueries(env.db);
        final first = (await queries.load('g1', cycleNumber: 1))!;
        final second = (await queries.load('g1'))!;
        expect(first.reviewSessions.map((s) => s.id), [between]);
        expect(second.reviewSessions.map((s) => s.id), [later]);
        expect(
          first.students
              .firstWhere((s) => s.studentId == 's1')
              .reviewSessionIds,
          {between},
        );
      },
    );
  });

  group('الإحصاءات', () {
    test('تلميذ المرة الواحدة لا يُعدّ بين تلاميذ المدرسة', () async {
      await env.db.customStatement(
        "UPDATE students SET single_use = 1 WHERE id IN ('s3', 's4')",
      );
      final now = DateTime.now();
      final stats = await StatisticsService(env.db)
          .load(now.year, const StatisticsScope(students: true));
      expect(stats.activeStudents, 2);
    });
  });

  group('ماسح العامل', () {
    test('الخروج يعيد مدة العمل الفعلية ليومه', () async {
      const code = 'W-ABCDEFGHJK';
      await env.db
          .into(env.db.workers)
          .insert(
            WorkersCompanion.insert(
              id: 'w1',
              createdAt: 1,
              updatedAt: 1,
              name: 'سمير',
              phone: '0660000000',
              email: '0660000000@school.local',
              qrCode: code,
              fullDayWage: const Value(2000),
              halfDayWage: const Value(1200),
            ),
          );
      final scanner = ScanService(env.db, env.writer, cycles, dues);
      await scanner.loadIndex();
      final entered = await scanner.scan(code, now: DateTime(2026, 11, 14, 8));
      expect(entered.outcome, ScanOutcome.workerIn);
      final left = await scanner.scan(
        code,
        now: DateTime(2026, 11, 14, 12, 30),
      );
      expect(left.outcome, ScanOutcome.workerOut);
      expect(left.workedMinutes, 270);

      // اليوم يُحسب نصف يوم بحسب مدة بقائه والحدّين الافتراضيين.
      final month = await WageService(
        env.db,
        env.writer,
      ).month('w1', '2026-11');
      final day = month.days.firstWhere((d) => d.date == '2026-11-14');
      expect(day.paidKind, WorkDayKind.half);
      expect(day.wage, 1200);

      // الخروج الأخير يغلب: بقاء أطول يجعله يوماً كاملاً.
      final later = await scanner.scan(
        code,
        now: DateTime(2026, 11, 14, 16, 45),
      );
      expect(later.workedMinutes, 525);
      final updated = (await WageService(
        env.db,
        env.writer,
      ).month('w1', '2026-11')).days.firstWhere((d) => d.date == '2026-11-14');
      expect(updated.paidKind, WorkDayKind.full);
      expect(updated.wage, 2000);
    });
  });

  group('اللوحة: الأساتذة والعمال', () {
    test('عدد الأساتذة والعمال وحضورهم اليوم ومن في عمله الآن', () async {
      await env.teacher(id: 't2');
      for (final id in ['w1', 'w2', 'w3']) {
        await env.db
            .into(env.db.workers)
            .insert(
              WorkersCompanion.insert(
                id: id,
                createdAt: 1,
                updatedAt: 1,
                name: 'عامل $id',
                phone: '06600000${id.substring(1)}0',
                email: '$id@school.local',
                qrCode: 'W-$id',
              ),
            );
      }
      await env.db.customStatement(
        "UPDATE workers SET deleted_at = 9 WHERE id = 'w3'",
      );
      const day = '2026-11-14';
      await env.db
          .into(env.db.teacherAttendance)
          .insert(
            TeacherAttendanceCompanion.insert(
              id: 'ta1',
              createdAt: 1,
              updatedAt: 1,
              teacherId: 't1',
              date: day,
              checkIn: const Value(100),
            ),
          );
      await env.db
          .into(env.db.workerAttendance)
          .insert(
            WorkerAttendanceCompanion.insert(
              id: 'wa1',
              createdAt: 1,
              updatedAt: 1,
              workerId: 'w1',
              date: day,
              checkIn: const Value(100),
              checkOut: const Value(200),
            ),
          );
      await env.db
          .into(env.db.workerAttendance)
          .insert(
            WorkerAttendanceCompanion.insert(
              id: 'wa2',
              createdAt: 1,
              updatedAt: 1,
              workerId: 'w2',
              date: day,
              checkIn: const Value(100),
            ),
          );
      final stats = await DashboardQueries(
        env.db,
        env.writer,
      ).load(now: DateTime(2026, 11, 14, 10));
      expect(stats.teachers, 2);
      expect(stats.teachersPresent, 1);
      expect(stats.workers, 2, reason: 'المحذوف لا يُعدّ');
      expect(stats.workersPresent, 2);
      expect(stats.workersInside, 1);
    });
  });

  group('أرشيف سجل الحضور PDF', () {
    late Directory dir;
    late AttendanceArchiveService archive;

    DateTime at(int day, int hour) => DateTime(2026, 11, day, hour);

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('attendance_archive_test');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      archive = AttendanceArchiveService(
        db: env.db,
        attendance: attendance,
        settings: SettingsService(env.db, env.writer),
        preferences: DevicePreferences(env.db),
        fontLoader: () async =>
            File('../ui/assets/fonts/Cairo.ttf').readAsBytesSync(),
        clock: () => DateTime.fromMillisecondsSinceEpoch(env.time),
      );
      await env.enroll(id: 'e1', studentId: 's1');
      await env.enroll(id: 'e2', studentId: 's2');
    });

    /// حصة في يوم نوفمبر 2026 تنتهي 11:00 وتُغلق الساعة [closedHour].
    Future<void> heldAndClosed(int day, {int closedHour = 12}) async {
      await cycles.addSession(
        groupId: 'g1',
        date: '2026-11-${day.toString().padLeft(2, '0')}',
        startMinutes: 600,
        endMinutes: 660,
        status: SessionStatus.normal,
      );
      env.time = at(day, closedHour).millisecondsSinceEpoch;
      await attendance.closeDueSessions(at(day, closedHour));
    }

    List<File> pdfs() =>
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.pdf'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    test('دون مجلد لا شيء يُكتب ولا خطأ', () async {
      await heldAndClosed(10);
      final report = await archive.archiveNew();
      expect(report.written, 0);
      expect(report.error, isNull);
      expect(await archive.folder(), isNull);
    });

    test(
      'نسخة جديدة لكل حصة تنتهي بعد ضبط المجلد، ولا تُحدَّث بعد ذلك',
      () async {
        // حصة أُغلقت قبل ضبط المجلد: لا تُنسخ.
        await heldAndClosed(10);
        env.time = at(10, 13).millisecondsSinceEpoch;
        await archive.setFolder(dir.path);
        expect(await archive.folder(), dir.path);
        expect((await archive.archiveNew()).written, 0);
        expect(pdfs(), isEmpty);

        // حصة جديدة: نسخة جديدة في مجلد يومها.
        await heldAndClosed(11);
        final first = await archive.archiveNew();
        expect(first.written, 1);
        expect(first.error, isNull);
        var files = pdfs();
        expect(files, hasLength(1));
        expect(files.single.path, contains('2026-11-11'));
        expect(files.single.path, contains('فوج1'));
        final bytes = files.single.readAsBytesSync();
        expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');

        // لا تكرار.
        expect((await archive.archiveNew()).written, 0);
        expect(pdfs(), hasLength(1));

        // تصحيح الحضور بعد الإغلاق لا يغيّر النسخة ولا ينتج أخرى.
        final session = (await env.db.select(env.db.sessions).get()).firstWhere(
          (s) => s.date == '2026-11-11',
        );
        await attendance.mark(
          sessionId: session.id,
          studentId: 's1',
          status: AttendanceStatus.present,
        );
        expect((await archive.archiveNew()).written, 0);
        expect(pdfs().single.readAsBytesSync(), bytes);

        // حصة ثالثة: ملف ثانٍ باسم مختلف.
        await heldAndClosed(12);
        expect((await archive.archiveNew()).written, 1);
        files = pdfs();
        expect(files, hasLength(2));
        expect(files.first.path, isNot(files.last.path));
      },
    );

    test(
      'إيقاف الأرشفة بمجلد فارغ، وتغيير المجلد لا يعيد نسخ ما نُسخ',
      () async {
        env.time = at(9, 8).millisecondsSinceEpoch;
        await archive.setFolder(dir.path);
        await heldAndClosed(10);
        expect((await archive.archiveNew()).written, 1);
        await archive.setFolder(null);
        expect(await archive.folder(), isNull);
        await heldAndClosed(11);
        expect((await archive.archiveNew()).written, 0);
        final other = Directory.systemTemp.createTempSync('archive_other');
        addTearDown(() => other.deleteSync(recursive: true));
        await archive.setFolder(other.path);
        // حصة 10 نُسخت من قبل (علامتها على هذا الجهاز)، وحصة 11 أُغلقت بعد ضبط أول مجلد.
        final report = await archive.archiveNew();
        expect(report.written, 1);
        expect(
          other.listSync(recursive: true).whereType<File>().single.path,
          contains('2026-11-11'),
        );
      },
    );

    test('اسم الملف صالح على ويندوز', () {
      expect(
        AttendanceArchiveService.safeName('رياضيات: السنة 3/ثانوي?'),
        'رياضيات-_السنة_3-ثانوي-',
      );
      expect(AttendanceArchiveService.safeName('   '), 'حصة');
      expect(
        AttendanceArchiveService.safeName('ا' * 100).length,
        lessThanOrEqualTo(40),
      );
    });

    test('مجلد لا يُكتب فيه يرفضه الضبط', () async {
      final file = File('${dir.path}/ملف.txt')..writeAsStringSync('x');
      await expectLater(
        archive.setFolder('${file.path}/داخل'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await archive.folder(), isNull);
    });
  });
}
