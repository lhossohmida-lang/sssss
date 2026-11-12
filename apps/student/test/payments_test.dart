import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'home_test.dart' hide main;

int at(int day, int hour) =>
    DateTime(2026, 11, day, hour).toUtc().millisecondsSinceEpoch;

/// يفتح «المدفوعات»: لنور (الابن الثاني بالاسم) دفعتان: شهر الرياضيات
/// (2000 دج) وحقوق التسجيل (1000 دج)، ولسمير دفعة (1500 دج) ولابن وليّ آخر
/// دفعة لا تظهر لأحد.
Future<AppRuntime> openPayments(
  WidgetTester tester, {
  bool seed = true,
  String? child,
  FakePdfPresenter? presenter,
}) async {
  final runtime = await openParent(tester, seed: seed, pdfPresenter: presenter);
  if (seed) {
    await runDb(tester, () async {
      final db = runtime.db;
      Future<void> pay(
        String id,
        String student,
        String type,
        int amount,
        String receipt,
        int createdAt, {
        String? group,
        int? cycle,
        String? period,
      }) => db.customInsert(
        'INSERT INTO payments (id, created_at, updated_at, student_id, type, '
        'group_id, cycle_number, period_key, amount, received_by, '
        'receipt_number) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable.withString(id),
          Variable.withInt(createdAt),
          Variable.withInt(createdAt),
          Variable.withString(student),
          Variable.withString(type),
          Variable<String>(group),
          Variable<int>(cycle),
          Variable<String>(period),
          Variable.withInt(amount),
          Variable.withString('u-owner'),
          Variable.withString(receipt),
        ],
        updates: {db.payments},
      );
      await pay(
        'p1',
        's1',
        'month',
        2000,
        'AAA-000001',
        at(10, 9),
        group: 'g1',
        cycle: 1,
      );
      await pay(
        'p2',
        's1',
        'registration',
        1000,
        'AAA-000002',
        at(11, 9),
        period: '2026-2027',
      );
      await pay(
        'p3',
        's2',
        'month',
        1500,
        'AAA-000003',
        at(12, 9),
        group: 'g1',
        cycle: 1,
      );
      await pay(
        'p4',
        's3',
        'month',
        1800,
        'AAA-000004',
        at(12, 10),
        group: 'g1',
        cycle: 1,
      );
    });
  }
  await tester.tap(find.text('المدفوعات').last);
  await tester.pumpAndSettle();
  if (child != null) {
    await tester.tap(find.widgetWithText(ClayChip, child));
    await tester.pumpAndSettle();
  }
  return runtime;
}

void main() {
  appTest('وليّ بلا أبناء: رسالة', (tester) async {
    await openPayments(tester, seed: false);
    expect(find.text('لا أبناء مرتبطون بحسابك'), findsOneWidget);
  });

  appTest('دفعات الابن وحده بوصفها ووصلها ومبلغها وتاريخها', (tester) async {
    await openPayments(tester, child: 'نور');
    expect(find.text('شهر — رياضيات · المجموعة 1 · الدورة 1'), findsOneWidget);
    expect(find.text('حقوق التسجيل — 2026-2027'), findsOneWidget);
    expect(find.textContaining('AAA-000001'), findsOneWidget);
    expect(find.textContaining('AAA-000002'), findsOneWidget);
    expect(find.text(Money.format(2000)), findsWidgets);
    expect(find.text(Money.format(1000)), findsWidgets);
    // دفعة أخيه وابن وليّ آخر لا تظهران.
    expect(find.textContaining('AAA-000003'), findsNothing);
    expect(find.textContaining('AAA-000004'), findsNothing);
    // الأحدث أولاً: حقوق التسجيل (يوم 11) قبل الشهر (يوم 10).
    final fee = tester.getTopLeft(find.textContaining('AAA-000002'));
    final month = tester.getTopLeft(find.textContaining('AAA-000001'));
    expect(fee.dy, lessThan(month.dy));
  });

  appTest('الابن الآخر: دفعته هو', (tester) async {
    await openPayments(tester);
    expect(find.textContaining('AAA-000003'), findsOneWidget);
    expect(find.textContaining('AAA-000001'), findsNothing);
    expect(find.text(Money.format(1500)), findsWidgets);
  });

  appTest('ابن بلا دفعات: رسالة', (tester) async {
    final runtime = await openPayments(tester, child: 'نور');
    await runDb(
      tester,
      () => runtime.db.customUpdate(
        "UPDATE payments SET deleted_at = 9 WHERE student_id = 's1'",
        updates: {runtime.db.payments},
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pumpAndSettle();
    expect(find.text('لا مدفوعات بعد'), findsOneWidget);
  });

  appTest('المتبقي: بند لكل مادة عليه فيها باقٍ', (tester) async {
    await openPayments(tester, child: 'نور');
    // الرياضيات سُدِّدت دورتها الأولى بالكامل، والفيزياء لم تُسدَّد.
    expect(find.text('المتبقي عليه'), findsOneWidget);
    expect(find.text('فيزياء · المجموعة 2'), findsOneWidget);
    expect(find.text('رياضيات · المجموعة 1'), findsNothing);
  });

  appTest('الضغط على دفعة يعرض وصلها PDF', (tester) async {
    final presenter = FakePdfPresenter();
    await openPayments(tester, child: 'نور', presenter: presenter);
    await tester.tap(find.textContaining('AAA-000001'));
    for (var i = 0; i < 40 && presenter.shown.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(presenter.shown, hasLength(1));
    final shown = presenter.shown.single;
    expect(shown.fileName, 'receipt-AAA-000001.pdf');
    expect(shown.title, 'وصل AAA-000001');
    expect(String.fromCharCodes(shown.bytes.take(5)), '%PDF-');
  });
}
