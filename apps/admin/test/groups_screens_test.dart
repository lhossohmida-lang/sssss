import 'package:admin/admin_tabs.dart';
import 'package:admin/screens/group_setup_screen.dart';
import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

const owner = TestAccount(
  id: 'u-owner',
  email: 'owner@school.local',
  password: 'owner-pass-1',
  role: UserRole.owner,
  displayName: 'المدير',
);

const viewer = TestAccount(
  id: 'u-worker',
  email: 'worker@school.local',
  password: 'worker-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'عامل',
  permissions: '{"groups":["view"]}',
);

/// يبذر مادة وأستاذين وقاعتين ثم يفتح تبويب المجموعات.
Future<AppRuntime> openGroups(
  WidgetTester tester, {
  TestAccount account = owner,
  FakePdfPresenter? pdfPresenter,
  AccountProvisioner? provisioner,
}) async {
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: [account],
    pages: adminPages,
    pdfPresenter: pdfPresenter,
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
    for (final id in ['t1', 't2']) {
      await db
          .into(db.teachers)
          .insert(
            TeachersCompanion.insert(
              id: id,
              createdAt: 1,
              updatedAt: 1,
              name: id == 't1' ? 'كمال' : 'ياسين',
              phone: '066000000${id.substring(1)}',
              email: '$id@school.local',
              qrCode: 'T-$id',
              ratePerStudent: Value(id == 't1' ? 800 : 0),
            ),
          );
      await db
          .into(db.teacherSubjects)
          .insert(
            TeacherSubjectsCompanion.insert(
              teacherId: id,
              subjectId: 'math',
              updatedAt: 1,
            ),
          );
    }
    await db.batch((b) {
      b.insertAll(db.rooms, [
        RoomsCompanion.insert(
          id: 'r1',
          createdAt: 1,
          updatedAt: 1,
          name: 'القاعة 1',
          capacity: const Value(30),
        ),
        RoomsCompanion.insert(
          id: 'r2',
          createdAt: 1,
          updatedAt: 1,
          name: 'القاعة 2',
          capacity: const Value(20),
        ),
      ]);
    });
  });
  // من لا يملك صلاحية المجموعات لا يرى تبويبها.
  if (find.text('الأفواج').evaluate().isNotEmpty) {
    await tester.tap(find.text('الأفواج').last);
    await tester.pumpAndSettle();
  }
  return runtime;
}

/// يختار [option] من القائمة المنسدلة ذات التسمية [label].
Future<void> pick(WidgetTester tester, String label, String option) async {
  final dropdown = find.descendant(
    of: find
        .ancestor(of: find.text(label), matching: find.byType(Column))
        .first,
    matching: find.byWidgetPredicate((w) => w is DropdownButton),
  );
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> openForm(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ClayButton, 'إنشاء فوج'));
  await tester.pumpAndSettle();
  tester.view.physicalSize = const Size(420, 3200);
  await tester.pumpAndSettle();
}

Future<void> fillBasics(WidgetTester tester) async {
  await pick(tester, 'المادة', 'رياضيات');
  await pick(tester, 'الأستاذ', 'كمال');
  await pick(tester, 'القاعة الافتراضية', 'القاعة 1 (30)');
}

Future<void> submit(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ClayButton, 'إنشاء الفوج'));
  await tester.pumpAndSettle();
}

/// بعد إنشاء الفوج تُفتح صفحة إعداده (تلاميذه وحضورهم وتسديدهم)؛ «تم» يعيد
/// إلى القائمة.
Future<void> finishSetup(WidgetTester tester) async {
  expect(find.text('إعداد الفوج'), findsOneWidget);
  await tester.tap(find.widgetWithText(ClayButton, 'تم'));
  await tester.pumpAndSettle();
}

