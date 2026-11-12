import 'package:admin/admin_tabs.dart';
import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
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
}) async {
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: [account],
    pages: adminPages,
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
  await tester.tap(find.text('المجموعات').last);
  await tester.pumpAndSettle();
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
  await tester.tap(find.widgetWithText(ClayButton, 'إنشاء مجموعة'));
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
  await tester.tap(find.widgetWithText(ClayButton, 'إنشاء المجموعة'));
  await tester.pumpAndSettle();
}

void main() {
  appTest('قائمة فارغة برسالة وزر إنشاء', (tester) async {
    await openGroups(tester);
    expect(find.text('لا توجد مجموعات بعد'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'إنشاء مجموعة'), findsOneWidget);
  });

  appTest('إنشاء مجموعة: تظهر في القائمة بجدولها وتُولَّد حصصها', (
    tester,
  ) async {
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

    expect(find.text('المجموعة 1 · رياضيات'), findsOneWidget);
    expect(find.textContaining('كمال · القاعة 1 · 0 تلميذ'), findsOneWidget);
    expect(find.textContaining('الثلاثاء 10:00–11:30'), findsOneWidget);
    final sessions = await runDb(
      tester,
      () => runtime.db.select(runtime.db.sessions).get(),
    );
    expect(sessions, hasLength(8));
  });

  appTest('بيانات ناقصة: أخطاء المادة والأستاذ', (tester) async {
    await openGroups(tester);
    await openForm(tester);
    await submit(tester);
    expect(find.text('اختر المادة'), findsWidgets);
    expect(find.text('اختر الأستاذ'), findsOneWidget);
    expect(find.text('إنشاء مجموعة'), findsWidgets);
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
    expect(find.text('المجموعة 2 · رياضيات'), findsOneWidget);
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
    expect(find.text('إنشاء مجموعة'), findsWidgets);
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

  appTest('تعديل مجموعة: الأستاذ والجدول، والمادة وعدد الحصص مقفلان', (
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
    await tester.tap(find.byTooltip('تعديل المجموعة 1'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(420, 3200);
    await tester.pumpAndSettle();
    expect(find.text('تعديل المجموعة'), findsOneWidget);
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
    await tester.tap(find.byTooltip('أرشفة المجموعة 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'أرشفة'));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد مجموعات بعد'), findsOneWidget);
  });

  appTest('صلاحية العرض فقط: بلا إنشاء ولا أرشفة', (tester) async {
    final runtime = await openGroups(tester, account: viewer);
    expect(find.widgetWithText(ClayButton, 'إنشاء مجموعة'), findsNothing);
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
    expect(find.text('المجموعة 1 · رياضيات'), findsOneWidget);
    expect(find.byTooltip('أرشفة المجموعة 1'), findsNothing);
    expect(find.byTooltip('تعديل المجموعة 1'), findsNothing);
  });
}
