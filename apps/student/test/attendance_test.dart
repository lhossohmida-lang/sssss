import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'home_test.dart' hide main;

/// «1 نوفمبر · الأحد» لتاريخ الشهر الجاري، كما تعرضه الشاشة.
String label(String date) =>
    '${int.parse(date.substring(8))} '
    '${DateKey.monthName(int.parse(date.substring(5, 7)))} · '
    '${GroupService.weekdayName(DateKey.weekday(date))}';

String dayOfMonth(int day) => '${currentMonthKey()}-${'$day'.padLeft(2, '0')}';

/// يفتح «الحضور» لنور (الابن الثاني بالاسم) وفي مجموعة الرياضيات حصص هذا
/// الشهر: يوم 1 حضر، 2 غاب، 3 برخصة، 4 أُلغيت؛ كلها مسجّلة فلا يتغير حالها
/// بمرور الوقت.
Future<AppRuntime> openAttendance(
  WidgetTester tester, {
  bool seed = true,
}) async {
  final runtime = await openParent(tester, seed: seed);
  if (seed) {
    await runDb(tester, () async {
      final db = runtime.db;
      for (final (n, status) in [
        (1, 'present'),
        (2, 'absent'),
        (3, 'excused'),
        (4, null),
      ]) {
        await db
            .into(db.sessions)
            .insert(
              SessionsCompanion.insert(
                id: 'cur$n',
                createdAt: 1,
                updatedAt: 1,
                groupId: 'g1',
                cycleNumber: 1,
                date: dayOfMonth(n),
                startMinutes: 600,
                endMinutes: 690,
                status: Value(status == null ? 'cancelled' : 'normal'),
                closedAt: const Value(5),
              ),
            );
        if (status != null) {
          await db
              .into(db.attendance)
              .insert(
                AttendanceCompanion.insert(
                  id: 'ca$n',
                  createdAt: 1,
                  updatedAt: 1,
                  sessionId: 'cur$n',
                  studentId: 's1',
                  status: status,
                  method: 'manual',
                ),
              );
        }
      }
    });
  }
  await tester.tap(find.text('الحضور').last);
  await tester.pumpAndSettle();
  if (seed) {
    await tester.tap(find.widgetWithText(ClayChip, 'نور'));
    await tester.pumpAndSettle();
  }
  return runtime;
}

void main() {
  appTest('وليّ بلا أبناء: رسالة', (tester) async {
    await openAttendance(tester, seed: false);
    expect(find.text('لا أبناء مرتبطون بحسابك'), findsOneWidget);
  });

  appTest('الحضور: المواد شرائح، وعدّادات الشهر، وحال كل حصة', (tester) async {
    await openAttendance(tester);
    expect(find.widgetWithText(ClayChip, 'رياضيات · م1'), findsOneWidget);
    expect(find.widgetWithText(ClayChip, 'فيزياء · م2'), findsOneWidget);
    expect(find.text(DateKey.monthLabel(currentMonthKey())), findsOneWidget);
    expect(find.text('حضر 1'), findsOneWidget);
    expect(find.text('غاب 1'), findsOneWidget);
    expect(find.text('برخصة 1'), findsOneWidget);

    tester.view.physicalSize = const Size(420, 3000);
    await tester.pumpAndSettle();
    for (final (day, state) in [
      (1, 'حضر'),
      (2, 'غاب'),
      (3, 'غاب برخصة'),
      (4, 'أُلغيت'),
    ]) {
      final tile = find.ancestor(
        of: find.text(label(dayOfMonth(day))),
        matching: find.byType(ClayListTile),
      );
      expect(tile, findsOneWidget, reason: 'يوم $day');
      expect(
        find.descendant(of: tile, matching: find.text(state)),
        findsOneWidget,
        reason: 'يوم $day',
      );
    }
    expect(find.text('10:00 - 11:30'), findsNWidgets(4));
  });

  appTest('التقويم: خلية لكل يوم من الشهر وأيامه من السبت', (tester) async {
    await openAttendance(tester);
    final days = DateTime(DateTime.now().year, DateTime.now().month + 1, 0).day;
    // أيام الأسبوع في رأس التقويم، وأرقام الأيام كلها.
    expect(find.text('السبت'), findsWidgets);
    for (final day in [1, 2, 3, 4, days]) {
      expect(find.text('$day'), findsWidgets, reason: 'يوم $day');
    }
  });

  appTest('مادة بلا حصص في الشهر: رسالة، والتنقل بين الأشهر', (tester) async {
    await openAttendance(tester);
    await tester.tap(find.widgetWithText(ClayChip, 'فيزياء · م2'));
    await tester.pumpAndSettle();
    expect(find.text('لا حصص في هذا الشهر'), findsOneWidget);
    expect(find.text('حضر 0'), findsOneWidget);

    await tester.tap(find.widgetWithText(ClayChip, 'رياضيات · م1'));
    await tester.pumpAndSettle();
    expect(find.text('حضر 1'), findsOneWidget);
    // الشهر السابق بلا حصص، والعودة تعيد الحصص.
    await tester.tap(find.byTooltip('الشهر السابق'));
    await tester.pumpAndSettle();
    expect(find.text('لا حصص في هذا الشهر'), findsOneWidget);
    await tester.tap(find.byTooltip('الشهر التالي'));
    await tester.pumpAndSettle();
    expect(find.text('حضر 1'), findsOneWidget);
  });

  appTest('الابن الآخر: كشفه هو لا كشف أخيه', (tester) async {
    await openAttendance(tester);
    await tester.tap(find.widgetWithText(ClayChip, 'سمير'));
    await tester.pumpAndSettle();
    expect(find.text('حضر 0'), findsOneWidget);
    expect(find.text('غاب 0'), findsOneWidget);
    expect(find.text('حضر 1'), findsNothing);
  });

  appTest('تسجيل حضور جديد يصل إلى الشاشة', (tester) async {
    final runtime = await openAttendance(tester);
    await runDb(
      tester,
      () => runtime.db.customStatement(
        "UPDATE attendance SET status = 'absent' WHERE id = 'ca1'",
      ),
    );
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
        .invalidate(childMonthProvider);
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pumpAndSettle();
    expect(find.text('حضر 0'), findsOneWidget);
    expect(find.text('غاب 2'), findsOneWidget);
  });
}
