import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;

const paymentsViewer = TestAccount(
  id: 'u-pviewer',
  email: 'pviewer@school.local',
  password: 'pviewer-pass-1',
  role: UserRole.worker,
  entityId: 'w4',
  displayName: 'عامل عرض',
  permissions: '{"payments":["view"]}',
);

/// يبذر مجموعة وتلميذين (الأول عليه شهر 2000)، ثم يفتح تبويب المدفوعات.
Future<AppRuntime> openPayments(
  WidgetTester tester, {
  TestAccount account = owner,
  FakePdfPresenter? pdfPresenter,
}) async {
  final runtime = await openGroups(
    tester,
    account: account,
    pdfPresenter: pdfPresenter,
  );
  final db = runtime.db;
  await runDb(tester, () async {
    await GroupService(
      db,
      runtime.writer,
      ScheduleService(db),
      CycleService(db, runtime.writer),
    ).create(
      subjectId: 'math',
      teacherId: 't1',
      roomId: 'r1',
      slots: const [
        GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690),
      ],
      startDate: '2026-11-07',
    );
    final group = (await db.select(db.groups).get()).single;
    for (final (id, first) in [('s1', 'سمير'), ('s2', 'نور')]) {
      await db
          .into(db.students)
          .insert(
            StudentsCompanion.insert(
              id: id,
              createdAt: 1,
              updatedAt: 1,
              firstName: first,
              lastName: 'بن علي',
              parentPhone: '055012345${id.substring(1)}',
              qrCode: 'S-$id',
            ),
          );
    }
    await db
        .into(db.groupStudents)
        .insert(
          GroupStudentsCompanion.insert(
            id: 'gs-s1',
            createdAt: 1,
            updatedAt: 1,
            groupId: group.id,
            studentId: 's1',
            joinedAt: 1,
            monthlyPrice: 2000,
          ),
        );
  });
  await tester.tap(find.text('المدفوعات').last);
  await tester.pumpAndSettle();
  return runtime;
}

