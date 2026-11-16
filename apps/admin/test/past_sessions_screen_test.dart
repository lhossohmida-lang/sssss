import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;

/// يفتح شاشة «تسجيل الحضور السابق» لفوج يدرس في يوم أسبوع الأمس، فتكون حصتاه
/// المقترحتان أمس وقبله بأسبوع مهما كان تاريخ تشغيل الاختبار.
Future<({AppRuntime runtime, String yesterday, String lastWeek})> openPast(
  WidgetTester tester, {
  TestAccount account = owner,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  final runtime = await openGroups(tester, account: account);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  final lastWeek = DateTime(today.year, today.month, today.day - 8);
  final db = runtime.db;
  await runDb(tester, () async {
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
  });
  await tester.tap(find.text('الفوج 1 · رياضيات'));
  await tester.pumpAndSettle();
  if (find
      .widgetWithText(ClayButton, 'تسجيل الحضور السابق')
      .evaluate()
      .isEmpty) {
    return (
      runtime: runtime,
      yesterday: DateKey.of(yesterday),
      lastWeek: DateKey.of(lastWeek),
    );
  }
  await tester.tap(find.widgetWithText(ClayButton, 'تسجيل الحضور السابق'));
  await tester.pumpAndSettle();
  return (
    runtime: runtime,
    yesterday: DateKey.of(yesterday),
    lastWeek: DateKey.of(lastWeek),
  );
}

void main() {
  appTest('تقترح حصتي الجدول السابقتين وتعرض شبكة التلاميذ حاضرين', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final opened = await openPast(tester);
    expect(find.text('الحضور السابق · الفوج 1'), findsOneWidget);
    expect(find.textContaining('يمكن تسجيل 7 حصة سابقة'), findsOneWidget);
    expect(find.text(opened.yesterday), findsOneWidget);
    expect(find.text(opened.lastWeek), findsOneWidget);
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

  appTest('الحفظ يسجّل الحصتين مغلقتين بحضورهما ويحذف الزائد من آخر الدورة', (
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

  appTest('من لا يملك صلاحية تعديل الحضور لا يرى الزر', (tester) async {
    await openPast(tester, account: viewer);
    expect(find.text('تسجيل الحضور السابق'), findsNothing);
    expect(find.byTooltip('تسجيل الحضور السابق'), findsNothing);
  });
}
