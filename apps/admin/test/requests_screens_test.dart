import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;

const requestsViewer = TestAccount(
  id: 'u-rv',
  email: 'rv@school.local',
  password: 'rv-pass-1',
  role: UserRole.worker,
  entityId: 'w8',
  displayName: 'عامل عرض',
  permissions: '{"requests":["view"]}',
);

String inDays(int n) {
  final now = DateTime.now();
  return DateKey.of(DateTime(now.year, now.month, now.day + n));
}

/// مجموعة للأستاذ كمال بحصص قادمة، وطلب تغيير موعد لأولى حصصها إن طُلب،
/// ثم يفتح «طلبات الأساتذة» من «المزيد».
Future<({AppRuntime runtime, SessionRow session})> openRequests(
  WidgetTester tester, {
  bool withRequest = true,
  TestAccount account = owner,
  bool busyAtNewSlot = false,
}) async {
  final runtime = await openGroups(tester, account: account);
  final db = runtime.db;
  late SessionRow first;
  await runDb(tester, () async {
    final cycles = CycleService(db, runtime.writer);
    final service = GroupService(
      db,
      runtime.writer,
      ScheduleService(db),
      cycles,
    );
    final group = await service.create(
      subjectId: 'math',
      teacherId: 't1',
      roomId: 'r1',
      slots: [
        GroupSlotInput(
          weekday: DateKey.weekday(inDays(2)),
          startMinutes: 600,
          endMinutes: 690,
        ),
      ],
      startDate: inDays(2),
    );
    first = (await cycles.cycleSessions(group.id, 1)).first;
    if (withRequest) {
      await RequestService(
        db,
        runtime.writer,
        ScheduleService(db),
        cycles,
      ).submit(
        teacherId: 't1',
        groupId: group.id,
        type: SessionRequestType.reschedule,
        sessionId: first.id,
        newDate: inDays(3),
        newStartMinutes: 900,
        newEndMinutes: 990,
        reason: 'ظرف عائلي',
      );
    }
    if (busyAtNewSlot) {
      await db.customStatement(
        'INSERT INTO groups (id, created_at, updated_at, number, subject_id, '
        "teacher_id) VALUES ('gx', 1, 1, 9, 'math', 't1')",
      );
      await db.customStatement(
        'INSERT INTO sessions (id, created_at, updated_at, group_id, '
        'cycle_number, date, start_minutes, end_minutes, status) VALUES '
        "('sx', 1, 1, 'gx', 1, '${inDays(3)}', 900, 990, 'normal')",
      );
    }
  });
  await tester.pumpAndSettle();
  await openMoreEntry(tester, 'طلبات الأساتذة');
  return (runtime: runtime, session: first);
}

Future<void> settleCheck(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pumpAndSettle();
}

Future<void> openRequest(WidgetTester tester) async {
  await tester.tap(find.textContaining('كمال · تغيير موعد'));
  await tester.pumpAndSettle();
  await settleCheck(tester);
}

void main() {
  appTest('لا طلبات معلّقة: رسالة', (tester) async {
    await openRequests(tester, withRequest: false);
    expect(find.text('لا طلبات معلّقة'), findsOneWidget);
  });

  appTest('طلب معلّق: الأستاذ والنوع والمجموعة والموعد المطلوب', (
    tester,
  ) async {
    await openRequests(tester);
    expect(find.textContaining('كمال · تغيير موعد'), findsOneWidget);
    expect(find.textContaining('المجموعة 1 · رياضيات'), findsOneWidget);
    expect(find.textContaining(inDays(3)), findsOneWidget);
    expect(find.text('قيد الانتظار'), findsOneWidget);
    expect(find.text('قيد الانتظار (1)'), findsOneWidget);
  });

  appTest('شارة «المزيد» وبطاقة اللوحة تعدّان المعلّق', (tester) async {
    await openRequests(tester);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('1 معلّق'), findsOneWidget);
  });

  appTest('الموافقة: قاعة مقترحة ويتحدث الجدول ويصير مقبولاً', (tester) async {
    final o = await openRequests(tester);
    await openRequest(tester);
    expect(find.text('تفاصيل الطلب'), findsOneWidget);
    expect(find.text('ظرف عائلي'), findsOneWidget);
    // القاعة حُجزت عند الإرسال، فتظهر مختارة لا مقترحة.
    expect(find.text('القاعة 1 (30)'), findsNothing);
    expect(find.textContaining('مشغول'), findsNothing);

    await tester.tap(find.widgetWithText(ClayButton, 'موافقة'));
    await tester.pumpAndSettle();
    await settleCheck(tester);
    expect(find.text('مقبول'), findsOneWidget);
    final session = await runDb(
      tester,
      () => (o.runtime.db.select(
        o.runtime.db.sessions,
      )..where((s) => s.id.equals(o.session.id))).getSingle(),
    );
    expect(session.date, inDays(3));
    expect(session.startMinutes, 900);
    final requests = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.sessionRequests).get(),
    );
    expect(requests.single.status, 'approved');
  });

  appTest('تعارض عند البتّ: الموافقة معطّلة وسببه ظاهر', (tester) async {
    await openRequests(tester, busyAtNewSlot: true);
    await openRequest(tester);
    expect(find.textContaining('الأستاذ مشغول: المجموعة 9'), findsOneWidget);
    final approve = tester.widget<ClayButton>(
      find.widgetWithText(ClayButton, 'موافقة'),
    );
    expect(approve.onPressed, isNull);
  });

  appTest('الرفض يشترط ملاحظة، ثم يصير مرفوضاً بملاحظته', (tester) async {
    final o = await openRequests(tester);
    await openRequest(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'رفض'));
    await tester.pumpAndSettle();
    expect(find.text('اكتب سبب الرفض ليصل الأستاذ'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'الموعد غير مناسب');
    await tester.ensureVisible(find.widgetWithText(ClayButton, 'رفض'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'رفض'));
    await tester.pumpAndSettle();
    expect(find.text('رفض الطلب'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'رفض').last);
    await tester.pumpAndSettle();
    await settleCheck(tester);
    expect(find.text('مرفوض'), findsOneWidget);
    expect(find.text('الموعد غير مناسب'), findsOneWidget);
    final requests = await runDb(
      tester,
      () => o.runtime.db.select(o.runtime.db.sessionRequests).get(),
    );
    expect(requests.single.status, 'rejected');
  });

  appTest('صلاحية العرض فقط: لا موافقة ولا رفض', (tester) async {
    await openRequests(tester, account: requestsViewer);
    await openRequest(tester);
    expect(find.text('ظرف عائلي'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'موافقة'), findsNothing);
    expect(find.widgetWithText(ClayButton, 'رفض'), findsNothing);
  });
}