void main() {
  appTest('قائمة فارغة برسالة وزر إنشاء', (tester) async {
    await openGroups(tester);
    expect(find.text('لا توجد أفواج بعد'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'إنشاء فوج'), findsOneWidget);
  });

  appTest('إنشاء فوج: تظهر في القائمة بجدولها وتُولَّد حصصها', (tester) async {
    final runtime = await openGroups(tester);
    await openForm(tester);
    await fillBasics(tester);
    // نصيب الأستاذ الافتراضي من ملفه.
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find
                  .ancestor(
                    of: find.text('نصيب الأستاذ لكل تلميذ (دج)'),
                    matching: find.byType(Column),
                  )
                  .first,
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      '800',
    );
    await pick(tester, 'اليوم', 'الثلاثاء');
    await submit(tester);

    // بعد الإنشاء تُفتح صفحة إعداد الفوج لإضافة تلاميذه من نفس المكان.
    expect(find.text('رياضيات · الفوج 1'), findsOneWidget);
    expect(find.text('لا تلاميذ في الفوج بعد.'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'إضافة تلميذ'), findsOneWidget);
    await finishSetup(tester);

    expect(find.text('الفوج 1 · رياضيات'), findsOneWidget);
    expect(find.textContaining('كمال · القاعة 1 · 0 تلميذ'), findsOneWidget);
    expect(find.textContaining('الثلاثاء 10:00–11:30'), findsOneWidget);
    final sessions = await runDb(
      tester,
      () => runtime.db.select(runtime.db.sessions).get(),
    );
    expect(sessions, hasLength(8));
  });

  /// يغيّر «تاريخ أول حصة» في نموذج الإنشاء إلى اليوم [day] من الشهر الذي يبعد عن الشهر
  /// الحالي [months] شهراً (سالباً للماضي).
  Future<void> pickFirstDate(
    WidgetTester tester, {
    required int months,
    required int day,
  }) async {
    await tester.tap(find.widgetWithText(ClayButton, 'تغيير التاريخ'));
    await tester.pumpAndSettle();
    for (var i = 0; i < months.abs(); i++) {
      await tester.tap(
        find.byTooltip(months > 0 ? 'الشهر التالي' : 'الشهر السابق'),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(
      find.descendant(of: find.byType(ClayDialog), matching: find.text('$day')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'تأكيد'));
    await tester.pumpAndSettle();
  }

  appTest('تاريخ أول حصة بعد اليوم: تُولَّد حصص الدورة الثماني منه', (
    tester,
  ) async {
    final runtime = await openGroups(tester);
    await openForm(tester);
    await fillBasics(tester);
    await pick(tester, 'اليوم', 'الثلاثاء');
    final now = DateTime.now();
    expect(find.text(DateKey.of(now)), findsOneWidget);
    await pickFirstDate(tester, months: 1, day: 15);
    final chosen = DateTime(now.year, now.month + 1, 15);
    expect(find.text(DateKey.of(chosen)), findsOneWidget);
    expect(find.textContaining('التاريخ قبل اليوم'), findsNothing);
    await submit(tester);
    await finishSetup(tester);

    final sessions =
        await runDb(tester, () => runtime.db.select(runtime.db.sessions).get())
          ..sort((a, b) => a.date.compareTo(b.date));
    expect(sessions, hasLength(8));
    // أول حصة أول ثلاثاء في أو بعد التاريخ المختار، ثم كل أسبوع.
    final first = DateKey.parse(sessions.first.date);
    expect(first.weekday, DateTime.tuesday);
    expect(first.isBefore(chosen), isFalse);
    expect(first.difference(chosen).inDays, lessThan(7));
    expect(sessions.every((s) => s.closedAt == null), isTrue);
  });

  appTest(
    'تاريخ أول حصة قبل اليوم: يُبرمج الفوج من اليوم ويُنقل التاريخ للحضور السابق',
    (tester) async {
      final runtime = await openGroups(tester);
      await openForm(tester);
      await fillBasics(tester);
      await pick(tester, 'اليوم', 'الثلاثاء');
      await pickFirstDate(tester, months: -1, day: 15);
      expect(find.textContaining('التاريخ قبل اليوم'), findsOneWidget);
      await submit(tester);
      expect(find.text('إعداد الفوج'), findsOneWidget);

      // حصص ماضية لا تُنشأ مفتوحة، فكلها من اليوم فصاعداً.
      final today = DateKey.of(DateTime.now());
      final sessions = await runDb(
        tester,
        () => runtime.db.select(runtime.db.sessions).get(),
      );
      expect(sessions, hasLength(8));
      expect(sessions.every((s) => s.date.compareTo(today) >= 0), isTrue);

      // وينتقل التاريخ إلى «الحضور السابق» فتُبنى منه الحصص المقررة (بعد إضافة تلميذ).
      final now = DateTime.now();
      final chosen = DateTime(now.year, now.month - 1, 15);
      expect(
        find.textContaining('تاريخ أول حصة الذي أدخلته: ${DateKey.of(chosen)}'),
        findsOneWidget,
      );
      final groupId = sessions.first.groupId;
      await runDb(tester, () async {
        final db = runtime.db;
        await db
            .into(db.students)
            .insert(
              StudentsCompanion.insert(
                id: 's1',
                createdAt: 1,
                updatedAt: 1,
                firstName: 'سمير',
                lastName: 'بن علي',
                parentPhone: '0550123456',
                qrCode: 'S-s1',
              ),
            );
        await db
            .into(db.groupStudents)
            .insert(
              GroupStudentsCompanion.insert(
                id: 'gs-s1',
                createdAt: 1,
                updatedAt: 1,
                groupId: groupId,
                studentId: 's1',
                joinedAt: 1,
                monthlyPrice: 2000,
              ),
            );
      });
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
          .invalidate(groupSetupRowsProvider(groupId));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'تسجيل الحضور السابق'));
      await tester.pumpAndSettle();
      expect(find.text('الحضور السابق · الفوج 1'), findsOneWidget);
      expect(find.text(DateKey.of(chosen)), findsWidgets);
      expect(find.text('الحصص المقررة'), findsOneWidget);
      expect(find.byType(ClayCheckbox), findsWidgets);
    },
  );

  appTest('تاريخ أول حصة بعيد جداً في الماضي يُرفض ولا يُنشأ فوج', (
    tester,
  ) async {
    final runtime = await openGroups(tester);
    await openForm(tester);
    await fillBasics(tester);
    await pickFirstDate(tester, months: -5, day: 1);
    await submit(tester);
    expect(find.textContaining('تاريخ بعيد في الماضي'), findsOneWidget);
    expect(find.text('إنشاء فوج'), findsWidgets);
    expect(
      await runDb(tester, () => runtime.db.select(runtime.db.groups).get()),
      isEmpty,
    );
  });

  appTest('بيانات ناقصة: أخطاء المادة والأستاذ', (tester) async {
    await openGroups(tester);
    await openForm(tester);
    await submit(tester);
    expect(find.text('اختر المادة'), findsWidgets);
    expect(find.text('اختر الأستاذ'), findsOneWidget);
    expect(find.text('إنشاء فوج'), findsWidgets);
  });

  appTest('الأستاذ لا يظهر إلا بعد اختيار المادة، ومن يدرّسها فقط', (
    tester,
  ) async {
    await openGroups(tester);
    await openForm(tester);
    expect(find.text('اختر المادة أولاً'), findsOneWidget);
    await pick(tester, 'المادة', 'رياضيات');
    await tester.tap(
      find.descendant(
        of: find
            .ancestor(of: find.text('الأستاذ'), matching: find.byType(Column))
            .first,
        matching: find.byWidgetPredicate((w) => w is DropdownButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('كمال'), findsWidgets);
    expect(find.text('ياسين'), findsWidgets);
  });

  appTest('تعارض القاعة يظهر لحظياً، وتُقترح قاعة متاحة', (tester) async {
    final runtime = await openGroups(tester);
    // مجموعة قائمة: كمال في القاعة 1 يوم السبت 10:00.
    await runDb(tester, () async {
      final service = GroupService(
        runtime.db,
        runtime.writer,
        ScheduleService(runtime.db),
        CycleService(runtime.db, runtime.writer),
      );
      await service.create(
        subjectId: 'math',
        teacherId: 't1',
        roomId: 'r1',
        slots: const [
          GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690),
        ],
        startDate: '2026-11-07',
      );
    });
    await openForm(tester);
    await pick(tester, 'المادة', 'رياضيات');
    await pick(tester, 'الأستاذ', 'ياسين');
    await pick(tester, 'القاعة الافتراضية', 'القاعة 1 (30)');
    // الخانة الافتراضية: السبت 10:00–11:30 في القاعة 1 = تعارض.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.textContaining('القاعة محجوزة'), findsOneWidget);

    await tester.tap(find.text('اقتراح قاعة متاحة 1'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.textContaining('القاعة محجوزة'), findsNothing);

    await submit(tester);
    await finishSetup(tester);
    expect(find.text('الفوج 2 · رياضيات'), findsOneWidget);
  });

  appTest('خانة غير صالحة تُرفض برسالة', (tester) async {
    await openGroups(tester);
    await openForm(tester);
    await fillBasics(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة خانة'));
    await tester.pumpAndSettle();
    // الخانتان متطابقتان: الثانية تتداخل مع الأولى.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.textContaining('تتداخل مع خانة 1'), findsOneWidget);
    await submit(tester);
    expect(find.text('إنشاء فوج'), findsWidgets);
    expect(find.textContaining('تتداخل مع خانة 1'), findsOneWidget);
    // حذف الخانة الثانية يزيل الخطأ.
    await tester.tap(find.byTooltip('حذف الخانة 2'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.textContaining('تتداخل مع خانة 1'), findsNothing);
  });

  appTest('منتقي الوقت: تغيير بداية الخانة يحرّك نهايتها بنفس المدة', (
    tester,
  ) async {
    await openGroups(tester);
    await openForm(tester);
    expect(find.text('من 10:00'), findsOneWidget);
    expect(find.text('إلى 11:30'), findsOneWidget);
    await tester.tap(find.text('من 10:00'));
    await tester.pumpAndSettle();
    await pick(tester, 'الساعة', '14');
    await tester.tap(find.widgetWithText(ClayButton, 'تأكيد'));
    await tester.pumpAndSettle();
    expect(find.text('من 14:00'), findsOneWidget);
    expect(find.text('إلى 15:30'), findsOneWidget);
  });

  appTest('تعديل فوج: الأستاذ والجدول، والمادة وعدد الحصص مقفلان', (
    tester,
  ) async {
    final runtime = await openGroups(tester);
    await runDb(tester, () async {
      await GroupService(
        runtime.db,
        runtime.writer,
        ScheduleService(runtime.db),
        CycleService(runtime.db, runtime.writer),
      ).create(
        subjectId: 'math',
        teacherId: 't1',
        roomId: 'r1',
        slots: const [
          GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690),
        ],
        startDate: '2026-11-07',
      );
    });
    await tester.tap(find.byTooltip('تعديل الفوج 1'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(420, 3200);
    await tester.pumpAndSettle();
    expect(find.text('تعديل الفوج'), findsOneWidget);
    expect(
      find.text('لا يتغير بعد الإنشاء لأنه أساس المستحقات'),
      findsOneWidget,
    );
    final subject = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>).first,
    );
    expect(subject.onChanged, isNull);

    await pick(tester, 'الأستاذ', 'ياسين');
    await pick(tester, 'القاعة الافتراضية', 'القاعة 2 (20)');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ التعديلات'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ياسين · القاعة 2'), findsOneWidget);
  });

  appTest('الأرشفة بعد التأكيد تفرغ القائمة', (tester) async {
    final runtime = await openGroups(tester);
    await runDb(tester, () async {
      await GroupService(
        runtime.db,
        runtime.writer,
        ScheduleService(runtime.db),
        CycleService(runtime.db, runtime.writer),
      ).create(
        subjectId: 'math',
        teacherId: 't1',
        slots: const [
          GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690),
        ],
        startDate: '2026-11-07',
      );
    });
    await tester.tap(find.byTooltip('أرشفة الفوج 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'أرشفة'));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد أفواج بعد'), findsOneWidget);
  });

  appTest('صلاحية العرض فقط: بلا إنشاء ولا أرشفة', (tester) async {
    final runtime = await openGroups(tester, account: viewer);
    expect(find.widgetWithText(ClayButton, 'إنشاء فوج'), findsNothing);
    await runDb(tester, () async {
      await GroupService(
        runtime.db,
        runtime.writer,
        ScheduleService(runtime.db),
        CycleService(runtime.db, runtime.writer),
      ).create(
        subjectId: 'math',
        teacherId: 't1',
        slots: const [
          GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690),
        ],
        startDate: '2026-11-07',
      );
    });
    expect(find.text('الفوج 1 · رياضيات'), findsOneWidget);
    expect(find.byTooltip('أرشفة الفوج 1'), findsNothing);
    expect(find.byTooltip('تعديل الفوج 1'), findsNothing);
    expect(find.byTooltip('حذف الفوج 1'), findsNothing);
  });

  Future<void> seedGroup(WidgetTester tester, AppRuntime runtime) =>
      runDb(tester, () async {
        await GroupService(
          runtime.db,
          runtime.writer,
          ScheduleService(runtime.db),
          CycleService(runtime.db, runtime.writer),
        ).create(
          subjectId: 'math',
          teacherId: 't1',
          roomId: 'r1',
          slots: const [
            GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690),
          ],
          startDate: '2026-11-07',
        );
      });

  appTest('حذف فوج من القائمة بعد التأكيد، والإلغاء لا يحذف', (tester) async {
    final runtime = await openGroups(tester);
    await seedGroup(tester, runtime);
    await tester.tap(find.byTooltip('حذف الفوج 1'));
    await tester.pumpAndSettle();
    expect(find.text('حذف الفوج'), findsOneWidget);
    expect(find.textContaining('أرشفه بدل ذلك'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('الفوج 1 · رياضيات'), findsOneWidget);

    await tester.tap(find.byTooltip('حذف الفوج 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حذف'));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد أفواج بعد'), findsOneWidget);
    final groups = await runDb(
      tester,
      () => runtime.db.select(runtime.db.groups).get(),
    );
    expect(groups.single.deletedAt, isNotNull);
    final sessions = await runDb(
      tester,
      () => (runtime.db.select(
        runtime.db.sessions,
      )..where((s) => s.deletedAt.isNull())).get(),
    );
    expect(sessions, isEmpty);
  });

  appTest('فوج له مدفوعات لا يُحذف: تظهر الرسالة وتبقى بياناته', (
    tester,
  ) async {
    final runtime = await openGroups(tester);
    await seedGroup(tester, runtime);
    await runDb(tester, () async {
      final db = runtime.db;
      final group = (await db.select(db.groups).get()).single;
      await db
          .into(db.students)
          .insert(
            StudentsCompanion.insert(
              id: 's1',
              createdAt: 1,
              updatedAt: 1,
              firstName: 'سمير',
              lastName: 'بن علي',
              parentPhone: '0550123456',
              qrCode: 'S-s1',
            ),
          );
      await db
          .into(db.payments)
          .insert(
            PaymentsCompanion.insert(
              id: 'p1',
              createdAt: 1,
              updatedAt: 1,
              studentId: 's1',
              type: 'month',
              amount: 2000,
              receivedBy: 'u1',
              receiptNumber: 'A-000001',
              groupId: Value(group.id),
            ),
          );
    });
    await tester.tap(find.byTooltip('حذف الفوج 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حذف'));
    await tester.pumpAndSettle();
    expect(find.textContaining('لا يمكن حذف الفوج 1'), findsOneWidget);
    expect(find.textContaining('مدفوعات مسجَّلة'), findsOneWidget);
    expect(find.text('الفوج 1 · رياضيات'), findsOneWidget);
    final group = (await runDb(
      tester,
      () => runtime.db.select(runtime.db.groups).get(),
    )).single;
    expect(group.deletedAt, isNull);
  });

  appTest('زر الحذف بصلاحية الحذف وحدها', (tester) async {
    final runtime = await openGroups(
      tester,
      account: const TestAccount(
        id: 'u-worker',
        email: 'worker@school.local',
        password: 'worker-pass-1',
        role: UserRole.worker,
        entityId: 'w1',
        displayName: 'عامل',
        permissions: '{"groups":["view","delete"]}',
      ),
    );
    await seedGroup(tester, runtime);
    expect(find.byTooltip('حذف الفوج 1'), findsOneWidget);
    expect(find.byTooltip('تعديل الفوج 1'), findsNothing);
    expect(find.byTooltip('أرشفة الفوج 1'), findsNothing);
  });

  appTest('حذف الفوج من نموذج التعديل يعيد إلى القائمة', (tester) async {
    final runtime = await openGroups(tester);
    await seedGroup(tester, runtime);
    await tester.tap(find.byTooltip('تعديل الفوج 1'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(420, 3200);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حذف الفوج'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حذف'));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد أفواج بعد'), findsOneWidget);
    expect(find.text('تعديل الفوج'), findsNothing);
  });

  appTest('نموذج الإنشاء بلا زر حذف', (tester) async {
    await openGroups(tester);
    await openForm(tester);
    expect(find.widgetWithText(ClayButton, 'حذف الفوج'), findsNothing);
  });
}
