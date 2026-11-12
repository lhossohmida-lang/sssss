import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;

const attendanceViewer = TestAccount(
  id: 'u-viewer',
  email: 'viewer@school.local',
  password: 'viewer-pass-1',
  role: UserRole.worker,
  entityId: 'w2',
  displayName: 'عامل عرض',
  permissions: '{"attendance":["view"],"groups":["view"]}',
);

/// مجموعة بحصة اليوم وتلميذين، ثم يفتح شاشة الحضور من «المزيد».
Future<AppRuntime> openAttendance(
  WidgetTester tester, {
  TestAccount account = owner,
  bool withSession = true,
}) async {
  final runtime = await openGroups(tester, account: account);
  final db = runtime.db;
  await runDb(tester, () async {
    if (withSession) {
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
            weekday: DateTime.now().weekday,
            startMinutes: 600,
            endMinutes: 690,
          ),
        ],
        startDate: DateKey.of(DateTime.now()),
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
    }
  });
  await tester.tap(find.text('المزيد').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('الحضور'));
  await tester.pumpAndSettle();
  return runtime;
}

Future<void> openRoster(WidgetTester tester) async {
  await tester.tap(find.text('المجموعة 1 · رياضيات'));
  await tester.pumpAndSettle();
}

/// شريحة [label] في صف التلميذ [name].
Finder chip(String name, String label) => find.descendant(
  of: find.ancestor(of: find.text(name), matching: find.byType(ClayCard)).first,
  matching: find.text(label),
);

Future<void> tapChip(WidgetTester tester, String name, String label) async {
  await tester.tap(chip(name, label));
  await tester.pumpAndSettle();
}

Future<List<AttendanceRow>> rows(WidgetTester tester, AppRuntime runtime) =>
    runDb(tester, () async {
      final all = await runtime.db.select(runtime.db.attendance).get();
      return all.where((a) => a.deletedAt == null).toList();
    });

void main() {
  appTest('يوم بلا حصص: رسالة فارغة', (tester) async {
    await openAttendance(tester, withSession: false);
    expect(find.text('لا حصص في هذا اليوم'), findsOneWidget);
  });

  appTest('حصة اليوم بعدّاداتها ثم فتح الورقة', (tester) async {
    await openAttendance(tester);
    expect(find.text('المجموعة 1 · رياضيات'), findsOneWidget);
    expect(
      find.textContaining('10:00–11:30 · كمال · القاعة 1'),
      findsOneWidget,
    );
    expect(find.textContaining('حاضر 0 · غائب 0 · برخصة 0'), findsOneWidget);
    expect(find.text('2 بلا تسجيل'), findsOneWidget);

    await openRoster(tester);
    expect(find.text('ورقة الحضور'), findsOneWidget);
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('نور بن علي'), findsOneWidget);
    expect(
      find.textContaining('حاضر 0 · غائب 0 · برخصة 0 · بلا تسجيل 2'),
      findsOneWidget,
    );
  });

  appTest('حاضر ثم غائب ثم برخصة، والنقر على المحددة يمسحها', (tester) async {
    final runtime = await openAttendance(tester);
    await openRoster(tester);

    await tapChip(tester, 'سمير بن علي', 'حاضر');
    expect((await rows(tester, runtime)).single.status, 'present');
    expect(find.textContaining('حاضر 1 · غائب 0'), findsOneWidget);

    await tapChip(tester, 'سمير بن علي', 'غائب');
    expect((await rows(tester, runtime)).single.status, 'absent');

    await tapChip(tester, 'سمير بن علي', 'غائب برخصة');
    expect((await rows(tester, runtime)).single.status, 'excused');
    final credits = await runDb(
      tester,
      () => runtime.db.select(runtime.db.studentCredits).get(),
    );
    expect(credits, hasLength(1));

    await tapChip(tester, 'سمير بن علي', 'غائب برخصة');
    expect(await rows(tester, runtime), isEmpty);
    expect(find.textContaining('بلا تسجيل 2'), findsOneWidget);
  });

  appTest('تسجيل الكل حاضراً لا يمس من سُجّل غائباً', (tester) async {
    final runtime = await openAttendance(tester);
    await openRoster(tester);
    await tapChip(tester, 'سمير بن علي', 'غائب');
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل الكل حاضراً'));
    await tester.pumpAndSettle();
    final byStudent = {
      for (final r in await rows(tester, runtime)) r.studentId: r.status,
    };
    expect(byStudent, {'s1': 'absent', 's2': 'present'});
    // لم يبقَ من لم يُسجَّل: يختفي الزر.
    expect(find.widgetWithText(ClayButton, 'تسجيل الكل حاضراً'), findsNothing);
  });

  appTest('الحصة المغلقة: التصحيح مسموح والمسح لا', (tester) async {
    final runtime = await openAttendance(tester);
    await runDb(tester, () async {
      final db = runtime.db;
      await AttendanceService(
        db,
        runtime.writer,
        CycleService(db, runtime.writer),
        DuesService(db, runtime.writer),
      ).closeDueSessions(DateTime.now().add(const Duration(days: 1)));
    });
    await openRoster(tester);
    expect(find.text('مغلقة'), findsOneWidget);
    expect((await rows(tester, runtime)).map((r) => r.status), [
      'absent',
      'absent',
    ]);
    await tapChip(tester, 'سمير بن علي', 'غائب برخصة');
    final byStudent = {
      for (final r in await rows(tester, runtime)) r.studentId: r.status,
    };
    expect(byStudent['s1'], 'excused');
    // النقر على المحددة في حصة مغلقة لا يمسحها.
    await tapChip(tester, 'سمير بن علي', 'غائب برخصة');
    expect(await rows(tester, runtime), hasLength(2));
  });

  appTest('التنقل بين الأيام والعودة إلى اليوم', (tester) async {
    await openAttendance(tester);
    expect(find.text('العودة إلى اليوم'), findsNothing);
    await tester.tap(find.byTooltip('اليوم التالي'));
    await tester.pumpAndSettle();
    expect(find.text('لا حصص في هذا اليوم'), findsOneWidget);
    expect(find.text('العودة إلى اليوم'), findsOneWidget);
    await tester.tap(find.text('العودة إلى اليوم'));
    await tester.pumpAndSettle();
    expect(find.text('المجموعة 1 · رياضيات'), findsOneWidget);
    await tester.tap(find.byTooltip('اليوم السابق'));
    await tester.pumpAndSettle();
    expect(find.text('لا حصص في هذا اليوم'), findsOneWidget);
  });

  appTest('صلاحية العرض فقط: الحالات ظاهرة بلا أزرار تسجيل', (tester) async {
    final runtime = await openAttendance(tester, account: attendanceViewer);
    await runDb(tester, () async {
      final db = runtime.db;
      final session = (await db.select(db.sessions).get()).first;
      await db
          .into(db.attendance)
          .insert(
            AttendanceCompanion.insert(
              id: 'a1',
              createdAt: 1,
              updatedAt: 1,
              sessionId: session.id,
              studentId: 's1',
              status: 'present',
              method: 'manual',
            ),
          );
    });
    await openRoster(tester);
    expect(find.widgetWithText(ClayButton, 'تسجيل الكل حاضراً'), findsNothing);
    expect(find.byType(ClayChip), findsNothing);
    expect(chip('سمير بن علي', 'حاضر'), findsOneWidget);
  });

  appTest('من لا يملك صلاحية الحضور لا يرى القسم', (tester) async {
    await openGroups(tester, account: viewer);
    await tester.tap(find.text('المزيد').last);
    await tester.pumpAndSettle();
    expect(find.text('الحضور'), findsNothing);
  });
}
