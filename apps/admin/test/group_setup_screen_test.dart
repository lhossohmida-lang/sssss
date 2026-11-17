import 'package:admin/admin_tabs.dart';
import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

const _owner = TestAccount(
  id: 'u-owner',
  email: 'owner@school.local',
  password: 'owner-pass-1',
  role: UserRole.owner,
  displayName: 'المدير',
);

/// عامل يرى الأفواج ويُضيف تلاميذ فقط: لا استلام مال ولا حضور سابق.
const _studentsOnly = TestAccount(
  id: 'u-worker',
  email: 'worker@school.local',
  password: 'worker-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'عامل',
  permissions: '{"groups":["view"],"students":["add"]}',
);

/// عامل يرى الأفواج فقط: لا زر إعداد في تفاصيل الفوج.
const _viewOnly = TestAccount(
  id: 'u-viewer',
  email: 'viewer@school.local',
  password: 'viewer-pass-1',
  role: UserRole.worker,
  entityId: 'w2',
  displayName: 'مشاهد',
  permissions: '{"groups":["view"]}',
);

const _setupButton = 'إعداد الفوج: تلاميذ وحضور وتسديد';

class Opened {
  Opened(this.runtime, this.provisioner);

  final AppRuntime runtime;
  final FakeAccountProvisioner provisioner;
}

/// يدخل، يبذر مادة وأستاذاً وفوجاً، ثم يفتح تفاصيل الفوج (ومنها صفحة الإعداد).
Future<Opened> openDetails(
  WidgetTester tester, {
  TestAccount account = _owner,
  bool openSetup = true,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  final provisioner = FakeAccountProvisioner();
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: [account],
    pages: adminPages,
    provisioner: provisioner,
  );
  await loginWith(tester, account.email, account.password);
  final db = runtime.db;
  await runDb(tester, () async {
    await db
        .into(db.subjects)
        .insert(
          SubjectsCompanion.insert(
            id: 'math',
            createdAt: 1,
            updatedAt: 1,
            name: 'رياضيات',
            monthlyPrice: const Value(2000),
          ),
        );
    await db
        .into(db.teachers)
        .insert(
          TeachersCompanion.insert(
            id: 't1',
            createdAt: 1,
            updatedAt: 1,
            name: 'كمال',
            phone: '0660000001',
            email: 't1@school.local',
            qrCode: 'T-t1',
          ),
        );
    await db
        .into(db.teacherSubjects)
        .insert(
          TeacherSubjectsCompanion.insert(
            teacherId: 't1',
            subjectId: 'math',
            updatedAt: 1,
          ),
        );
    await GroupService(
      db,
      runtime.writer,
      ScheduleService(db),
      CycleService(db, runtime.writer),
    ).create(
      subjectId: 'math',
      teacherId: 't1',
      slots: const [
        GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690),
      ],
      startDate: '2026-11-07',
    );
  });
  await tester.tap(find.text('الأفواج').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('الفوج 1 · رياضيات'));
  await tester.pumpAndSettle();
  if (openSetup) {
    await tester.tap(find.widgetWithText(ClayButton, _setupButton));
    await tester.pumpAndSettle();
  }
  return Opened(runtime, provisioner);
}

