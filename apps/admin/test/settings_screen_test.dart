import 'package:admin/admin_tabs.dart';
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

TestAccount worker(String permissions) => TestAccount(
  id: 'u-worker',
  email: 'worker@school.local',
  password: 'worker-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'عامل',
  permissions: permissions,
);

/// يفتح شاشة الإعدادات من «المزيد»، بشاشة طويلة تُبنى كل أقسامها.
Future<AppRuntime> openSettings(
  WidgetTester tester,
  TestAccount account, {
  SchoolSettings? preset,
}) async {
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: [account],
    pages: adminPages,
  );
  await loginWith(tester, account.email, account.password);
  await tester.runAsync(
    () => LevelService(runtime.db, runtime.writer).ensureDefaults(),
  );
  // إطار بين الكتابتين: إعادة جلب الاستعلامات المتدفقة بعد كل كتابة تعيش في
  // منطقة الاختبار الوهمية ولا تكتمل إلا بإطار، وإلا انتظرت القراءة التالية
  // إلى الأبد داخل runAsync.
  await tester.pump();
  if (preset != null) {
    await tester.runAsync(
      () => SettingsService(runtime.db, runtime.writer).save(preset),
    );
    await tester.pump();
  }
  await tester.tap(find.text('المزيد').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('الإعدادات'));
  await tester.pumpAndSettle();
  tester.view.physicalSize = const Size(420, 3600);
  await tester.pumpAndSettle();
  return runtime;
}

Finder field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

Future<SchoolSettings> stored(WidgetTester tester, AppRuntime runtime) async =>
    (await tester.runAsync(
      () => SettingsService(runtime.db, runtime.writer).load(),
    ))!;

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ClayButton, 'حفظ الإعدادات'));
  await tester.pumpAndSettle();
}

