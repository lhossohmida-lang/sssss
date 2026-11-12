import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'home_test.dart' hide main;

String inDays(int n) {
  final now = DateTime.now();
  return DateKey.of(DateTime(now.year, now.month, now.day + n));
}

/// يفتح «الجدول»: لمجموعة الرياضيات خانة السبت 10:00–11:30 في «القاعة 3»،
/// وللفيزياء خانة الاثنين 14:00–15:30؛ وللرياضيات حصتان قادمتان (بعد يومين
/// وبعد 5 أيام وهذه ملغاة)، وللفيزياء حصة بعد 3 أيام.
Future<AppRuntime> openSchedule(
  WidgetTester tester, {
  bool seed = true,
  String? child,
}) async {
  final runtime = await openParent(tester, seed: seed);
  if (seed) {
    await runDb(tester, () async {
      final db = runtime.db;
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              id: 'r3',
              createdAt: 1,
              updatedAt: 1,
              name: 'القاعة 3',
            ),
          );
      await db.customStatement(
        "UPDATE groups SET room_id = 'r3' WHERE id = 'g1'",
      );
      Future<void> slot(String id, String group, int weekday, int start) => db
          .into(db.groupSlots)
          .insert(
            GroupSlotsCompanion.insert(
              id: id,
              createdAt: 1,
              updatedAt: 1,
              groupId: group,
              weekday: weekday,
              startMinutes: start,
              endMinutes: start + 90,
            ),
          );
      await slot('sl1', 'g1', 6, 600);
      await slot('sl2', 'g2', 1, 840);
      Future<void> session(
        String id,
        String group,
        int days, {
        bool cancelled = false,
      }) => db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: id,
              createdAt: 1,
              updatedAt: 1,
              groupId: group,
              cycleNumber: 1,
              date: inDays(days),
              startMinutes: group == 'g1' ? 600 : 840,
              endMinutes: group == 'g1' ? 690 : 930,
              status: Value(cancelled ? 'cancelled' : 'normal'),
            ),
          );
      await session('up1', 'g1', 2);
      await session('up2', 'g2', 3);
      await session('up3', 'g1', 5, cancelled: true);
    });
  }
  await tester.tap(find.text('الجدول').last);
  await tester.pumpAndSettle();
  if (child != null) {
    await tester.tap(find.widgetWithText(ClayChip, child));
    await tester.pumpAndSettle();
  }
  return runtime;
}

void main() {
  appTest('وليّ بلا أبناء: رسالة', (tester) async {
    await openSchedule(tester, seed: false);
    expect(find.text('لا أبناء مرتبطون بحسابك'), findsOneWidget);
  });

  appTest('الحصص القادمة بمواعيدها وقاعتها، والملغاة معلَّمة', (tester) async {
    await openSchedule(tester, child: 'نور');
    expect(find.text('الحصص القادمة'), findsOneWidget);
    expect(
      find.text('${teacherDayLabel(inDays(2))} · 10:00 - 11:30 · القاعة 3'),
      findsOneWidget,
    );
    expect(
      find.text('${teacherDayLabel(inDays(3))} · 14:00 - 15:30'),
      findsOneWidget,
    );
    final cancelled = find.ancestor(
      of: find.textContaining(teacherDayLabel(inDays(5))),
      matching: find.byType(ClayListTile),
    );
    expect(cancelled, findsOneWidget);
    expect(
      find.descendant(of: cancelled, matching: find.text('أُلغيت')),
      findsOneWidget,
    );
  });

  appTest('الجدول الأسبوعي: خانات مواد الابن من السبت', (tester) async {
    await openSchedule(tester, child: 'نور');
    tester.view.physicalSize = const Size(420, 3000);
    await tester.pumpAndSettle();
    expect(find.text('الجدول الأسبوعي'), findsOneWidget);
    expect(
      find.textContaining('السبت 10:00–11:30 · كمال · القاعة 3'),
      findsOneWidget,
    );
    expect(find.textContaining('الاثنين 14:00–15:30 · كمال'), findsOneWidget);
    // السبت قبل الاثنين.
    final sat = tester.getTopLeft(find.textContaining('السبت 10:00–11:30'));
    final mon = tester.getTopLeft(find.textContaining('الاثنين 14:00–15:30'));
    expect(sat.dy, lessThan(mon.dy));
  });

  appTest('الابن الآخر: جدول مجموعته وحدها', (tester) async {
    await openSchedule(tester);
    // سمير (الأول بالاسم) في مجموعة الرياضيات فقط.
    tester.view.physicalSize = const Size(420, 3000);
    await tester.pumpAndSettle();
    expect(find.textContaining('السبت 10:00–11:30'), findsOneWidget);
    expect(find.textContaining('الاثنين'), findsNothing);
    expect(find.textContaining('فيزياء'), findsNothing);
  });

  appTest('ابن بلا مجموعات: رسالة', (tester) async {
    final runtime = await openSchedule(tester);
    await runDb(
      tester,
      () => runtime.db.customUpdate(
        "UPDATE group_students SET left_at = 5 WHERE student_id = 's2'",
        updates: {runtime.db.groupStudents},
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pumpAndSettle();
    expect(find.text('لا حصص في جدوله'), findsOneWidget);
  });
}
