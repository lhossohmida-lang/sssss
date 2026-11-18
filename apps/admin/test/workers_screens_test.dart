import 'package:admin/admin_tabs.dart';
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

const _viewer = TestAccount(
  id: 'u-wk',
  email: 'wk@school.local',
  password: 'wk-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'عامل',
  permissions: '{"workers":["view"]}',
);

class Opened {
  Opened(this.runtime, this.provisioner);

  final AppRuntime runtime;
  final FakeAccountProvisioner provisioner;
}

Future<Opened> openWorkers(
  WidgetTester tester, {
  TestAccount account = _owner,
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
  await openMoreEntry(tester, 'العمال');
  return Opened(runtime, provisioner);
}

Finder fieldOf(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

/// يملأ نموذج عامل جديد: لا أيام محددة للعامل، فلا برنامج أسبوعي في النموذج.
Future<void> fillWorker(
  WidgetTester tester, {
  String name = 'سمير حداد',
  String phone = '0660123456',
  String full = '1500',
  String half = '800',
}) async {
  tester.view.physicalSize = const Size(420, 3200);
  await tester.pumpAndSettle();
  await tester.enterText(fieldOf('الاسم الكامل'), name);
  await tester.enterText(fieldOf('الهاتف'), phone);
  await tester.enterText(fieldOf('أجر اليوم الكامل (دج)'), full);
  await tester.enterText(fieldOf('أجر نصف اليوم (دج)'), half);
  await tester.pumpAndSettle();
}

Future<void> submit(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ClayButton, 'إضافة العامل'));
  await tester.pumpAndSettle();
}

Future<void> addWorker(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ClayButton, 'إضافة عامل'));
  await tester.pumpAndSettle();
  await fillWorker(tester);
  await submit(tester);
  // بيانات الدخول ثم ملف العامل.
  await tester.tap(find.widgetWithText(ClayButton, 'تم'));
  await tester.pumpAndSettle();
}

