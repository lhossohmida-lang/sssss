import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late DuesService dues;
  late RegistrationFeeReports reports;

  setUp(() async {
    env = TestEnv();
    dues = DuesService(env.db, env.writer);
    reports = RegistrationFeeReports(env.db);
    await env.student();
    await env.student(id: 's2');
    await env.student(id: 's3');
  });
  tearDown(() => env.close());

  Future<void> fee(String student, String period, int amount) =>
      dues.ensureRegistrationFee(
        studentId: student,
        periodKey: period,
        amount: amount,
      );

  Future<void> pay(String student, String period, int amount) =>
      dues.payRegistrationFee(
        studentId: student,
        periodKey: period,
        amount: amount,
        receivedBy: 'u1',
        receiptNumber: 'A-${env.time++}',
      );

  test('بلا حقوق: فتراتها وتقريرها فارغان', () async {
    expect(await reports.periods(), isEmpty);
    expect((await reports.load(periodKey: '2026-2027')).isEmpty, isTrue);
  });

  test('الفترات الأحدث أولاً ولا تتكرر', () async {
    await fee('s1', '2025-2026', 1000);
    await fee('s2', '2026-2027', 1000);
    await fee('s1', '2026-2027', 1000);
    expect(await reports.periods(), ['2026-2027', '2025-2026']);
  });

  test('كل تلميذ بحقوقه وما دُفع منها والباقي', () async {
    await fee('s1', '2026-2027', 1000);
    await fee('s2', '2026-2027', 1000);
    await fee('s3', '2025-2026', 800);
    await pay('s1', '2026-2027', 1000);
    await pay('s2', '2026-2027', 400);
    final report = await reports.load(periodKey: '2026-2027');
    expect(report.items.map((i) => i.studentId), ['s1', 's2']);
    expect(report.items.first.isSettled, isTrue);
    expect(report.items.last.paid, 400);
    expect(report.items.last.remaining, 600);
    expect(report.totalAmount, 2000);
    expect(report.totalPaid, 1400);
    expect(report.totalRemaining, 600);
    expect(report.unpaidCount, 1);
  });

  test('غير المسدَّد فقط، والبحث', () async {
    await fee('s1', '2026-2027', 1000);
    await fee('s2', '2026-2027', 1000);
    await pay('s1', '2026-2027', 1000);
    final unpaid = await reports.load(periodKey: '2026-2027', unpaidOnly: true);
    expect(unpaid.items.map((i) => i.studentId), ['s2']);
    final found = await reports.load(periodKey: '2026-2027', query: 's1');
    expect(found.items.single.studentId, 's1');
    expect(
      (await reports.load(periodKey: '2026-2027', query: 'لا أحد')).isEmpty,
      isTrue,
    );
  });

  test('الحقوق المعفاة (مبلغ صفر) مسدَّدة والتلميذ المحذوف لا يظهر', () async {
    await fee('s1', '2026-2027', 0);
    await fee('s2', '2026-2027', 500);
    await env.db.customStatement(
      "UPDATE students SET deleted_at = 9 WHERE id = 's2'",
    );
    final report = await reports.load(periodKey: '2026-2027');
    expect(report.items.single.isSettled, isTrue);
    expect(report.items.single.amount, 0);
  });

  test('watch يتحدث بعد دفعة', () async {
    await fee('s1', '2026-2027', 1000);
    final paid = <int>[];
    final sub = reports
        .watch(periodKey: '2026-2027')
        .listen((r) => paid.add(r.totalPaid));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await pay('s1', '2026-2027', 300);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await sub.cancel();
    expect(paid.first, 0);
    expect(paid.last, 300);
  });
}
