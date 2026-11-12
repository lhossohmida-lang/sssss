import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  late DuesService dues;
  late DuesReports reports;

  setUp(() async {
    env = TestEnv();
    dues = DuesService(env.db, env.writer);
    reports = DuesReports(env.db, dues);
    await env.subject();
    await env.teacher();
    await env.group();
    await env.group(id: 'g2', number: 2);
    await env.student();
    await env.student(id: 's2');
    await env.student(id: 's3');
  });
  tearDown(() => env.close());

  Future<void> cycle(String groupId, int n) => env.db.customStatement(
    'UPDATE groups SET current_cycle_number = ? WHERE id = ?',
    [n, groupId],
  );

  Future<void> pay(String student, String group, int cycleNo, int amount) =>
      dues.recordMonthPayment(
        studentId: student,
        groupId: group,
        cycleNumber: cycleNo,
        amount: amount,
        receivedBy: 'u1',
        receiptNumber: 'A-${env.time++}',
      );

  test('لا انتساب: تقرير فارغ', () async {
    final report = await reports.load();
    expect(report.isEmpty, isTrue);
    expect(report.total, 0);
    expect(report.count, 0);
  });

  test('كل دورة غير مسدَّدة بند، ومجموع التلميذ مرتب تنازلياً', () async {
    await env.enroll(id: 'e1', studentId: 's1');
    await env.enroll(id: 'e2', studentId: 's2', joinedCycle: 3);
    await cycle('g1', 3);
    final report = await reports.load();
    expect(report.students.map((s) => s.studentId), ['s1', 's2']);
    final first = report.students.first;
    expect(first.total, 6000);
    expect(first.lines.map((l) => l.cycleNumber), [1, 2, 3]);
    expect(first.oldestCycle, 1);
    expect(first.name, 'تلميذ s1');
    expect(first.parentPhone, '0550123456');
    expect(first.lines.first.label, 'رياضيات · المجموعة 1 · الدورة 1');
    expect(report.students.last.total, 2000);
    expect(report.total, 8000);
    expect(report.count, 2);
  });

  test('الدفع يخفض الباقي، والكامل يُخرج البند', () async {
    await env.enroll(id: 'e1', studentId: 's1');
    await cycle('g1', 2);
    await pay('s1', 'g1', 1, 2000);
    await pay('s1', 'g1', 2, 500);
    final report = await reports.load();
    expect(report.students.single.lines, hasLength(1));
    expect(report.students.single.lines.single.remaining, 1500);
    await pay('s1', 'g1', 2, 1500);
    expect((await reports.load()).isEmpty, isTrue);
  });

  test('الحصر بمجموعة', () async {
    await env.enroll(id: 'e1', studentId: 's1');
    await env.enroll(id: 'e2', studentId: 's1', groupId: 'g2', price: 1500);
    await env.enroll(id: 'e3', studentId: 's2', groupId: 'g2', price: 1500);
    final all = await reports.load();
    expect(all.students.first.studentId, 's1');
    expect(all.students.first.total, 3500);
    final g2 = await reports.load(groupId: 'g2');
    expect(g2.students.map((s) => s.studentId).toSet(), {'s1', 's2'});
    expect(g2.students.first.total, 1500);
    expect(g2.students.first.lines.single.groupNumber, 2);
  });

  test('البحث بالاسم أو هاتف الوليّ', () async {
    await env.enroll(id: 'e1', studentId: 's1');
    await env.enroll(id: 'e2', studentId: 's2');
    await env.db.customStatement(
      "UPDATE students SET parent_phone = '0661000000' WHERE id = 's2'",
    );
    expect((await reports.load(query: 's2')).students.single.studentId, 's2');
    expect((await reports.load(query: '0661')).students.single.studentId, 's2');
    expect((await reports.load(query: 'لا أحد')).isEmpty, isTrue);
  });

  test('المعفى والمحذوف لا يظهران', () async {
    await env.enroll(id: 'e1', studentId: 's1', discountType: 'exempt');
    await env.enroll(id: 'e2', studentId: 's2');
    await env.enroll(id: 'e3', studentId: 's3');
    await env.db.customStatement(
      "UPDATE students SET deleted_at = 9 WHERE id = 's3'",
    );
    expect((await reports.load()).students.map((s) => s.studentId), ['s2']);
  });

  test('الرصيد يخفض المطلوب', () async {
    await env.enroll(id: 'e1', studentId: 's1');
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
    expect((await reports.load()).students.single.total, 1500);
  });

  test('watch يتحدث بعد الدفع', () async {
    await env.enroll(id: 'e1', studentId: 's1');
    final totals = <int>[];
    final sub = reports.watch().listen((r) => totals.add(r.total));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await pay('s1', 'g1', 1, 800);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await sub.cancel();
    expect(totals.first, 2000);
    expect(totals.last, 1200);
  });
}
