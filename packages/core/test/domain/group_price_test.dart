import 'dart:math';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';

import '../support/fixtures.dart';

/// سعر الشهر ومبلغ الأستاذ لكل فوج: يُعيَّنان عند إنشائه فقط، وبهما يُنسب التلاميذ.
void main() {
  late TestEnv env;
  late GroupService groups;
  late EnrolmentService enrolments;
  late RegistrationService registration;
  late GroupSetupService setup;

  const slot = GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690);

  setUp(() async {
    env = TestEnv();
    final dues = DuesService(env.db, env.writer);
    final cycles = CycleService(env.db, env.writer);
    groups = GroupService(env.db, env.writer, ScheduleService(env.db), cycles);
    enrolments = EnrolmentService(env.db, env.writer, dues, cycles);
    registration = RegistrationService(
      env.db,
      env.writer,
      accounts: AccountService(env.db, env.writer, FakeAccountProvisioner()),
      enrolments: enrolments,
      dues: dues,
    );
    setup = GroupSetupService(
      env.db,
      () => registration,
      PaymentService(
        env.db,
        env.writer,
        dues,
        DeviceInfoStore(env.db, random: Random(7)),
      ),
      dues,
      cycles,
      enrolments: () => enrolments,
      clock: () => DateTime(2026, 11, 14, 10),
    );
    // مادة المتوسط بسعرها الافتراضي 2000 ومادة الثانوي 3000؛ ولأستاذ نصيب افتراضي قديم 1000.
    await env.subject(id: 'middle', price: 2000);
    await env.subject(id: 'secondary', price: 3000);
    await env.teacher();
    for (final subject in ['middle', 'secondary']) {
      await env.db
          .into(env.db.teacherSubjects)
          .insert(
            TeacherSubjectsCompanion.insert(
              teacherId: 't1',
              subjectId: subject,
              updatedAt: 1,
            ),
          );
    }
    await env.room();
    await env.student();
  });
  tearDown(() => env.close());

  /// [weekday] يفرّق جدول فوجين لأستاذ وقاعة واحدين فلا يتعارضان.
  Future<GroupRow> create({
    String subject = 'middle',
    int? price,
    int? rate,
    int weekday = 6,
  }) => groups.create(
    subjectId: subject,
    teacherId: 't1',
    roomId: 'r1',
    monthlyPrice: price,
    ratePerStudent: rate,
    slots: [
      GroupSlotInput(weekday: weekday, startMinutes: 600, endMinutes: 690),
    ],
    startDate: '2026-11-07',
  );

  Future<GroupStudentRow> enrolment(String groupId) =>
      (env.db.select(
            env.db.groupStudents,
          )..where((e) => e.groupId.equals(groupId) & e.studentId.equals('s1')))
          .getSingle();

  group('الإنشاء', () {
    test('لكل فوج سعره ومبلغ أستاذه، ويختلفان من فوج إلى آخر', () async {
      final middle = await create(price: 2500, rate: 1200);
      final secondary = await create(
        subject: 'secondary',
        price: 3500,
        rate: 1800,
        weekday: 7,
      );
      expect(middle.monthlyPrice, 2500);
      expect(middle.ratePerStudent, 1200);
      expect(secondary.monthlyPrice, 3500);
      expect(secondary.ratePerStudent, 1800);
    });

    test('فوجان لمادة واحدة بسعرين مختلفين', () async {
      final a = await create(price: 2000, rate: 1000);
      final b = await create(price: 2400, rate: 1300, weekday: 7);
      expect(await GroupPrice.of(env.db, a), 2000);
      expect(await GroupPrice.of(env.db, b), 2400);
    });

    test(
      'دون قيمة يأخذ الفوج سعر مادته ومبلغ أستاذه الحاليين (استعمال قديم)',
      () async {
        final group = await create(subject: 'secondary');
        expect(group.monthlyPrice, 3000);
        expect(group.ratePerStudent, 1000);
      },
    );

    test('السعر الفاسد يُرفض عند حقله', () async {
      for (final bad in [0, -10, 1255]) {
        await expectLater(
          create(price: bad),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.errors.keys,
              'fields',
              contains(GroupService.fieldPrice),
            ),
          ),
          reason: '$bad',
        );
      }
      expect(await env.db.select(env.db.groups).get(), isEmpty);
    });

    test('مبلغ الأستاذ الفاسد يُرفض عند حقله', () async {
      await expectLater(
        create(price: 2000, rate: 1005),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys,
            'fields',
            contains(GroupService.fieldRate),
          ),
        ),
      );
    });

    test('قيمتان تُكتبان عبر SyncWriter فتُزامَنان مع الخادم', () async {
      await create(price: 2500, rate: 1200);
      final outbox = await env.db.select(env.db.outbox).get();
      final groupRow = outbox.firstWhere((o) => o.targetTable == 'groups');
      expect(groupRow.payload, contains('"monthly_price":2500'));
      expect(groupRow.payload, contains('"rate_per_student":1200'));
    });
  });

  group('سعر الفوج عند الربط', () {
    test('الانتساب يأخذ سعر الفوج كما عُيِّن عند إنشائه', () async {
      final group = await create(price: 2500, rate: 1200);
      final row = await enrolments.enrol(studentId: 's1', groupId: group.id);
      expect(row.monthlyPrice, 2500);
    });

    test('التخفيض يُحسب على سعر الفوج', () async {
      final group = await create(price: 2500, rate: 1200);
      final row = await enrolments.enrol(
        studentId: 's1',
        groupId: group.id,
        discountType: DiscountType.percent,
        discountValue: 20,
      );
      expect(row.monthlyPrice, 2500);
      expect(
        Pricing.netPrice(
          price: row.monthlyPrice,
          discountType: DiscountType.percent,
          discountValue: row.discountValue,
        ),
        2000,
      );
    });

    test('تخفيض ثابت أكبر من سعر الفوج مرفوض', () async {
      final group = await create(price: 2000, rate: 1000);
      await expectLater(
        enrolments.enrol(
          studentId: 's1',
          groupId: group.id,
          discountType: DiscountType.fixed,
          discountValue: 2500,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('فوج قديم بلا سعر يأخذ التلميذ فيه سعر مادته', () async {
      await env.group(id: 'old', subjectId: 'secondary');
      final row = await enrolments.enrol(studentId: 's1', groupId: 'old');
      expect(row.monthlyPrice, 3000);
    });

    test('التسجيل بفوج يأخذ سعره، ويتحقق من التخفيض على هذا السعر', () async {
      final group = await create(price: 2500, rate: 1200);
      final result = await registration.register(
        RegistrationRequest(
          firstName: 'أحمد',
          lastName: 'بن علي',
          parentName: 'علي بن علي',
          parentPhone: '0550123456',
          choices: [SubjectChoice(subjectId: 'middle', groupId: group.id)],
          date: '2026-11-10',
        ),
        settings: const SchoolSettings(),
      );
      final row = await (env.db.select(
        env.db.groupStudents,
      )..where((e) => e.studentId.equals(result.student.id))).getSingle();
      expect(row.monthlyPrice, 2500);

      await expectLater(
        registration.register(
          RegistrationRequest(
            firstName: 'سارة',
            lastName: 'بن علي',
            parentName: 'علي بن علي',
            parentPhone: '0550123457',
            choices: [
              SubjectChoice(
                subjectId: 'middle',
                groupId: group.id,
                discountType: DiscountType.fixed,
                discountValue: 3000,
              ),
            ],
            date: '2026-11-10',
          ),
          settings: const SchoolSettings(),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('إعداد الفوج: السعر سعر الفوج في الإضافة الجديدة والموجودة', () async {
      final group = await create(price: 2500, rate: 1200);
      expect(await setup.priceOfGroup(group.id), 2500);
      final added = await setup.addExisting(group.id, ['s1']);
      expect(added.added, ['s1']);
      expect((await enrolment(group.id)).monthlyPrice, 2500);

      final fresh = await setup.addStudent(
        group.id,
        const GroupSetupStudent(
          firstName: 'يوسف',
          lastName: 'بن علي',
          parentName: 'علي بن علي',
          parentPhone: '0550123458',
        ),
        settings: const SchoolSettings(),
      );
      final row = await (env.db.select(
        env.db.groupStudents,
      )..where((e) => e.studentId.equals(fresh.student.id))).getSingle();
      expect(row.monthlyPrice, 2500);
    });

    test('تغيير سعر المادة بعد إنشاء الفوج لا يغيّر سعره', () async {
      final group = await create(price: 2500, rate: 1200);
      await env.writer.patch(
        env.db.subjects,
        key: {'id': 'middle'},
        values: {'monthly_price': 9990},
      );
      final row = await enrolments.enrol(studentId: 's1', groupId: group.id);
      expect(row.monthlyPrice, 2500);
    });
  });

  group('التعديل', () {
    test('يُصحَّح السعر ومبلغ الأستاذ ما دام الفوج بلا تلاميذ', () async {
      final group = await create(price: 2500, rate: 1200);
      await groups.update(
        group.id,
        teacherId: 't1',
        roomId: 'r1',
        monthlyPrice: 2600,
        ratePerStudent: 1300,
        slots: const [slot],
        today: '2026-11-07',
      );
      final fresh = await (env.db.select(
        env.db.groups,
      )..where((g) => g.id.equals(group.id))).getSingle();
      expect(fresh.monthlyPrice, 2600);
      expect(fresh.ratePerStudent, 1300);
    });

    test('بعد ربط تلميذ لا يتغيّر السعر ولا مبلغ الأستاذ', () async {
      final group = await create(price: 2500, rate: 1200);
      await enrolments.enrol(studentId: 's1', groupId: group.id);

      Future<void> update({int? price, int? rate}) => groups.update(
        group.id,
        teacherId: 't1',
        roomId: 'r1',
        monthlyPrice: price,
        ratePerStudent: rate,
        slots: const [slot],
        today: '2026-11-07',
      );

      await expectLater(
        update(price: 2600),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys,
            'fields',
            contains(GroupService.fieldPrice),
          ),
        ),
      );
      await expectLater(
        update(rate: 1300),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys,
            'fields',
            contains(GroupService.fieldRate),
          ),
        ),
      );
      // القيمتان نفساهما (ما تفعله شاشة التعديل) وترك القيمة (`null`) مقبولان.
      await update(price: 2500, rate: 1200);
      await update();
      final fresh = await (env.db.select(
        env.db.groups,
      )..where((g) => g.id.equals(group.id))).getSingle();
      expect(fresh.monthlyPrice, 2500);
      expect(fresh.ratePerStudent, 1200);
    });

    test('من غادر الفوج لا يمنع تصحيح السعر', () async {
      final group = await create(price: 2500, rate: 1200);
      await enrolments.enrol(studentId: 's1', groupId: group.id);
      await env.writer.patch(
        env.db.groupStudents,
        key: {'id': StableId.groupStudent(group.id, 's1')},
        values: {'left_at': 5},
      );
      await groups.update(
        group.id,
        teacherId: 't1',
        roomId: 'r1',
        monthlyPrice: 2700,
        slots: const [slot],
        today: '2026-11-07',
      );
      final fresh = await (env.db.select(
        env.db.groups,
      )..where((g) => g.id.equals(group.id))).getSingle();
      expect(fresh.monthlyPrice, 2700);
    });
  });

  group('GroupPrice', () {
    test('فوج غير موجود يعيد null', () async {
      expect(await GroupPrice.ofId(env.db, 'missing'), isNull);
    });

    test('سعر الفوج يتقدم على سعر مادته، والصفر يرجع إلى المادة', () async {
      await env.group(id: 'priced', subjectId: 'secondary', price: 3300);
      await env.group(id: 'legacy', number: 2, subjectId: 'secondary');
      expect(await GroupPrice.ofId(env.db, 'priced'), 3300);
      expect(await GroupPrice.ofId(env.db, 'legacy'), 3000);
    });
  });

  group('ترقية القاعدة المحلية', () {
    /// يرجع بالقاعدة إلى مخطط الإصدار 5 (قبل الأفواج المنتظِرة وضيوف الحصص ودليل الهواتف).
    Future<void> downToV5() async {
      for (final statement in [
        'ALTER TABLE groups DROP COLUMN waiting_target',
        'ALTER TABLE groups DROP COLUMN start_alerted_at',
        'ALTER TABLE groups DROP COLUMN is_review',
        'ALTER TABLE group_students DROP COLUMN teacher_amount',
        'ALTER TABLE students DROP COLUMN single_use',
        'DROP TABLE session_guests',
        'DROP TABLE contacts',
      ]) {
        await env.db.customStatement(statement);
      }
    }

    Future<Set<String>> columns(String table) async => {
      for (final row
          in await env.db.customSelect('PRAGMA table_info($table)').get())
        row.read<String>('name'),
    };

    test(
      'من الإصدار 4: تضيف عمود سعر الفوج وتملؤه من مادته ومبلغ أستاذه',
      () async {
        // قاعدة بمخطط الإصدار 4: بلا العمود، وفوج أُنشئ قبله بلا مبلغ أستاذ.
        await downToV5();
        await env.db.customStatement(
          'ALTER TABLE groups DROP COLUMN monthly_price',
        );
        await env.db.customStatement(
          'INSERT INTO groups (id, created_at, updated_at, number, subject_id, '
          'teacher_id, sessions_per_cycle, current_cycle_number) '
          "VALUES ('legacy', 1, 1, 1, 'secondary', 't1', 8, 1)",
        );
        await env.db.migration.onUpgrade(Migrator(env.db), 4, 6);
        final row = await env.db
            .customSelect(
              "SELECT monthly_price, rate_per_student FROM groups WHERE id = 'legacy'",
            )
            .getSingle();
        expect(row.read<int>('monthly_price'), 3000);
        expect(row.read<int>('rate_per_student'), 1000);
      },
    );

    test('من الإصدار 6: تضيف عمود السنة لدليل الهواتف وتبقي أرقامه', () async {
      await env.db.customStatement('ALTER TABLE contacts DROP COLUMN level_id');
      await env.db.customStatement(
        'INSERT INTO contacts (id, created_at, updated_at, name, phone, note, source) '
        "VALUES ('c1', 1, 1, 'مهتم', '0550000001', 'اتصل بعد شهر', 'manual')",
      );
      await env.db.migration.onUpgrade(Migrator(env.db), 6, 7);
      expect(await columns('contacts'), contains('level_id'));
      final row = await env.db
          .customSelect("SELECT phone, level_id FROM contacts WHERE id = 'c1'")
          .getSingle();
      expect(row.read<String>('phone'), '0550000001');
      expect(row.read<String?>('level_id'), isNull);
    });

    test(
      'من الإصدار 5 مباشرة إلى 7: جدول الدليل يُنشأ بعموده ولا يتكرر',
      () async {
        await downToV5();
        await env.db.migration.onUpgrade(Migrator(env.db), 5, 7);
        final names = [
          for (final row
              in await env.db.customSelect('PRAGMA table_info(contacts)').get())
            row.read<String>('name'),
        ];
        expect(names.where((n) => n == 'level_id'), hasLength(1));
      },
    );

    test('من الإصدار 5: تضيف أعمدة الأفواج المنتظِرة والضيوف وجدولي الضيوف والهواتف', () async {
      await downToV5();
      await env.db.customStatement(
        'INSERT INTO groups (id, created_at, updated_at, number, subject_id, '
        'teacher_id, sessions_per_cycle, current_cycle_number, monthly_price) '
        "VALUES ('legacy', 1, 1, 1, 'secondary', 't1', 8, 1, 4200)",
      );
      await env.db.migration.onUpgrade(Migrator(env.db), 5, 6);

      expect(
        await columns('groups'),
        containsAll(['waiting_target', 'start_alerted_at', 'is_review']),
      );
      expect(await columns('group_students'), contains('teacher_amount'));
      expect(await columns('students'), contains('single_use'));
      expect(
        await columns('session_guests'),
        containsAll(['session_id', 'student_id', 'price', 'ticket_code']),
      );
      expect(await columns('contacts'), containsAll(['name', 'phone', 'note']));

      // الفوج القائم: عادي (ليس منتظِراً ولا مراجعة)، وسعره كما هو لم يُمسّ.
      final row = await env.db
          .customSelect(
            "SELECT monthly_price, waiting_target, is_review FROM groups WHERE id = 'legacy'",
          )
          .getSingle();
      expect(row.read<int>('monthly_price'), 4200);
      expect(row.read<int?>('waiting_target'), isNull);
      expect(row.read<int>('is_review'), 0);

      final indexes = [
        for (final r
            in await env.db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'index' "
                  "AND (name LIKE 'idx_session_guests%' OR name LIKE 'idx_contacts%')",
                )
                .get())
          r.read<String>('name'),
      ];
      expect(indexes, hasLength(7));
    });
  });
}
