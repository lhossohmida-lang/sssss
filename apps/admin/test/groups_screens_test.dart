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

import 'support/groups_nav.dart';

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

/// الحقل النصي ذو التسمية [label] في النموذج.
Finder fieldOf(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

/// نص الحقل ذي التسمية [label].
String textOf(WidgetTester tester, String label) =>
    tester.widget<TextField>(fieldOf(label)).controller!.text;

/// يكتب [value] في الحقل ذي التسمية [label].
Future<void> typeIn(WidgetTester tester, String label, String value) async {
  await tester.enterText(fieldOf(label), value);
  await tester.pumpAndSettle();
}

const priceLabel = 'سعر الشهر للتلميذ (دج)';
const rateLabel = 'نصيب الأستاذ لكل تلميذ (دج)';

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
    // نصيب الأستاذ المقترح من ملفه، وسعر الفوج المقترح من سعر المادة.
    expect(textOf(tester, rateLabel), '800');
    expect(textOf(tester, priceLabel), '2000');
    await pick(tester, 'اليوم', 'الثلاثاء');
    await submit(tester);

    // بعد الإنشاء تُفتح صفحة إعداد الفوج لإضافة تلاميذه من نفس المكان.
    expect(find.text('رياضيات · الفوج 1'), findsOneWidget);
    expect(find.text('لا تلاميذ في الفوج بعد.'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'إضافة تلميذ'), findsOneWidget);
    await finishSetup(tester);

    await openGroupList(tester);
    expect(find.text('فوج 1'), findsOneWidget);
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
    // ياسين بلا نصيب افتراضي في ملفه: يُكتب عند إنشاء الفوج (لازم).
    await typeIn(tester, rateLabel, '900');
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
    await openGroupList(tester);
    expect(find.text('فوج 2'), findsOneWidget);
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
    await openGroupList(tester);
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

  appTest('إنشاء فوج بسعره ومبلغ أستاذه: يُحفظان كما كُتبا ويظهران في إعداده', (
    tester,
  ) async {
    final runtime = await openGroups(tester);
    await openForm(tester);
    await fillBasics(tester);
    // سعر الفوج غير سعر مادته (فوج متوسط غير فوج ابتدائي)، ونصيب الأستاذ غير الافتراضي.
    await typeIn(tester, priceLabel, '3500');
    await typeIn(tester, rateLabel, '1200');
    await pick(tester, 'اليوم', 'الثلاثاء');
    await submit(tester);

    expect(
      find.textContaining('سعر الشهر للتلميذ: ${Money.format(3500)}'),
      findsOneWidget,
    );
    expect(
      find.textContaining('نصيب الأستاذ لكل تلميذ: ${Money.format(1200)}'),
      findsOneWidget,
    );
    final groups = await runDb(
      tester,
      () => runtime.db.select(runtime.db.groups).get(),
    );
    expect(groups.single.monthlyPrice, 3500);
    expect(groups.single.ratePerStudent, 1200);
  });

  appTest('السعر ومبلغ الأستاذ لازمان عند إنشاء الفوج', (tester) async {
    final runtime = await openGroups(tester);
    await openForm(tester);
    await fillBasics(tester);
    await typeIn(tester, priceLabel, '');
    await typeIn(tester, rateLabel, '');
    await submit(tester);
    expect(find.text('أدخل سعر الشهر للتلميذ'), findsOneWidget);
    expect(find.text('أدخل ما يأخذه الأستاذ عن كل تلميذ'), findsOneWidget);
    expect(find.text('إنشاء الفوج'), findsWidgets);
    expect(
      await runDb(tester, () => runtime.db.select(runtime.db.groups).get()),
      isEmpty,
    );
  });

  appTest('سعر فاسد يظهر عند حقله ولا يُنشأ فوج', (tester) async {
    final runtime = await openGroups(tester);
    await openForm(tester);
    await fillBasics(tester);
    await typeIn(tester, priceLabel, '2555');
    await submit(tester);
    expect(find.text('السعر من مضاعفات 10 دج'), findsOneWidget);
    expect(
      await runDb(tester, () => runtime.db.select(runtime.db.groups).get()),
      isEmpty,
    );
  });

  appTest('تغيير المادة يقترح سعرها لا سعر المادة السابقة', (tester) async {
    final runtime = await openGroups(tester);
    await runDb(tester, () async {
      final db = runtime.db;
      await db
          .into(db.subjects)
          .insert(
            SubjectsCompanion.insert(
              id: 'physics',
              createdAt: 1,
              updatedAt: 1,
              name: 'فيزياء',
              monthlyPrice: const Value(3000),
            ),
          );
      await db
          .into(db.teacherSubjects)
          .insert(
            TeacherSubjectsCompanion.insert(
              teacherId: 't1',
              subjectId: 'physics',
              updatedAt: 1,
            ),
          );
    });
    await openForm(tester);
    await pick(tester, 'المادة', 'رياضيات');
    expect(textOf(tester, priceLabel), '2000');
    await pick(tester, 'المادة', 'فيزياء');
    expect(textOf(tester, priceLabel), '3000');
  });

  appTest('تعديل فوج بلا تلاميذ: يُصحَّح سعره ومبلغ أستاذه', (tester) async {
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
        monthlyPrice: 2500,
        ratePerStudent: 900,
        slots: const [
          GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690),
        ],
        startDate: '2026-11-07',
      );
    });
    await openGroupList(tester);
    await tester.tap(find.byTooltip('تعديل الفوج 1'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(420, 3200);
    await tester.pumpAndSettle();
    expect(textOf(tester, priceLabel), '2500');
    expect(textOf(tester, rateLabel), '900');
    expect(tester.widget<TextField>(fieldOf(priceLabel)).enabled, isTrue);
    await typeIn(tester, priceLabel, '2600');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ التعديلات'));
    await tester.pumpAndSettle();
    final group = await runDb(
      tester,
      () => runtime.db.select(runtime.db.groups).getSingle(),
    );
    expect(group.monthlyPrice, 2600);
  });

  appTest('تعديل فوج فيه تلاميذ: السعر ومبلغ الأستاذ مقفلان', (tester) async {
    final runtime = await openGroups(tester);
    await runDb(tester, () async {
      final db = runtime.db;
      final group =
          await GroupService(
            db,
            runtime.writer,
            ScheduleService(db),
            CycleService(db, runtime.writer),
          ).create(
            subjectId: 'math',
            teacherId: 't1',
            roomId: 'r1',
            monthlyPrice: 2500,
            ratePerStudent: 900,
            slots: const [
              GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690),
            ],
            startDate: '2026-11-07',
          );
      await db
          .into(db.students)
          .insert(
            StudentsCompanion.insert(
              id: 's1',
              createdAt: 1,
              updatedAt: 1,
              firstName: 'أحمد',
              lastName: 'بن علي',
              parentPhone: '0550123456',
              qrCode: 'S-s1',
            ),
          );
      await db
          .into(db.groupStudents)
          .insert(
            GroupStudentsCompanion.insert(
              id: 'gs1',
              createdAt: 1,
              updatedAt: 1,
              groupId: group.id,
              studentId: 's1',
              joinedAt: 1,
              monthlyPrice: 2500,
            ),
          );
    });
    await openGroupList(tester);
    await tester.tap(find.byTooltip('تعديل الفوج 1'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(420, 3200);
    await tester.pumpAndSettle();
    expect(textOf(tester, priceLabel), '2500');
    expect(tester.widget<TextField>(fieldOf(priceLabel)).enabled, isFalse);
    expect(tester.widget<TextField>(fieldOf(rateLabel)).enabled, isFalse);
    expect(find.text('لا يتغيّر بعد ربط التلاميذ بالفوج'), findsNWidgets(2));
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
    await openGroupList(tester);
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
    await openGroupList(tester);
    expect(find.text('فوج 1'), findsOneWidget);
    await openGroupList(tester);
    expect(find.byTooltip('أرشفة الفوج 1'), findsNothing);
    await openGroupList(tester);
    expect(find.byTooltip('تعديل الفوج 1'), findsNothing);
    await openGroupList(tester);
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
    await openGroupList(tester);
    await tester.tap(find.byTooltip('حذف الفوج 1'));
    await tester.pumpAndSettle();
    expect(find.text('حذف الفوج'), findsOneWidget);
    expect(find.textContaining('أرشفه بدل ذلك'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'إلغاء'));
    await tester.pumpAndSettle();
    await openGroupList(tester);
    expect(find.text('فوج 1'), findsOneWidget);

    await openGroupList(tester);
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
    await openGroupList(tester);
    await tester.tap(find.byTooltip('حذف الفوج 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حذف'));
    await tester.pumpAndSettle();
    expect(find.textContaining('لا يمكن حذف الفوج 1'), findsOneWidget);
    expect(find.textContaining('مدفوعات مسجَّلة'), findsOneWidget);
    await openGroupList(tester);
    expect(find.text('فوج 1'), findsOneWidget);
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
    await openGroupList(tester);
    expect(find.byTooltip('حذف الفوج 1'), findsOneWidget);
    await openGroupList(tester);
    expect(find.byTooltip('تعديل الفوج 1'), findsNothing);
    await openGroupList(tester);
    expect(find.byTooltip('أرشفة الفوج 1'), findsNothing);
  });

  appTest('حذف الفوج من نموذج التعديل يعيد إلى القائمة', (tester) async {
    final runtime = await openGroups(tester);
    await seedGroup(tester, runtime);
    await openGroupList(tester);
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

  group('الأفواج بالمادة ثم السنة', () {
    /// مستويان («2 ثانوي» و«3 ثانوي») وثلاث مواد: رياضيات لكل من السنتين وفيزياء للثالثة، وأفواجها
    /// بترقيم كل مادة وسنة: رياضيات 3: فوجان، رياضيات 2: فوج، فيزياء 3: فوج.
    Future<AppRuntime> seedHierarchy(WidgetTester tester) async {
      final runtime = await openGroups(tester);
      final db = runtime.db;
      await runDb(tester, () async {
        for (final (id, name, order) in [
          ('l2', '2 ثانوي', 2),
          ('l3', '3 ثانوي', 3),
        ]) {
          await db
              .into(db.levels)
              .insert(
                LevelsCompanion.insert(
                  id: id,
                  createdAt: 1,
                  updatedAt: 1,
                  name: name,
                  stage: EducationStage.secondary.code,
                  sortOrder: order,
                ),
              );
        }
        for (final (id, name, level) in [
          ('math3', 'رياضيات', 'l3'),
          ('math2', 'رياضيات', 'l2'),
          ('phys3', 'فيزياء', 'l3'),
        ]) {
          await db
              .into(db.subjects)
              .insert(
                SubjectsCompanion.insert(
                  id: id,
                  createdAt: 1,
                  updatedAt: 1,
                  name: name,
                  monthlyPrice: const Value(2000),
                  levelId: Value(level),
                ),
              );
          await db
              .into(db.teacherSubjects)
              .insert(
                TeacherSubjectsCompanion.insert(
                  teacherId: 't1',
                  subjectId: id,
                  updatedAt: 1,
                ),
              );
        }
        final service = GroupService(
          db,
          runtime.writer,
          ScheduleService(db),
          CycleService(db, runtime.writer),
        );
        var hour = 8;
        for (final subject in ['math3', 'math3', 'math2', 'phys3']) {
          await service.create(
            subjectId: subject,
            teacherId: 't1',
            roomId: null,
            slots: [
              GroupSlotInput(
                weekday: 6,
                startMinutes: hour * 60,
                endMinutes: hour * 60 + 60,
              ),
            ],
            startDate: '2026-11-07',
          );
          hour += 2;
        }
      });
      // الشاشة تعرض المواد من البداية.
      await tester.pumpAndSettle();
      return runtime;
    }

    appTest('تُعرض المواد أولاً بأسمائها مرة واحدة مع عدد سنواتها وأفواجها', (
      tester,
    ) async {
      await seedHierarchy(tester);
      expect(find.text('رياضيات'), findsOneWidget, reason: 'مرة واحدة للسنتين');
      expect(find.text('فيزياء'), findsOneWidget);
      expect(find.text('2 سنة · 3 فوج · 0 تلميذ'), findsOneWidget);
      expect(find.text('1 سنة · 1 فوج · 0 تلميذ'), findsOneWidget);
      // لا أفواج بعد في هذا المستوى من العرض.
      expect(find.text('فوج 1'), findsNothing);
      expect(find.text('أفواج'), findsNothing);
    });

    appTest('اختيار مادة ثم سنة يُظهر أفواجها مرقَّمة من 1', (tester) async {
      await seedHierarchy(tester);
      await tester.tap(find.text('رياضيات'));
      await tester.pumpAndSettle();
      // السنوات بترتيب المستويات: الثانية قبل الثالثة.
      final years = tester
          .widgetList<ClayListTile>(find.byType(ClayListTile))
          .map((t) => t.title)
          .toList();
      expect(years, ['2 ثانوي', '3 ثانوي']);
      expect(find.text('2 فوج · 0 تلميذ'), findsOneWidget);
      expect(find.text('1 فوج · 0 تلميذ'), findsOneWidget);

      await tester.tap(find.text('3 ثانوي'));
      await tester.pumpAndSettle();
      expect(find.text('فوج 1'), findsOneWidget);
      expect(find.text('فوج 2'), findsOneWidget);
      expect(find.text('فوج 3'), findsNothing);
      // مسار التنقل: الأفواج › رياضيات › 3 ثانوي.
      expect(find.widgetWithText(TextButton, 'الأفواج'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'رياضيات'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '3 ثانوي'), findsOneWidget);

      // سنة أخرى لها ترقيمها: فوج 1 وحده.
      await tester.tap(find.widgetWithText(TextButton, 'رياضيات'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 ثانوي'));
      await tester.pumpAndSettle();
      expect(find.text('فوج 1'), findsOneWidget);
      expect(find.text('فوج 2'), findsNothing);
    });

    appTest('مسار التنقل والرجوع يصعدان درجة درجة', (tester) async {
      await seedHierarchy(tester);
      await tester.tap(find.text('فيزياء'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 ثانوي'));
      await tester.pumpAndSettle();
      expect(find.text('فوج 1'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('فوج 1'), findsNothing);
      expect(find.text('3 ثانوي'), findsOneWidget, reason: 'قائمة السنوات');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('رياضيات'), findsOneWidget, reason: 'قائمة المواد');

      await tester.tap(find.text('فيزياء'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'الأفواج'));
      await tester.pumpAndSettle();
      expect(find.text('رياضيات'), findsOneWidget);
    });

    appTest('الإنشاء من أفواج سنة يختار مادتها مسبقاً', (tester) async {
      await seedHierarchy(tester);
      await tester.tap(find.text('رياضيات'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 ثانوي'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'إنشاء فوج'));
      await tester.pumpAndSettle();
      expect(find.text('رياضيات (3 ثانوي)'), findsWidgets);
    });

    appTest('أرشفة آخر فوج في سنة تعيد إلى ما فوقها', (tester) async {
      await seedHierarchy(tester);
      await tester.tap(find.text('فيزياء'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 ثانوي'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('أرشفة الفوج 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'أرشفة'));
      await tester.pumpAndSettle();
      // اختفت الفيزياء كلها: عاد إلى قائمة المواد وفيها رياضيات فقط.
      expect(find.text('فيزياء'), findsNothing);
      expect(find.text('رياضيات'), findsOneWidget);
    });

    appTest('الفوج الجديد في مادة وسنة يأخذ رقمها التالي لا رقماً عالمياً', (
      tester,
    ) async {
      final runtime = await seedHierarchy(tester);
      final db = runtime.db;
      final numbers = await runDb(
        tester,
        () async => {
          for (final g in await db.select(db.groups).get())
            g.subjectId: g.number,
        },
      );
      // آخر فوج لكل مادة وسنة: رياضيات 3 هي 2 (أنشئ فوجان)، والبقية 1.
      expect(numbers['math3'], 2);
      expect(numbers['math2'], 1);
      expect(numbers['phys3'], 1);
    });
  });
}
