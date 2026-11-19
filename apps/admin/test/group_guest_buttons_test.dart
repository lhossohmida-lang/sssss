import 'dart:async';

import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;

GroupService _service(AppRuntime runtime) => GroupService(
  runtime.db,
  runtime.writer,
  ScheduleService(runtime.db),
  CycleService(runtime.db, runtime.writer),
);

/// خدمة الضيوف كما يراها التطبيق (بمدفوعاتها).
GuestService guestsOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
        .read(guestServiceProvider);

/// يفتح تفاصيل الفوج [id] مباشرة بمساره.
Future<void> openDetailsOf(WidgetTester tester, String id) async {
  final context = tester.element(find.byType(Scaffold).first);
  unawaited(GoRouter.of(context).push('/groups/$id'));
  await tester.pumpAndSettle();
  tester.view.physicalSize = const Size(420, 3200);
  await tester.pumpAndSettle();
}

/// فوج عادي من ثماني حصص أسبوعية تبدأ اليوم.
Future<GroupRow> regularGroup(WidgetTester tester, AppRuntime runtime) => runDb(
  tester,
  () => _service(runtime).create(
    subjectId: 'math',
    teacherId: 't1',
    roomId: 'r1',
    monthlyPrice: 2000,
    ratePerStudent: 800,
    slots: [
      GroupSlotInput(
        weekday: DateTime.now().weekday,
        startMinutes: 600,
        endMinutes: 690,
      ),
    ],
    startDate: DateKey.of(DateTime.now()),
  ),
);

