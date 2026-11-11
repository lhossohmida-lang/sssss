import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late FakeAccountProvisioner provisioner;
  late AccountService accounts;
  late DuesService dues;
  late EnrolmentService enrolments;
  late RegistrationService service;

  setUp(() async {
    env = TestEnv();
    provisioner = FakeAccountProvisioner();
    accounts = AccountService(env.db, env.writer, provisioner);
    dues = DuesService(env.db, env.writer);
    enrolments = EnrolmentService(
      env.db,
      env.writer,
      dues,
      CycleService(env.db, env.writer),
    );
    service = RegistrationService(
      env.db,
      env.writer,
      accounts: accounts,
      enrolments: enrolments,
      dues: dues,
    );
    await env.subject();
    await env.subject(id: 'sub2', price: 2500);
    await env.teacher();
    await env.group();
  });
  tearDown(() => env.close());

  /// حصة مغلقة (منعقدة) في الدورة الحالية للمجموعة g1.
  Future<void> heldSession(int n) => env.db
      .into(env.db.sessions)
      .insert(
        SessionsCompanion.insert(
          id: 'ses$n',
          createdAt: 1,
          updatedAt: 1,
          groupId: 'g1',
          cycleNumber: 1,
          sessionNumber: Value(n),
          date: '2026-11-${n.toString().padLeft(2, '0')}',
          startMinutes: 600,
          endMinutes: 690,
          closedAt: const Value(5),
        ),
      );

  RegistrationRequest request({
    String first = 'أحمد',
    String last = 'بن علي',
    String parent = 'علي بن علي',
    String phone = '0550123456',
    List<SubjectChoice>? choices,
    bool transport = false,
    int transportPrice = 0,
    String date = '2026-11-10',
  }) => RegistrationRequest(
    firstName: first,
    lastName: last,
    parentName: parent,
    parentPhone: phone,
    choices:
        choices ??
        const [
          SubjectChoice(subjectId: 'sub', groupId: 'g1', monthlyPrice: 2000),
        ],
    date: date,
    usesTransport: transport,
    transportPrice: transportPrice,
  );

  const settings = SchoolSettings(registrationFee: 1500);

  group('EnrolmentService', () {
    setUp(() => env.student());

    test('الانتساب من بداية الدورة: بلا رصيد', () async {
      final row = await enrolments.enrol(
        studentId: 's1',
        groupId: 'g1',
        monthlyPrice: 2000,
      );
      expect(row.id, StableId.groupStudent('g1', 's1'));
      expect(row.joinedAtCycleNumber, 1);
      expect(row.joinedAtSessionNumber, 1);
      expect(row.monthlyPrice, 2000);
      expect(await env.db.select(env.db.studentCredits).get(), isEmpty);
    });

    test(
      'الملتحق في المنتصف: رصيد الحصص الفائتة على السعر بعد التخفيض',
      () async {
        await heldSession(1);
        await heldSession(2);
        final row = await enrolments.enrol(
          studentId: 's1',
          groupId: 'g1',
          monthlyPrice: 2000,
          discountType: DiscountType.percent,
          discountValue: 50,
        );
        expect(row.joinedAtSessionNumber, 3);
        final credit = await env.db.select(env.db.studentCredits).getSingle();
        // صافي 1000 × حصتان ÷ 8 = 250.
        expect(credit.amount, 250);
        expect(credit.reason, DuesService.reasonMidJoin);
      },
    );

    test('منتسب أصلاً أو مجموعة مؤرشفة: مرفوض', () async {
      await enrolments.enrol(
        studentId: 's1',
        groupId: 'g1',
        monthlyPrice: 2000,
      );
      await expectLater(
        enrolments.enrol(studentId: 's1', groupId: 'g1', monthlyPrice: 2000),
        throwsA(isA<ValidationException>()),
      );
      await env.db.customStatement(
        "UPDATE groups SET archived_at = 9 WHERE id = 'g1'",
      );
      await env.student(id: 's2');
      await expectLater(
        enrolments.enrol(studentId: 's2', groupId: 'g1', monthlyPrice: 2000),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        enrolments.enrol(studentId: 's2', groupId: 'nope', monthlyPrice: 2000),
        throwsA(isA<ValidationException>()),
      );
    });

    test('من غادر يعود بنفس السجل', () async {
      final first = await enrolments.enrol(
        studentId: 's1',
        groupId: 'g1',
        monthlyPrice: 2000,
      );
      await env.db.customStatement(
        "UPDATE group_students SET left_at = 50 WHERE id = '${first.id}'",
      );
      final again = await enrolments.enrol(
        studentId: 's1',
        groupId: 'g1',
        monthlyPrice: 2200,
      );
      expect(again.id, first.id);
      expect(again.leftAt, isNull);
      expect(again.monthlyPrice, 2200);
      expect(await env.db.select(env.db.groupStudents).get(), hasLength(1));
    });

    test('التحقق من السعر والتخفيض', () {
      Map<String, String> errors(int price, DiscountType type, int value) =>
          EnrolmentService.priceErrors(
            price: price,
            discountType: type,
            discountValue: value,
          );
      expect(errors(2000, DiscountType.none, 0), isEmpty);
      expect(errors(2000, DiscountType.exempt, 0), isEmpty);
      expect(errors(2005, DiscountType.none, 0).keys, ['price']);
      expect(errors(-10, DiscountType.none, 0).keys, ['price']);
      expect(errors(2000, DiscountType.percent, 0).keys, ['discount']);
      expect(errors(2000, DiscountType.percent, 101).keys, ['discount']);
      expect(errors(2000, DiscountType.percent, 100), isEmpty);
      expect(errors(2000, DiscountType.fixed, 505).keys, ['discount']);
      expect(errors(2000, DiscountType.fixed, 2500).keys, ['discount']);
      expect(errors(2000, DiscountType.fixed, 500), isEmpty);
    });

    test(
      'قائمة الانتظار: تُنشأ مرة، والتلميذ لا يتكرر، والأستاذ المفضّل يُحفظ',
      () async {
        final listId = await enrolments.addToWaiting(
          studentId: 's1',
          subjectId: 'sub',
        );
        expect(listId, StableId.waitingList('sub', null));
        expect(
          await enrolments.addToWaiting(
            studentId: 's1',
            subjectId: 'sub',
            preferredTeacherId: 't1',
          ),
          listId,
        );
        expect(await env.db.select(env.db.waitingLists).get(), hasLength(1));
        expect(await env.db.select(env.db.waitingEntries).get(), hasLength(1));
        final list = await env.db.select(env.db.waitingLists).getSingle();
        expect(list.preferredTeacherId, 't1');
        expect(list.threshold, 10);
      },
    );

    test('قائمة لكل مستوى', () async {
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
      final a = await enrolments.addToWaiting(
        studentId: 's1',
        subjectId: 'sub',
      );
      final b = await enrolments.addToWaiting(
        studentId: 's1',
        subjectId: 'sub',
        levelId: 'lv',
      );
      expect(a, isNot(b));
    });

    test('الانتساب إلى مجموعة يزيله من قائمة انتظار مادتها', () async {
      await enrolments.addToWaiting(studentId: 's1', subjectId: 'sub');
      await enrolments.addToWaiting(studentId: 's1', subjectId: 'sub2');
      await enrolments.enrol(
        studentId: 's1',
        groupId: 'g1',
        monthlyPrice: 2000,
      );
      final entries = await env.db.select(env.db.waitingEntries).get();
      final live = entries.where((e) => e.deletedAt == null).toList();
      expect(live, hasLength(1));
      expect(live.single.waitingListId, StableId.waitingList('sub2', null));
      // والعودة إلى الانتظار تُحيي السجل نفسه.
      await env.db.customStatement(
        "UPDATE group_students SET left_at = 9 WHERE student_id = 's1'",
      );
      await enrolments.addToWaiting(studentId: 's1', subjectId: 'sub');
      expect(await env.db.select(env.db.waitingEntries).get(), hasLength(2));
    });

    test('مجموعات المادة وأساتذتها', () async {
      await env.teacher(id: 't2');
      await env.group(id: 'g2', teacherId: 't2');
      await env.db.customStatement(
        "UPDATE groups SET number = 2 WHERE id = 'g2'",
      );
      await env.group(id: 'g3', subjectId: 'sub2');
      await enrolments.enrol(
        studentId: 's1',
        groupId: 'g1',
        monthlyPrice: 2000,
      );
      final options = await enrolments.groupsForSubject('sub');
      expect(options.map((o) => o.id), ['g1', 'g2']);
      expect(options.first.studentCount, 1);
      expect(options.last.studentCount, 0);
      expect(options.first.label, 'المجموعة 1 · الأستاذ t1');

      await env.db
          .into(env.db.teacherSubjects)
          .insert(
            TeacherSubjectsCompanion.insert(
              teacherId: 't2',
              subjectId: 'sub',
              updatedAt: 1,
            ),
          );
      expect((await enrolments.teachersOfSubject('sub')).map((t) => t.id), [
        't2',
      ]);
      expect(await enrolments.teachersOfSubject('sub2'), isEmpty);
    });
  });

  group('SchoolSettings.feePeriodKey', () {
    test('السنة الدراسية تبدأ في سبتمبر', () {
      expect(SchoolSettings.schoolYearOf('2026-09-01'), '2026-2027');
      expect(SchoolSettings.schoolYearOf('2026-08-31'), '2025-2026');
      expect(SchoolSettings.schoolYearOf('2027-06-15'), '2026-2027');
    });

    test('سنوية، أو فصلية برقم الفصل', () {
      const semesters = [
        Semester(name: 'الأول', start: '2026-09-15', end: '2026-12-20'),
        Semester(name: 'الثاني', start: '2027-01-05', end: '2027-03-31'),
      ];
      const yearly = SchoolSettings(semesters: semesters);
      expect(yearly.feePeriodKey('2026-11-10'), '2026-2027');
      const bySemester = SchoolSettings(
        registrationFeePeriod: FeePeriod.semester,
        semesters: semesters,
      );
      expect(bySemester.feePeriodKey('2026-11-10'), '2026-2027/1');
      expect(bySemester.feePeriodKey('2027-02-01'), '2026-2027/2');
      // بين فصلين: على آخر فصل بدأ.
      expect(bySemester.feePeriodKey('2026-12-28'), '2026-2027/1');
      // قبل أي فصل: الأول.
      expect(bySemester.feePeriodKey('2026-09-02'), '2026-2027/1');
      // فصلية دون فصول معرَّفة: السنة.
      expect(
        const SchoolSettings(registrationFeePeriod: FeePeriod.semester)
            .feePeriodKey('2026-11-10'),
        '2026-2027',
      );
    });
  });

  group('RegistrationService', () {
    test('تسجيل كامل: تلميذ، وليّ، حساب، انتساب، حقوق تسجيل، رمز QR', () async {
      final result = await service.register(request(), settings: settings);
      final s = result.student;
      expect(s.firstName, 'أحمد');
      expect(s.lastName, 'بن علي');
      expect(s.parentPhone, '0550123456');
      expect(QrCodes.parse(s.qrCode)?.kind, QrOwnerKind.student);

      final parent = await env.db.select(env.db.parents).getSingle();
      expect(s.parentAccountId, parent.id);
      expect(parent.phone, '0550123456');
      expect(parent.name, 'علي بن علي');
      expect(parent.email, '0550123456@school.local');

      expect(result.parentAccount.created, isTrue);
      expect(result.parentAccount.password, hasLength(8));
      final account = await accounts.findByEmail(parent.email);
      expect(account?.role, 'parent');
      // الخادم يطابق entity_id الحساب مع parent_account_id التلميذ.
      expect(account?.entityId, parent.id);

      expect(result.enrolledGroupIds, ['g1']);
      expect(result.waitingListIds, isEmpty);
      expect(result.registrationFee?.amount, 1500);
      expect(result.registrationFee?.periodKey, '2026-2027');
      expect(result.registrationFee?.paid, isFalse);

      final sms = await env.db.select(env.db.smsQueue).getSingle();
      expect(sms.phone, '+213550123456');
      expect(sms.message, contains(result.parentAccount.password));
    });

    test(
      'الأخ الثاني: يُربط بحساب الوليّ القائم بلا حساب ولا رسالة جديدة',
      () async {
        final first = await service.register(request(), settings: settings);
        final second = await service.register(
          request(first: 'سارة', phone: '+213 550 12 34 56'),
          settings: settings,
        );
        expect(second.parentAccount.created, isFalse);
        expect(second.parentAccount.accountId, first.parentAccount.accountId);
        expect(second.student.parentAccountId, first.student.parentAccountId);
        expect(await env.db.select(env.db.parents).get(), hasLength(1));
        expect(provisioner.created, hasLength(1));
        expect(await env.db.select(env.db.smsQueue).get(), hasLength(1));
        // حقوق التسجيل لكل تلميذ.
        expect(
          await env.db.select(env.db.registrationFees).get(),
          hasLength(2),
        );
      },
    );

    test('عدة مواد: مجموعة وقائمة انتظار، وحقوق التسجيل مرة واحدة', () async {
      final result = await service.register(
        request(
          choices: const [
            SubjectChoice(
              subjectId: 'sub',
              groupId: 'g1',
              monthlyPrice: 2000,
              discountType: DiscountType.fixed,
              discountValue: 500,
            ),
            SubjectChoice(subjectId: 'sub2', preferredTeacherId: 't1'),
          ],
        ),
        settings: settings,
      );
      expect(result.enrolledGroupIds, ['g1']);
      expect(result.waitingListIds, [StableId.waitingList('sub2', null)]);
      final enrolment = await env.db.select(env.db.groupStudents).getSingle();
      expect(enrolment.discountType, 'fixed');
      expect(enrolment.discountValue, 500);
      expect(await env.db.select(env.db.registrationFees).get(), hasLength(1));
    });

    test('حقوق التسجيل صفر: لا سجل', () async {
      final result = await service.register(
        request(),
        settings: const SchoolSettings(),
      );
      expect(result.registrationFee, isNull);
      expect(await env.db.select(env.db.registrationFees).get(), isEmpty);
    });

    test('النقل يُحفظ بسعره، ودونه يُصفَّر', () async {
      final withBus = await service.register(
        request(transport: true, transportPrice: 1200),
        settings: settings,
      );
      expect(withBus.student.usesTransport, isTrue);
      expect(withBus.student.transportPrice, 1200);
      final without = await service.register(
        request(first: 'سارة', transportPrice: 900),
        settings: settings,
      );
      expect(without.student.usesTransport, isFalse);
      expect(without.student.transportPrice, 0);
    });

    test('أخطاء الاستمارة حسب الحقل ولا يُكتب شيء ولا يُنشأ حساب', () async {
      await expectLater(
        service.register(
          request(
            first: ' ',
            last: '',
            parent: '',
            phone: '12',
            choices: const [],
            transport: true,
          ),
          settings: settings,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys,
            'keys',
            containsAll([
              RegistrationService.fieldFirstName,
              RegistrationService.fieldLastName,
              RegistrationService.fieldParentName,
              RegistrationService.fieldPhone,
              RegistrationService.fieldSubjects,
              RegistrationService.fieldTransport,
            ]),
          ),
        ),
      );
      expect(await env.db.select(env.db.students).get(), isEmpty);
      expect(provisioner.created, isEmpty);
    });

    test('خطأ سعر المادة مفهرس برقمها، والمادة المكررة مرفوضة', () async {
      final errors = await service.validate(
        request(
          choices: const [
            SubjectChoice(subjectId: 'sub', groupId: 'g1', monthlyPrice: 2000),
            SubjectChoice(
              subjectId: 'sub',
              groupId: 'g1',
              monthlyPrice: 2005,
              discountType: DiscountType.percent,
              discountValue: 150,
            ),
          ],
        ),
      );
      expect(errors[RegistrationService.choiceField(1, 'price')], isNotNull);
      expect(errors[RegistrationService.choiceField(1, 'discount')], isNotNull);
      expect(errors[RegistrationService.fieldSubjects], contains('مكررة'));
    });

    test('نفس التلميذ لنفس الوليّ مرتين مرفوض', () async {
      await service.register(request(), settings: settings);
      await expectLater(
        service.register(request(), settings: settings),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors[RegistrationService.fieldFirstName],
            'message',
            contains('مسجَّل من قبل'),
          ),
        ),
      );
      expect(await env.db.select(env.db.students).get(), hasLength(1));
    });

    test('هاتف حساب أستاذ لا يصلح للوليّ', () async {
      await accounts.create(
        role: UserRole.teacher,
        entityId: 't1',
        displayName: 'أستاذ',
        phone: '0550123456',
      );
      final errors = await service.validate(request());
      expect(errors[RegistrationService.fieldPhone], contains('أستاذ'));
    });

    test('فشل إنشاء حساب الوليّ: لا تلميذ ولا وليّ', () async {
      provisioner.failing = true;
      await expectLater(
        service.register(request(), settings: settings),
        throwsA(isA<AuthFailureException>()),
      );
      expect(await env.db.select(env.db.students).get(), isEmpty);
      expect(await env.db.select(env.db.parents).get(), isEmpty);
    });

    test('فشل الانتساب يتراجع عن التلميذ كله (معاملة واحدة)', () async {
      await env.db.customStatement(
        "UPDATE groups SET archived_at = 9 WHERE id = 'g1'",
      );
      await expectLater(
        service.register(request(), settings: settings),
        throwsA(isA<ValidationException>()),
      );
      expect(await env.db.select(env.db.students).get(), isEmpty);
      expect(await env.db.select(env.db.parents).get(), isEmpty);
      // الحساب أُنشئ قبل المعاملة؛ إعادة المحاولة تربط به ولا تكرره.
      await env.db.customStatement(
        "UPDATE groups SET archived_at = NULL WHERE id = 'g1'",
      );
      final retry = await service.register(request(), settings: settings);
      expect(retry.parentAccount.created, isFalse);
      expect(provisioner.created, hasLength(1));
      expect(await env.db.select(env.db.parents).get(), hasLength(1));
    });

    test('كل الكتابات عبر SyncWriter', () async {
      await service.register(
        request(
          choices: const [
            SubjectChoice(subjectId: 'sub', groupId: 'g1', monthlyPrice: 2000),
            SubjectChoice(subjectId: 'sub2'),
          ],
        ),
        settings: settings,
      );
      final tables = (await env.db.select(env.db.outbox).get())
          .map((o) => o.targetTable)
          .toSet();
      expect(
        tables,
        containsAll([
          'students',
          'parents',
          'user_accounts',
          'group_students',
          'waiting_lists',
          'waiting_entries',
          'registration_fees',
          'sms_queue',
        ]),
      );
    });
  });
}
