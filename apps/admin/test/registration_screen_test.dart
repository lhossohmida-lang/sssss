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

class Opened {
  Opened(this.runtime, this.provisioner);

  final AppRuntime runtime;
  final FakeAccountProvisioner provisioner;
}

/// يدخل، يبذر مادتين وأستاذاً ومجموعة، ثم يفتح استمارة التسجيل.
Future<Opened> openForm(
  WidgetTester tester, {
  TestAccount account = owner,
  int registrationFee = 0,
  bool open = true,
}) async {
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
  await runDb(tester, () async {
    final db = runtime.db;
    await db
        .into(db.levels)
        .insert(
          LevelsCompanion.insert(
            id: 'lv3',
            createdAt: 1,
            updatedAt: 1,
            name: '3 متوسط',
            stage: 'middle',
            sortOrder: 203,
          ),
        );
    await db
        .into(db.levels)
        .insert(
          LevelsCompanion.insert(
            id: 'lv4',
            createdAt: 1,
            updatedAt: 1,
            name: '4 متوسط',
            stage: 'middle',
            sortOrder: 204,
          ),
        );
    await db.batch((b) {
      b.insertAll(db.subjects, [
        SubjectsCompanion.insert(
          id: 'math',
          createdAt: 1,
          updatedAt: 1,
          name: 'رياضيات',
          monthlyPrice: const Value(2000),
        ),
        SubjectsCompanion.insert(
          id: 'phys',
          createdAt: 1,
          updatedAt: 1,
          name: 'فيزياء',
          monthlyPrice: const Value(2500),
          levelId: const Value('lv4'),
        ),
      ]);
    });
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
            qrCode: 'T-1',
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
    await db
        .into(db.groups)
        .insert(
          GroupsCompanion.insert(
            id: 'g1',
            createdAt: 1,
            updatedAt: 1,
            number: 1,
            subjectId: 'math',
            teacherId: 't1',
          ),
        );
  });
  if (registrationFee > 0) {
    await runDb(
      tester,
      () => SettingsService(
        runtime.db,
        runtime.writer,
      ).save(SchoolSettings(registrationFee: registrationFee)),
    );
  }
  await tester.tap(find.text('التلاميذ').last);
  await tester.pumpAndSettle();
  if (open) {
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل تلميذ'));
    await tester.pumpAndSettle();
    // شاشة طويلة حتى تُبنى كل أقسام الاستمارة.
    tester.view.physicalSize = const Size(420, 4200);
    await tester.pumpAndSettle();
  }
  return Opened(runtime, provisioner);
}