Finder fieldOf(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

/// يفتح نموذج «إضافة تلميذ» ويملأ بياناته.
Future<void> openAddForm(
  WidgetTester tester, {
  String first = 'أحمد',
  String phone = '0550123456',
}) async {
  await tester.tap(find.widgetWithText(ClayButton, 'إضافة تلميذ'));
  await tester.pumpAndSettle();
  await fillPeople(tester, first: first, phone: phone);
}

Future<void> fillPeople(
  WidgetTester tester, {
  String first = 'أحمد',
  String phone = '0550123456',
}) async {
  await tester.enterText(fieldOf('الاسم'), first);
  await tester.enterText(fieldOf('اللقب'), 'بن علي');
  await tester.enterText(fieldOf('اسم الوليّ'), 'علي بن علي');
  await tester.enterText(fieldOf('هاتف الوليّ'), phone);
}

Future<void> save(WidgetTester tester, [String label = 'حفظ']) async {
  await tester.tap(find.widgetWithText(ClayButton, label));
  await tester.pumpAndSettle();
}

void main() {
  appTest('تفاصيل الفوج: زر الإعداد يفتح الصفحة بلا تلاميذ بعد', (
    tester,
  ) async {
    await openDetails(tester);
    expect(find.text('إعداد الفوج'), findsOneWidget);
    expect(find.text('رياضيات · الفوج 1'), findsOneWidget);
    expect(find.text('1. التلاميذ'), findsOneWidget);
    expect(find.text('2. الحضور السابق'), findsOneWidget);
    expect(find.text('لا تلاميذ في الفوج بعد.'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'إضافة تلميذ'), findsOneWidget);
    // الحضور السابق يحتاج تلميذاً واحداً على الأقل.
    expect(
      tester
          .widget<ClayButton>(
            find.widgetWithText(ClayButton, 'تسجيل الحضور السابق'),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('أضف تلميذاً واحداً على الأقل أولاً.'), findsOneWidget);
  });

  appTest('تلميذ غير مسدّد: يظهر بباقي الدورة وتصل وليّه بياناته', (
    tester,
  ) async {
    final o = await openDetails(tester);
    await openAddForm(tester);
    await save(tester);

    expect(find.text('إضافة تلميذ إلى الفوج'), findsNothing, reason: 'أُغلق');
    expect(find.text('أحمد بن علي'), findsOneWidget);
    expect(find.text('الوليّ 0550123456'), findsOneWidget);
    expect(find.text('الباقي ${Money.format(2000)}'), findsOneWidget);
    expect(
      find.textContaining('أُضيف أحمد بن علي وأُرسلت بيانات دخول وليّه برسالة'),
      findsOneWidget,
    );
    expect(find.text('لا تلاميذ في الفوج بعد.'), findsNothing);
    expect(o.provisioner.created, hasLength(1));

    final queued = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.smsQueue).get(),
    );
    expect(
      queued.where((m) => m.kind == SmsTemplateKeys.accountCreated),
      hasLength(1),
      reason: 'بيانات الدخول تُرسل تلقائياً',
    );
    // صار الحضور السابق متاحاً.
    expect(
      tester
          .widget<ClayButton>(
            find.widgetWithText(ClayButton, 'تسجيل الحضور السابق'),
          )
          .onPressed,
      isNotNull,
    );
  });

  appTest('مسدّدة كاملة: دفعة بوصل مرقّم وباقٍ صفر وتصل الوليّ رسالة وصل', (
    tester,
  ) async {
    final o = await openDetails(tester);
    await openAddForm(tester);
    await tester.tap(find.text('مسدّدة كاملة (${Money.format(2000)})'));
    await tester.pumpAndSettle();
    await save(tester);

    expect(find.text('مسدّدة'), findsOneWidget);
    expect(find.textContaining('الباقي'), findsNothing);
    expect(find.text('تسديد'), findsNothing);
    expect(
      find.textContaining('وسُدِّد ${Money.format(2000)}'),
      findsOneWidget,
    );
    final payments = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.payments).get(),
    );
    expect(payments, hasLength(1));
    expect(payments.single.amount, 2000);
    expect(payments.single.type, PaymentType.month.code);
    expect(payments.single.receiptNumber, isNotEmpty);
    final queued = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.smsQueue).get(),
    );
    expect(
      queued.where((m) => m.kind == SmsTemplateKeys.paymentReceipt),
      hasLength(1),
    );
  });

  appTest('سُدِّد جزء: يطلب المبلغ، ثم يبقى الباقي ويُسدَّد لاحقاً بوصل ثان', (
    tester,
  ) async {
    final o = await openDetails(tester);
    await openAddForm(tester);
    await tester.tap(find.text('سُدِّد جزء منها'));
    await tester.pumpAndSettle();

    // بلا مبلغ: خطأ ولا يُضاف شيء.
    await save(tester);
    expect(find.text('أدخل المبلغ المسدَّد'), findsOneWidget);
    expect(find.text('أحمد بن علي'), findsNothing);

    await tester.enterText(fieldOf('المبلغ المسدَّد (دج)'), '750');
    await save(tester);
    expect(find.text('أحمد بن علي'), findsOneWidget);
    expect(find.text('الباقي ${Money.format(1250)}'), findsOneWidget);

    // التسديد لاحقاً: المقترح هو الباقي كاملاً، والزيادة مرفوضة.
    await tester.tap(find.widgetWithText(TextButton, 'تسديد'));
    await tester.pumpAndSettle();
    expect(find.text('تسديد أحمد بن علي'), findsOneWidget);
    expect(
      tester.widget<TextField>(fieldOf('المبلغ (دج)')).controller!.text,
      '1250',
    );
    await tester.enterText(fieldOf('المبلغ (دج)'), '9000');
    await save(tester, 'تسديد');
    expect(find.textContaining('المبلغ يزيد'), findsOneWidget);
    await tester.enterText(fieldOf('المبلغ (دج)'), '1250');
    await save(tester, 'تسديد');

    expect(find.text('مسدّدة'), findsOneWidget);
    expect(find.text('سُجّلت الدفعة وأُرسل وصلها إلى الوليّ'), findsOneWidget);
    final payments = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.payments).get(),
    );
    expect(payments.map((p) => p.amount).toList()..sort(), [750, 1250]);
    expect(
      payments.map((p) => p.receiptNumber).toSet(),
      hasLength(2),
      reason: 'لكل دفعة وصلها المرقّم',
    );
  });

  appTest(
    'حفظ وإضافة تلميذ آخر: يبقى النموذج ويحتفظ بوليّه وإخوته بحساب واحد',
    (tester) async {
      final o = await openDetails(tester);
      await openAddForm(tester);
      await save(tester, 'حفظ وإضافة تلميذ آخر');

      // النموذج ما زال مفتوحاً: الاسم واللقب فارغان والوليّ محفوظ.
      expect(find.text('إضافة تلميذ إلى الفوج'), findsOneWidget);
      expect(tester.widget<TextField>(fieldOf('الاسم')).controller!.text, '');
      expect(tester.widget<TextField>(fieldOf('اللقب')).controller!.text, '');
      expect(
        tester.widget<TextField>(fieldOf('هاتف الوليّ')).controller!.text,
        '0550123456',
      );

      await tester.enterText(fieldOf('الاسم'), 'سعاد');
      await tester.enterText(fieldOf('اللقب'), 'بن علي');
      await save(tester);

      expect(find.text('أحمد بن علي'), findsOneWidget);
      expect(find.text('سعاد بن علي'), findsOneWidget);
      expect(
        o.provisioner.created,
        hasLength(1),
        reason: 'إخوة بوليّ واحد يشتركون في حساب واحد',
      );
    },
  );

  appTest('بيانات ناقصة: أخطاء الحقول ولا يُضاف تلميذ', (tester) async {
    final o = await openDetails(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة تلميذ'));
    await tester.pumpAndSettle();
    await save(tester);
    expect(find.text('أدخل الاسم'), findsOneWidget);
    expect(find.text('أدخل اللقب'), findsOneWidget);
    expect(find.text('أدخل اسم الوليّ'), findsOneWidget);
    expect(find.textContaining('يبدأ بـ 05 أو 06 أو 07'), findsOneWidget);
    expect(find.text('إضافة تلميذ إلى الفوج'), findsOneWidget);
    expect(o.provisioner.created, isEmpty);
    final students = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.students).get(),
    );
    expect(students, isEmpty);
  });

  appTest('الحضور السابق: الزر يفتح شاشته ويعيد إلى الصفحة', (tester) async {
    await openDetails(tester);
    await openAddForm(tester);
    await save(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل الحضور السابق'));
    await tester.pumpAndSettle();
    expect(find.text('الحضور السابق · الفوج 1'), findsOneWidget);

    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('إعداد الفوج'), findsOneWidget);
  });

  appTest('«تم» يعود إلى تفاصيل الفوج', (tester) async {
    await openDetails(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'تم'));
    await tester.pumpAndSettle();
    expect(find.text('إعداد الفوج'), findsNothing);
    expect(find.text('الفوج 1'), findsWidgets);
    expect(find.widgetWithText(ClayButton, _setupButton), findsOneWidget);
  });

  appTest('عامل يُضيف تلاميذ فقط: لا دفع في النموذج ولا تسديد ولا حضور سابق', (
    tester,
  ) async {
    final o = await openDetails(tester, account: _studentsOnly);
    expect(find.text('2. الحضور السابق'), findsNothing);
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة تلميذ'));
    await tester.pumpAndSettle();
    expect(find.text('الدورة الحالية'), findsNothing);
    expect(find.text('غير مسدّدة'), findsNothing);

    await fillPeople(tester);
    await save(tester);
    expect(find.text('أحمد بن علي'), findsOneWidget);
    expect(find.text('الباقي ${Money.format(2000)}'), findsOneWidget);
    expect(find.text('تسديد'), findsNothing, reason: 'لا صلاحية لاستلام المال');
    final payments = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.payments).get(),
    );
    expect(payments, isEmpty);
  });

  appTest('عامل يرى الأفواج فقط: لا زر إعداد في التفاصيل', (tester) async {
    await openDetails(tester, account: _viewOnly, openSetup: false);
    expect(find.widgetWithText(ClayButton, _setupButton), findsNothing);
    expect(find.text('الفوج 1'), findsWidgets);
  });
}
