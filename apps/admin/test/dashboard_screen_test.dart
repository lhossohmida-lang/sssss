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

TestAccount _worker(String permissions) => TestAccount(
  id: 'u-w',
  email: 'w@school.local',
  password: 'w-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'عامل',
  permissions: permissions,
);

/// يفتح لوحة التحكم (أول تبويب بعد الدخول)، ويبذر بيانات إن طُلب.
Future<AppRuntime> openDashboard(
  WidgetTester tester, {
  TestAccount account = _owner,
  bool seed = false,
}) async {
  tester.view.physicalSize = const Size(420, 2000);
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: [account],
    pages: adminPages,
  );
  await loginWith(tester, account.email, account.password);
  if (seed) {
    final db = runtime.db;
    await runDb(tester, () async {
      await SettingsService(
        db,
        runtime.writer,
      ).save(const SchoolSettings(schoolName: 'مدرسة النجاح'));
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
                parentPhone: '0550123456',
                qrCode: 'S-$id',
              ),
            );
        await db
            .into(db.groupStudents)
            .insert(
              GroupStudentsCompanion.insert(
                id: 'gs-$id',
                createdAt: 1,
                updatedAt: 1,
                groupId: 'g1',
                studentId: id,
                joinedAt: 1,
                monthlyPrice: 2000,
              ),
            );
      }
      await PaymentService(
        db,
        runtime.writer,
        DuesService(db, runtime.writer),
        DeviceInfoStore(db),
      ).record(
        studentId: 's1',
        type: PaymentType.month,
        groupId: 'g1',
        cycleNumber: 1,
        amount: 500,
      );
    });
    await tester.pumpAndSettle();
  }
  return runtime;
}

void main() {
  appTest('المالك: ترحيب وكل البطاقات والإجراءات السريعة', (tester) async {
    await openDashboard(tester);
    expect(find.text('أهلاً المدير'), findsOneWidget);
    for (final label in [
      'حصص اليوم',
      'التلاميذ',
      'استُلم اليوم',
      'المستحقات',
      'خلاص الأساتذة',
      'انتظار بلغ حدّه',
      'حصص لم يحضرها أستاذها',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    for (final label in [
      'تسجيل تلميذ',
      'تسجيل دفعة',
      'الماسح',
      'الحضور',
      'شاشة المدخل',
    ]) {
      expect(find.widgetWithText(ClayButton, label), findsOneWidget);
    }
  });

  appTest('أرقام اليوم من البيانات: تلاميذ ومقبوضات ومستحقات', (tester) async {
    await openDashboard(tester, seed: true);
    expect(find.text('مدرسة النجاح', findRichText: true), findsNothing);
    expect(find.textContaining('مدرسة النجاح'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('1 مجموعة نشطة'), findsOneWidget);
    // 500 دج استُلمت اليوم، وما بقي 3500 على تلميذين.
    expect(find.text(Money.format(500)), findsWidgets);
    expect(find.text(Money.format(3500)), findsOneWidget);
    expect(find.text('2 تلميذ'), findsOneWidget);
    expect(find.text('الشهر ${Money.format(500)}'), findsOneWidget);
  });

  appTest('رسم مقبوضات الأسبوع يظهر بمجموعه', (tester) async {
    await openDashboard(tester, seed: true);
    await tester.scrollUntilVisible(
      find.textContaining('مقبوضات آخر 7 أيام'),
      200,
    );
    expect(find.textContaining('مقبوضات آخر 7 أيام'), findsOneWidget);
    expect(find.text('المجموع ${Money.format(500)}'), findsOneWidget);
  });

  appTest('عامل بصلاحية التلاميذ فقط: بطاقة التلاميذ بلا مال ولا إجراءات', (
    tester,
  ) async {
    await openDashboard(
      tester,
      account: _worker('{"students":["view"]}'),
      seed: false,
    );
    expect(find.text('التلاميذ'), findsWidgets);
    expect(find.text('استُلم اليوم'), findsNothing);
    expect(find.text('المستحقات'), findsNothing);
    expect(find.text('خلاص الأساتذة'), findsNothing);
    expect(find.text('حصص اليوم'), findsNothing);
    expect(find.widgetWithText(ClayButton, 'تسجيل تلميذ'), findsNothing);
    expect(find.widgetWithText(ClayButton, 'تسجيل دفعة'), findsNothing);
  });

  appTest('عامل بصلاحية الإضافة: زر تسجيل تلميذ', (tester) async {
    await openDashboard(
      tester,
      account: _worker('{"students":["view","add"]}'),
    );
    expect(find.widgetWithText(ClayButton, 'تسجيل تلميذ'), findsOneWidget);
  });

  appTest('عامل بلا صلاحيات: رسالة بدل الأرقام', (tester) async {
    await openDashboard(tester, account: _worker('{}'));
    expect(find.text('لا توجد بيانات متاحة'), findsOneWidget);
  });

  appTest('النقر على بطاقة المستحقات يفتح شاشتها', (tester) async {
    await openDashboard(tester, seed: true);
    await tester.tap(find.text('المستحقات'));
    await tester.pumpAndSettle();
    expect(find.text('2 تلميذ عليهم مستحقات'), findsOneWidget);
  });

  appTest('بطاقة التلاميذ تنقل إلى تبويبها', (tester) async {
    await openDashboard(tester, seed: true);
    await tester.tap(find.text('التلاميذ').first);
    await tester.pumpAndSettle();
    expect(find.text('سمير بن علي'), findsOneWidget);
  });

  appTest('الإجراء السريع «تسجيل تلميذ» يفتح الاستمارة', (tester) async {
    await openDashboard(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل تلميذ'));
    await tester.pumpAndSettle();
    expect(find.text('تسجيل تلميذ'), findsWidgets);
    expect(find.widgetWithText(ClayButton, 'تسجيل التلميذ'), findsOneWidget);
  });

  appTest('«المزيد»: أقسام مجمّعة بعناوينها وتختفي المجموعة الفارغة', (
    tester,
  ) async {
    await openDashboard(
      tester,
      account: _worker('{"rooms":["view"],"payments":["view"]}'),
    );
    await tester.tap(find.text('المزيد').last);
    await tester.pumpAndSettle();
    expect(find.text('المالية'), findsOneWidget);
    expect(find.text('النظام'), findsOneWidget);
    expect(find.text('التعليم'), findsNothing);
    expect(find.text('الفريق'), findsNothing);
    expect(find.text('المستحقات'), findsOneWidget);
    expect(find.text('القاعات'), findsOneWidget);
    expect(find.text('الإعدادات'), findsNothing);
  });

  appTest('«المزيد» للمالك: العناوين الأربعة', (tester) async {
    await openDashboard(tester);
    await tester.tap(find.text('المزيد').last);
    await tester.pumpAndSettle();
    expect(find.text('التعليم'), findsOneWidget);
    expect(find.text('المالية'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('النظام'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('النظام'), findsOneWidget);
  });
}
