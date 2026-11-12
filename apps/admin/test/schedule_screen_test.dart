import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;

/// يفتح «الجدول الأسبوعي» من «المزيد»، وقبله ينشئ مجموعتين إن طُلب.
Future<AppRuntime> openSchedule(
  WidgetTester tester, {
  bool withGroups = true,
}) async {
  tester.view.physicalSize = const Size(1000, 3600);
  final runtime = await openGroups(tester);
  if (withGroups) {
    final db = runtime.db;
    await runDb(tester, () async {
      final service = GroupService(
        db,
        runtime.writer,
        ScheduleService(db),
        CycleService(db, runtime.writer),
      );
      await service.create(
        subjectId: 'math',
        teacherId: 't1',
        roomId: 'r1',
        slots: const [
          GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690),
          GroupSlotInput(
            weekday: 2,
            startMinutes: 960,
            endMinutes: 1050,
            roomId: 'r2',
          ),
        ],
        startDate: '2026-11-07',
      );
      await service.create(
        subjectId: 'math',
        teacherId: 't2',
        roomId: 'r2',
        slots: const [
          GroupSlotInput(weekday: 6, startMinutes: 840, endMinutes: 930),
        ],
        startDate: '2026-11-07',
      );
    });
  }
  await tester.tap(find.text('المزيد').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('الجدول الأسبوعي'));
  await tester.pumpAndSettle();
  return runtime;
}

void main() {
  appTest('بلا مجموعات: رسالة فارغة', (tester) async {
    await openSchedule(tester, withGroups: false);
    expect(find.text('لا حصص في الجدول'), findsOneWidget);
  });

  appTest('حسب القاعة: بطاقة لكل قاعة وفيها حصصها', (tester) async {
    await openSchedule(tester);
    expect(find.text('القاعة 1'), findsOneWidget);
    expect(find.text('القاعة 2'), findsOneWidget);
    // القاعة 1: حصة السبت للمجموعة 1. القاعة 2: الثلاثاء للأولى والسبت للثانية.
    expect(find.text('م1 · رياضيات'), findsNWidgets(2));
    expect(find.text('م2 · رياضيات'), findsOneWidget);
    expect(find.text('10:00–11:30'), findsOneWidget);
    expect(find.text('16:00–17:30'), findsOneWidget);
    expect(find.text('14:00–15:30'), findsOneWidget);
    // السبت أولاً في عمود الأيام.
    expect(find.text('السبت'), findsNWidgets(2));
    expect(find.text('الجمعة'), findsNWidgets(2));
  });

  appTest('حسب الأستاذ: بطاقة لكل أستاذ وفيها حصصه', (tester) async {
    await openSchedule(tester);
    await tester.tap(find.text('حسب الأستاذ'));
    await tester.pumpAndSettle();
    expect(find.text('الأستاذ كمال'), findsOneWidget);
    expect(find.text('الأستاذ ياسين'), findsOneWidget);
    expect(find.text('القاعة 1'), findsNothing);
    expect(find.text('م1 · رياضيات'), findsNWidgets(2));
    expect(find.text('م2 · رياضيات'), findsOneWidget);
  });

  appTest('وصف الحصة لقارئ الشاشة يتضمن الأستاذ في عرض القاعات', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await openSchedule(tester);
    expect(
      find.bySemanticsLabel('المجموعة 2 · رياضيات · السبت 14:00–15:30 · ياسين'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  appTest('النقر على حصة يفتح تفاصيل مجموعتها', (tester) async {
    await openSchedule(tester);
    await tester.tap(find.text('م2 · رياضيات'));
    await tester.pumpAndSettle();
    expect(find.text('المجموعة 2'), findsOneWidget);
    expect(find.text('الدورة 1 (الحالية)'), findsOneWidget);
  });

  appTest('المجموعة المؤرشفة تختفي من الجدول', (tester) async {
    final runtime = await openSchedule(tester);
    await runDb(
      tester,
      () => runtime.db.customUpdate(
        'UPDATE groups SET archived_at = 5 WHERE number = 2',
        updates: {runtime.db.groups},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('م2 · رياضيات'), findsNothing);
    expect(find.text('م1 · رياضيات'), findsNWidgets(2));
  });
}
