import 'dart:async';

import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;
import 'support/groups_nav.dart';

/// يفتح شاشة «الحضور السابق» لفوج يدرس في يوم أسبوع الأمس، فتكون حصتاه الماضيتان
/// أمس وقبله بأسبوع مهما كان تاريخ تشغيل الاختبار. مع [fromLastWeek] يفتحها بتاريخ
/// أول حصة قبل ثمانية أيام كما يمرّره إنشاء الفوج، وبدونه بتاريخها الافتراضي
/// (أول حصة مبرمجة في الدورة، بعد ستة أيام).
Future<
  ({AppRuntime runtime, String yesterday, String lastWeek, String groupId})
>
openPast(
  WidgetTester tester, {
  TestAccount account = owner,
  bool fromLastWeek = true,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  final runtime = await openGroups(tester, account: account);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  final lastWeek = DateTime(today.year, today.month, today.day - 8);
  final db = runtime.db;
  final groupId = await runDb(tester, () async {
    await GroupService(
      db,
      runtime.writer,
      ScheduleService(db),
      CycleService(db, runtime.writer),
    ).create(
      subjectId: 'math',
      teacherId: 't1',
      roomId: 'r1',
      slots: [
        GroupSlotInput(
          weekday: yesterday.weekday,
          startMinutes: 600,
          endMinutes: 690,
        ),
      ],
      startDate: DateKey.of(today),
    );
    final group = (await db.select(db.groups).get()).single;
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
              groupId: group.id,
              studentId: id,
              joinedAt: 1,
              monthlyPrice: 2000,
            ),
          );
    }
    return group.id;
  });
  await tapGroup(tester);
  final opened = (
    runtime: runtime,
    yesterday: DateKey.of(yesterday),
    lastWeek: DateKey.of(lastWeek),
    groupId: groupId,
  );
  if (find
      .widgetWithText(ClayButton, 'تسجيل الحضور السابق')
      .evaluate()
      .isEmpty) {
    return opened;
  }
  if (fromLastWeek) {
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    unawaited(
      router.push<void>('/groups/$groupId/past?from=${DateKey.of(lastWeek)}'),
    );
  } else {
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل الحضور السابق'));
  }
  await tester.pumpAndSettle();
  return opened;
}

Finder dialogDay(int day) =>
    find.descendant(of: find.byType(ClayDialog), matching: find.text('$day'));

/// يختار [target] في نافذة التقويم المفتوحة على شهر [shown]، ويؤكد.
Future<void> pickDay(
  WidgetTester tester, {
  required DateTime shown,
  required DateTime target,
}) async {
  var months = (target.year - shown.year) * 12 + target.month - shown.month;
  while (months > 0) {
    await tester.tap(find.byTooltip('الشهر التالي'));
    await tester.pumpAndSettle();
    months--;
  }
  while (months < 0) {
    await tester.tap(find.byTooltip('الشهر السابق'));
    await tester.pumpAndSettle();
    months++;
  }
  await tester.tap(dialogDay(target.day));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ClayButton, 'تأكيد'));
  await tester.pumpAndSettle();
}

