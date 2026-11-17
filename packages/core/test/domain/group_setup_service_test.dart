import 'dart:math';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late FakeAccountProvisioner provisioner;
  late PaymentService payments;
  late GroupSetupService service;

  const settings = SchoolSettings();

  setUp(() async {
    env = TestEnv();
    provisioner = FakeAccountProvisioner();
    final dues = DuesService(env.db, env.writer);
    final cycles = CycleService(env.db, env.writer);
    payments = PaymentService(
      env.db,
      env.writer,
      dues,
      DeviceInfoStore(env.db, random: Random(7)),
    );
    final registration = RegistrationService(
      env.db,
      env.writer,
      accounts: AccountService(env.db, env.writer, provisioner),
      enrolments: EnrolmentService(env.db, env.writer, dues, cycles),
      dues: dues,
    );
    service = GroupSetupService(
      env.db,
      () => registration,
      payments,
      dues,
      cycles,
      clock: () => DateTime(2026, 11, 14, 10),
    );
    await env.subject();
    await env.teacher();
    await env.group();
  });
  tearDown(() => env.close());

  GroupSetupStudent input({
    String first = 'أحمد',
    String last = 'بن علي',
    String phone = '0550123456',
    CyclePaymentChoice payment = CyclePaymentChoice.unpaid,
    int partial = 0,
  }) => GroupSetupStudent(
    firstName: first,
    lastName: last,
    parentName: 'علي بن علي',
    parentPhone: phone,
    payment: payment,
    partialAmount: partial,
  );

  /// حصة مغلقة (منعقدة) في الدورة الحالية للفوج g1.
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

  group('إضافة تلميذ', () {
    test(
      'يُنشأ التلميذ وحساب وليّه ويُنتسب بسعر المادة وتُرسل بياناته',
      () async {
        final result = await service.addStudent(
          'g1',
          input(),
          settings: settings,
        );

        expect(result.student.firstName, 'أحمد');
        expect(result.parentAccount.created, isTrue);
        expect(result.paidNow, 0);
        expect(result.remaining, 2000);
        expect(result.payment, isNull);
        expect(result.paymentError, isNull);

        final enrolment = await env.db.select(env.db.groupStudents).getSingle();
        expect(enrolment.groupId, 'g1');
        expect(enrolment.monthlyPrice, 2000);
        final queued = await env.db.select(env.db.smsQueue).get();
        expect(
          queued.where((m) => m.kind == SmsTemplateKeys.accountCreated),
          hasLength(1),
          reason: 'بيانات الدخول تُرسل تلقائياً',
        );
      },
    );

    test('سُدِّدت الدورة كاملة: دفعة بوصل بمبلغ الدورة وباقٍ صفر', () async {
      final result = await service.addStudent(
        'g1',
        input(payment: CyclePaymentChoice.full),
        settings: settings,
      );
      expect(result.paidNow, 2000);
      expect(result.remaining, 0);
      expect(result.payment?.amount, 2000);
      expect(result.payment?.type, PaymentType.month.code);
      expect(result.payment?.groupId, 'g1');
      expect(result.payment?.cycleNumber, 1);
      expect(result.payment?.receiptNumber, isNotEmpty);
      final receipt = (await env.db.select(env.db.smsQueue).get()).where(
        (m) => m.kind == SmsTemplateKeys.paymentReceipt,
      );
      expect(receipt, hasLength(1), reason: 'وصل الدفع يصل الوليّ');
    });

    test('سُدِّد جزء: يبقى الباقي في المستحقات', () async {
      final result = await service.addStudent(
        'g1',
        input(payment: CyclePaymentChoice.partial, partial: 750),
        settings: settings,
      );
      expect(result.paidNow, 750);
      expect(result.remaining, 1250);
      final rows = await service.students('g1');
      expect(rows.single.paid, 750);
      expect(rows.single.remaining, 1250);
      expect(rows.single.isSettled, isFalse);
    });

    test('جزء أكبر من الدورة: يُضاف التلميذ ويُعاد سبب تعذّر الدفعة', () async {
      final result = await service.addStudent(
        'g1',
        input(payment: CyclePaymentChoice.partial, partial: 9000),
        settings: settings,
      );
      expect(result.student.firstName, 'أحمد', reason: 'بقي مضافاً');
      expect(result.paidNow, 0);
      expect(result.remaining, 2000);
      expect(result.paymentError, contains('المبلغ يزيد عن الباقي'));
      expect(await env.db.select(env.db.payments).get(), isEmpty);
    });

    test('جزء بلا مبلغ: رسالة ولا دفعة', () async {
      final result = await service.addStudent(
        'g1',
        input(payment: CyclePaymentChoice.partial),
        settings: settings,
      );
      expect(result.paidNow, 0);
      expect(result.paymentError, isNotNull);
    });

    test(
      'الملتحق في منتصف الدورة: الدورة الحالية كاملة ورصيد الفائت للتالية',
      () async {
        await heldSession(1);
        await heldSession(2);
        final result = await service.addStudent(
          'g1',
          input(payment: CyclePaymentChoice.full),
          settings: settings,
        );
        // الدورة الحالية بسعرها كاملاً؛ قيمة حصتين من ثمان (500) رصيد يُخصم
        // من الدورة التالية لا من هذه.
        expect(result.paidNow, 2000);
        expect(result.remaining, 0);
        final credits = await env.db.select(env.db.studentCredits).get();
        expect(credits.single.amount, 500);
      },
    );

    test('بيانات ناقصة: ValidationException ولا شيء يُكتب', () async {
      await expectLater(
        service.addStudent(
          'g1',
          input(first: '', phone: '123'),
          settings: settings,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await env.db.select(env.db.students).get(), isEmpty);
      expect(provisioner.created, isEmpty);
    });

    test('فوج غير موجود أو مؤرشف: مرفوض', () async {
      await expectLater(
        service.addStudent('nope', input(), settings: settings),
        throwsA(isA<ValidationException>()),
      );
      await env.db.customStatement(
        'UPDATE groups SET archived_at = 9 WHERE id = ?',
        ['g1'],
      );
      await expectLater(
        service.addStudent('g1', input(), settings: settings),
        throwsA(isA<ValidationException>()),
      );
    });

    test('إخوة بوليّ واحد: يُربطان بحساب واحد', () async {
      final first = await service.addStudent('g1', input(), settings: settings);
      final second = await service.addStudent(
        'g1',
        input(first: 'سعاد'),
        settings: settings,
      );
      expect(first.parentAccount.created, isTrue);
      expect(second.parentAccount.created, isFalse);
      expect(provisioner.created, hasLength(1));
    });
  });

  group('تلاميذ الفوج والتسديد', () {
    test('القائمة بترتيب الاسم ومعها حالة تسديد كل تلميذ', () async {
      await service.addStudent(
        'g1',
        input(first: 'ياسين', last: 'زيدان', phone: '0661111111'),
        settings: settings,
      );
      await service.addStudent(
        'g1',
        input(
          first: 'أمينة',
          last: 'بوعلام',
          phone: '0662222222',
          payment: CyclePaymentChoice.full,
        ),
        settings: settings,
      );
      final rows = await service.students('g1');
      expect(rows.map((r) => r.name), ['أمينة بوعلام', 'ياسين زيدان']);
      expect(rows.first.isSettled, isTrue);
      expect(rows.last.remaining, 2000);
      expect(rows.last.parentPhone, '0661111111');
    });

    test('تسديد الباقي لاحقاً بوصل ثان', () async {
      final added = await service.addStudent(
        'g1',
        input(payment: CyclePaymentChoice.partial, partial: 500),
        settings: settings,
      );
      final payment = await service.payCurrentCycle(
        groupId: 'g1',
        studentId: added.student.id,
        amount: 1500,
      );
      expect(payment.amount, 1500);
      expect((await service.students('g1')).single.isSettled, isTrue);
      expect(await env.db.select(env.db.payments).get(), hasLength(2));
      await expectLater(
        service.payCurrentCycle(
          groupId: 'g1',
          studentId: added.student.id,
          amount: 1,
        ),
        throwsA(isA<ValidationException>()),
        reason: 'لا شيء بقي',
      );
    });

    test('من غادر الفوج لا يظهر', () async {
      final added = await service.addStudent('g1', input(), settings: settings);
      await env.db.customStatement(
        'UPDATE group_students SET left_at = 9 WHERE student_id = ?',
        [added.student.id],
      );
      expect(await service.students('g1'), isEmpty);
    });

    test('عدد الحصص المنعقدة في الدورة الحالية', () async {
      expect(await service.heldSessions('g1'), 0);
      await heldSession(1);
      await heldSession(2);
      expect(await service.heldSessions('g1'), 2);
      expect(await service.priceOfGroup('g1'), 2000);
    });
  });
}
