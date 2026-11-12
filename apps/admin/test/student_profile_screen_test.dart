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
  permissions: '{"students":["view"]}',
);

class Opened {
  Opened(this.runtime, this.provisioner, this.student);

  final AppRuntime runtime;
  final FakeAccountProvisioner provisioner;
  final StudentRow student;
}

/// يبذر مادتين ومجموعة وتلميذاً مسجَّلاً فيها، ثم يفتح ملفه من القائمة.
Future<Opened> openProfile(
  WidgetTester tester, {
  TestAccount account = owner,
  FakePdfPresenter? presenter,
}) async {
  final provisioner = FakeAccountProvisioner();
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: [account],
    pages: adminPages,
    provisioner: provisioner,
    pdfPresenter: presenter,
  );
  await loginWith(tester, account.email, account.password);
  final db = runtime.db;
  final result = await runDb(tester, () async {
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
    final dues = DuesService(db, runtime.writer);
    return RegistrationService(
      db,
      runtime.writer,
      accounts: AccountService(db, runtime.writer, provisioner),
      enrolments: EnrolmentService(
        db,
        runtime.writer,
        dues,
        CycleService(db, runtime.writer),
      ),
      dues: dues,
    ).register(
      const RegistrationRequest(
        firstName: 'أحمد',
        lastName: 'بن علي',
        parentName: 'علي بن علي',
        parentPhone: '0550123456',
        date: '2026-11-10',
        choices: [
          SubjectChoice(subjectId: 'math', groupId: 'g1', monthlyPrice: 2000),
        ],
      ),
      settings: const SchoolSettings(registrationFee: 1500),
    );
  });
  await tester.tap(find.text('التلاميذ').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('أحمد بن علي'));
  await tester.pumpAndSettle();
  // شاشة طويلة حتى تُبنى كل أقسام الملف.
  tester.view.physicalSize = const Size(420, 3600);
  await tester.pumpAndSettle();
  return Opened(runtime, provisioner, result.student);
}

/// حقل داخل الحوار المفتوح (فالملف نفسه فيه نصوص بنفس التسميات مثل «الاسم»).
Finder fieldOf(String label) => find.descendant(
  of: find
      .descendant(
        of: find.byType(ClayDialog),
        matching: find.ancestor(
          of: find.text(label),
          matching: find.byType(Column),
        ),
      )
      .last,
  matching: find.byType(TextField),
);