void main() {
  appTest('«المزيد» يفتح الإعدادات ويعرض القيم الافتراضية', (tester) async {
    await openSettings(tester, owner);
    expect(find.text('بيانات المدرسة'), findsOneWidget);
    expect(find.text('حقوق التسجيل'), findsOneWidget);
    expect(find.text('الفصول الدراسية'), findsOneWidget);
    expect(find.text('المستويات الدراسية'), findsOneWidget);
    expect(find.text('الحضور والمسح'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(field('هامش المسح قبل الحصة (دقيقة)'))
          .controller!
          .text,
      '30',
    );
    expect(
      tester
          .widget<TextField>(field('مهلة السماح للتأخر (دقيقة)'))
          .controller!
          .text,
      '5',
    );
    expect(
      tester
          .widget<TextField>(field('مستحقات الدورة الحالية بعد حصة رقم'))
          .controller!
          .text,
      '2',
    );
    expect(find.text('لم تُضف فصول بعد'), findsOneWidget);
  });

  appTest('تعديل الحقول وحفظها يكتبها في القاعدة', (tester) async {
    final runtime = await openSettings(tester, owner);
    await tester.enterText(field('اسم المدرسة'), 'مدرسة النجاح');
    await tester.enterText(field('الهاتف'), '0550123456');
    await tester.enterText(field('المبلغ (دج)'), '2500');
    await tester.enterText(field('هامش المسح قبل الحصة (دقيقة)'), '45');
    await save(tester);
    expect(find.text('تم حفظ الإعدادات'), findsOneWidget);
    final s = await stored(tester, runtime);
    expect(s.schoolName, 'مدرسة النجاح');
    expect(s.schoolPhone, '0550123456');
    expect(s.registrationFee, 2500);
    expect(s.scanMarginMinutes, 45);
  });

  appTest('قيم غير صالحة: أخطاء عربية ولا حفظ', (tester) async {
    final runtime = await openSettings(tester, owner);
    await tester.enterText(field('الهاتف'), '123');
    await tester.enterText(field('مهلة السماح للتأخر (دقيقة)'), '99');
    await tester.enterText(field('المبلغ (دج)'), '1505');
    await save(tester);
    expect(find.textContaining('يبدأ بـ 05'), findsOneWidget);
    expect(find.text('المهلة من 0 إلى 60 دقيقة'), findsOneWidget);
    expect(find.textContaining('من مضاعفات 10'), findsOneWidget);
    expect((await stored(tester, runtime)).schoolPhone, '');
  });

  appTest('حقل رقمي فارغ: «أدخل رقماً صحيحاً»', (tester) async {
    await openSettings(tester, owner);
    await tester.enterText(field('هامش المسح قبل الحصة (دقيقة)'), '');
    await save(tester);
    expect(find.text('أدخل رقماً صحيحاً'), findsOneWidget);
  });

  appTest('الحقول الرقمية لا تقبل حروفاً', (tester) async {
    await openSettings(tester, owner);
    await tester.enterText(field('المبلغ (دج)'), '12ab3');
    expect(
      tester.widget<TextField>(field('المبلغ (دج)')).controller!.text,
      '123',
    );
  });

  appTest('إضافة فصل بالتقويم اللاتيني ثم الحفظ', (tester) async {
    final runtime = await openSettings(tester, owner);
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة فصل'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'الفصل الأول');
    await tester.tap(find.widgetWithText(ClayButton, 'تاريخ البداية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5').last);
    await tester.pump();
    await tester.tap(find.widgetWithText(ClayButton, 'تأكيد'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'تاريخ النهاية'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20').last);
    await tester.pump();
    await tester.tap(find.widgetWithText(ClayButton, 'تأكيد'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ').last);
    await tester.pumpAndSettle();
    expect(find.text('الفصل الأول'), findsOneWidget);
    await save(tester);
    final semesters = (await stored(tester, runtime)).semesters;
    expect(semesters, hasLength(1));
    expect(semesters.single.name, 'الفصل الأول');
    expect(semesters.single.start.endsWith('-05'), isTrue);
    expect(semesters.single.end.endsWith('-20'), isTrue);
  });

  appTest('فصل بلا تاريخين لا يُقبل', (tester) async {
    await openSettings(tester, owner);
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة فصل'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'الفصل الأول');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ').last);
    await tester.pumpAndSettle();
    expect(find.text('اختر تاريخي البداية والنهاية'), findsOneWidget);
  });

  appTest('تعديل فصل وحذف آخر ثم الحفظ', (tester) async {
    final runtime = await openSettings(
      tester,
      owner,
      preset: const SchoolSettings(
        semesters: [
          Semester(name: 'الأول', start: '2026-09-15', end: '2026-12-20'),
          Semester(name: 'الثاني', start: '2027-01-05', end: '2027-03-31'),
        ],
      ),
    );
    expect(find.text('الأول'), findsOneWidget);
    expect(find.text('15/09/2026  →  20/12/2026'), findsOneWidget);

    await tester.tap(find.byTooltip('تعديل الثاني'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'الفصل الثالث');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ').last);
    await tester.pumpAndSettle();
    expect(find.text('الفصل الثالث'), findsOneWidget);

    await tester.tap(find.byTooltip('حذف الأول'));
    await tester.pumpAndSettle();
    expect(find.text('الأول'), findsNothing);
    await save(tester);
    final semesters = (await stored(tester, runtime)).semesters;
    expect(semesters.map((e) => e.name), ['الفصل الثالث']);
    expect(semesters.single.start, '2027-01-05');
  });

  appTest('فصلان متداخلان: خطأ التحقق يظهر', (tester) async {
    await openSettings(
      tester,
      owner,
      preset: const SchoolSettings(
        semesters: [
          Semester(name: 'أ', start: '2000-01-01', end: '2100-12-31'),
        ],
      ),
    );
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة فصل'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'ب');
    for (final label in ['تاريخ البداية', 'تاريخ النهاية']) {
      await tester.tap(find.widgetWithText(ClayButton, label));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10').last);
      await tester.pump();
      await tester.tap(find.widgetWithText(ClayButton, 'تأكيد'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ').last);
    await tester.pumpAndSettle();
    await save(tester);
    expect(find.textContaining('متداخلان'), findsOneWidget);
  });

  appTest('المستويات: تظهر الافتراضية وتُضاف وتُحذف', (tester) async {
    final runtime = await openSettings(tester, owner);
    expect(find.text('1 ابتدائي'), findsOneWidget);
    expect(find.text('3 ثانوي'), findsOneWidget);

    await tester.tap(find.widgetWithText(ClayButton, 'إضافة مستوى'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '5 متوسط');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ').last);
    await tester.pumpAndSettle();
    expect(find.text('5 متوسط'), findsOneWidget);

    await tester.tap(find.byTooltip('حذف 5 متوسط'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حذف').last);
    await tester.pumpAndSettle();
    expect(find.text('5 متوسط'), findsNothing);
    final rows = (await tester.runAsync(
      () => runtime.db.select(runtime.db.levels).get(),
    ))!;
    expect(rows.firstWhere((r) => r.name == '5 متوسط').deletedAt, isNotNull);
  });

  appTest('اسم مستوى مكرر يظهر خطؤه ولا يُضاف', (tester) async {
    await openSettings(tester, owner);
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة مستوى'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '1 ابتدائي');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ').last);
    await tester.pumpAndSettle();
    expect(find.text('يوجد مستوى بهذا الاسم'), findsOneWidget);
  });

  appTest('عامل بصلاحية العرض فقط: قراءة بلا حفظ', (tester) async {
    await openSettings(tester, worker('{"settings":["view"]}'));
    expect(find.byType(ClayBadge), findsOneWidget);
    expect(
      tester.widget<ClayBadge>(find.byType(ClayBadge)).label,
      contains('عرض فقط'),
    );
    final saveButton = tester.widget<ClayButton>(
      find.widgetWithText(ClayButton, 'حفظ الإعدادات'),
    );
    expect(saveButton.onPressed, isNull);
    expect(tester.widget<TextField>(field('اسم المدرسة')).enabled, isFalse);
  });

  appTest('عامل بلا صلاحية الإعدادات: لا قسم في «المزيد»', (tester) async {
    await bootApp(
      tester,
      adminTabs,
      app: AppIdentity.admin,
      accounts: [worker('{"students":["view"]}')],
      pages: adminPages,
    );
    await loginWith(tester, 'worker@school.local', 'worker-pass-1');
    await tester.tap(find.text('المزيد').last);
    await tester.pumpAndSettle();
    expect(find.text('الإعدادات'), findsNothing);
    expect(find.text('لا توجد أقسام متاحة'), findsOneWidget);
  });
}
