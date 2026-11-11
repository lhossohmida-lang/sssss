import 'package:admin/admin_tabs.dart';
import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/testing.dart';

const owner = TestAccount(
  id: 'u-owner',
  email: 'owner@school.local',
  password: 'owner-pass-1',
  role: UserRole.owner,
  displayName: 'المدير',
);

Future<AppRuntime> openStudents(WidgetTester tester) async {
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: [owner],
    pages: adminPages,
  );
  await loginWith(tester, owner.email, owner.password);
  await tester.tap(find.text('التلاميذ').last);
  await tester.pumpAndSettle();
  return runtime;
}

Future<void> seed(
  WidgetTester tester,
  AppRuntime runtime,
  int count, {
  String firstPrefix = 'اسم',
}) => runDb(tester, () async {
  await runtime.db.batch((batch) {
    batch.insertAll(runtime.db.students, [
      for (var i = 0; i < count; i++)
        StudentsCompanion.insert(
          id: 's$i',
          createdAt: 1,
          updatedAt: 1,
          firstName: '$firstPrefix$i',
          lastName: 'لقب${i.toString().padLeft(3, '0')}',
          parentPhone: '05${(50000000 + i).toString().padLeft(8, '0')}',
          qrCode: 'S-Q$i',
        ),
    ]);
  });
});

void main() {
  appTest('قائمة فارغة برسالة', (tester) async {
    await openStudents(tester);
    expect(find.text('لا يوجد تلاميذ بعد'), findsOneWidget);
  });

  appTest('يعرض أول صفحة والعدد الكلي ويحمّل المزيد بالتمرير', (tester) async {
    final runtime = await openStudents(tester);
    await seed(tester, runtime, 130);
    expect(find.text('130 تلميذ'), findsOneWidget);
    expect(find.text('اسم0 لقب000'), findsOneWidget);
    // الصف 100 لم يُحمَّل بعد.
    expect(find.text('اسم100 لقب100'), findsNothing);

    final list = find.byType(ListView);
    for (var i = 0; i < 40; i++) {
      await tester.drag(list, const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('اسم129 لقب129'), findsOneWidget);
  });

  appTest('القائمة ListView.builder بارتفاع صف ثابت', (tester) async {
    final runtime = await openStudents(tester);
    await seed(tester, runtime, 10);
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.itemExtent, 72);
  });

  appTest('البحث بالاسم واللقب والهاتف مع مهلة', (tester) async {
    final runtime = await openStudents(tester);
    await seed(tester, runtime, 30);
    await tester.enterText(find.byType(TextField).first, 'لقب007');
    // قبل انقضاء المهلة لم يتغير شيء.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('30 تلميذ'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('1 نتيجة'), findsOneWidget);
    expect(find.text('اسم7 لقب007'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '0550000002');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('اسم2 لقب002'), findsOneWidget);
    expect(find.text('اسم7 لقب007'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'لا أحد');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('لا نتائج مطابقة للبحث'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('30 تلميذ'), findsOneWidget);
  });

  appTest('اسم المستوى ورقم الوليّ في الصف', (tester) async {
    final runtime = await openStudents(tester);
    await runDb(tester, () async {
      final db = runtime.db;
      await db
          .into(db.levels)
          .insert(
            LevelsCompanion.insert(
              id: 'lv',
              createdAt: 1,
              updatedAt: 1,
              name: '3 متوسط',
              stage: 'middle',
              sortOrder: 203,
            ),
          );
      await db
          .into(db.students)
          .insert(
            StudentsCompanion.insert(
              id: 'a',
              createdAt: 1,
              updatedAt: 1,
              firstName: 'أحمد',
              lastName: 'علي',
              parentPhone: '0550123456',
              qrCode: 'S-A',
              levelId: const Value('lv'),
            ),
          );
    });
    expect(find.text('3 متوسط · 0550123456'), findsOneWidget);
  });

  appTest('الصورة المصغّرة تُقرأ من المسار المحلي مصغَّرةً', (tester) async {
    final runtime = await openStudents(tester);
    await runDb(
      tester,
      () => runtime.db
          .into(runtime.db.students)
          .insert(
            StudentsCompanion.insert(
              id: 'a',
              createdAt: 1,
              updatedAt: 1,
              firstName: 'أحمد',
              lastName: 'علي',
              parentPhone: '0550123456',
              qrCode: 'S-A',
              photoLocalPath: const Value('Z:/missing/photo.jpg'),
            ),
          ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    expect(image.errorBuilder, isNotNull);
    tester.takeException();
  });

  appTest('بلا صورة: الأحرف الأولى', (tester) async {
    final runtime = await openStudents(tester);
    await seed(tester, runtime, 1);
    expect(find.byType(Image), findsNothing);
    expect(find.text('ال'), findsOneWidget);
  });
}
