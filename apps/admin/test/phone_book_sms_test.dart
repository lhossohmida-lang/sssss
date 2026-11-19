import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;

const _studentsViewer = TestAccount(
  id: 'u-sv',
  email: 'sv@school.local',
  password: 'sv-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'عامل',
  permissions: '{"students":["view"]}',
);

Future<void> _insertStudent(
  AppDatabase db,
  String id,
  String first, {
  required String phone,
  String? levelId,
}) => db
    .into(db.students)
    .insert(
      StudentsCompanion.insert(
        id: id,
        createdAt: 1,
        updatedAt: 1,
        firstName: first,
        lastName: 'بن علي',
        parentPhone: phone,
        qrCode: 'S-$id',
        levelId: Value(levelId),
      ),
    );

void main() {
  /// يفتح دليل الهواتف وفيه سنتان («3 متوسط» من البذر و«4 متوسط»).
  Future<AppRuntime> openBook(
    WidgetTester tester, {
    TestAccount account = owner,
  }) async {
    final runtime = await openGroups(tester, account: account);
    await runDb(
      tester,
      () => runtime.db
          .into(runtime.db.levels)
          .insert(
            LevelsCompanion.insert(
              id: 'lv4',
              createdAt: 1,
              updatedAt: 1,
              name: '4 متوسط',
              stage: 'middle',
              sortOrder: 204,
            ),
          ),
    );
    await openMoreEntry(tester, 'دليل الهواتف');
    tester.view.physicalSize = const Size(420, 3200);
    await tester.pumpAndSettle();
    return runtime;
  }

  /// خمسة تلاميذ: أخوان بهاتف وليّ واحد في 3 متوسط، وتلميذ في 4 متوسط، وبلا سنة، ورقم غير صالح للرسائل.
  Future<void> seedStudents(
    WidgetTester tester,
    AppRuntime runtime,
  ) => runDb(tester, () async {
    final db = runtime.db;
    await _insertStudent(db, 's1', 'سمير', phone: '0550111111', levelId: 'lv3');
    await _insertStudent(db, 's2', 'نور', phone: '0550111111', levelId: 'lv3');
    await _insertStudent(
      db,
      's3',
      'ياسين',
      phone: '0660222222',
      levelId: 'lv4',
    );
    await _insertStudent(db, 's4', 'ليلى', phone: '0770333333');
    await _insertStudent(db, 's5', 'زكرياء', phone: '12345', levelId: 'lv3');
  });

  Future<void> openStudentsTab(WidgetTester tester) async {
    await tester.tap(find.text('أرقام تلاميذنا'));
    await tester.pumpAndSettle();
  }

  group('أرقام تلاميذنا: التصنيف والتحديد', () {
    appTest('مرشّح السنة بأعدادها، وعدّادا المعروض والمحدَّد', (tester) async {
      final runtime = await openBook(tester);
      await seedStudents(tester, runtime);
      await openStudentsTab(tester);
      expect(find.text('المعروض 5 · المحدَّد 0'), findsOneWidget);
      expect(find.text('سمير بن علي'), findsOneWidget);
      expect(find.text('هاتف الوليّ: 0550111111 · 3 متوسط'), findsNWidgets(2));

      await pick(tester, 'السنة الدراسية', '3 متوسط (3)');
      expect(find.text('المعروض 3 · المحدَّد 0'), findsOneWidget);
      expect(find.text('ياسين بن علي'), findsNothing);

      await pick(tester, 'السنة الدراسية', '4 متوسط (1)');
      expect(find.text('المعروض 1 · المحدَّد 0'), findsOneWidget);
      expect(find.text('ياسين بن علي'), findsOneWidget);

      await pick(tester, 'السنة الدراسية', 'بلا سنة (1)');
      expect(find.text('ليلى بن علي'), findsOneWidget);
      expect(find.text('سمير بن علي'), findsNothing);

      // البحث يعمل داخل السنة المختارة، ولا نتائج عند عدم التطابق.
      await tester.enterText(
        find.widgetWithText(TextField, 'ابحث بالاسم أو الرقم'),
        'ياسين',
      );
      await tester.pumpAndSettle();
      expect(find.text('لا نتائج'), findsOneWidget);
    });

    appTest('تحديد الكل في المعروض وإلغاؤه، ومسح التحديد', (tester) async {
      final runtime = await openBook(tester);
      await seedStudents(tester, runtime);
      await openStudentsTab(tester);
      await pick(tester, 'السنة الدراسية', '3 متوسط (3)');

      await tester.tap(find.widgetWithText(ClayButton, 'تحديد الكل'));
      await tester.pumpAndSettle();
      expect(find.text('المعروض 3 · المحدَّد 3'), findsOneWidget);
      expect(
        find.widgetWithText(ClayButton, 'إلغاء تحديد الكل'),
        findsOneWidget,
      );
      // من خارج المعروض لا يُحدَّد أحد.
      await pick(tester, 'السنة الدراسية', 'كل السنوات (5)');
      expect(find.text('المعروض 5 · المحدَّد 3'), findsOneWidget);

      await tester.tap(find.widgetWithText(ClayButton, 'مسح التحديد'));
      await tester.pumpAndSettle();
      expect(find.text('المعروض 5 · المحدَّد 0'), findsOneWidget);

      // النقر على صف يبدّل تحديده.
      await tester.tap(find.text('سمير بن علي'));
      await tester.pumpAndSettle();
      expect(find.text('المعروض 5 · المحدَّد 1'), findsOneWidget);
      await tester.tap(find.text('سمير بن علي'));
      await tester.pumpAndSettle();
      expect(find.text('المعروض 5 · المحدَّد 0'), findsOneWidget);
    });

    appTest('تحديد عدد معين من أول القائمة، وخطأ العدد الخاطئ', (tester) async {
      final runtime = await openBook(tester);
      await seedStudents(tester, runtime);
      await openStudentsTab(tester);

      await tester.tap(find.widgetWithText(ClayButton, 'تحديد عدد'));
      await tester.pumpAndSettle();
      expect(find.text('المعروض 5'), findsOneWidget);
      await tester.enterText(
        fieldOf('عدد الأرقام (من أول القائمة المعروضة)'),
        '0',
      );
      await tester.tap(find.widgetWithText(ClayButton, 'تحديد'));
      await tester.pumpAndSettle();
      expect(find.text('اكتب عدداً من 1 إلى 5'), findsOneWidget);
      await tester.enterText(
        fieldOf('عدد الأرقام (من أول القائمة المعروضة)'),
        '9',
      );
      await tester.tap(find.widgetWithText(ClayButton, 'تحديد'));
      await tester.pumpAndSettle();
      expect(find.text('اكتب عدداً من 1 إلى 5'), findsOneWidget);

      await tester.enterText(
        fieldOf('عدد الأرقام (من أول القائمة المعروضة)'),
        '2',
      );
      await tester.tap(find.widgetWithText(ClayButton, 'تحديد'));
      await tester.pumpAndSettle();
      expect(find.text('المعروض 5 · المحدَّد 2'), findsOneWidget);
      expect(find.text('رسالة SMS إلى المحدَّدين (2)'), findsOneWidget);
    });

    appTest(
      'رسالة SMS دفعة واحدة: رسالة لكل رقم صالح مرة واحدة بأسماء أصحابه',
      (tester) async {
        final runtime = await openBook(tester);
        await seedStudents(tester, runtime);
        await openStudentsTab(tester);
        await pick(tester, 'السنة الدراسية', '3 متوسط (3)');
        // بلا تحديد: الزر معطّل.
        expect(
          tester
              .widget<ClayButton>(
                find.widgetWithText(ClayButton, 'رسالة SMS للمحدَّدين'),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.widgetWithText(ClayButton, 'تحديد الكل'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(ClayButton, 'رسالة SMS إلى المحدَّدين (3)'),
        );
        await tester.pumpAndSettle();

        // الأخوان بهاتف واحد رقم واحد، والثالث رقمه غير صالح للرسائل فيُتجاهل.
        expect(find.text('رسالة SMS إلى 1 رقماً'), findsOneWidget);
        expect(find.textContaining('يُتجاهل 1 رقم غير صالح'), findsOneWidget);

        // نص فارغ: خطأ.
        await tester.tap(
          find.widgetWithText(ClayButton, 'إضافة إلى طابور الرسائل'),
        );
        await tester.pumpAndSettle();
        expect(find.text('اكتب نص الرسالة'), findsOneWidget);

        await tester.enterText(
          fieldOf('نص الرسالة'),
          'مرحباً وليّ {name}: اجتماع يوم السبت',
        );
        await tester.pumpAndSettle();
        expect(
          find.text('مرحباً وليّ سمير بن علي و نور بن علي: اجتماع يوم السبت'),
          findsOneWidget,
          reason: 'المعاينة باسمي الأخوين',
        );
        await tester.tap(
          find.widgetWithText(ClayButton, 'إضافة إلى طابور الرسائل'),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('أُضيفت 1 رسالة إلى طابور الرسائل'),
          findsOneWidget,
        );
        expect(find.text('المعروض 3 · المحدَّد 0'), findsOneWidget);
        final queue = await runDb(
          tester,
          () => runtime.db.select(runtime.db.smsQueue).get(),
        );
        expect(queue, hasLength(1));
        expect(queue.single.kind, SmsTemplateKeys.broadcast);
        expect(queue.single.status, 'pending');
        expect(queue.single.phone, contains('550111111'));
        expect(
          queue.single.message,
          'مرحباً وليّ سمير بن علي و نور بن علي: اجتماع يوم السبت',
        );
      },
    );

    appTest('تحديد كل التلاميذ يرسل لكل الأرقام الصالحة المختلفة', (
      tester,
    ) async {
      final runtime = await openBook(tester);
      await seedStudents(tester, runtime);
      await openStudentsTab(tester);
      await tester.tap(find.widgetWithText(ClayButton, 'تحديد الكل'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(ClayButton, 'رسالة SMS إلى المحدَّدين (5)'),
      );
      await tester.pumpAndSettle();
      // أربعة أرقام مختلفة: 0550111111 (الأخوان) و0660222222 و0770333333 وغير الصالح يُتجاهل.
      expect(find.text('رسالة SMS إلى 3 رقماً'), findsOneWidget);
      await tester.enterText(fieldOf('نص الرسالة'), 'تذكير من {school}');
      await tester.tap(
        find.widgetWithText(ClayButton, 'إضافة إلى طابور الرسائل'),
      );
      await tester.pumpAndSettle();
      final queue = await runDb(
        tester,
        () => runtime.db.select(runtime.db.smsQueue).get(),
      );
      expect(queue, hasLength(3));
      // لا اسم للمدرسة في الاختبار: «المدرسة».
      expect(queue.every((m) => m.message == 'تذكير من المدرسة'), isTrue);
    });

    appTest('بلا صلاحية الرسائل: التصنيف ظاهر وبلا أزرار التحديد والرسالة', (
      tester,
    ) async {
      final runtime = await openBook(tester, account: _studentsViewer);
      await seedStudents(tester, runtime);
      await openStudentsTab(tester);
      expect(find.text('المعروض 5 · المحدَّد 0'), findsOneWidget);
      await pick(tester, 'السنة الدراسية', '4 متوسط (1)');
      expect(find.text('ياسين بن علي'), findsOneWidget);
      expect(find.widgetWithText(ClayButton, 'تحديد الكل'), findsNothing);
      expect(find.widgetWithText(ClayButton, 'تحديد عدد'), findsNothing);
      expect(find.textContaining('رسالة SMS'), findsNothing);
    });
  });

  group('أرقام مسجَّلة: السنة والتصنيف والرسالة', () {
    appTest('رقم بسنة من نافذة الإضافة، ويظهر في تصنيفها ومع الرقم', (
      tester,
    ) async {
      final runtime = await openBook(tester);
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة رقم'));
      await tester.pumpAndSettle();
      await tester.enterText(fieldOf('الاسم (اختياري)'), 'أم سارة');
      await tester.enterText(fieldOf('رقم الهاتف'), '0551234567');
      await pick(tester, 'السنة الدراسية (اختياري)', '3 متوسط');
      await tester.tap(find.widgetWithText(ClayButton, 'حفظ'));
      await tester.pumpAndSettle();

      final row = (await runDb(
        tester,
        () => runtime.db.select(runtime.db.contacts).get(),
      )).single;
      expect(row.levelId, 'lv3');
      expect(find.textContaining('0551234567 · 3 متوسط'), findsOneWidget);
      expect(find.text('المعروض 1 · المحدَّد 0'), findsOneWidget);

      // التعديل يغيّر السنة أو يمسحها.
      await tester.tap(find.byTooltip('تعديل'));
      await tester.pumpAndSettle();
      await pick(tester, 'السنة الدراسية (اختياري)', 'بلا سنة');
      await tester.tap(find.widgetWithText(ClayButton, 'حفظ'));
      await tester.pumpAndSettle();
      expect(
        (await runDb(
          tester,
          () => runtime.db.select(runtime.db.contacts).get(),
        )).single.levelId,
        isNull,
      );
    });

    appTest('تصنيف الأرقام المسجَّلة وإرسال رسالة لمن اختير', (tester) async {
      final runtime = await openBook(tester);
      await runDb(tester, () async {
        final contacts = ContactService(runtime.db, runtime.writer);
        await contacts.add(
          name: 'أم سارة',
          phone: '0551234567',
          levelId: 'lv3',
        );
        await contacts.add(
          name: 'أبو يوسف',
          phone: '0661112233',
          levelId: 'lv4',
        );
        await contacts.add(name: 'سعاد', phone: '0211234567');
      });
      await tester.pumpAndSettle();
      expect(find.text('المعروض 3 · المحدَّد 0'), findsOneWidget);
      await pick(tester, 'السنة الدراسية', '4 متوسط (1)');
      expect(find.text('أبو يوسف'), findsOneWidget);
      expect(find.text('أم سارة'), findsNothing);

      await pick(tester, 'السنة الدراسية', 'كل السنوات (3)');
      await tester.tap(find.widgetWithText(ClayButton, 'تحديد الكل'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(ClayButton, 'رسالة SMS إلى المحدَّدين (3)'),
      );
      await tester.pumpAndSettle();
      // الهاتف الثابت لا يصلح للرسائل فيُتجاهل.
      expect(find.text('رسالة SMS إلى 2 رقماً'), findsOneWidget);
      expect(find.textContaining('يُتجاهل 1 رقم غير صالح'), findsOneWidget);
      await tester.enterText(fieldOf('نص الرسالة'), 'سجّلوا أبناءكم: {name}');
      await tester.tap(
        find.widgetWithText(ClayButton, 'إضافة إلى طابور الرسائل'),
      );
      await tester.pumpAndSettle();
      final queue = await runDb(
        tester,
        () => runtime.db.select(runtime.db.smsQueue).get(),
      );
      expect(
        queue.map((m) => m.message),
        unorderedEquals([
          'سجّلوا أبناءكم: أم سارة',
          'سجّلوا أبناءكم: أبو يوسف',
        ]),
      );
    });
  });
}
