import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late FakeAccountProvisioner provisioner;
  late AccountService accounts;
  late TeacherService service;

  setUp(() {
    env = TestEnv();
    provisioner = FakeAccountProvisioner();
    accounts = AccountService(env.db, env.writer, provisioner);
    service = TeacherService(env.db, env.writer, accounts);
  });
  tearDown(() => env.close());

  Future<List<SmsQueueRow>> sms() => env.db.select(env.db.smsQueue).get();

  group('AccountService', () {
    test('إنشاء حساب: بريد من الهاتف، كلمة سر مؤقتة، صف محلي ورسالة', () async {
      await (env.db.into(env.db.settings)).insert(
        SettingsCompanion.insert(
          key: SettingKeys.schoolName,
          value: 'مدرسة النجاح',
          updatedAt: 1,
        ),
      );
      final result = await accounts.create(
        role: UserRole.teacher,
        entityId: 't1',
        displayName: 'الأستاذ كمال',
        phone: '055 012 34 56',
      );
      expect(result.created, isTrue);
      expect(result.email, '0550123456@school.local');
      expect(result.password.length, 8);
      expect(provisioner.created[result.accountId]?.email, result.email);
      expect(provisioner.created[result.accountId]?.role, UserRole.teacher);

      final row = await (env.db.select(
        env.db.userAccounts,
      )..where((t) => t.id.equals(result.accountId))).getSingle();
      expect(row.role, 'teacher');
      expect(row.entityId, 't1');
      expect(row.mustChangePassword, isTrue);

      final queued = (await sms()).single;
      expect(queued.phone, '+213550123456');
      expect(queued.status, 'pending');
      expect(queued.kind, SmsTemplateKeys.accountCreated);
      expect(queued.message, contains('مدرسة النجاح'));
      expect(queued.message, contains(result.email));
      expect(queued.message, contains(result.password));
      expect(queued.message, contains('الأستاذ كمال'));
      expect(queued.createdBy, 'u1');
    });

    test('بلا اسم مدرسة: «المدرسة»', () async {
      await accounts.create(
        role: UserRole.worker,
        entityId: 'w1',
        displayName: 'عامل',
        phone: '0661234567',
      );
      expect((await sms()).single.message, contains('المدرسة'));
    });

    test('القالب المعدَّل يُستعمل بدل الافتراضي', () async {
      await env.db
          .into(env.db.smsTemplates)
          .insert(
            SmsTemplatesCompanion.insert(
              key: SmsTemplateKeys.accountCreated,
              body: 'أهلاً {name}: {email} / {password} / {unknown}',
              updatedAt: 1,
            ),
          );
      final result = await accounts.create(
        role: UserRole.teacher,
        entityId: 't1',
        displayName: 'سعد',
        phone: '0550123456',
      );
      expect(
        (await sms()).single.message,
        'أهلاً سعد: ${result.email} / ${result.password} / {unknown}',
      );
    });

    test('هاتف غير صالح أو مستعمل: ValidationException', () async {
      await expectLater(
        accounts.create(
          role: UserRole.teacher,
          entityId: 't1',
          displayName: 'س',
          phone: '123',
        ),
        throwsA(isA<ValidationException>()),
      );
      await accounts.create(
        role: UserRole.teacher,
        entityId: 't1',
        displayName: 'س',
        phone: '0550123456',
      );
      await expectLater(
        accounts.create(
          role: UserRole.worker,
          entityId: 'w1',
          displayName: 'ع',
          phone: '+213 550 12 34 56',
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(provisioner.created, hasLength(1));
    });

    test('الوليّ بنفس الهاتف يُربط بحسابه دون حساب ثانٍ ولا رسالة', () async {
      final first = await accounts.create(
        role: UserRole.parent,
        entityId: 'p1',
        displayName: 'ولي',
        phone: '0770000001',
        reuseExisting: true,
      );
      final second = await accounts.create(
        role: UserRole.parent,
        entityId: 'p1',
        displayName: 'ولي',
        phone: '0770000001',
        reuseExisting: true,
      );
      expect(second.created, isFalse);
      expect(second.accountId, first.accountId);
      expect(second.password, isEmpty);
      expect(provisioner.created, hasLength(1));
      expect(await sms(), hasLength(1));
    });

    test('إعادة الاستعمال لا تعبر الأدوار', () async {
      await accounts.create(
        role: UserRole.teacher,
        entityId: 't1',
        displayName: 'أ',
        phone: '0550123456',
      );
      await expectLater(
        accounts.create(
          role: UserRole.parent,
          entityId: 'p1',
          displayName: 'و',
          phone: '0550123456',
          reuseExisting: true,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('فشل إنشاء المستخدم لا يترك صفاً ولا رسالة', () async {
      provisioner.failing = true;
      await expectLater(
        accounts.create(
          role: UserRole.teacher,
          entityId: 't1',
          displayName: 'أ',
          phone: '0550123456',
        ),
        throwsA(isA<AuthFailureException>()),
      );
      expect(await env.db.select(env.db.userAccounts).get(), isEmpty);
      expect(await sms(), isEmpty);
    });

    test('إعادة توليد كلمة السر: تُرسل ويُفرض تغييرها', () async {
      await env.teacher(id: 't1');
      await env.db.customStatement(
        "UPDATE teachers SET phone = '0550123456' WHERE id = 't1'",
      );
      final created = await accounts.create(
        role: UserRole.teacher,
        entityId: 't1',
        displayName: 'الأستاذ',
        phone: '0550123456',
      );
      await env.db.customStatement(
        "UPDATE user_accounts SET must_change_password = 0 WHERE id = '${created.accountId}'",
      );
      final reset = await accounts.resetPassword(created.accountId);
      expect(reset.password, isNot(created.password));
      expect(provisioner.resets[created.accountId], reset.password);
      final row = await (env.db.select(
        env.db.userAccounts,
      )..where((t) => t.id.equals(created.accountId))).getSingle();
      expect(row.mustChangePassword, isTrue);
      final messages = await sms();
      expect(messages, hasLength(2));
      expect(messages.last.kind, SmsTemplateKeys.passwordReset);
      expect(messages.last.message, contains(reset.password));
    });

    test('إعادة التوليد لحساب مجهول ترمي', () async {
      await expectLater(accounts.resetPassword('missing'), throwsArgumentError);
    });

    test('التعطيل حذف ناعم', () async {
      final created = await accounts.create(
        role: UserRole.teacher,
        entityId: 't1',
        displayName: 'أ',
        phone: '0550123456',
      );
      expect(await accounts.disable(created.accountId), isTrue);
      expect(await accounts.findByEmail(created.email), isNull);
    });
  });

  group('SmsTemplateRenderer.fill', () {
    test('يعوّض المعروف ويترك المجهول', () {
      expect(
        SmsTemplateRenderer.fill('{a} و{b} و{c}', {'a': '1', 'b': '2'}),
        '1 و2 و{c}',
      );
    });
  });

  group('TeacherService', () {
    Future<String> subject(String name) async => (await SubjectService(
      env.db,
      env.writer,
    ).add(name: name, monthlyPrice: 2000)).id;

    test('إضافة أستاذ: صف، مواد، حساب، رمز QR، رسالة', () async {
      final math = await subject('رياضيات');
      final physics = await subject('فيزياء');
      final created = await service.add(
        name: ' كمال ',
        phone: '0550123456',
        subjectIds: {math, physics},
        ratePerStudent: 800,
      );
      final t = created.teacher;
      expect(t.name, 'كمال');
      expect(t.phone, '0550123456');
      expect(t.email, '0550123456@school.local');
      expect(t.ratePerStudent, 800);
      expect(QrCodes.parse(t.qrCode)?.kind, QrOwnerKind.teacher);
      expect(t.authUserId, created.account.accountId);

      expect(await service.subjectIdsOf(t.id), {math, physics});
      final account = await accounts.findByEmail(t.email);
      expect(account?.entityId, t.id);
      expect(account?.role, 'teacher');
      expect(account?.displayName, 'كمال');
      expect(await sms(), hasLength(1));
    });

    test('القائمة بأسماء المواد مرتبة', () async {
      final math = await subject('رياضيات');
      await service.add(
        name: 'ياسين',
        phone: '0550000002',
        subjectIds: {math},
        ratePerStudent: 0,
      );
      await service.add(
        name: 'أحمد',
        phone: '0550000001',
        subjectIds: const {},
        ratePerStudent: 0,
      );
      final items = await service.watchAll().first;
      expect(items.map((i) => i.name), ['أحمد', 'ياسين']);
      expect(items.first.subjectNames, isEmpty);
      expect(items.last.subjectNames, ['رياضيات']);
    });

    test('بيانات غير صالحة: أخطاء لكل حقل ولا حساب', () async {
      await expectLater(
        service.add(
          name: ' ',
          phone: '12',
          subjectIds: const {},
          ratePerStudent: 15,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors.keys,
            'keys',
            containsAll([
              TeacherService.fieldName,
              TeacherService.fieldPhone,
              TeacherService.fieldRate,
            ]),
          ),
        ),
      );
      expect(provisioner.created, isEmpty);
      expect(await env.db.select(env.db.teachers).get(), isEmpty);
    });

    test('هاتف مستعمل: يُرفض قبل أي اتصال خارجي', () async {
      await service.add(
        name: 'أ',
        phone: '0550123456',
        subjectIds: const {},
        ratePerStudent: 0,
      );
      await expectLater(
        service.add(
          name: 'ب',
          phone: '0550123456',
          subjectIds: const {},
          ratePerStudent: 0,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(provisioner.created, hasLength(1));
    });

    test('التعديل: المواد تُضاف وتُزال وتُعاد، والاسم يتبعه الحساب', () async {
      final math = await subject('رياضيات');
      final physics = await subject('فيزياء');
      final chem = await subject('كيمياء');
      final created = await service.add(
        name: 'كمال',
        phone: '0550123456',
        subjectIds: {math, physics},
        ratePerStudent: 800,
      );
      final id = created.teacher.id;
      expect(
        await service.update(
          id,
          name: 'كمال بن علي',
          phone: '0661234567',
          subjectIds: {physics, chem},
          ratePerStudent: 900,
        ),
        isTrue,
      );
      expect(await service.subjectIdsOf(id), {physics, chem});
      final row = await (env.db.select(
        env.db.teachers,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.name, 'كمال بن علي');
      expect(row.phone, '0661234567');
      expect(row.email, '0550123456@school.local');
      expect(row.ratePerStudent, 900);
      expect(
        (await accounts.findByEmail(row.email))?.displayName,
        'كمال بن علي',
      );

      // إعادة مادة محذوفة تُحييها.
      await service.update(
        id,
        name: 'كمال بن علي',
        phone: '0661234567',
        subjectIds: {math, physics, chem},
        ratePerStudent: 900,
      );
      expect(await service.subjectIdsOf(id), {math, physics, chem});
      final links = await env.db.select(env.db.teacherSubjects).get();
      expect(links, hasLength(3));
    });

    test('تعديل أستاذ مجهول أو ببيانات سيئة', () async {
      expect(
        await service.update(
          'missing',
          name: 'س',
          phone: '0550123456',
          subjectIds: const {},
          ratePerStudent: 0,
        ),
        isFalse,
      );
      await expectLater(
        service.update(
          'x',
          name: '',
          phone: 'bad',
          subjectIds: const {},
          ratePerStudent: -5,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('الحذف يعطّل الحساب ويحجب أستاذاً له مجموعات نشطة', () async {
      final created = await service.add(
        name: 'كمال',
        phone: '0550123456',
        subjectIds: const {},
        ratePerStudent: 0,
      );
      final id = created.teacher.id;
      await env.subject();
      await env.room();
      await env.group(teacherId: id);
      await expectLater(
        service.remove(id),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors['groups'],
            'groups',
            contains('1 مجموعة نشطة'),
          ),
        ),
      );
      await env.db.customStatement(
        "UPDATE groups SET archived_at = 5 WHERE id = 'g1'",
      );
      expect(await service.remove(id), isTrue);
      expect(await service.remove(id), isFalse);
      expect(await service.watchAll().first, isEmpty);
      expect(await accounts.findByEmail(created.teacher.email), isNull);
    });

    test('إعادة توليد كلمة سر الأستاذ', () async {
      final created = await service.add(
        name: 'كمال',
        phone: '0550123456',
        subjectIds: const {},
        ratePerStudent: 0,
      );
      final reset = await service.resetPassword(created.teacher.id);
      expect(reset.email, created.teacher.email);
      expect(await sms(), hasLength(2));
      await expectLater(
        service.resetPassword('missing'),
        throwsA(isA<ValidationException>()),
      );
    });

    test('كل الكتابات عبر SyncWriter', () async {
      final math = await subject('رياضيات');
      await service.add(
        name: 'كمال',
        phone: '0550123456',
        subjectIds: {math},
        ratePerStudent: 0,
      );
      final outbox = await env.db.select(env.db.outbox).get();
      final tables = outbox.map((o) => o.targetTable).toSet();
      expect(
        tables,
        containsAll([
          'teachers',
          'teacher_subjects',
          'user_accounts',
          'sms_queue',
        ]),
      );
    });
  });
}