void main() {
  group('فوج حصة المراجعة: زر العودة إلى ورقة الحضور', () {
    Future<GroupRow> reviewGroup(WidgetTester tester, AppRuntime runtime) =>
        runDb(
          tester,
          () => _service(runtime).createReview(
            subjectId: 'math',
            teacherId: 't1',
            roomId: 'r1',
            date: DateKey.of(DateTime.now()),
            startMinutes: 600,
            endMinutes: 780,
            fee: 500,
            teacherAmount: 300,
            today: DateKey.of(DateTime.now()),
          ),
        );

    appTest('زر في تفاصيل الفوج يفتح ورقة حضور حصته وضيوفها', (tester) async {
      final runtime = await openGroups(tester);
      final group = await reviewGroup(tester, runtime);
      await openDetailsOf(tester, group.id);
      expect(find.text('ورقة حضور الحصة والضيوف'), findsOneWidget);
      // لا زر «إضافة تلميذ لحصة واحدة» هنا: الضيوف تُضاف من ورقة الحضور نفسها.
      expect(find.text('إضافة تلميذ لحصة واحدة'), findsNothing);

      await tester.tap(
        find.widgetWithText(ClayButton, 'ورقة حضور الحصة والضيوف'),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ClayButton, 'ضيوف الحصة'), findsOneWidget);
    });

    appTest('بلا صلاحية الحضور: لا زر', (tester) async {
      final runtime = await openGroups(tester, account: viewer);
      final group = await reviewGroup(tester, runtime);
      await openDetailsOf(tester, group.id);
      expect(
        find.text('حصة مراجعة: حصة واحدة يحضرها ضيوف يدفعون ثمنها'),
        findsOneWidget,
      );
      expect(find.text('ورقة حضور الحصة والضيوف'), findsNothing);
    });
  });

  group('فوج عادي: إضافة تلميذ لحصة واحدة', () {
    appTest('الزر يعرض الحصص القادمة ثم يفتح ضيوف الحصة المختارة', (
      tester,
    ) async {
      final runtime = await openGroups(tester);
      final group = await regularGroup(tester, runtime);
      await openDetailsOf(tester, group.id);
      expect(
        find.widgetWithText(ClayButton, 'إضافة تلميذ لحصة واحدة'),
        findsOneWidget,
      );

      await tester.tap(
        find.widgetWithText(ClayButton, 'إضافة تلميذ لحصة واحدة'),
      );
      await tester.pumpAndSettle();
      expect(find.text('اختر الحصة'), findsOneWidget);
      expect(find.textContaining('في أي وقت من عمر الفوج'), findsOneWidget);
      // أول حصة قادمة معروضة بيومها وتاريخها ووقتها.
      final db = runtime.db;
      final open = await runDb(
        tester,
        () =>
            guestsOf(tester)
                .openSessions(group.id, today: DateKey.of(DateTime.now())),
      );
      expect(open, isNotEmpty);
      final first = open.first;
      final title =
          '${GroupService.weekdayName(DateKey.weekday(first.date))} ${first.date}';
      await tester.tap(find.text(title).first);
      await tester.pumpAndSettle();

      // قائمة ضيوف تلك الحصة: تلميذ لمرة واحدة بثمن حصة واحدة من سعر الدورة.
      expect(find.text('لا ضيوف بعد'), findsOneWidget);
      await tester.tap(find.widgetWithText(ClayButton, 'تلميذ لمرة واحدة'));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'ثمن هذه الحصة (دج)'), '250');
      await tester.enterText(fieldOf('الاسم'), 'زائر');
      await tester.tap(find.widgetWithText(ClayButton, 'إضافة'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ClayButton, 'إغلاق'));
      await tester.pumpAndSettle();

      final guest = (await runDb(
        tester,
        () => db.select(db.sessionGuests).get(),
      )).single;
      expect(guest.sessionId, first.id);
      expect(guest.price, 250);
      final session = await runDb(
        tester,
        () => (db.select(
          db.sessions,
        )..where((s) => s.id.equals(guest.sessionId))).getSingle(),
      );
      expect(session.groupId, group.id);
    });

    appTest('لا حصة قادمة (كلها مغلقة): رسالة ولا نافذة', (tester) async {
      final runtime = await openGroups(tester);
      final group = await regularGroup(tester, runtime);
      await runDb(
        tester,
        () => runtime.db.customUpdate(
          'UPDATE sessions SET closed_at = 5',
          updates: {runtime.db.sessions},
        ),
      );
      await openDetailsOf(tester, group.id);
      await tester.tap(
        find.widgetWithText(ClayButton, 'إضافة تلميذ لحصة واحدة'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('لا حصة قادمة في هذا الفوج لإضافة تلميذ إليها'),
        findsOneWidget,
      );
      expect(find.text('اختر الحصة'), findsNothing);
    });

    appTest('الفوج المنتظِر والعرض فقط: لا زر', (tester) async {
      final runtime = await openGroups(tester);
      final waiting = await runDb(
        tester,
        () => _service(runtime).createWaiting(
          subjectId: 'math',
          teacherId: 't1',
          roomId: 'r1',
          monthlyPrice: 2000,
          ratePerStudent: 800,
          waitingTarget: 5,
        ),
      );
      await openDetailsOf(tester, waiting.id);
      expect(find.text('إضافة تلميذ لحصة واحدة'), findsNothing);
    });

    appTest('صلاحية العرض فقط: لا زر', (tester) async {
      final runtime = await openGroups(tester, account: viewer);
      final group = await regularGroup(tester, runtime);
      await openDetailsOf(tester, group.id);
      expect(find.text('إضافة تلميذ لحصة واحدة'), findsNothing);
    });
  });

  group('GuestService.openSessions', () {
    appTest('الحصص غير المغلقة وغير الملغاة من اليوم فصاعداً بترتيبها', (
      tester,
    ) async {
      final runtime = await openGroups(tester);
      final group = await regularGroup(tester, runtime);
      final db = runtime.db;
      final today = DateKey.of(DateTime.now());
      final all = await runDb(
        tester,
        () =>
            (db.select(db.sessions)
                  ..where((s) => s.groupId.equals(group.id))
                  ..orderBy([(s) => OrderingTerm.asc(s.date)]))
                .get(),
      );
      expect(all, hasLength(8));
      // أُلغيت الثانية وأُغلقت الثالثة، والأولى قد تكون اليوم.
      await runDb(tester, () async {
        await db.customUpdate(
          "UPDATE sessions SET status = 'cancelled' WHERE id = '${all[1].id}'",
          updates: {db.sessions},
        );
        await db.customUpdate(
          "UPDATE sessions SET closed_at = 5 WHERE id = '${all[2].id}'",
          updates: {db.sessions},
        );
      });
      final open = await runDb(
        tester,
        () => guestsOf(tester).openSessions(group.id, today: today),
      );
      final ids = open.map((s) => s.id).toList();
      expect(ids, isNot(contains(all[1].id)));
      expect(ids, isNot(contains(all[2].id)));
      expect(open.every((s) => s.date.compareTo(today) >= 0), isTrue);
      expect(
        [...open]..sort((a, b) => a.date.compareTo(b.date)),
        open,
        reason: 'بترتيبها الزمني',
      );
      // من غد: لا حصة اليوم.
      final tomorrow = DateKey.of(DateTime.now().add(const Duration(days: 1)));
      final later = await runDb(
        tester,
        () => guestsOf(tester).openSessions(group.id, today: tomorrow),
      );
      expect(later.every((s) => s.date.compareTo(tomorrow) >= 0), isTrue);
    });
  });
}
