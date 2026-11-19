import 'package:admin/screens/guests_panel.dart';
import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;
import 'support/groups_nav.dart';

const _studentsViewer = TestAccount(
  id: 'u-sv',
  email: 'sv@school.local',
  password: 'sv-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'عامل',
  permissions: '{"students":["view"]}',
);

ContactService _contacts(AppRuntime runtime) =>
    ContactService(runtime.db, runtime.writer);

GroupService _groupService(AppRuntime runtime) => GroupService(
  runtime.db,
  runtime.writer,
  ScheduleService(runtime.db),
  CycleService(runtime.db, runtime.writer),
);

Future<void> _insertStudent(
  AppDatabase db,
  String id,
  String first, {
  String phone = '0550123456',
  bool singleUse = false,
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
        singleUse: Value(singleUse),
      ),
    );

/// يختار يوماً من الشهر الذي يبعد [months] شهراً عن الحالي في منتقي التاريخ المفتوح.
Future<void> _pickDay(
  WidgetTester tester, {
  required int months,
  required int day,
}) async {
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

void main() {
  group('دليل الهواتف', () {
    Future<AppRuntime> openBook(
      WidgetTester tester, {
      TestAccount account = owner,
    }) async {
      final runtime = await openGroups(tester, account: account);
      await openMoreEntry(tester, 'دليل الهواتف');
      return runtime;
    }

    Future<void> addDialog(
      WidgetTester tester, {
      String name = '',
      String phone = '',
      String note = '',
    }) async {
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة رقم'));
      await tester.pumpAndSettle();
      if (name.isNotEmpty) {
        await tester.enterText(fieldOf('الاسم (اختياري)'), name);
      }
      if (phone.isNotEmpty) {
        await tester.enterText(fieldOf('رقم الهاتف'), phone);
      }
      if (note.isNotEmpty) {
        await tester.enterText(fieldOf('ملاحظة (مثلاً: اتصل بعد شهر)'), note);
      }
      await tester.pumpAndSettle();
    }

    appTest('فارغ برسالة، ثم إضافة رقم فيظهر ويُحفظ ككتابة يدوية', (
      tester,
    ) async {
      final runtime = await openBook(tester);
      expect(find.text('دليل الهواتف'), findsWidgets);
      expect(find.text('لا أرقام مسجَّلة'), findsOneWidget);
      await addDialog(
        tester,
        name: 'أم سارة',
        phone: '0551234567',
        note: 'اتصل بعد شهر',
      );
      await tester.tap(find.widgetWithText(ClayButton, 'حفظ'));
      await tester.pumpAndSettle();

      expect(find.text('لا أرقام مسجَّلة'), findsNothing);
      expect(find.text('أم سارة'), findsOneWidget);
      expect(find.textContaining('0551234567 · اتصل بعد شهر'), findsOneWidget);
      final rows = await runDb(
        tester,
        () => runtime.db.select(runtime.db.contacts).get(),
      );
      expect(rows, hasLength(1));
      expect(rows.single.source, ContactService.sourceManual);
      expect(rows.single.followUpDate, isNull);
    });

    appTest('رقم ناقص أو غير صالح: خطأ عربي عند الحقل ولا حفظ', (tester) async {
      final runtime = await openBook(tester);
      await addDialog(tester, name: 'بلا رقم');
      await tester.tap(find.widgetWithText(ClayButton, 'حفظ'));
      await tester.pumpAndSettle();
      expect(find.text('أدخل رقم الهاتف'), findsOneWidget);

      await tester.enterText(fieldOf('رقم الهاتف'), 'abc');
      await tester.tap(find.widgetWithText(ClayButton, 'حفظ'));
      await tester.pumpAndSettle();
      expect(
        find.text('رقم الهاتف غير صحيح (أرقام فقط، من 8 إلى 15 رقماً)'),
        findsOneWidget,
      );
      expect(
        await runDb(tester, () => runtime.db.select(runtime.db.contacts).get()),
        isEmpty,
      );
      // الإلغاء يغلق النافذة.
      await tester.tap(find.widgetWithText(ClayButton, 'إلغاء'));
      await tester.pumpAndSettle();
      expect(find.text('إضافة رقم'), findsOneWidget);
      expect(find.text('رقم الهاتف'), findsNothing);
    });

    appTest('تاريخ تواصل حلّ موعده: شارة «حان الاتصال» ويُحفظ التاريخ', (
      tester,
    ) async {
      final runtime = await openBook(tester);
      await addDialog(tester, name: 'أبو يوسف', phone: '0661112233');
      expect(find.text('بلا تاريخ تواصل'), findsOneWidget);
      await tester.tap(find.widgetWithText(ClayButton, 'تحديد تاريخ'));
      await tester.pumpAndSettle();
      // الخامس عشر من الشهر الماضي: موعد فات فيحين الاتصال.
      await _pickDay(tester, months: -1, day: 15);
      expect(find.textContaining('التواصل:'), findsOneWidget);
      expect(find.text('بلا تاريخ تواصل'), findsNothing);
      await tester.tap(find.widgetWithText(ClayButton, 'حفظ'));
      await tester.pumpAndSettle();

      expect(find.text('حان الاتصال'), findsOneWidget);
      expect(find.textContaining('(حان)'), findsOneWidget);
      final row = (await runDb(
        tester,
        () => runtime.db.select(runtime.db.contacts).get(),
      )).single;
      final now = DateTime.now();
      expect(
        row.followUpDate,
        DateKey.of(DateTime(now.year, now.month - 1, 15)),
      );
    });

    appTest('موعد بعيد لا شارة له، والرقم المسجَّل من حصة واحدة يحمل شارتها', (
      tester,
    ) async {
      final runtime = await openBook(tester);
      final next = DateKey.of(DateTime.now().add(const Duration(days: 40)));
      await runDb(tester, () async {
        final contacts = _contacts(runtime);
        await contacts.add(
          name: 'سعاد',
          phone: '0771234567',
          followUpDate: next,
        );
        await contacts.add(
          name: 'زائر',
          phone: '0661234567',
          source: ContactService.sourceOneTime,
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('سعاد'), findsOneWidget);
      expect(find.text('حان الاتصال'), findsNothing);
      expect(find.text('حصة واحدة'), findsOneWidget);
    });

    appTest('البحث بالاسم والرقم والملاحظة، وتعديل رقم، وحذفه بتأكيد', (
      tester,
    ) async {
      final runtime = await openBook(tester);
      await runDb(tester, () async {
        final contacts = _contacts(runtime);
        await contacts.add(
          name: 'أم سارة',
          phone: '0551234567',
          note: 'اتصل بعد شهر',
        );
        await contacts.add(
          name: 'أبو يوسف',
          phone: '0661112233',
          note: 'مراجعة الرياضيات',
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('أم سارة'), findsOneWidget);
      expect(find.text('أبو يوسف'), findsOneWidget);

      Future<void> search(String query) async {
        await tester.enterText(
          find.widgetWithText(TextField, 'ابحث بالاسم أو الرقم أو الملاحظة'),
          query,
        );
        await tester.pumpAndSettle();
      }

      await search('يوسف');
      expect(find.text('أبو يوسف'), findsOneWidget);
      expect(find.text('أم سارة'), findsNothing);
      await search('0551');
      expect(find.text('أم سارة'), findsOneWidget);
      expect(find.text('أبو يوسف'), findsNothing);
      await search('الرياضيات');
      expect(find.text('أبو يوسف'), findsOneWidget);
      await search('غير موجود');
      expect(find.text('لا نتائج'), findsOneWidget);

      // تعديل ما بقي بعد البحث عن «يوسف».
      await search('يوسف');
      await tester.tap(find.byTooltip('تعديل'));
      await tester.pumpAndSettle();
      expect(find.text('تعديل الرقم'), findsOneWidget);
      expect(textOf(tester, 'رقم الهاتف'), '0661112233');
      await tester.enterText(fieldOf('الاسم (اختياري)'), 'يوسف الأب');
      await tester.tap(find.widgetWithText(ClayButton, 'حفظ'));
      await tester.pumpAndSettle();
      expect(find.text('يوسف الأب'), findsOneWidget);

      // الحذف يحتاج تأكيداً ثم يخفي الرقم (حذف ناعم).
      await tester.tap(find.byTooltip('حذف'));
      await tester.pumpAndSettle();
      expect(find.text('حذف الرقم'), findsOneWidget);
      await tester.tap(find.widgetWithText(ClayButton, 'حذف'));
      await tester.pumpAndSettle();
      expect(find.text('يوسف الأب'), findsNothing);
      final all = await runDb(
        tester,
        () => runtime.db.select(runtime.db.contacts).get(),
      );
      expect(all.where((c) => c.deletedAt != null), hasLength(1));
      expect(all.where((c) => c.deletedAt == null).single.name, 'أم سارة');
    });

    appTest('أرقام تلاميذنا: أولياء المسجَّلين فقط دون تلاميذ المرة الواحدة', (
      tester,
    ) async {
      final runtime = await openBook(tester);
      await runDb(tester, () async {
        await _insertStudent(runtime.db, 's1', 'سمير');
        await _insertStudent(
          runtime.db,
          's2',
          'زائر',
          phone: '0660000009',
          singleUse: true,
        );
      });
      await tester.tap(find.text('أرقام تلاميذنا'));
      await tester.pumpAndSettle();
      expect(find.text('سمير بن علي'), findsOneWidget);
      expect(find.text('هاتف الوليّ: 0550123456'), findsOneWidget);
      expect(find.text('زائر بن علي'), findsNothing);
      // للقراءة فقط: لا إضافة هنا.
      expect(find.widgetWithText(ClayButton, 'إضافة رقم'), findsNothing);
    });

    appTest('صلاحية عرض التلاميذ فقط: قراءة بلا إضافة ولا تعديل ولا حذف', (
      tester,
    ) async {
      final runtime = await openBook(tester, account: _studentsViewer);
      await runDb(
        tester,
        () => _contacts(runtime).add(name: 'أم سارة', phone: '0551234567'),
      );
      await tester.pumpAndSettle();
      expect(find.text('أم سارة'), findsOneWidget);
      expect(find.widgetWithText(ClayButton, 'إضافة رقم'), findsNothing);
      expect(find.byTooltip('تعديل'), findsNothing);
      expect(find.byTooltip('حذف'), findsNothing);
      expect(find.byTooltip('نسخ الرقم'), findsOneWidget);
    });
  });

  group('فوج منتظِر', () {
    const targetLabel = 'عدد التلاميذ المطلوب لبدء الفوج';

    Finder waitingToggle() => find.descendant(
      of: find
          .ancestor(
            of: find.text('فوج منتظِر (بلا موعد لأول حصة بعد)'),
            matching: find.byType(Row),
          )
          .first,
      matching: find.byType(ClayToggle),
    );

    appTest('النموذج: التفعيل يُظهر العدد المطلوب ويخفي الجدول وتاريخ الأول', (
      tester,
    ) async {
      await openGroups(tester);
      await openForm(tester);
      await fillBasics(tester);
      expect(find.text(targetLabel), findsNothing);
      expect(find.text('إضافة خانة'), findsOneWidget);
      expect(find.text('تاريخ أول حصة'), findsOneWidget);

      await tester.tap(waitingToggle());
      await tester.pumpAndSettle();
      expect(find.text(targetLabel), findsOneWidget);
      expect(find.text('إضافة خانة'), findsNothing);
      expect(find.text('تاريخ أول حصة'), findsNothing);
      expect(find.textContaining('لا جدول لفوج منتظِر'), findsOneWidget);

      // إيقاف التفعيل يعيد الجدول وتاريخ أول حصة.
      await tester.tap(waitingToggle());
      await tester.pumpAndSettle();
      expect(find.text(targetLabel), findsNothing);
      expect(find.text('إضافة خانة'), findsOneWidget);
    });

    appTest('العدد المطلوب إلزامي وصالح، ثم يُنشأ الفوج بلا جدول ولا حصص', (
      tester,
    ) async {
      final runtime = await openGroups(tester);
      await openForm(tester);
      await fillBasics(tester);
      await tester.tap(waitingToggle());
      await tester.pumpAndSettle();

      await submit(tester);
      const targetError = 'أدخل عدد التلاميذ المطلوب لبدء الفوج (من 1 إلى 500)';
      expect(find.text(targetError), findsOneWidget);
      await typeIn(tester, targetLabel, '0');
      await submit(tester);
      expect(find.text(targetError), findsOneWidget);
      expect(
        await runDb(tester, () => runtime.db.select(runtime.db.groups).get()),
        isEmpty,
      );

      await typeIn(tester, targetLabel, '2');
      await submit(tester);
      // تُفتح صفحة الإعداد لإضافة تلاميذه من المكان نفسه.
      expect(find.text('رياضيات (3 متوسط) · الفوج 1'), findsOneWidget);
      await finishSetup(tester);

      final db = runtime.db;
      final group = (await runDb(
        tester,
        () => db.select(db.groups).get(),
      )).single;
      expect(group.waitingTarget, 2);
      expect(group.startAlertedAt, isNull);
      expect(group.isReview, isFalse);
      expect(
        await runDb(tester, () => db.select(db.groupSlots).get()),
        isEmpty,
      );
      expect(await runDb(tester, () => db.select(db.sessions).get()), isEmpty);

      await openGroupList(tester);
      expect(find.text('فوج 1'), findsOneWidget);
      expect(
        find.textContaining('منتظِر 0 من 2 — بلا موعد لأول حصة بعد'),
        findsOneWidget,
      );
    });

    /// فوج منتظِر قائم (هدفه تلميذ واحد) وفيه تلميذ، ثم تفتح شاشة تحديد تاريخ أول حصة من تعديله.
    Future<AppRuntime> openStart(WidgetTester tester) async {
      final runtime = await openGroups(tester);
      await runDb(tester, () async {
        final group = await _groupService(runtime).createWaiting(
          subjectId: 'math',
          teacherId: 't1',
          roomId: 'r1',
          monthlyPrice: 2000,
          ratePerStudent: 800,
          waitingTarget: 1,
        );
        await _insertStudent(runtime.db, 's1', 'سمير');
        await runtime.db
            .into(runtime.db.groupStudents)
            .insert(
              GroupStudentsCompanion.insert(
                id: 'gs-s1',
                createdAt: 1,
                updatedAt: 1,
                groupId: group.id,
                studentId: 's1',
                joinedAt: 1,
                monthlyPrice: 2000,
              ),
            );
      });
      await tester.pumpAndSettle();
      await openGroupList(tester);
      await tester.tap(find.byTooltip('تعديل الفوج 1'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(420, 3200);
      await tester.pumpAndSettle();
      return runtime;
    }

    appTest('تعديل الفوج المنتظِر: زر تحديد تاريخ أول حصة بدل الجدول', (
      tester,
    ) async {
      await openStart(tester);
      expect(find.text('تعديل الفوج'), findsOneWidget);
      expect(find.textContaining('لا جدول لفوج منتظِر'), findsOneWidget);
      expect(find.text('إضافة خانة'), findsNothing);
      // العدد المطلوب يُحدَّد عند الإنشاء فقط.
      expect(find.text(targetLabel), findsNothing);
      await tester.tap(find.widgetWithText(ClayButton, 'تحديد تاريخ أول حصة'));
      await tester.pumpAndSettle();
      expect(find.text('الخانة 1'), findsOneWidget);
      expect(find.text('بدء الفوج'), findsOneWidget);
    });

    appTest('بدء الفوج: تُولَّد حصص الدورة ويُبلَّغ الأولياء ويزول الانتظار', (
      tester,
    ) async {
      final runtime = await openStart(tester);
      await tester.tap(find.widgetWithText(ClayButton, 'تحديد تاريخ أول حصة'));
      await tester.pumpAndSettle();
      expect(find.text('رياضيات · الفوج 1'), findsOneWidget);
      expect(
        find.textContaining('كمال · 1 من 1 تلميذاً — اكتمل العدد'),
        findsOneWidget,
      );
      // التاريخ المقترح اليوم.
      expect(find.text(DateKey.of(DateTime.now())), findsOneWidget);

      await tester.tap(find.widgetWithText(ClayButton, 'بدء الفوج'));
      await tester.pumpAndSettle();

      final db = runtime.db;
      final sessions = await runDb(tester, () => db.select(db.sessions).get());
      expect(sessions, hasLength(8));
      expect(
        sessions
            .map((s) => s.date)
            .reduce((a, b) => a.compareTo(b) <= 0 ? a : b)
            .compareTo(DateKey.of(DateTime.now())),
        greaterThanOrEqualTo(0),
        reason: 'لا حصة في الماضي',
      );
      final slots = await runDb(tester, () => db.select(db.groupSlots).get());
      expect(slots.where((s) => s.deletedAt == null), hasLength(1));
      // رسالة الموعد إلى ولي التلميذ، مرة واحدة.
      final sms = await runDb(tester, () => db.select(db.smsQueue).get());
      expect(
        sms.where((m) => m.kind == SmsTemplateKeys.groupStarted),
        hasLength(1),
      );
      // يفتح صفحة الفوج بعد البدء، ولا يظهر منتظِراً بعد الآن.
      expect(find.text('رياضيات'), findsWidgets);
      expect(find.text('الدورة 1 (الحالية)'), findsOneWidget);
    });

    appTest('تاريخ أول حصة في الماضي: خطأ عند التاريخ ولا حصص', (tester) async {
      final runtime = await openStart(tester);
      await tester.tap(find.widgetWithText(ClayButton, 'تحديد تاريخ أول حصة'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'تغيير التاريخ'));
      await tester.pumpAndSettle();
      await _pickDay(tester, months: -1, day: 15);
      await tester.tap(find.widgetWithText(ClayButton, 'بدء الفوج'));
      await tester.pumpAndSettle();
      expect(find.text('اختر تاريخاً من اليوم فصاعداً'), findsOneWidget);
      expect(
        await runDb(tester, () => runtime.db.select(runtime.db.sessions).get()),
        isEmpty,
      );
    });
  });

  group('حصة المراجعة والضيوف', () {
    const feeLabel = 'ثمن الحصة (دج)';
    const rateLabelReview = 'نصيب الأستاذ عن كل حاضر (دج)';

    Future<AppRuntime> openReview(WidgetTester tester) async {
      final runtime = await openGroups(tester);
      await tester.tap(
        find.widgetWithText(ClayButton, 'حصة مراجعة (حصة واحدة)'),
      );
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(420, 3200);
      await tester.pumpAndSettle();
      return runtime;
    }

    /// ينشئ حصة مراجعة بثمن 500 ونصيب أستاذ 800 فتُفتح ورقة حضورها.
    Future<AppRuntime> createReview(WidgetTester tester) async {
      final runtime = await openReview(tester);
      await pick(tester, 'المادة', 'رياضيات');
      await pick(tester, yearLabel, '3 متوسط');
      await pick(tester, 'الأستاذ', 'كمال');
      await typeIn(tester, feeLabel, '500');
      await tester.tap(find.widgetWithText(ClayButton, 'إنشاء حصة المراجعة'));
      await tester.pumpAndSettle();
      return runtime;
    }

    Future<void> openGuests(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(ClayButton, 'ضيوف الحصة'));
      await tester.pumpAndSettle();
    }

    Future<SessionGuestRow> onlyGuest(
      WidgetTester tester,
      AppRuntime runtime,
    ) async => (await runDb(
      tester,
      () => runtime.db.select(runtime.db.sessionGuests).get(),
    )).single;

    appTest('النموذج الفارغ: أخطاء عربية ولا فوج', (tester) async {
      final runtime = await openReview(tester);
      expect(find.text('حصة مراجعة'), findsWidgets);
      await tester.tap(find.widgetWithText(ClayButton, 'إنشاء حصة المراجعة'));
      await tester.pumpAndSettle();
      expect(find.text('اختر المادة'), findsWidgets);
      expect(find.text('اختر الأستاذ'), findsWidgets);
      expect(find.text('أدخل ثمن الحصة'), findsOneWidget);
      expect(find.text('أدخل ما يأخذه الأستاذ عن كل حاضر'), findsOneWidget);
      expect(
        await runDb(tester, () => runtime.db.select(runtime.db.groups).get()),
        isEmpty,
      );
    });

    appTest('الأستاذ يقترح نصيبه، والإنشاء يفتح ورقة حضور الحصة', (
      tester,
    ) async {
      final runtime = await openReview(tester);
      await pick(tester, 'المادة', 'رياضيات');
      await pick(tester, yearLabel, '3 متوسط');
      await pick(tester, 'الأستاذ', 'كمال');
      expect(textOf(tester, rateLabelReview), '800');
      await typeIn(tester, feeLabel, '500');
      await tester.tap(find.widgetWithText(ClayButton, 'إنشاء حصة المراجعة'));
      await tester.pumpAndSettle();

      // ورقة الحضور مفتوحة وفيها زر ضيوف الحصة.
      expect(find.widgetWithText(ClayButton, 'ضيوف الحصة'), findsOneWidget);
      final db = runtime.db;
      final group = (await runDb(
        tester,
        () => db.select(db.groups).get(),
      )).single;
      expect(group.isReview, isTrue);
      expect(group.sessionsPerCycle, 1);
      expect(group.monthlyPrice, 500);
      expect(group.ratePerStudent, 800);
      expect(
        await runDb(tester, () => db.select(db.groupSlots).get()),
        isEmpty,
      );
      final session = (await runDb(
        tester,
        () => db.select(db.sessions).get(),
      )).single;
      expect(session.date, DateKey.of(DateTime.now()));
      expect(session.startMinutes, 600);
      expect(session.endMinutes, 780);
    });

    appTest('ضيف لمرة واحدة: سعر مقترح، تذكرة QR، دفع، ورقمه في الدليل', (
      tester,
    ) async {
      final runtime = await createReview(tester);
      await openGuests(tester);
      expect(find.text('لا ضيوف بعد'), findsOneWidget);
      await tester.tap(find.widgetWithText(ClayButton, 'تلميذ لمرة واحدة'));
      await tester.pumpAndSettle();
      // ثمن الحصة ونصيب الأستاذ المقترحان من حصة المراجعة، ويُدفع الثمن كاملاً مبدئياً.
      expect(textOf(tester, 'ثمن هذه الحصة (دج)'), '500');
      expect(textOf(tester, 'ما يأخذه الأستاذ عنه (دج)'), '800');
      expect(textOf(tester, 'المدفوع الآن (دج)'), '500');

      await tester.enterText(fieldOf('الاسم'), 'زائر المراجعة');
      await tester.enterText(
        fieldOf('الهاتف (اختياري، يُسجَّل في دليل الهواتف)'),
        '0661112233',
      );
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة'));
      await tester.pumpAndSettle();

      // تذكرة الدخول بعد الإضافة.
      expect(find.text('تذكرة زائر المراجعة'), findsOneWidget);
      expect(find.byType(ClayQrCode), findsOneWidget);
      expect(find.textContaining('تُمسح عند الدخول'), findsOneWidget);
      expect(find.textContaining('مدفوع'), findsWidgets);
      await tester.tap(find.widgetWithText(ClayButton, 'إغلاق'));
      await tester.pumpAndSettle();

      // اسمه في قائمة الضيوف، وصفّه كذلك في ورقة الحضور خلفها.
      expect(
        find.descendant(
          of: find.byType(GuestsSheet),
          matching: find.text('زائر المراجعة'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('لمرة واحدة · ${Money.format(500)} · مدفوع'),
        findsOneWidget,
      );
      expect(find.byTooltip('تذكرة الدخول'), findsOneWidget);
      // مدفوع كله: لا زر دفع.
      expect(find.byTooltip('تسجيل دفعة'), findsNothing);

      final db = runtime.db;
      final guest = await onlyGuest(tester, runtime);
      expect(guest.price, 500);
      expect(guest.teacherAmount, 800);
      expect(guest.ticketCode, startsWith('G-'));
      final student = (await runDb(
        tester,
        () => (db.select(
          db.students,
        )..where((s) => s.id.equals(guest.studentId))).getSingle(),
      ));
      expect(student.singleUse, isTrue);
      expect(student.firstName, 'زائر');
      final payment = (await runDb(
        tester,
        () => db.select(db.payments).get(),
      )).single;
      expect(payment.type, PaymentType.session.code);
      expect(payment.amount, 500);
      expect(payment.studentId, student.id);
      final contacts = await runDb(tester, () => db.select(db.contacts).get());
      expect(contacts.single.phone, '0661112233');
      expect(contacts.single.source, ContactService.sourceOneTime);
    });

    appTest('ضيف بلا دفع: يظهر باقيه ويمكن حذفه ما لم يحضر أو يدفع', (
      tester,
    ) async {
      final runtime = await createReview(tester);
      await openGuests(tester);
      await tester.tap(find.widgetWithText(ClayButton, 'تلميذ لمرة واحدة'));
      await tester.pumpAndSettle();
      await tester.enterText(fieldOf('الاسم'), 'متأخر');
      await typeIn(tester, 'المدفوع الآن (دج)', '0');
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'إغلاق'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'لمرة واحدة · ${Money.format(500)} · باقي ${Money.format(500)}',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('تسجيل دفعة'), findsOneWidget);
      expect(
        await runDb(tester, () => runtime.db.select(runtime.db.payments).get()),
        isEmpty,
      );

      await tester.tap(find.byTooltip('حذف الضيف'));
      await tester.pumpAndSettle();
      expect(find.text('لا ضيوف بعد'), findsOneWidget);
      expect(
        (await runDb(
          tester,
          () => runtime.db.select(runtime.db.sessionGuests).get(),
        )).where((g) => g.deletedAt == null),
        isEmpty,
      );
    });

    appTest('اسم الضيف إلزامي ومبلغه لا يتجاوز ثمنه', (tester) async {
      final runtime = await createReview(tester);
      await openGuests(tester);
      await tester.tap(find.widgetWithText(ClayButton, 'تلميذ لمرة واحدة'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة'));
      await tester.pumpAndSettle();
      expect(find.text('أدخل اسم التلميذ'), findsOneWidget);

      await tester.enterText(fieldOf('الاسم'), 'زائر');
      await typeIn(tester, 'المدفوع الآن (دج)', '900');
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة'));
      await tester.pumpAndSettle();
      // لا يُحفظ شيء والنافذة مفتوحة بخطئها.
      expect(find.widgetWithText(ClayButton, 'إضافة'), findsOneWidget);
      expect(
        await runDb(
          tester,
          () => runtime.db.select(runtime.db.sessionGuests).get(),
        ),
        isEmpty,
      );
    });

    appTest('تلميذ مسجَّل في فوج آخر: يُختار ويحضر برمزه العادي بلا تذكرة', (
      tester,
    ) async {
      final runtime = await createReview(tester);
      await runDb(tester, () => _insertStudent(runtime.db, 's1', 'سمير'));
      await openGuests(tester);
      await tester.tap(find.widgetWithText(ClayButton, 'تلميذ مسجَّل'));
      await tester.pumpAndSettle();
      expect(find.text('تلميذ مسجَّل يحضر هذه الحصة'), findsOneWidget);
      await tester.tap(find.text('سمير بن علي'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ClayButton, 'اختيار (1)'));
      await tester.pumpAndSettle();

      // نافذة الضيف باسمه وبثمن الحصة المقترح.
      expect(find.text('سمير بن علي'), findsWidgets);
      expect(textOf(tester, 'ثمن هذه الحصة (دج)'), '500');
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة'));
      await tester.pumpAndSettle();

      // لا تذكرة لتلميذ مسجَّل، ويظهر في القائمة «من فوج آخر».
      expect(find.byTooltip('تذكرة الدخول'), findsNothing);
      expect(
        find.text('من فوج آخر · ${Money.format(500)} · مدفوع'),
        findsOneWidget,
      );
      final guest = await onlyGuest(tester, runtime);
      expect(guest.studentId, 's1');
      expect(guest.ticketCode, isNull);
      final student = await runDb(
        tester,
        () => (runtime.db.select(
          runtime.db.students,
        )..where((s) => s.id.equals('s1'))).getSingle(),
      );
      expect(student.singleUse, isFalse);
    });

    appTest('حصة أُغلقت: لا إضافة ضيوف', (tester) async {
      final runtime = await createReview(tester);
      await runDb(
        tester,
        () => runtime.db.customUpdate(
          'UPDATE sessions SET closed_at = 5',
          updates: {runtime.db.sessions},
        ),
      );
      await tester.pumpAndSettle();
      await openGuests(tester);
      expect(
        find.text('انتهت الحصة أو أُلغيت: لا يُضاف إليها ضيوف.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(ClayButton, 'تلميذ لمرة واحدة'), findsNothing);
      expect(find.widgetWithText(ClayButton, 'تلميذ مسجَّل'), findsNothing);
    });

    appTest('عدد الضيوف يظهر على زر الورقة', (tester) async {
      await createReview(tester);
      await openGuests(tester);
      await tester.tap(find.widgetWithText(ClayButton, 'تلميذ لمرة واحدة'));
      await tester.pumpAndSettle();
      await tester.enterText(fieldOf('الاسم'), 'زائر');
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'إغلاق'));
      await tester.pumpAndSettle();
      // يُغلق الدرج فيظهر العدد على الزر.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ClayButton, 'ضيوف الحصة (1)'), findsOneWidget);
    });
  });
}