Future<void> startPayment(
  WidgetTester tester, {
  String student = 'سمير',
}) async {
  await tester.tap(find.widgetWithText(ClayButton, 'تسجيل دفعة'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, student);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  await tester.tap(find.text('$student بن علي'));
  await tester.pumpAndSettle();
}

Finder amountField() => find.descendant(
  of: find
      .ancestor(
        of: find.textContaining('المبلغ المدفوع'),
        matching: find.byType(Column),
      )
      .first,
  matching: find.byType(TextField),
);

void main() {
  appTest('لا مدفوعات: رسالة فارغة ومجموع اليوم صفر', (tester) async {
    await openPayments(tester);
    expect(find.text('لا مدفوعات بعد'), findsOneWidget);
    expect(find.text('استُلم اليوم'), findsOneWidget);
    expect(find.text(Money.format(0)), findsOneWidget);
  });

  appTest('تسجيل دفعة جزئية: وصل مرقَّم ثم تفاصيل ثم القائمة', (tester) async {
    final runtime = await openPayments(tester);
    await startPayment(tester);
    expect(find.text('رياضيات · المجموعة 1 · الدورة 1'), findsOneWidget);
    expect(find.text('الباقي ${Money.format(2000)}'), findsOneWidget);

    await tester.tap(find.text('رياضيات · المجموعة 1 · الدورة 1'));
    await tester.pumpAndSettle();
    // المبلغ مملوء بالباقي.
    expect(tester.widget<TextField>(amountField()).controller!.text, '2000');
    await tester.enterText(amountField(), '500');
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل الدفعة'));
    await tester.pumpAndSettle();

    // شاشة الوصل.
    expect(find.text('الوصل'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^[A-Z]{3}-000001$')), findsOneWidget);
    expect(find.text(Money.format(500)), findsOneWidget);
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('المدير'), findsOneWidget);
    // الباقي بعد الجزئية.
    expect(find.text(Money.format(1500)), findsOneWidget);

    final rows = await runDb(
      tester,
      () => runtime.db.select(runtime.db.payments).get(),
    );
    expect(rows.single.amount, 500);
    expect(rows.single.type, 'month');

    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.textContaining('000001'), findsOneWidget);
    expect(find.text('1 دفعة'), findsOneWidget);
    expect(find.text(Money.format(500)), findsWidgets);
  });

  appTest('الوصل PDF بمقاس A5 يُعرض للمعاينة والمشاركة', (tester) async {
    final presenter = FakePdfPresenter();
    await openPayments(tester, pdfPresenter: presenter);
    await startPayment(tester);
    await tester.tap(find.text('رياضيات · المجموعة 1 · الدورة 1'));
    await tester.pumpAndSettle();
    await tester.enterText(amountField(), '2000');
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل الدفعة'));
    await tester.pumpAndSettle();
    expect(find.text('مسدَّد بالكامل'), findsOneWidget);

    await tester.tap(find.widgetWithText(ClayButton, 'عرض الوصل وطباعته'));
    // بناء الملف يعمل في الزمن الحقيقي (قراءة الخط والإعدادات).
    for (var i = 0; i < 40 && presenter.shown.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(presenter.shown, hasLength(1));
    final shown = presenter.shown.single;
    expect(shown.fileName, matches(RegExp(r'^receipt-[A-Z]{3}-000001\.pdf$')));
    expect(shown.title, startsWith('وصل '));
    expect(String.fromCharCodes(shown.bytes.take(5)), '%PDF-');
    expect(shown.bytes.length, greaterThan(5000));
  });

  appTest('الباقي بعد الجزئية يظهر في المرة التالية', (tester) async {
    await openPayments(tester);
    await startPayment(tester);
    await tester.tap(find.text('رياضيات · المجموعة 1 · الدورة 1'));
    await tester.pumpAndSettle();
    await tester.enterText(amountField(), '500');
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل الدفعة'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();

    await startPayment(tester);
    expect(find.text('الباقي ${Money.format(1500)}'), findsOneWidget);
    expect(find.textContaining('دُفع ${Money.format(500)}'), findsOneWidget);
  });

  appTest('مبلغ يزيد عن الباقي أو صفر: خطأ ولا تسجيل', (tester) async {
    final runtime = await openPayments(tester);
    await startPayment(tester);
    await tester.tap(find.text('رياضيات · المجموعة 1 · الدورة 1'));
    await tester.pumpAndSettle();

    await tester.enterText(amountField(), '3000');
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل الدفعة'));
    await tester.pumpAndSettle();
    expect(find.textContaining('يزيد عن الباقي'), findsOneWidget);

    await tester.enterText(amountField(), '0');
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل الدفعة'));
    await tester.pumpAndSettle();
    expect(find.text('أدخل مبلغاً أكبر من صفر'), findsOneWidget);

    final rows = await runDb(
      tester,
      () => runtime.db.select(runtime.db.payments).get(),
    );
    expect(rows, isEmpty);
  });

  appTest('تلميذ لا شيء عليه', (tester) async {
    await openPayments(tester);
    await startPayment(tester, student: 'نور');
    expect(find.text('لا شيء مستحق'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'تسجيل الدفعة'), findsNothing);
  });

  appTest('تغيير التلميذ يعيد البحث', (tester) async {
    await openPayments(tester);
    await startPayment(tester);
    await tester.tap(find.text('تغيير'));
    await tester.pumpAndSettle();
    expect(find.text('نور بن علي'), findsOneWidget);
  });

  appTest('البحث والتصفية في القائمة', (tester) async {
    final runtime = await openPayments(tester);
    await runDb(tester, () async {
      final dues = DuesService(runtime.db, runtime.writer);
      await dues.recordMonthPayment(
        studentId: 's1',
        groupId: (await runtime.db.select(runtime.db.groups).get()).single.id,
        cycleNumber: 1,
        amount: 700,
        receivedBy: 'u-owner',
        receiptNumber: 'AAA-000001',
      );
      await dues.ensureRegistrationFee(
        studentId: 's1',
        periodKey: '2026-2027',
        amount: 1000,
      );
      await dues.payRegistrationFee(
        studentId: 's1',
        periodKey: '2026-2027',
        amount: 1000,
        receivedBy: 'u-owner',
        receiptNumber: 'AAA-000002',
      );
    });
    await tester.pumpAndSettle();
    expect(find.text('2 دفعة'), findsOneWidget);

    await tester.tap(find.widgetWithText(ClayChip, 'حقوق تسجيل'));
    await tester.pumpAndSettle();
    expect(find.text('1 دفعة'), findsOneWidget);
    expect(find.textContaining('AAA-000002'), findsOneWidget);

    await tester.tap(find.widgetWithText(ClayChip, 'الكل'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'AAA-000001');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('1 دفعة'), findsOneWidget);
    expect(find.byType(ClayListTile), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ClayListTile),
        matching: find.textContaining('AAA-000001'),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).first, 'لا أحد');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('لا نتائج مطابقة'), findsOneWidget);
  });

  appTest('صلاحية العرض فقط: لا زر تسجيل', (tester) async {
    await openPayments(tester, account: paymentsViewer);
    expect(find.widgetWithText(ClayButton, 'تسجيل دفعة'), findsNothing);
  });
}
