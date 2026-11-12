import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'home_screens_test.dart' hide main;

String inDays(int n) {
  final now = DateTime.now();
  return DateKey.of(DateTime(now.year, now.month, now.day + n));
}

/// يبذر قاعتين وحصصاً قادمة مفتوحة، ثم يفتح تبويب «طلباتي».
Future<AppRuntime> openRequests(
  WidgetTester tester, {
  bool busyTwin = false,
}) async {
  final runtime = await openTeacher(tester);
  final db = runtime.db;
  await runDb(tester, () async {
    for (final id in ['r1', 'r2']) {
      await db.customStatement(
        'INSERT INTO rooms (id, created_at, updated_at, name, capacity) '
        "VALUES ('$id', 1, 1, 'القاعة $id', 30)",
      );
    }
    await db.customStatement(
      "UPDATE groups SET room_id = 'r1' WHERE id = 'g1'",
    );
    Future<void> session(String id, String group, String date) =>
        db.customStatement(
          'INSERT INTO sessions (id, created_at, updated_at, group_id, '
          'cycle_number, date, start_minutes, end_minutes, status, '
          'room_id) VALUES '
          "('$id', 1, 1, '$group', 1, '$date', 600, 690, 'normal', 'r1')",
        );
    await session('f1', 'g1', inDays(7));
    await session('f2', 'g1', inDays(14));
    if (busyTwin) {
      await db.customStatement(
        'INSERT INTO groups (id, created_at, updated_at, number, subject_id, '
        "teacher_id) VALUES ('g4', 1, 1, 4, 'math', 't1')",
      );
      await session('f3', 'g4', inDays(14));
    }
  });
  await tester.pumpAndSettle();
  await tester.tap(find.text('طلباتي').last);
  await tester.pumpAndSettle();
  return runtime;
}

Future<void> pick(WidgetTester tester, String label, String option) async {
  final dropdown = find.descendant(
    of: find
        .ancestor(of: find.text(label), matching: find.byType(Column))
        .first,
    matching: find.byWidgetPredicate((w) => w is DropdownButton),
  );
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(option).last);
  await tester.pumpAndSettle();
}

/// يمهل الفحص اللحظي (مهلة 250ms) ثم يستقر.
Future<void> settleCheck(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pumpAndSettle();
}

/// يعيد قراءة القائمة (لا يصل إشعار الاستعلام اللحظي داخل منطقة الاختبار
/// الوهمية، وهو يعمل في التطبيق: اختبار core `watchMine`).
Future<void> refreshList(WidgetTester tester) async {
  ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
      .invalidate(myRequestsProvider);
  await settleCheck(tester);
}

Future<void> openForm(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ClayButton, 'طلب جديد'));
  await tester.pumpAndSettle();
  tester.view.physicalSize = const Size(420, 2400);
  await tester.pumpAndSettle();
}

void main() {
  appTest('لا طلبات: رسالة وزر طلب جديد', (tester) async {
    await openRequests(tester);
    expect(find.text('لا طلبات بعد'), findsOneWidget);
    expect(find.widgetWithText(ClayButton, 'طلب جديد'), findsOneWidget);
  });

  appTest('طلب تغيير موعد: فحص لحظي وقاعة مقترحة ثم إرسال', (tester) async {
    final runtime = await openRequests(tester);
    await openForm(tester);
    await pick(tester, 'الحصة', inDays(7));
    await settleCheck(tester);
    expect(find.text('القاعة المقترحة: القاعة r1'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'إرسال الطلب'));
    await tester.pumpAndSettle();
    await refreshList(tester);

    // عودة إلى القائمة بالطلب قيد الانتظار.
    expect(find.text('تغيير موعد · المجموعة 1 · رياضيات'), findsOneWidget);
    expect(find.text('قيد الانتظار'), findsOneWidget);
    final rows = await runDb(
      tester,
      () => runtime.db.select(runtime.db.sessionRequests).get(),
    );
    expect(rows.single.type, 'reschedule');
    expect(rows.single.status, 'pending');
    expect(rows.single.newRoomId, 'r1');
  });

  appTest('تعارض الأستاذ يمنع الإرسال ويُظهر سببه', (tester) async {
    await openRequests(tester, busyTwin: true);
    await openForm(tester);
    await pick(tester, 'الحصة', inDays(14));
    await settleCheck(tester);
    expect(find.textContaining('الأستاذ مشغول: المجموعة 4'), findsOneWidget);
    final send = tester.widget<ClayButton>(
      find.widgetWithText(ClayButton, 'إرسال الطلب'),
    );
    expect(send.onPressed, isNull);
  });

  appTest('إلغاء حصة: لا موعد جديد ويُرسل مباشرة', (tester) async {
    final runtime = await openRequests(tester);
    await openForm(tester);
    await tester.tap(find.widgetWithText(ClayChip, 'إلغاء حصة'));
    await tester.pumpAndSettle();
    expect(find.text('الموعد الجديد'), findsNothing);
    await pick(tester, 'الحصة', inDays(7));
    await settleCheck(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'إرسال الطلب'));
    await tester.pumpAndSettle();
    await refreshList(tester);
    final rows = await runDb(
      tester,
      () => runtime.db.select(runtime.db.sessionRequests).get(),
    );
    expect(rows.single.type, 'cancel');
    expect(rows.single.sessionId, 'f1');
    expect(find.text('إلغاء حصة · المجموعة 1 · رياضيات'), findsOneWidget);
  });

  appTest('إضافة حصة بلا تاريخ: لا إرسال حتى يُحدَّد الموعد', (tester) async {
    await openRequests(tester);
    await openForm(tester);
    await tester.tap(find.widgetWithText(ClayChip, 'إضافة حصة'));
    await tester.pumpAndSettle();
    await settleCheck(tester);
    expect(find.text('حدّد التاريخ والوقت الجديدين'), findsOneWidget);
    final send = tester.widget<ClayButton>(
      find.widgetWithText(ClayButton, 'إرسال الطلب'),
    );
    expect(send.onPressed, isNull);
  });

  appTest('تفاصيل طلب مقبول بملاحظة الإدارة', (tester) async {
    final runtime = await openRequests(tester);
    await runDb(tester, () async {
      await runtime.db.customStatement(
        'INSERT INTO session_requests (id, created_at, updated_at, teacher_id, '
        'group_id, type, session_id, reason, status, admin_note) VALUES '
        "('rq1', 1, 1, 't1', 'g1', 'cancel', 'f1', 'ظرف عائلي', 'approved', "
        "'تمت الموافقة')",
      );
    });
    await tester.pumpAndSettle();
    await refreshList(tester);
    expect(find.text('مقبول'), findsOneWidget);
    await tester.tap(find.text('إلغاء حصة · المجموعة 1 · رياضيات'));
    await tester.pumpAndSettle();
    expect(find.text('ملاحظة الإدارة'), findsOneWidget);
    expect(find.text('تمت الموافقة'), findsOneWidget);
    expect(find.text('ظرف عائلي'), findsWidgets);
  });
}
