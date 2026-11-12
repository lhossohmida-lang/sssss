import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late DuesService dues;
  late DeviceInfoStore device;
  late PaymentService payments;

  // الشهر الجاري في الاختبارات.
  final now = DateTime(2026, 11, 14, 10);

  setUp(() async {
    env = TestEnv();
    dues = DuesService(env.db, env.writer);
    device = DeviceInfoStore(env.db, random: Random(7));
    payments = PaymentService(env.db, env.writer, dues, device);
    await env.subject();
    await env.teacher();
    await env.group();
    await env.student();
    await env.student(id: 's2');
    await env.enroll(id: 'e1', studentId: 's1', price: 2000);
  });
  tearDown(() => env.close());

  Future<PaymentRow> payMonth(int amount, {String student = 's1'}) =>
      payments.record(
        studentId: student,
        type: PaymentType.month,
        groupId: 'g1',
        cycleNumber: 1,
        amount: amount,
      );

  group('بادئة الجهاز', () {
    test('ثلاثة أحرف تُولَّد مرة وتبقى', () async {
      final first = await device.receiptPrefix();
      expect(first, matches(RegExp(r'^[A-Z]{3}$')));
      expect(first, isNot(contains('I')));
      expect(first, isNot(contains('O')));
      expect(await device.receiptPrefix(), first);
      expect(await DeviceInfoStore(env.db).receiptPrefix(), first);
    });

    test('جهازان مختلفان لا يتشاركان البادئة غالباً', () async {
      final other = TestEnv();
      addTearDown(other.close);
      final a = await device.receiptPrefix();
      final b = await DeviceInfoStore(
        other.db,
        random: Random(99),
      ).receiptPrefix();
      expect(a, isNot(b));
    });
  });

  group('ما يُدفع', () {
    test('الشهر غير المسدَّد بمادته ومجموعته ودورته', () async {
      final items = await payments.payables('s1', now: now);
      expect(items, hasLength(1));
      final item = items.single;
      expect(item.type, PaymentType.month);
      expect(item.label, 'رياضيات · المجموعة 1 · الدورة 1');
      expect(item.total, 2000);
      expect(item.paid, 0);
      expect(item.remaining, 2000);
      expect(item.groupId, 'g1');
      expect(item.cycleNumber, 1);
    });

    test('الدفع الجزئي يُبقي الباقي، والكامل يخفي العنصر', () async {
      await payMonth(500);
      final item = (await payments.payables('s1', now: now)).single;
      expect(item.paid, 500);
      expect(item.remaining, 1500);
      await payMonth(1500);
      expect(await payments.payables('s1', now: now), isEmpty);
    });

    test('الرصيد يُخصم من المطلوب', () async {
      await env.db
          .into(env.db.studentCredits)
          .insert(
            StudentCreditsCompanion.insert(
              id: 'c1',
              createdAt: 1,
              updatedAt: 1,
              studentId: 's1',
              groupId: 'g1',
              amount: 500,
              reason: 'excused',
              sourceCycleNumber: 0,
              targetCycleNumber: 1,
            ),
          );
      final item = (await payments.payables('s1', now: now)).single;
      expect(item.credits, 500);
      expect(item.total, 1500);
    });

    test('حقوق التسجيل غير المسدَّدة تظهر ثم تختفي بعد الدفع', () async {
      await dues.ensureRegistrationFee(
        studentId: 's1',
        periodKey: '2026-2027',
        amount: 1000,
      );
      final fee = (await payments.payables(
        's1',
        now: now,
      )).firstWhere((i) => i.type == PaymentType.registrationFee);
      expect(fee.label, 'حقوق التسجيل 2026-2027');
      expect(fee.total, 1000);
      await payments.record(
        studentId: 's1',
        type: PaymentType.registrationFee,
        periodKey: '2026-2027',
        amount: 1000,
      );
      expect(
        (await payments.payables(
          's1',
          now: now,
        )).where((i) => i.type == PaymentType.registrationFee),
        isEmpty,
      );
    });

    test('النقل لشهر التاريخ الجاري فقط ولمن يستعمله', () async {
      expect(
        (await payments.payables(
          's1',
          now: now,
        )).where((i) => i.type == PaymentType.transport),
        isEmpty,
      );
      await env.db.customStatement(
        'UPDATE students SET uses_transport = 1, transport_price = 600 '
        "WHERE id = 's1'",
      );
      final transport = (await payments.payables(
        's1',
        now: now,
      )).firstWhere((i) => i.type == PaymentType.transport);
      expect(transport.periodKey, '2026-11');
      expect(transport.total, 600);
      await payments.record(
        studentId: 's1',
        type: PaymentType.transport,
        periodKey: '2026-11',
        amount: 200,
      );
      final after = (await payments.payables(
        's1',
        now: now,
      )).firstWhere((i) => i.type == PaymentType.transport);
      expect(after.remaining, 400);
    });

    test('تلميذ بلا التزامات: لا عناصر', () async {
      expect(await payments.payables('s2', now: now), isEmpty);
    });
  });

  group('التسجيل', () {
    test('وصل بالبادئة ورقم تسلسلي، والمستلم صاحب الجلسة', () async {
      final prefix = await device.receiptPrefix();
      final first = await payMonth(500);
      final second = await payMonth(300);
      expect(first.receiptNumber, '$prefix-000001');
      expect(second.receiptNumber, '$prefix-000002');
      expect(first.receivedBy, 'u1');
      expect(first.type, 'month');
      expect(first.amount, 500);
      expect(await payments.nextReceiptNumber(), '$prefix-000003');
    });

    test('الدفعة تُسجَّل في سجل العمليات ومنتظرة للمزامنة', () async {
      await payMonth(500);
      final audit = await env.db.select(env.db.auditLog).get();
      expect(audit.where((a) => a.action == 'receive_money'), hasLength(1));
      final outbox = await env.db.select(env.db.outbox).get();
      expect(outbox.where((o) => o.targetTable == 'payments'), hasLength(1));
    });

    test('مبلغ صفري أو سالب مرفوض', () async {
      for (final bad in [0, -5]) {
        await expectLater(
          payMonth(bad),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.errors[PaymentService.fieldAmount],
              'amount',
              isNotNull,
            ),
          ),
        );
      }
      expect(await env.db.select(env.db.payments).get(), isEmpty);
    });

    test('مبلغ يزيد عن الباقي مرفوض بذكر الباقي', () async {
      await payMonth(1500);
      await expectLater(
        payMonth(600),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.errors[PaymentService.fieldAmount],
            'amount',
            contains('500'),
          ),
        ),
      );
    });

    test('دورة غير ملزَم بها أو بيانات ناقصة: مرفوض', () async {
      await expectLater(
        payMonth(100, student: 's2'),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        payments.record(studentId: 's1', type: PaymentType.month, amount: 100),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        payments.record(
          studentId: 's1',
          type: PaymentType.transport,
          amount: 100,
        ),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        payments.record(
          studentId: 's1',
          type: PaymentType.registrationFee,
          amount: 100,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('الإعفاء الكامل لا مطلوب منه', () async {
      await env.db.customStatement(
        "UPDATE group_students SET discount_type = 'exempt' WHERE id = 'e1'",
      );
      expect(await payments.payables('s1', now: now), isEmpty);
    });
  });

  group('القوائم', () {
    Future<void> seed() async {
      await env.enroll(id: 'e2', studentId: 's2', price: 2000);
      env.time = 1000;
      await payMonth(500);
      env.time = 2000;
      await payMonth(700, student: 's2');
      env.time = 3000;
      await dues.ensureRegistrationFee(
        studentId: 's1',
        periodKey: '2026-2027',
        amount: 1000,
      );
      await payments.record(
        studentId: 's1',
        type: PaymentType.registrationFee,
        periodKey: '2026-2027',
        amount: 1000,
      );
    }

    test('الأحدث أولاً بوصفها واسم التلميذ', () async {
      await seed();
      final page = await payments.payments();
      expect(page.total, 3);
      expect(page.items.map((i) => i.payment.amount), [1000, 700, 500]);
      expect(page.items.first.studentName, 'تلميذ s1');
      expect(page.items.first.description, 'حقوق التسجيل — 2026-2027');
      expect(
        page.items.last.description,
        'شهر — رياضيات · المجموعة 1 · الدورة 1',
      );
      expect(page.hasMore, isFalse);
    });

    test('البحث باسم التلميذ وبرقم الوصل', () async {
      await seed();
      expect((await payments.payments(query: 's2')).total, 1);
      final receipt =
          (await payments.payments()).items.first.payment.receiptNumber;
      final hit = await payments.payments(query: receipt);
      expect(hit.total, 1);
      expect(hit.items.single.payment.receiptNumber, receipt);
      expect((await payments.payments(query: 'لا أحد')).items, isEmpty);
    });

    test('الحصر بتلميذ: دفعاته وحدها بعدّها الصحيح', () async {
      await seed();
      final s2 = await payments.payments(studentId: 's2');
      expect(s2.total, 1);
      expect(s2.items.single.payment.studentId, 's2');
      final s1 = await payments.payments(studentId: 's1');
      expect(s1.total, 2);
      expect(s1.items.map((i) => i.payment.studentId).toSet(), {'s1'});
      expect((await payments.payments(studentId: 'nobody')).items, isEmpty);
      // مع نوع معيّن.
      expect(
        (await payments.payments(
          studentId: 's1',
          type: PaymentType.registrationFee,
        )).total,
        1,
      );
    });

    test('التصفية بالنوع والتحميل المقسّم', () async {
      await seed();
      final fees = await payments.payments(type: PaymentType.registrationFee);
      expect(fees.total, 1);
      final first = await payments.payments(limit: 2);
      expect(first.items, hasLength(2));
      expect(first.total, 3);
      expect(first.hasMore, isTrue);
    });

    test('المحذوفة لا تظهر، والمجموع حسب اليوم', () async {
      await seed();
      final day = DateTime.fromMillisecondsSinceEpoch(
        1000,
        isUtc: true,
      ).toLocal();
      expect(await payments.receivedOn(day), 2200);
      expect(
        await payments.receivedBetween(from: 1500, to: 2500),
        700,
        reason: 'النطاق نصف مفتوح',
      );
      await env.db.customStatement(
        'UPDATE payments SET deleted_at = 9 WHERE amount = 700',
      );
      expect((await payments.payments()).total, 2);
      expect(await payments.receivedOn(day), 1500);
    });

    test('تفاصيل الدفعة: التلميذ والمستلم والوصف', () async {
      await env.db.customStatement(
        'INSERT INTO user_accounts (id, created_at, updated_at, email, role, '
        'display_name, must_change_password) VALUES '
        "('u1', 1, 1, 'owner@school.local', 'owner', 'المدير', 0)",
      );
      final paid = await payMonth(500);
      final detail = (await payments.detail(paid.id))!;
      expect(detail.item.studentName, 'تلميذ s1');
      expect(detail.receivedByName, 'المدير');
      expect(detail.studentId, 's1');
      expect(detail.payment.receiptNumber, paid.receiptNumber);
      expect(detail.item.description, contains('رياضيات'));
      expect(await payments.detail('nope'), isNull);
    });

    test('الباقي الآن من البند في تفاصيل الدفعة', () async {
      final first = await payMonth(500);
      expect((await payments.detail(first.id))!.remaining, 1500);
      final last = await payMonth(1500);
      expect((await payments.detail(last.id))!.remaining, 0);
      // الباقي حالي لا تاريخي: يظهر صفراً في وصل الدفعة الأولى أيضاً.
      expect((await payments.detail(first.id))!.remaining, 0);
    });

    test('المستلم بلا اسم يُعرض ببريده، والمجهول بشرطة', () async {
      final paid = await payMonth(500);
      expect((await payments.detail(paid.id))!.receivedByName, '—');
      await env.db.customStatement(
        'INSERT INTO user_accounts (id, created_at, updated_at, email, role, '
        'display_name, must_change_password) VALUES '
        "('u1', 1, 1, 'w@school.local', 'worker', '', 0)",
      );
      expect(
        (await payments.detail(paid.id))!.receivedByName,
        'w@school.local',
      );
    });

    test('watchReceivedOn يتحدث مع كل دفعة', () async {
      final day = DateTime.now();
      env.time = DateTime.now().millisecondsSinceEpoch;
      final seen = <int>[];
      final sub = payments.watchReceivedOn(day).listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await payMonth(500);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await sub.cancel();
      expect(seen.first, 0);
      expect(seen.last, 500);
    });

    test('watchPayments يتحدث بعد دفعة جديدة', () async {
      final seen = <int>[];
      final sub = payments.watchPayments().listen((p) => seen.add(p.total));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await payMonth(500);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await sub.cancel();
      expect(seen.first, 0);
      expect(seen.last, 1);
    });
  });
}