void main() {
  appTest('قائمة فارغة برسالة وزر إضافة', (tester) async {
    await openWorkers(tester);
    expect(find.text('لا يوجد عمال بعد'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'إضافة عامل'), findsOneWidget);
  });

  appTest('إضافة عامل: بيانات دخوله مرة واحدة ثم ملفه بأجريه', (tester) async {
    final o = await openWorkers(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة عامل'));
    await tester.pumpAndSettle();
    await fillWorker(tester);
    await submit(tester);

    expect(find.text('بيانات دخول سمير حداد'), findsOneWidget);
    expect(find.text('رقم الدخول'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ClayDialog),
        matching: find.text('0660123456'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('@school.local'), findsNothing);
    expect(o.provisioner.created.values.single.role, UserRole.worker);
    await tester.tap(find.widgetWithText(ClayButton, 'تم'));
    await tester.pumpAndSettle();

    // ملف العامل.
    expect(find.text('ملف العامل'), findsOneWidget);
    expect(find.text('سمير حداد'), findsOneWidget);
    expect(find.text(Money.format(1500)), findsOneWidget);
    expect(find.text(Money.format(800)), findsOneWidget);
    // لا برنامج أسبوعي: يُحسب يومه من وقت دخوله وخروجه حسب إعدادات المدرسة.
    expect(find.text('احتساب اليوم'), findsOneWidget);
    expect(find.textContaining('لا أيام عمل محددة'), findsOneWidget);
    expect(find.textContaining('4 ساعات'), findsOneWidget);
    expect(find.textContaining('8 ساعات'), findsOneWidget);
    expect(
      find.text('بلا صلاحيات؛ لا يرى شيئاً في التطبيق حتى تُفعَّل له'),
      findsOneWidget,
    );
    expect(find.byType(ClayQrCode), findsOneWidget);
  });

  appTest('أخطاء التحقق: اسم ناقص وأجر نصف أكبر من الكامل', (tester) async {
    await openWorkers(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة عامل'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(420, 3200);
    await tester.pumpAndSettle();
    await tester.enterText(fieldOf('الهاتف'), '0660123456');
    await tester.enterText(fieldOf('أجر اليوم الكامل (دج)'), '500');
    await tester.enterText(fieldOf('أجر نصف اليوم (دج)'), '900');
    await submit(tester);
    expect(find.text('أدخل اسم العامل'), findsOneWidget);
    expect(
      find.text('أجر نصف اليوم لا يزيد عن أجر اليوم الكامل'),
      findsOneWidget,
    );
    expect(find.text('اختر يوم عمل واحداً على الأقل'), findsNothing);
    expect(find.text('بيانات دخول'), findsNothing);
  });

  appTest('هاتف مستعمل يُرفض بخطئه', (tester) async {
    await openWorkers(tester);
    await addWorker(tester);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة عامل'));
    await tester.pumpAndSettle();
    await fillWorker(tester, name: 'آخر');
    await submit(tester);
    expect(find.text('رقم الهاتف مستعمل في حساب آخر'), findsOneWidget);
  });

  appTest('القائمة تعرض العامل بأجرَي يومه ونصفه، والبحث', (tester) async {
    await openWorkers(tester);
    await addWorker(tester);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('سمير حداد'), findsOneWidget);
    expect(
      find.textContaining(
        'يوم ${Money.format(1500)} · نصف يوم ${Money.format(800)}',
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).first, 'لا أحد');
    await tester.pumpAndSettle();
    expect(find.text('لا نتائج مطابقة للبحث'), findsOneWidget);
  });

  appTest('تعديل الأجرين', (tester) async {
    final o = await openWorkers(tester);
    await addWorker(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'تعديل البيانات'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(420, 3200);
    await tester.pumpAndSettle();
    expect(find.text('تعديل العامل'), findsOneWidget);
    await tester.enterText(fieldOf('أجر اليوم الكامل (دج)'), '2000');
    await tester.enterText(fieldOf('أجر نصف اليوم (دج)'), '1000');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ التعديلات'));
    await tester.pumpAndSettle();
    final row = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.workers).getSingle(),
    );
    expect(row.fullDayWage, 2000);
    expect(row.halfDayWage, 1000);
    expect(find.text(Money.format(2000)), findsOneWidget);
  });

  appTest('ضبط الصلاحيات: وحدات وأفعال، ثم الحفظ بصيغة الخادم', (tester) async {
    final o = await openWorkers(tester);
    await addWorker(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'ضبط الصلاحيات'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(420, 4200);
    await tester.pumpAndSettle();
    expect(find.text('صلاحيات العامل'), findsOneWidget);

    // «التلاميذ»: عرض وإضافة. «الماسح»: الكل.
    Finder chipIn(String module, String label) => find.descendant(
      of: find
          .ancestor(of: find.text(module), matching: find.byType(ClayCard))
          .first,
      matching: find.widgetWithText(ClayChip, label),
    );
    await tester.tap(chipIn('التلاميذ', 'عرض'));
    await tester.pumpAndSettle();
    await tester.tap(chipIn('التلاميذ', 'إضافة'));
    await tester.pumpAndSettle();
    await tester.tap(chipIn('الماسح', 'الكل'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ الصلاحيات'));
    await tester.pumpAndSettle();

    final row = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.workers).getSingle(),
    );
    expect(row.permissions, '{"students":["view","add"],"scanner":["use"]}');
    // الملف يعرض الوحدات المفعَّلة.
    expect(find.widgetWithText(ClayChip, 'التلاميذ'), findsOneWidget);
    expect(find.widgetWithText(ClayChip, 'الماسح'), findsOneWidget);
  });

  appTest('إعادة توليد كلمة السر والحذف', (tester) async {
    final o = await openWorkers(tester);
    await addWorker(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'إعادة توليد كلمة السر'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'إعادة التوليد'));
    await tester.pumpAndSettle();
    expect(find.text('بيانات دخول سمير حداد'), findsOneWidget);
    expect(o.provisioner.resets, isNotEmpty);
    await tester.tap(find.widgetWithText(ClayButton, 'تم'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ClayButton, 'حذف العامل'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حذف'));
    await tester.pumpAndSettle();
    expect(find.text('لا يوجد عمال بعد'), findsOneWidget);
  });

  appTest('صلاحية العرض فقط: قراءة بلا إضافة ولا تعديل', (tester) async {
    final o = await openWorkers(tester, account: _viewer);
    expect(find.widgetWithText(ClayButton, 'إضافة عامل'), findsNothing);
    final db = o.runtime.db;
    await runDb(tester, () async {
      await WorkerService(
        db,
        o.runtime.writer,
        AccountService(db, o.runtime.writer, o.provisioner),
      ).add(
        name: 'ياسين',
        phone: '0660000009',
        fullDayWage: 1000,
        halfDayWage: 500,
      );
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('ياسين'));
    await tester.pumpAndSettle();
    expect(find.text('ملف العامل'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'تعديل البيانات'), findsNothing);
    expect(find.widgetWithText(ClayButton, 'ضبط الصلاحيات'), findsNothing);
    expect(find.widgetWithText(ClayButton, 'حذف العامل'), findsNothing);
  });
}