Finder fieldOf(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

/// يفتح القائمة المنسدلة ذات التسمية [label] ويختار [option].
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

/// يختار المادة في أول بطاقة مادة لم تُختر مادتها بعد.
Future<void> pickSubject(WidgetTester tester, String name) async {
  await tester.tap(find.text('اختر المادة').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
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

Future<void> submit(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ClayButton, 'تسجيل التلميذ'));
  await tester.pumpAndSettle();
}

void main() {
  appTest('تسجيل في فوج: بيانات دخول الوليّ ثم التلميذ في القائمة', (
    tester,
  ) async {
    final o = await openForm(tester, registrationFee: 1500);
    expect(
      find.textContaining('${Money.format(1500)} عن كل سنة دراسية'),
      findsOneWidget,
    );
    await fillPeople(tester);
    await pick(tester, 'المستوى', '3 متوسط');
    await pickSubject(tester, 'رياضيات');
    await pick(tester, 'الفوج', 'الفوج 1 · كمال (0 تلميذ)');
    // سعر الفوج يظهر كما عُيِّن عند إنشائه ولا يُدخَل من جديد (فوج قديم بلا سعر يأخذ سعر مادته).
    expect(
      find.text('سعر الشهر في هذا الفوج: ${Money.format(2000)}'),
      findsOneWidget,
    );
    expect(find.text('سعر الشهر (دج)'), findsNothing);
    expect(find.text('يدفع عن كل دورة: ${Money.format(2000)}'), findsOneWidget);
    await submit(tester);

    expect(find.text('بيانات دخول علي بن علي'), findsOneWidget);
    // رقم الدخول هو هاتف الوليّ لا البريد المولَّد منه.
    expect(find.text('رقم الدخول'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ClayDialog),
        matching: find.text('0550123456'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('@school.local'), findsNothing);
    expect(
      find.text(o.provisioner.created.values.single.password),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(ClayButton, 'تم'));
    await tester.pumpAndSettle();

    expect(find.text('أحمد بن علي'), findsOneWidget);
    expect(find.text('3 متوسط · 0550123456'), findsOneWidget);
    final db = o.runtime.db;
    final enrolment = await runDb(
      tester,
      () => db.select(db.groupStudents).getSingle(),
    );
    expect(enrolment.groupId, 'g1');
    expect(enrolment.monthlyPrice, 2000);
    final fee = await runDb(
      tester,
      () => db.select(db.registrationFees).getSingle(),
    );
    expect(fee.amount, 1500);
    final student = await runDb(
      tester,
      () => db.select(db.students).getSingle(),
    );
    expect(student.qrCode.startsWith('S-'), isTrue);
    expect(student.levelId, 'lv3');
  });

  /// فوج ثانٍ لمادة الرياضيات بسعره الخاص (يُعيَّن عند إنشائه).
  Future<void> addPricedGroup(WidgetTester tester, Opened o) async {
    final db = o.runtime.db;
    await runDb(
      tester,
      () => db
          .into(db.groups)
          .insert(
            GroupsCompanion.insert(
              id: 'g2',
              createdAt: 1,
              updatedAt: 1,
              number: 2,
              subjectId: 'math',
              teacherId: 't1',
              monthlyPrice: const Value(3500),
            ),
          ),
    );
    await tester.pumpAndSettle();
  }

  appTest('سعر الفوج يختلف من فوج إلى آخر وبه يُنسب التلميذ', (tester) async {
    final o = await openForm(tester);
    await addPricedGroup(tester, o);
    await fillPeople(tester);
    await pickSubject(tester, 'رياضيات');
    await pick(tester, 'الفوج', 'الفوج 2 · كمال (0 تلميذ)');
    expect(
      find.text('سعر الشهر في هذا الفوج: ${Money.format(3500)}'),
      findsOneWidget,
    );
    expect(find.text('يدفع عن كل دورة: ${Money.format(3500)}'), findsOneWidget);
    // وسعر الفوج الأول غير سعر الثاني.
    await pick(tester, 'الفوج', 'الفوج 1 · كمال (0 تلميذ)');
    expect(
      find.text('سعر الشهر في هذا الفوج: ${Money.format(2000)}'),
      findsOneWidget,
    );
    await pick(tester, 'الفوج', 'الفوج 2 · كمال (0 تلميذ)');
    await submit(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'تم'));
    await tester.pumpAndSettle();
    final enrolment = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.groupStudents).getSingle(),
    );
    expect(enrolment.groupId, 'g2');
    expect(enrolment.monthlyPrice, 3500);
  });

  appTest('المجموع الشهري: سعر الفوج بعد التخفيض مع النقل إن استعمله', (
    tester,
  ) async {
    final o = await openForm(tester);
    await addPricedGroup(tester, o);
    await fillPeople(tester);
    // لا مجموع قبل اختيار فوج.
    expect(find.text('ما يدفعه التلميذ شهرياً'), findsNothing);
    await pickSubject(tester, 'رياضيات');
    await pick(tester, 'الفوج', 'الفوج 2 · كمال (0 تلميذ)');
    expect(find.text('ما يدفعه التلميذ شهرياً'), findsOneWidget);
    expect(find.text('الأفواج: ${Money.format(3500)}'), findsOneWidget);
    expect(find.text('المجموع: ${Money.format(3500)}'), findsOneWidget);

    await pick(tester, 'التخفيض', 'نسبة مئوية');
    await tester.enterText(fieldOf('النسبة (%)'), '20');
    await tester.pump();
    expect(find.text('المجموع: ${Money.format(2800)}'), findsOneWidget);

    await tester.tap(find.byType(ClayToggle));
    await tester.pumpAndSettle();
    await tester.enterText(fieldOf('سعر النقل الشهري (دج)'), '600');
    await tester.pump();
    expect(find.text('الأفواج: ${Money.format(2800)}'), findsOneWidget);
    expect(find.text('النقل: ${Money.format(600)}'), findsOneWidget);
    expect(find.text('المجموع: ${Money.format(3400)}'), findsOneWidget);
  });

  appTest('دون اختيار فوج: قائمة الانتظار مع الأستاذ المفضّل', (tester) async {
    final o = await openForm(tester);
    await fillPeople(tester);
    await pickSubject(tester, 'رياضيات');
    expect(find.text('سعر الشهر (دج)'), findsNothing);
    await pick(tester, 'الأستاذ المفضّل (اختياري)', 'كمال');
    await submit(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'تم'));
    await tester.pumpAndSettle();
    final db = o.runtime.db;
    expect(
      await runDb(tester, () => db.select(db.groupStudents).get()),
      isEmpty,
    );
    final list = await runDb(
      tester,
      () => db.select(db.waitingLists).getSingle(),
    );
    expect(list.subjectId, 'math');
    expect(list.preferredTeacherId, 't1');
    expect(
      await runDb(tester, () => db.select(db.waitingEntries).get()),
      hasLength(1),
    );
  });

  appTest('استمارة فارغة: أخطاء عربية ولا تسجيل', (tester) async {
    final o = await openForm(tester);
    await submit(tester);
    expect(find.text('أدخل الاسم'), findsOneWidget);
    expect(find.text('أدخل اللقب'), findsOneWidget);
    expect(find.text('أدخل اسم الوليّ'), findsOneWidget);
    expect(find.textContaining('يبدأ بـ 05'), findsOneWidget);
    expect(find.text('اختر مادة واحدة على الأقل'), findsOneWidget);
    expect(o.provisioner.created, isEmpty);
    expect(find.text('تسجيل تلميذ'), findsOneWidget);
  });

  appTest('التخفيض يغيّر المبلغ المعروض ويُحفظ', (tester) async {
    final o = await openForm(tester);
    await fillPeople(tester);
    await pickSubject(tester, 'رياضيات');
    await pick(tester, 'الفوج', 'الفوج 1 · كمال (0 تلميذ)');
    await pick(tester, 'التخفيض', 'نسبة مئوية');
    await tester.enterText(fieldOf('النسبة (%)'), '50');
    await tester.pump();
    expect(find.text('يدفع عن كل دورة: ${Money.format(1000)}'), findsOneWidget);

    await pick(tester, 'التخفيض', 'إعفاء كامل');
    expect(find.text('يدفع عن كل دورة: 0 دج'), findsOneWidget);
    expect(find.text('النسبة (%)'), findsNothing);
    await submit(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'تم'));
    await tester.pumpAndSettle();
    final enrolment = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.groupStudents).getSingle(),
    );
    expect(enrolment.discountType, 'exempt');
  });

  appTest('خطأ نسبة التخفيض يظهر عند حقلها', (tester) async {
    await openForm(tester);
    await fillPeople(tester);
    await pickSubject(tester, 'رياضيات');
    await pick(tester, 'الفوج', 'الفوج 1 · كمال (0 تلميذ)');
    await pick(tester, 'التخفيض', 'نسبة مئوية');
    await tester.enterText(fieldOf('النسبة (%)'), '150');
    await submit(tester);
    expect(find.text('النسبة من 1 إلى 100'), findsOneWidget);
  });

  /// فوج ثالث بسعر 3000 ونصيب أستاذ 1500 عن كل تلميذ، لاختبار من يتحمّل التخفيض.
  Future<void> addSharedGroup(WidgetTester tester, Opened o) async {
    final db = o.runtime.db;
    await runDb(
      tester,
      () => db
          .into(db.groups)
          .insert(
            GroupsCompanion.insert(
              id: 'g3',
              createdAt: 1,
              updatedAt: 1,
              number: 3,
              subjectId: 'math',
              teacherId: 't1',
              monthlyPrice: const Value(3000),
              ratePerStudent: const Value(1500),
            ),
          ),
    );
    await tester.pumpAndSettle();
    await fillPeople(tester);
    await pickSubject(tester, 'رياضيات');
    await pick(tester, 'الفوج', 'الفوج 3 · كمال (0 تلميذ)');
  }

  /// يسجّل ويعيد صف الانتساب الوحيد.
  Future<GroupStudentRow> registerAndRead(WidgetTester tester, Opened o) async {
    await submit(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'تم'));
    await tester.pumpAndSettle();
    return runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.groupStudents).getSingle(),
    );
  }

  String teacherTakes(int amount, {int rate = 1500}) =>
      'يأخذ الأستاذ عن هذا التلميذ: ${Money.format(amount)} '
      'من نصيبه ${Money.format(rate)}';

  appTest('تخفيض بلا تحمّل: لا حقل بلا تخفيض، والمدرسة هي الأصل', (
    tester,
  ) async {
    final o = await openForm(tester);
    await addSharedGroup(tester, o);
    expect(find.text('من يتحمّل التخفيض؟'), findsNothing);

    await pick(tester, 'التخفيض', 'نسبة مئوية');
    await tester.enterText(fieldOf('النسبة (%)'), '20');
    await tester.pump();
    expect(find.text('من يتحمّل التخفيض؟'), findsOneWidget);
    // التخفيض 600 تتحمله المدرسة: الأستاذ يأخذ نصيبه كاملاً.
    expect(find.text('يدفع عن كل دورة: ${Money.format(2400)}'), findsOneWidget);
    expect(find.text(teacherTakes(1500)), findsOneWidget);

    final enrolment = await registerAndRead(tester, o);
    expect(enrolment.discountType, 'percent');
    expect(enrolment.teacherAmount, isNull, reason: 'نصيب الفوج كاملاً');
  });

  appTest('الأستاذ يتحمّل التخفيض: يُخصم من نصيبه ويُحفظ مبلغه', (
    tester,
  ) async {
    final o = await openForm(tester);
    await addSharedGroup(tester, o);
    await pick(tester, 'التخفيض', 'نسبة مئوية');
    await tester.enterText(fieldOf('النسبة (%)'), '20');
    await tester.pump();
    await pick(tester, 'من يتحمّل التخفيض؟', 'الأستاذ');
    expect(find.text('يُخصم التخفيض من نصيب الأستاذ'), findsOneWidget);
    // التخفيض 600 يُخصم من نصيبه 1500.
    expect(find.text(teacherTakes(900)), findsOneWidget);

    final enrolment = await registerAndRead(tester, o);
    expect(enrolment.teacherAmount, 900);
    expect(enrolment.monthlyPrice, 3000);
  });

  appTest('إعفاء كامل يتحمّله الأستاذ: لا يأخذ عن التلميذ شيئاً', (
    tester,
  ) async {
    final o = await openForm(tester);
    await addSharedGroup(tester, o);
    await pick(tester, 'التخفيض', 'إعفاء كامل');
    await pick(tester, 'من يتحمّل التخفيض؟', 'الأستاذ');
    expect(find.text(teacherTakes(0)), findsOneWidget);
    final enrolment = await registerAndRead(tester, o);
    expect(enrolment.discountType, 'exempt');
    expect(enrolment.teacherAmount, 0);
  });

  appTest('أزرار المجاني: على الأستاذ يُخصم من حقه نصيب المدرسة', (
    tester,
  ) async {
    final o = await openForm(tester);
    await addSharedGroup(tester, o);
    await tester.ensureVisible(find.text('مجاني على الأستاذ'));
    await tester.tap(find.text('مجاني على الأستاذ'));
    await tester.pumpAndSettle();
    final enrolment = await registerAndRead(tester, o);
    expect(enrolment.discountType, 'exempt');
    expect(enrolment.teacherAmount, isNegative);
  });

  appTest('مجاني لا يُحسب على أحد: الأستاذ لا يأخذ شيئاً', (tester) async {
    final o = await openForm(tester);
    await addSharedGroup(tester, o);
    await tester.ensureVisible(find.text('مجاني لا يُحسب على أحد'));
    await tester.tap(find.text('مجاني لا يُحسب على أحد'));
    await tester.pumpAndSettle();
    final enrolment = await registerAndRead(tester, o);
    expect(enrolment.discountType, 'exempt');
    expect(enrolment.teacherAmount, 0);
  });

  appTest('يبدأ من الحصة الثالثة: تُحفظ مع الانتساب', (tester) async {
    final o = await openForm(tester);
    await addSharedGroup(tester, o);
    await pick(tester, 'يبدأ من الحصة', 'الحصة 3');
    final enrolment = await registerAndRead(tester, o);
    expect(enrolment.joinedAtSessionNumber, 3);
  });

  appTest('مبلغ يحدده المدير للأستاذ: حقل يظهر بالاختيار ويُحفظ', (
    tester,
  ) async {
    final o = await openForm(tester);
    await addSharedGroup(tester, o);
    await pick(tester, 'التخفيض', 'مبلغ ثابت');
    await tester.enterText(fieldOf('مبلغ التخفيض (دج)'), '500');
    await tester.pump();
    const label = 'ما يأخذه الأستاذ عن هذا التلميذ (دج)';
    expect(find.text(label), findsNothing);
    await pick(tester, 'من يتحمّل التخفيض؟', 'مبلغ أحدده للأستاذ');
    expect(find.text(label), findsOneWidget);

    await tester.enterText(fieldOf(label), '1200');
    await tester.pump();
    expect(find.text(teacherTakes(1200)), findsOneWidget);
    final enrolment = await registerAndRead(tester, o);
    expect(enrolment.teacherAmount, 1200);
  });

  appTest('مبلغ الأستاذ فوق نصيبه أو فارغ: خطأ عند حقله ولا تسجيل', (
    tester,
  ) async {
    final o = await openForm(tester);
    await addSharedGroup(tester, o);
    await pick(tester, 'التخفيض', 'إعفاء كامل');
    await pick(tester, 'من يتحمّل التخفيض؟', 'مبلغ أحدده للأستاذ');
    const label = 'ما يأخذه الأستاذ عن هذا التلميذ (دج)';
    await submit(tester);
    expect(find.text('أدخل ما يأخذه الأستاذ عن هذا التلميذ'), findsOneWidget);

    await tester.enterText(fieldOf(label), '2000');
    await submit(tester);
    expect(
      find.text(
        'مبلغ الأستاذ لا يزيد عن نصيبه في الفوج (${Money.format(1500)})',
      ),
      findsOneWidget,
    );
    expect(
      await runDb(
        tester,
        () => o.runtime.db.select(o.runtime.db.groupStudents).get(),
      ),
      isEmpty,
    );
  });

  appTest('بلا تخفيض يُهمل اختيار التحمّل القديم ويُحفظ نصيب الفوج', (
    tester,
  ) async {
    final o = await openForm(tester);
    await addSharedGroup(tester, o);
    await pick(tester, 'التخفيض', 'نسبة مئوية');
    await tester.enterText(fieldOf('النسبة (%)'), '20');
    await tester.pump();
    await pick(tester, 'من يتحمّل التخفيض؟', 'الأستاذ');
    // رجع المدير عن التخفيض: لا حقل ولا خصم من نصيب الأستاذ.
    await pick(tester, 'التخفيض', 'دون تخفيض');
    expect(find.text('من يتحمّل التخفيض؟'), findsNothing);
    final enrolment = await registerAndRead(tester, o);
    expect(enrolment.discountType, 'none');
    expect(enrolment.teacherAmount, isNull);
  });

  appTest('الأخ الثاني يُربط بحساب وليّه دون نافذة بيانات دخول', (
    tester,
  ) async {
    final o = await openForm(tester);
    await fillPeople(tester);
    await pickSubject(tester, 'رياضيات');
    await submit(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'تم'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل تلميذ'));
    await tester.pumpAndSettle();
    await fillPeople(tester, first: 'سارة');
    await pickSubject(tester, 'رياضيات');
    await submit(tester);
    expect(find.textContaining('رُبط بحساب وليّه القائم'), findsOneWidget);
    expect(find.textContaining('بيانات دخول'), findsNothing);
    expect(o.provisioner.created, hasLength(1));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('2 تلميذ'), findsOneWidget);
  });

  appTest('عدة مواد: إضافة بطاقة ثانية وإزالتها', (tester) async {
    await openForm(tester);
    expect(find.text('المادة 1'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة مادة أخرى'));
    await tester.pumpAndSettle();
    expect(find.text('المادة 2'), findsOneWidget);
    await tester.tap(find.byTooltip('إزالة المادة 2'));
    await tester.pumpAndSettle();
    expect(find.text('المادة 2'), findsNothing);
    // البطاقة الوحيدة لا تُزال.
    expect(find.byTooltip('إزالة المادة 1'), findsNothing);
  });

  appTest('المواد المعروضة تتبع مستوى التلميذ', (tester) async {
    await openForm(tester);
    await pick(tester, 'المستوى', '3 متوسط');
    await tester.tap(find.text('اختر المادة').first);
    await tester.pumpAndSettle();
    expect(find.text('رياضيات'), findsWidgets);
    // الفيزياء لمستوى 4 متوسط فقط.
    expect(find.text('فيزياء (4 متوسط)'), findsNothing);
    await tester.tap(find.text('رياضيات').last);
    await tester.pumpAndSettle();
  });

  appTest('مادة عامة لها مثيل في سنة التلميذ: يُعرض مثيلها وحده', (
    tester,
  ) async {
    final o = await openForm(tester);
    // فوج ثالث متوسط أُنشئ من الرياضيات العامة: مادته «رياضيات» لتلك السنة.
    await runDb(
      tester,
      () => o.runtime.db
          .into(o.runtime.db.subjects)
          .insert(
            SubjectsCompanion.insert(
              id: 'math3',
              createdAt: 1,
              updatedAt: 1,
              name: 'رياضيات',
              levelId: const Value('lv3'),
              monthlyPrice: const Value(2000),
            ),
          ),
    );
    await tester.pumpAndSettle();
    await pick(tester, 'المستوى', '3 متوسط');
    await tester.tap(find.text('اختر المادة').first);
    await tester.pumpAndSettle();
    // مادة السنة وحدها، لا العامة معها.
    expect(find.text('رياضيات (3 متوسط)'), findsOneWidget);
    expect(find.text('رياضيات'), findsNothing);
    await tester.tap(find.text('رياضيات (3 متوسط)').last);
    await tester.pumpAndSettle();
  });

  appTest('النقل: الحقل يظهر بالتفعيل، وسعره مطلوب', (tester) async {
    final o = await openForm(tester);
    expect(find.text('سعر النقل الشهري (دج)'), findsNothing);
    await tester.tap(find.byType(ClayToggle));
    await tester.pumpAndSettle();
    expect(find.text('سعر النقل الشهري (دج)'), findsOneWidget);
    await fillPeople(tester);
    await pickSubject(tester, 'رياضيات');
    await submit(tester);
    expect(find.text('أدخل سعر النقل الشهري'), findsOneWidget);
    await tester.enterText(fieldOf('سعر النقل الشهري (دج)'), '1200');
    await submit(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'تم'));
    await tester.pumpAndSettle();
    final student = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.students).getSingle(),
    );
    expect(student.usesTransport, isTrue);
    expect(student.transportPrice, 1200);
  });

  appTest('دون إنترنت: يُسجَّل التلميذ وحساب وليّه ينتظر الخادم', (
    tester,
  ) async {
    final o = await openForm(tester);
    o.provisioner.failing = true;
    await fillPeople(tester);
    await pickSubject(tester, 'رياضيات');
    await submit(tester);
    expect(find.textContaining('لا إنترنت الآن'), findsOneWidget);
    expect(
      await runDb(
        tester,
        () => o.runtime.db.select(o.runtime.db.students).get(),
      ),
      hasLength(1),
    );
  });

  appTest('رفض الخادم لحساب الوليّ: رسالة ولا تلميذ', (tester) async {
    final o = await openForm(tester);
    o.provisioner.rejecting = true;
    await fillPeople(tester);
    await pickSubject(tester, 'رياضيات');
    await submit(tester);
    expect(find.text('يوجد حساب بهذا البريد مسبقاً'), findsOneWidget);
    expect(
      await runDb(
        tester,
        () => o.runtime.db.select(o.runtime.db.students).get(),
      ),
      isEmpty,
    );
  });

  appTest('عامل بصلاحية العرض فقط: بلا زر التسجيل', (tester) async {
    await openForm(
      tester,
      account: const TestAccount(
        id: 'u-worker',
        email: 'worker@school.local',
        password: 'worker-pass-1',
        role: UserRole.worker,
        entityId: 'w1',
        displayName: 'عامل',
        permissions: '{"students":["view"]}',
      ),
      open: false,
    );
    expect(find.widgetWithText(ClayButton, 'تسجيل تلميذ'), findsNothing);
  });
}
