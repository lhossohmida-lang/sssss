import 'dart:io';

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

class Opened {
  Opened(this.runtime, this.provisioner);

  final AppRuntime runtime;
  final FakeAccountProvisioner provisioner;
}

Future<Opened> openTeachers(
  WidgetTester tester, {
  TestAccount account = owner,
  FakePhotoSource? photoSource,
}) async {
  final provisioner = FakeAccountProvisioner();
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: [account],
    pages: adminPages,
    provisioner: provisioner,
    photoSource: photoSource,
  );
  await loginWith(tester, account.email, account.password);
  await tester.tap(find.text('المزيد').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('الأساتذة'));
  await tester.pumpAndSettle();
  return Opened(runtime, provisioner);
}

Finder fieldOf(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

Future<void> saveDialog(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ClayButton, 'حفظ').last);
  await tester.pumpAndSettle();
}

Future<void> fillTeacher(
  WidgetTester tester, {
  String name = 'كمال بن علي',
  String phone = '0550123456',
}) async {
  await tester.enterText(fieldOf('الاسم الكامل'), name);
  await tester.enterText(fieldOf('الهاتف'), phone);
}

void main() {
  appTest('قائمة فارغة برسالة وزر إضافة', (tester) async {
    await openTeachers(tester);
    expect(find.text('لا يوجد أساتذة بعد'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'إضافة أستاذ'), findsOneWidget);
  });

  appTest('إضافة أستاذ: تظهر بياناته في القائمة وبيانات دخوله مرة واحدة', (
    tester,
  ) async {
    final o = await openTeachers(tester);
    await runDb(
      tester,
      () => SubjectService(
        o.runtime.db,
        o.runtime.writer,
      ).add(name: 'رياضيات', monthlyPrice: 2000),
    );
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة أستاذ'));
    await tester.pumpAndSettle();
    await fillTeacher(tester);
    await tester.tap(find.widgetWithText(ClayChip, 'رياضيات'));
    await tester.pump();
    await saveDialog(tester);

    // نافذة بيانات الدخول.
    expect(find.text('بيانات دخول كمال بن علي'), findsOneWidget);
    expect(find.text('0550123456@school.local'), findsOneWidget);
    final password = o.provisioner.created.values.single.password;
    expect(find.text(password), findsOneWidget);
    expect(find.textContaining('طابور الإرسال إلى 0550123456'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'تم'));
    await tester.pumpAndSettle();

    expect(find.text('كمال بن علي'), findsOneWidget);
    expect(find.text('رياضيات · 0550123456'), findsOneWidget);
    // وصل الرسالة في الطابور.
    final queued = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.smsQueue).get(),
    );
    expect(queued.single.message, contains(password));
  });

  appTest('أخطاء التحقق في الحقول ولا يُغلق النموذج', (tester) async {
    final o = await openTeachers(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة أستاذ'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldOf('الهاتف'), '123');
    await saveDialog(tester);
    expect(find.text('أدخل اسم الأستاذ'), findsOneWidget);
    expect(find.textContaining('يبدأ بـ 05'), findsOneWidget);
    expect(find.byType(ClayDialog), findsOneWidget);
    expect(o.provisioner.created, isEmpty);
  });

  appTest('هاتف مستعمل يُرفض بخطئه', (tester) async {
    final o = await openTeachers(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة أستاذ'));
    await tester.pumpAndSettle();
    await fillTeacher(tester);
    await saveDialog(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'تم'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ClayButton, 'إضافة أستاذ'));
    await tester.pumpAndSettle();
    await fillTeacher(tester, name: 'آخر');
    await saveDialog(tester);
    expect(find.text('رقم الهاتف مستعمل في حساب آخر'), findsOneWidget);
    expect(o.provisioner.created, hasLength(1));
  });

  appTest('فشل إنشاء الحساب على الخادم: رسالة ولا أستاذ', (tester) async {
    final o = await openTeachers(tester);
    o.provisioner.failing = true;
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة أستاذ'));
    await tester.pumpAndSettle();
    await fillTeacher(tester);
    await saveDialog(tester);
    expect(find.text('لا يوجد اتصال بالإنترنت'), findsOneWidget);
    expect(find.byType(ClayDialog), findsOneWidget);
    final rows = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.teachers).get(),
    );
    expect(rows, isEmpty);
  });

  appTest('البحث بالاسم والمادة', (tester) async {
    final o = await openTeachers(tester);
    await runDb(tester, () async {
      final math = (await SubjectService(
        o.runtime.db,
        o.runtime.writer,
      ).add(name: 'رياضيات', monthlyPrice: 2000)).id;
      final service = TeacherService(
        o.runtime.db,
        o.runtime.writer,
        AccountService(o.runtime.db, o.runtime.writer, o.provisioner),
      );
      await service.add(
        name: 'كمال',
        phone: '0550000001',
        subjectIds: {math},
        ratePerStudent: 0,
      );
      await service.add(
        name: 'ياسين',
        phone: '0550000002',
        subjectIds: const {},
        ratePerStudent: 0,
      );
    });
    expect(find.text('كمال'), findsOneWidget);
    expect(find.text('ياسين'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'رياض');
    await tester.pump();
    expect(find.text('كمال'), findsOneWidget);
    expect(find.text('ياسين'), findsNothing);
  });

  group('ملف الأستاذ', () {
    Future<(Opened, TeacherRow)> withTeacher(WidgetTester tester) async {
      final o = await openTeachers(tester);
      final created = await runDb(
        tester,
        () =>
            TeacherService(
              o.runtime.db,
              o.runtime.writer,
              AccountService(o.runtime.db, o.runtime.writer, o.provisioner),
            ).add(
              name: 'كمال بن علي',
              phone: '0550123456',
              subjectIds: const {},
              ratePerStudent: 800,
            ),
      );
      await tester.tap(find.text('كمال بن علي'));
      // شاشة طويلة حتى تُبنى أزرار آخر الصفحة.
      tester.view.physicalSize = const Size(420, 2400);
      await tester.pumpAndSettle();
      return (o, created.teacher);
    }

    appTest('يعرض البيانات ورمز QR', (tester) async {
      final (_, teacher) = await withTeacher(tester);
      expect(find.text('ملف الأستاذ'), findsOneWidget);
      expect(find.text('0550123456@school.local'), findsOneWidget);
      expect(find.text('800 دج'), findsOneWidget);
      expect(find.byType(ClayQrCode), findsOneWidget);
      expect(find.text(teacher.qrCode), findsOneWidget);
      expect(teacher.qrCode.startsWith('T-'), isTrue);
    });

    appTest('تعديل البيانات', (tester) async {
      final (o, teacher) = await withTeacher(tester);
      await tester.tap(find.widgetWithText(ClayButton, 'تعديل البيانات'));
      await tester.pumpAndSettle();
      await tester.enterText(fieldOf('الاسم الكامل'), 'كمال الدين');
      await saveDialog(tester);
      expect(find.text('كمال الدين'), findsOneWidget);
      final row = await runDb(
        tester,
        () => (o.runtime.db.select(
          o.runtime.db.teachers,
        )..where((t) => t.id.equals(teacher.id))).getSingle(),
      );
      expect(row.name, 'كمال الدين');
    });

    appTest('إعادة توليد كلمة السر تعرض الجديدة وتضع رسالة', (tester) async {
      final (o, teacher) = await withTeacher(tester);
      await tester.tap(
        find.widgetWithText(ClayButton, 'إعادة توليد كلمة السر'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'إعادة التوليد'));
      await tester.pumpAndSettle();
      expect(find.text('بيانات دخول كمال بن علي'), findsOneWidget);
      final accountId = o.provisioner.resets.keys.single;
      expect(find.text(o.provisioner.resets[accountId]!), findsOneWidget);
      expect(teacher.id, isNotEmpty);
    });

    appTest('الحذف يعطّل الحساب ويعيد إلى القائمة', (tester) async {
      final (o, teacher) = await withTeacher(tester);
      await tester.tap(find.widgetWithText(ClayButton, 'حذف الأستاذ'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'حذف').last);
      await tester.pumpAndSettle();
      expect(find.text('لا يوجد أساتذة بعد'), findsOneWidget);
      final account = await runDb(
        tester,
        () => AccountService(
          o.runtime.db,
          o.runtime.writer,
          o.provisioner,
        ).findByEmail(teacher.email),
      );
      expect(account, isNull);
    });

    appTest('أستاذ له مجموعة نشطة: لا يُحذف مع رسالة', (tester) async {
      final (o, teacher) = await withTeacher(tester);
      await runDb(tester, () async {
        final db = o.runtime.db;
        await db
            .into(db.subjects)
            .insert(
              SubjectsCompanion.insert(
                id: 'sub',
                createdAt: 1,
                updatedAt: 1,
                name: 'م',
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
                subjectId: 'sub',
                teacherId: teacher.id,
              ),
            );
      });
      await tester.tap(find.widgetWithText(ClayButton, 'حذف الأستاذ'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'حذف').last);
      await tester.pumpAndSettle();
      expect(find.text('تعذّرت العملية'), findsOneWidget);
      expect(find.textContaining('1 مجموعة نشطة'), findsOneWidget);
    });
  });

  appTest('عامل بصلاحية العرض: قراءة بلا إضافة ولا تعديل ولا حذف', (
    tester,
  ) async {
    final o = await openTeachers(
      tester,
      account: worker('{"teachers":["view"]}'),
    );
    expect(find.widgetWithText(ClayButton, 'إضافة أستاذ'), findsNothing);
    await runDb(
      tester,
      () =>
          TeacherService(
            o.runtime.db,
            o.runtime.writer,
            AccountService(o.runtime.db, o.runtime.writer, o.provisioner),
          ).add(
            name: 'كمال',
            phone: '0550123456',
            subjectIds: const {},
            ratePerStudent: 0,
          ),
    );
    await tester.tap(find.text('كمال'));
    tester.view.physicalSize = const Size(420, 2400);
    await tester.pumpAndSettle();
    expect(find.text('ملف الأستاذ'), findsOneWidget);
    expect(find.byType(ClayQrCode), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'تعديل البيانات'), findsNothing);
    expect(find.widgetWithText(ClayButton, 'حذف الأستاذ'), findsNothing);
    expect(
      find.widgetWithText(ClayButton, 'إعادة توليد كلمة السر'),
      findsNothing,
    );
  });

  group('الصورة', () {
    appTest('الصورة الملتقطة تُضغط وتُحفظ محلياً وتُوضع في طابور الرفع', (
      tester,
    ) async {
      final source = FakePhotoSource(samplePngBytes(width: 1600, height: 1200));
      final o = await openTeachers(tester, photoSource: source);
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة أستاذ'));
      await tester.pumpAndSettle();
      await fillTeacher(tester);
      await tester.tap(find.widgetWithText(ClayButton, 'التقاط صورة'));
      await tester.pumpAndSettle();
      expect(source.captures, 1);
      // الصورة الملتقطة تظهر وتتحول الأزرار إلى «تغيير».
      expect(find.widgetWithText(ClayButton, 'تغيير الصورة'), findsOneWidget);
      expect(find.text('إلغاء الصورة الملتقطة'), findsOneWidget);

      // الضغط يجري في isolate حقيقي: يُنتظر بزمن حقيقي، وبين ذلك تُدفع
      // الإطارات يدوياً (مؤشر التحميل يمنع pumpAndSettle من الاستقرار).
      await tester.tap(find.widgetWithText(ClayButton, 'حفظ').last);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        if (find.widgetWithText(ClayButton, 'تم').evaluate().isNotEmpty) break;
      }
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'تم'));
      await tester.pumpAndSettle();

      final teacher = (await runDb(
        tester,
        () => o.runtime.db.select(o.runtime.db.teachers).getSingle(),
      ));
      final path = teacher.photoLocalPath!;
      expect(path.startsWith(o.runtime.photosDirectory.path), isTrue);
      expect(File(path).existsSync(), isTrue);
      expect(File(path).lengthSync(), lessThan(200 * 1024));
      final queue = await runDb(
        tester,
        () => o.runtime.db.select(o.runtime.db.uploadQueue).getSingle(),
      );
      expect(queue.targetTable, 'teachers');
      expect(queue.targetColumn, 'photo_url');
      // الأستاذ يظهر بصورته في القائمة.
      expect(find.byType(Image), findsWidgets);
    });

    appTest('إلغاء الصورة الملتقطة يرجع إلى بلا صورة', (tester) async {
      final source = FakePhotoSource(samplePngBytes(width: 100, height: 100));
      await openTeachers(tester, photoSource: source);
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة أستاذ'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'التقاط صورة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إلغاء الصورة الملتقطة'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ClayButton, 'التقاط صورة'), findsOneWidget);
    });

    appTest('إلغاء الالتقاط لا يغيّر شيئاً', (tester) async {
      final source = FakePhotoSource(null);
      await openTeachers(tester, photoSource: source);
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة أستاذ'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'التقاط صورة'));
      await tester.pumpAndSettle();
      expect(source.captures, 1);
      expect(find.widgetWithText(ClayButton, 'التقاط صورة'), findsOneWidget);
    });
  });
}
