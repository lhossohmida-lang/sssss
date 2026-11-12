import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;

const teachersViewer = TestAccount(
  id: 'u-tv',
  email: 'tv@school.local',
  password: 'tv-pass-1',
  role: UserRole.worker,
  entityId: 'w7',
  displayName: 'عامل عرض',
  permissions: '{"teachers":["view"]}',
);

/// يبذر مجموعة بحصتين مغلقتين اليوم (الأولى لم يحضرها الأستاذ، والثانية
/// حضرها)، ثم يفتح «حضور الأساتذة».
Future<AppRuntime> openTeacherSheet(
  WidgetTester tester, {
  bool withSessions = true,
  TestAccount account = owner,
}) async {
  final runtime = await openGroups(tester, account: account);
  if (withSessions) {
    final db = runtime.db;
    await runDb(tester, () async {
      await db
          .into(db.groups)
          .insert(
            GroupsCompanion.insert(
              id: 'g1',
              createdAt: 1,
              updatedAt: 1,
              number: 1,
              subjectId: 'math',
              teacherId: 't1',
            ),
          );
      final today = DateKey.of(DateTime.now());
      for (final (id, start) in [('se1', 600), ('se2', 780)]) {
        await db
            .into(db.sessions)
            .insert(
              SessionsCompanion.insert(
                id: id,
                createdAt: 1,
                updatedAt: 1,
                groupId: 'g1',
                cycleNumber: 1,
                date: today,
                startMinutes: start,
                endMinutes: start + 90,
                sessionNumber: Value(start == 600 ? 1 : 2),
                closedAt: const Value(5),
              ),
            );
      }
      await db
          .into(db.teacherAttendance)
          .insert(
            TeacherAttendanceCompanion.insert(
              id: 'ta-se2',
              createdAt: 1,
              updatedAt: 1,
              teacherId: 't1',
              sessionId: const Value('se2'),
              date: today,
              checkIn: Value(
                DateTime(2026, 1, 1, 13, 5).toUtc().millisecondsSinceEpoch,
              ),
              checkOut: Value(
                DateTime(2026, 1, 1, 14, 30).toUtc().millisecondsSinceEpoch,
              ),
              lateMinutes: const Value(5),
            ),
          );
    });
  }
  await openMoreEntry(tester, 'حضور الأساتذة');
  return runtime;
}

void main() {
  appTest('لا حصص في الشهر: رسالة فارغة', (tester) async {
    await openTeacherSheet(tester, withSessions: false);
    expect(find.text('لا حصص في هذا الشهر'), findsOneWidget);
    expect(find.text(DateKey.monthLabel(currentMonthKey())), findsOneWidget);
  });

  appTest('الكشف: حضر 1 من 2 وغاب 1 مع تنبيه الحصة الفائتة', (tester) async {
    await openTeacherSheet(tester);
    expect(find.text('كمال'), findsWidgets);
    expect(
      find.textContaining('حضر 1 من 2 حصة منتهية · غاب 1'),
      findsOneWidget,
    );
    expect(find.textContaining('تأخر 5 د'), findsOneWidget);
    expect(find.text('غاب 1'), findsOneWidget);
    expect(find.text('حصص لم يحضرها أستاذها في آخر 7 أيام: 1'), findsOneWidget);
    expect(find.textContaining('المجموعة 1 (رياضيات)'), findsOneWidget);
  });

  appTest('كشف الأستاذ حصة بحصة بدخوله وخروجه وتأخره', (tester) async {
    await openTeacherSheet(tester);
    await tester.tap(find.textContaining('حضر 1 من 2'));
    await tester.pumpAndSettle();
    expect(find.text('حضر'), findsOneWidget);
    expect(find.text('لم يحضر'), findsOneWidget);
    expect(
      find.textContaining('دخل 13:05 وخرج 14:30 · تأخر 5 د'),
      findsOneWidget,
    );
    expect(find.textContaining('10:00–11:30'), findsOneWidget);
  });

  appTest('تسجيل حضور الأستاذ يدوياً لحصة فائتة', (tester) async {
    final runtime = await openTeacherSheet(tester);
    await tester.tap(find.textContaining('حضر 1 من 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('لم يحضر'));
    await tester.pumpAndSettle();
    expect(find.text('تسجيل حضور الأستاذ'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل الحضور'));
    await tester.pumpAndSettle();

    expect(find.text('لم يحضر'), findsNothing);
    expect(find.text('حضر'), findsNWidgets(2));
    final rows = await runDb(
      tester,
      () => runtime.db.select(runtime.db.teacherAttendance).get(),
    );
    expect(rows.where((r) => r.sessionId == 'se1'), hasLength(1));
  });

  appTest('الرجوع من الكشف وزوال التنبيه بعد التسجيل', (tester) async {
    await openTeacherSheet(tester);
    await tester.tap(find.textContaining('حضر 1 من 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('لم يحضر'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل الحضور'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.textContaining('حصص لم يحضرها أستاذها'), findsNothing);
    expect(find.textContaining('حضر 2 من 2'), findsOneWidget);
  });

  appTest('الشهر التالي بلا حصص', (tester) async {
    await openTeacherSheet(tester);
    await tester.tap(find.byTooltip('الشهر التالي'));
    await tester.pumpAndSettle();
    expect(find.text('لا حصص في هذا الشهر'), findsOneWidget);
  });

  appTest('صلاحية العرض فقط: لا تسجيل يدوي', (tester) async {
    await openTeacherSheet(tester, account: teachersViewer);
    await tester.tap(find.textContaining('حضر 1 من 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('لم يحضر'));
    await tester.pumpAndSettle();
    expect(find.text('تسجيل حضور الأستاذ'), findsNothing);
  });
}