void main() {
  appTest('يعرض البيانات والوليّ والمجموعة والمستحقات ورمز QR', (tester) async {
    final o = await openProfile(tester);
    expect(find.text('ملف التلميذ'), findsOneWidget);
    expect(find.text('أحمد بن علي'), findsOneWidget);
    expect(find.text('علي بن علي'), findsOneWidget);
    expect(find.text('0550123456@school.local'), findsOneWidget);
    expect(find.text('رياضيات · المجموعة 1'), findsOneWidget);
    expect(find.text('كمال · 2 000 دج للدورة'), findsOneWidget);
    expect(find.text('حاضر 0'), findsOneWidget);
    expect(find.text('الباقي 2 000 دج'), findsOneWidget);
    // دورة 2000 + حقوق تسجيل 1500.
    expect(find.text('عليه 3 500 دج'), findsOneWidget);
    expect(find.text('1 500 دج'), findsOneWidget);
    expect(find.byType(ClayQrCode), findsOneWidget);
    expect(find.text(o.student.qrCode), findsOneWidget);
  });

  appTest('تعديل الاسم والنقل', (tester) async {
    final o = await openProfile(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'تعديل البيانات'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldOf('الاسم'), 'محمد');
    await tester.tap(find.byType(ClayToggle));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('أدخل سعر النقل الشهري'), findsOneWidget);
    await tester.enterText(fieldOf('سعر النقل الشهري (دج)'), '1200');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('محمد بن علي'), findsOneWidget);
    expect(find.text('نقل هذا الشهر'), findsOneWidget);
    final row = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.students).getSingle(),
    );
    expect(row.firstName, 'محمد');
    expect(row.transportPrice, 1200);
  });

  appTest('إضافة مادة إلى قائمة الانتظار ثم إزالتها', (tester) async {
    await openProfile(tester);
    expect(find.text('قوائم الانتظار'), findsNothing);
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة مادة'));
    await tester.pumpAndSettle();
    // دون اختيار مادة.
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة'));
    await tester.pumpAndSettle();
    expect(find.text('اختر المادة'), findsWidgets);
    await tester.tap(find.text('اختر المادة').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('فيزياء').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة'));
    await tester.pumpAndSettle();
    expect(find.text('قوائم الانتظار'), findsOneWidget);
    expect(find.text('فيزياء'), findsOneWidget);

    await tester.tap(find.byTooltip('إزالة من انتظار فيزياء'));
    await tester.pumpAndSettle();
    expect(find.text('قوائم الانتظار'), findsNothing);
  });

  appTest('إضافة مادة هو منتسب إليها: خطأ واضح', (tester) async {
    await openProfile(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة مادة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اختر المادة').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('رياضيات').last);
    await tester.pumpAndSettle();
    final group = find.descendant(
      of: find
          .ancestor(of: find.text('المجموعة'), matching: find.byType(Column))
          .first,
      matching: find.byWidgetPredicate((w) => w is DropdownButton),
    );
    await tester.tap(group);
    await tester.pumpAndSettle();
    await tester.tap(find.text('المجموعة 1 · كمال (1 تلميذ)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة'));
    await tester.pumpAndSettle();
    expect(find.text('التلميذ منتسب إلى هذه المجموعة'), findsOneWidget);
  });

  appTest('مغادرة المجموعة بعد التأكيد', (tester) async {
    final o = await openProfile(tester);
    await tester.tap(find.byTooltip('مغادرة مجموعة رياضيات'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'مغادرة'));
    await tester.pumpAndSettle();
    expect(find.text('غير منتسب إلى أي مجموعة'), findsOneWidget);
    final enrolment = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.groupStudents).getSingle(),
    );
    expect(enrolment.leftAt, isNotNull);
  });

  appTest('إعادة كلمة سر الوليّ تعرض الجديدة', (tester) async {
    final o = await openProfile(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'إعادة كلمة سر الوليّ'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'إعادة التوليد'));
    await tester.pumpAndSettle();
    expect(find.text('بيانات دخول علي بن علي'), findsOneWidget);
    expect(find.text(o.provisioner.resets.values.single), findsOneWidget);
  });

  appTest('الحذف يعيد إلى القائمة الفارغة', (tester) async {
    await openProfile(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'حذف التلميذ'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حذف').last);
    await tester.pumpAndSettle();
    expect(find.text('لا يوجد تلاميذ بعد'), findsOneWidget);
  });

  appTest('صلاحية العرض فقط: بلا أزرار تعديل ولا حذف', (tester) async {
    // التلميذ يُبذر باسم العامل، ثم تُفحص شاشته.
    await openProfile(tester, account: viewer);
    expect(find.text('ملف التلميذ'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'تعديل البيانات'), findsNothing);
    expect(find.widgetWithText(ClayButton, 'إضافة مادة'), findsNothing);
    expect(find.widgetWithText(ClayButton, 'حذف التلميذ'), findsNothing);
    expect(find.byTooltip('مغادرة مجموعة رياضيات'), findsNothing);
  });

  appTest('من لا يملك عرض المدفوعات: لا مبالغ ولا مستحقات ولا زر دفع', (
    tester,
  ) async {
    await openProfile(tester, account: viewer);
    expect(find.text('أحمد بن علي'), findsWidgets);
    expect(find.textContaining('عليه'), findsNothing);
    expect(find.text('المستحقات'), findsNothing);
    expect(find.textContaining('للدورة'), findsNothing);
    expect(find.textContaining('الباقي'), findsNothing);
    expect(find.widgetWithText(ClayButton, 'تسجيل دفعة'), findsNothing);
    // الحضور والمجموعة ظاهران.
    expect(find.textContaining('رياضيات · المجموعة 1'), findsOneWidget);
  });

  appTest('عرض المدفوعات بلا استلام المال: المبالغ بلا زر دفع', (tester) async {
    await openProfile(
      tester,
      account: const TestAccount(
        id: 'u-w2',
        email: 'w2@school.local',
        password: 'w2-pass-1',
        role: UserRole.worker,
        entityId: 'w2',
        displayName: 'عامل',
        permissions: '{"students":["view"],"payments":["view"]}',
      ),
    );
    expect(find.text('المستحقات'), findsOneWidget);
    expect(find.textContaining('للدورة'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'تسجيل دفعة'), findsNothing);
  });

  appTest('استلام المال: زر دفع يفتح التسجيل بالتلميذ مختاراً', (tester) async {
    await openProfile(
      tester,
      account: const TestAccount(
        id: 'u-w3',
        email: 'w3@school.local',
        password: 'w3-pass-1',
        role: UserRole.worker,
        entityId: 'w3',
        displayName: 'عامل',
        permissions:
            '{"students":["view"],"payments":["view"],"receive_money":["use"]}',
      ),
    );
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل دفعة'));
    await tester.pumpAndSettle();
    expect(find.text('تسجيل دفعة'), findsWidgets);
    expect(find.text('رياضيات · المجموعة 1 · الدورة 1'), findsOneWidget);
  });

  appTest('المالك: المستحقات وزر الدفع ظاهران', (tester) async {
    await openProfile(tester);
    expect(find.text('المستحقات'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'تسجيل دفعة'), findsOneWidget);
  });

  appTest('بطاقة التلميذ: PDF حقيقي يُعرض بالمعاينة والمشاركة', (tester) async {
    final presenter = FakePdfPresenter();
    final o = await openProfile(tester, presenter: presenter);
    await runDb(
      tester,
      () => SettingsService(
        o.runtime.db,
        o.runtime.writer,
      ).save(const SchoolSettings(schoolName: 'مدرسة النجاح')),
    );
    await tester.tap(find.widgetWithText(ClayButton, 'بطاقة التلميذ PDF'));
    // بناء الملف يعمل في الزمن الحقيقي (قراءة الخط والملفات).
    for (var i = 0; i < 40 && presenter.shown.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(presenter.shown, hasLength(1));
    final shown = presenter.shown.single;
    expect(shown.title, 'بطاقة أحمد بن علي');
    expect(shown.fileName, 'student-card-${o.student.id}.pdf');
    expect(String.fromCharCodes(shown.bytes.take(5)), '%PDF-');
    expect(shown.bytes.length, greaterThan(5000));
  });
}