void main() {
  appTest('تعرض الحصص المقررة بعدد حصص الدورة من تاريخ أول حصة', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final opened = await openPast(tester);
    expect(find.text('الحضور السابق · الفوج 1'), findsOneWidget);
    expect(find.textContaining('يمكن تسجيل 7 حصة سابقة'), findsOneWidget);
    expect(find.text('الحصص المقررة'), findsOneWidget);
    expect(find.text('الحصص التي انعقدت'), findsNothing);
    // تاريخ أول حصة في بطاقته وفي صفّه الأول.
    expect(find.text(opened.lastWeek), findsNWidgets(2));
    expect(find.text(opened.yesterday), findsOneWidget);
    // العدد دائماً ثماني حصص: حصتان ماضيتان محدَّدتان وست قادمة.
    expect(find.text('حصص الدورة 8: 2 منعقدة و6 قادمة.'), findsOneWidget);
    expect(find.text('قادمة'), findsNWidgets(6));
    expect(find.byType(ClayCheckbox), findsNWidgets(2));
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('نور بن علي'), findsOneWidget);
    // الافتراضي: الجميع حاضرون في الحصتين.
    expect(find.text('حاضر 4'), findsOneWidget);
    expect(find.text('غائب 0'), findsOneWidget);
    expect(
      find.bySemanticsLabel('سمير بن علي، ${opened.yesterday}: حاضر'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  appTest('إلغاء تحديد حصة ماضية يضيف قادمة بدلها فتبقى الدورة ثمانياً', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final opened = await openPast(tester);
    await tester.tap(find.bySemanticsLabel('حصة ${opened.yesterday}'));
    await tester.pumpAndSettle();
    expect(find.text('حصص الدورة 8: 1 منعقدة و7 قادمة.'), findsOneWidget);
    expect(find.text('قادمة'), findsNWidgets(7));
    expect(find.text('حاضر 2'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('حصة ${opened.yesterday}'));
    await tester.pumpAndSettle();
    expect(find.text('حصص الدورة 8: 2 منعقدة و6 قادمة.'), findsOneWidget);
    semantics.dispose();
  });

  appTest('نقرة الخلية تبدّل حالتها: غائب ثم برخصة ثم لا تسجيل', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final opened = await openPast(tester);
    String cell(String state) => 'سمير بن علي، ${opened.yesterday}: $state';
    await tester.tap(find.bySemanticsLabel(cell('حاضر')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(cell('غائب')), findsOneWidget);
    expect(find.text('غائب 1'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(cell('غائب')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(cell('غائب برخصة')), findsOneWidget);
    expect(find.text('غائب برخصة 1'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(cell('غائب برخصة')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(cell('لا تسجيل')), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(cell('لا تسجيل')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(cell('حاضر')), findsOneWidget);
    semantics.dispose();
  });

  appTest('الحفظ يسجّل الحصتين مغلقتين بحضورهما ويُبقي الدورة بثماني حصص', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final opened = await openPast(tester);
    // سمير غائب أمس.
    await tester.tap(
      find.bySemanticsLabel('سمير بن علي، ${opened.yesterday}: حاضر'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ الحضور السابق'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ستُسجَّل 2 حصة سابقة'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل'));
    await tester.pumpAndSettle();

    // عاد إلى تفاصيل الفوج وبقيت الدورة بثماني حصص، انعقدت منها اثنتان.
    expect(find.text('الفوج 1'), findsWidgets);
    expect(find.text('انعقدت 2 من 8 حصة'), findsOneWidget);

    final db = opened.runtime.db;
    final sessions =
        await (db.select(db.sessions)
              ..where((s) => s.deletedAt.isNull())
              ..orderBy([(s) => OrderingTerm(expression: s.date)]))
            .get();
    expect(sessions, hasLength(8));
    expect(sessions.first.date, opened.lastWeek);
    expect(sessions[1].date, opened.yesterday);
    expect(sessions.take(2).every((s) => s.closedAt != null), isTrue);
    expect(sessions.skip(2).every((s) => s.closedAt == null), isTrue);
    final yesterdayId = sessions[1].id;
    final marks = await (db.select(
      db.attendance,
    )..where((a) => a.deletedAt.isNull())).get();
    expect(marks, hasLength(4));
    expect(
      marks
          .singleWhere((a) => a.sessionId == yesterdayId && a.studentId == 's1')
          .status,
      'absent',
    );
    expect(marks.where((a) => a.status == 'present'), hasLength(3));
    semantics.dispose();
  });

  appTest('تغيير تاريخ أول حصة إلى ما بعد اليوم يعيد برمجة الدورة كلها منه', (
    tester,
  ) async {
    final opened = await openPast(tester, fromLastWeek: false);
    final now = DateTime.now();
    final firstDefault = DateTime(now.year, now.month, now.day + 6);
    expect(find.text(DateKey.of(firstDefault)), findsNWidgets(2));
    expect(find.text('حصص الدورة 8: 0 منعقدة و8 قادمة.'), findsOneWidget);
    // لا شيء تغيّر بعد: زر الحفظ معطّل.
    expect(
      tester
          .widget<ClayButton>(
            find.widgetWithText(ClayButton, 'حفظ الحصص المقررة'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.widgetWithText(ClayButton, 'تغيير التاريخ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('الشهر التالي'));
    await tester.pumpAndSettle();
    await tester.tap(dialogDay(15));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'تأكيد'));
    await tester.pumpAndSettle();

    final picked = DateTime(firstDefault.year, firstDefault.month + 1, 15);
    // إن وافق الخامس عشر يوم دراسة الفوج صارت أول حصة في التاريخ نفسه فيظهر مرتين.
    final studyDay = picked.weekday == DateKey.parse(opened.yesterday).weekday;
    expect(find.text(DateKey.of(picked)), findsNWidgets(studyDay ? 2 : 1));
    expect(find.text('حصص الدورة 8: 0 منعقدة و8 قادمة.'), findsOneWidget);
    expect(find.text('قادمة'), findsNWidgets(8));

    await tester.tap(find.widgetWithText(ClayButton, 'حفظ الحصص المقررة'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ستُعاد برمجة حصص الدورة'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'برمجة'));
    await tester.pumpAndSettle();

    final db = opened.runtime.db;
    final sessions =
        await (db.select(db.sessions)
              ..where((s) => s.deletedAt.isNull())
              ..orderBy([(s) => OrderingTerm(expression: s.date)]))
            .get();
    expect(sessions, hasLength(8));
    // أول حصة هي أول يوم دراسة للفوج في أو بعد التاريخ المختار، وبينها أسبوع.
    final first = DateKey.parse(sessions.first.date);
    expect(first.isBefore(picked), isFalse);
    expect(first.difference(picked).inDays, lessThan(7));
    expect(first.weekday, DateKey.parse(opened.yesterday).weekday);
    expect(sessions.every((s) => s.closedAt == null), isTrue);
    for (var i = 1; i < sessions.length; i++) {
      expect(
        DateKey.parse(sessions[i].date)
            .difference(DateKey.parse(sessions[i - 1].date))
            .inDays,
        7,
      );
    }
  });

  appTest('تاريخ أول حصة قبل اليوم يُظهر الماضية، وبعد التغيير تُعاد القائمة', (
    tester,
  ) async {
    final opened = await openPast(tester, fromLastWeek: false);
    expect(find.byType(ClayCheckbox), findsNothing);
    await tester.tap(find.widgetWithText(ClayButton, 'تغيير التاريخ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('الشهر السابق'));
    await tester.pumpAndSettle();
    await tester.tap(dialogDay(15));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'تأكيد'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final picked = DateTime(now.year, now.month - 1, 15);
    expect(find.text(DateKey.of(picked)), findsWidgets);
    // الحصص الماضية من ذلك التاريخ إلى أمس محدَّدة، والمجموع ثمانٍ دائماً.
    final past = tester.widgetList<ClayCheckbox>(find.byType(ClayCheckbox));
    expect(past, isNotEmpty);
    expect(past.every((c) => c.value), isTrue);
    final held = past.length;
    expect(
      find.text('حصص الدورة 8: $held منعقدة و${8 - held} قادمة.'),
      findsOneWidget,
    );
    expect(opened.yesterday, isNotEmpty);
  });

  appTest('من لا يملك صلاحية تعديل الحضور لا يرى الزر', (tester) async {
    await openPast(tester, account: viewer);
    expect(find.text('تسجيل الحضور السابق'), findsNothing);
    expect(find.byTooltip('تسجيل الحضور السابق'), findsNothing);
  });

  group('تغيير تاريخ حصة قادمة', () {
    // أول حصة قادمة بعد ستة أيام، وكل الحصص الثماني قادمة.
    DateTime firstUpcoming() {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day + 6);
    }

    appTest('الزر يحلّ محل «إضافة حصة بتاريخ آخر» وينقل حصة قادمة ويحفظها', (
      tester,
    ) async {
      final opened = await openPast(tester, fromLastWeek: false);
      expect(find.text('إضافة حصة بتاريخ آخر'), findsNothing);
      expect(find.text('اختر تاريخاً قبل اليوم'), findsNothing);
      expect(find.text('قادمة'), findsNWidgets(8));
      final first = firstUpcoming();
      final firstKey = DateKey.of(first);

      await tester.tap(find.widgetWithText(ClayButton, 'تغيير تاريخ حصة'));
      await tester.pumpAndSettle();
      expect(find.text('اختر الحصة التي يتغير تاريخها'), findsOneWidget);
      final dayName = GroupService.weekdayName(first.weekday);
      await tester.tap(find.widgetWithText(ClayListTile, '$dayName $firstKey'));
      await tester.pumpAndSettle();

      // اليوم السابق للحصة: فيه لا حصة للفوج، ولا يسبق اليوم.
      final target = first.subtract(const Duration(days: 1));
      await pickDay(tester, shown: first, target: target);
      final targetKey = DateKey.of(target);
      expect(find.text('منقولة'), findsOneWidget);
      expect(find.text('قادمة'), findsNWidgets(7));
      expect(find.text('كانت $firstKey'), findsOneWidget);
      expect(find.text(targetKey), findsOneWidget);
      expect(find.text('حصص الدورة 8: 0 منعقدة و8 قادمة.'), findsOneWidget);

      await tester.tap(find.widgetWithText(ClayButton, 'حفظ الحصص المقررة'));
      await tester.pumpAndSettle();
      expect(find.textContaining('تُنقل 1 حصة قادمة'), findsOneWidget);
      await tester.tap(find.widgetWithText(ClayButton, 'برمجة'));
      await tester.pumpAndSettle();

      final db = opened.runtime.db;
      final all = await (db.select(
        db.sessions,
      )..where((s) => s.deletedAt.isNull())).get();
      final live = all.where((s) => s.status != 'cancelled').toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      expect(live, hasLength(8), reason: 'تبقى الدورة بثماني حصص');
      expect(live.first.date, targetKey);
      expect(live.first.status, 'makeup');
      final ghost = all.singleWhere((s) => s.status == 'cancelled');
      expect(ghost.date, firstKey, reason: 'الموعد القديم محجوز بحصة ملغاة');
      expect(live.every((s) => s.closedAt == null), isTrue);
    });

    appTest('لا تُنقل الحصة القادمة إلى تاريخ مضى', (tester) async {
      await openPast(tester, fromLastWeek: false);
      final first = firstUpcoming();
      final firstKey = DateKey.of(first);
      await tester.tap(find.byTooltip('تغيير تاريخ حصة $firstKey'));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      await pickDay(tester, shown: first, target: yesterday);
      expect(find.textContaining('لا تُنقل إلى ما مضى'), findsOneWidget);
      expect(find.text('منقولة'), findsNothing);
      expect(find.text('قادمة'), findsNWidgets(8));
      // لا تغيير: زر الحفظ معطّل.
      expect(
        tester
            .widget<ClayButton>(
              find.widgetWithText(ClayButton, 'حفظ الحصص المقررة'),
            )
            .onPressed,
        isNull,
      );
    });

    appTest('أيقونة التقويم في صف الحصة تنقلها، والتراجع يعيدها إلى موعدها', (
      tester,
    ) async {
      await openPast(tester, fromLastWeek: false);
      final first = firstUpcoming();
      final firstKey = DateKey.of(first);
      await tester.tap(find.byTooltip('تغيير تاريخ حصة $firstKey'));
      await tester.pumpAndSettle();
      final target = first.add(const Duration(days: 1));
      await pickDay(tester, shown: first, target: target);
      expect(find.text('منقولة'), findsOneWidget);
      expect(find.text(DateKey.of(target)), findsOneWidget);
      // تاريخ أول حصة في بطاقته فقط؛ الصف عند موعده الجديد.
      expect(find.text(firstKey), findsOneWidget);

      await tester.tap(
        find.byTooltip('التراجع عن نقل حصة ${DateKey.of(target)}'),
      );
      await tester.pumpAndSettle();
      expect(find.text('منقولة'), findsNothing);
      expect(find.text(firstKey), findsNWidgets(2));
      expect(find.text('قادمة'), findsNWidgets(8));
      expect(
        tester
            .widget<ClayButton>(
              find.widgetWithText(ClayButton, 'حفظ الحصص المقررة'),
            )
            .onPressed,
        isNull,
        reason: 'عاد كل شيء كما كان فلا حفظ',
      );
    });
  });
}
