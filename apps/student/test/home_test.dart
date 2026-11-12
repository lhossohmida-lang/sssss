import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';
import 'package:student/student_tabs.dart';

import 'widget_test.dart' hide main;

/// يفتح تطبيق الوليّ بحسابه (الوليّ p1)، ويبذر له ابنين وابناً لوليّ آخر.
Future<AppRuntime> openParent(
  WidgetTester tester, {
  bool seed = true,
  bool secondChild = true,
}) async {
  final runtime = await bootApp(
    tester,
    studentTabs,
    app: AppIdentity.student,
    accounts: [parent],
  );
  await loginWith(tester, parent.email, parent.password);
  if (!seed) return runtime;
  final db = runtime.db;
  await runDb(tester, () async {
    await SettingsService(
      db,
      runtime.writer,
    ).save(const SchoolSettings(schoolName: 'مدرسة النجاح'));
    for (final id in ['p1', 'p2']) {
      await db
          .into(db.parents)
          .insert(
            ParentsCompanion.insert(
              id: id,
              createdAt: 1,
              updatedAt: 1,
              phone: '055000000${id.substring(1)}',
              email: '$id@school.local',
            ),
          );
    }
    await db
        .into(db.levels)
        .insert(
          LevelsCompanion.insert(
            id: 'l1',
            createdAt: 1,
            updatedAt: 1,
            name: 'الرابعة متوسط',
            stage: 'middle',
            sortOrder: 1,
          ),
        );
    for (final (id, name) in [('math', 'رياضيات'), ('phys', 'فيزياء')]) {
      await db
          .into(db.subjects)
          .insert(
            SubjectsCompanion.insert(
              id: id,
              createdAt: 1,
              updatedAt: 1,
              name: name,
              monthlyPrice: const Value(2000),
            ),
          );
    }
    await db
        .into(db.teachers)
        .insert(
          TeachersCompanion.insert(
            id: 't1',
            createdAt: 1,
            updatedAt: 1,
            name: 'كمال',
            phone: '',
            email: '',
            qrCode: 'X-t1',
          ),
        );
    for (final (id, number, subject) in [
      ('g1', 1, 'math'),
      ('g2', 2, 'phys'),
    ]) {
      await db
          .into(db.groups)
          .insert(
            GroupsCompanion.insert(
              id: id,
              createdAt: 1,
              updatedAt: 1,
              number: number,
              subjectId: subject,
              teacherId: 't1',
            ),
          );
    }
    Future<void> child(String id, String first, String parentId) async {
      await db
          .into(db.students)
          .insert(
            StudentsCompanion.insert(
              id: id,
              createdAt: 1,
              updatedAt: 1,
              firstName: first,
              lastName: 'بن علي',
              parentPhone: '0550000001',
              qrCode: 'S-$id',
              levelId: const Value('l1'),
              parentAccountId: Value(parentId),
            ),
          );
    }

    Future<void> enrol(String student, String group) => db
        .into(db.groupStudents)
        .insert(
          GroupStudentsCompanion.insert(
            id: 'gs-$student-$group',
            createdAt: 1,
            updatedAt: 1,
            groupId: group,
            studentId: student,
            joinedAt: 1,
            monthlyPrice: 2000,
          ),
        );

    await child('s1', 'نور', 'p1');
    if (secondChild) await child('s2', 'سمير', 'p1');
    await child('s3', 'ليلى', 'p2');
    await enrol('s1', 'g1');
    await enrol('s1', 'g2');
    if (secondChild) await enrol('s2', 'g1');
    await enrol('s3', 'g1');

    // حصص مجموعة الرياضيات: لنور حضور مرتين وغياب وغياب برخصة.
    var n = 0;
    for (final status in ['present', 'present', 'absent', 'excused']) {
      n++;
      await db
          .into(db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 'se$n',
              createdAt: 1,
              updatedAt: 1,
              groupId: 'g1',
              cycleNumber: 1,
              date: '2026-01-0$n',
              startMinutes: 600,
              endMinutes: 690,
              status: const Value('normal'),
              closedAt: const Value(5),
            ),
          );
      await db
          .into(db.attendance)
          .insert(
            AttendanceCompanion.insert(
              id: 'a$n',
              createdAt: 1,
              updatedAt: 1,
              sessionId: 'se$n',
              studentId: 's1',
              status: status,
              method: 'manual',
            ),
          );
    }
  });
  await tester.pumpAndSettle();
  return runtime;
}

void main() {
  appTest('وليّ بلا أبناء: رسالة', (tester) async {
    await openParent(tester, seed: false);
    expect(find.text('لا أبناء مرتبطون بحسابك'), findsOneWidget);
  });

  appTest('الرئيسية: مبدّل الأبناء وأبناء هذا الوليّ فقط', (tester) async {
    await openParent(tester);
    expect(find.widgetWithText(ClayChip, 'نور'), findsOneWidget);
    expect(find.widgetWithText(ClayChip, 'سمير'), findsOneWidget);
    // ابن وليّ آخر لا يظهر.
    expect(find.text('ليلى'), findsNothing);
    // الأول بالاسم هو المعروض: سمير ثم نور.
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('الرابعة متوسط'), findsOneWidget);
  });

  appTest('بطاقات المواد بأستاذ كل مادة وحضور الابن فيها', (tester) async {
    await openParent(tester);
    await tester.tap(find.widgetWithText(ClayChip, 'نور'));
    await tester.pumpAndSettle();
    expect(find.text('نور بن علي'), findsOneWidget);
    expect(find.text('رياضيات'), findsOneWidget);
    expect(find.text('فيزياء'), findsOneWidget);
    expect(find.text('المجموعة 1 · الأستاذ كمال'), findsOneWidget);
    expect(find.text('المجموعة 2 · الأستاذ كمال'), findsOneWidget);
    expect(find.text('حضر 2'), findsOneWidget);
    expect(find.text('غاب 1'), findsOneWidget);
    expect(find.text('برخصة 1'), findsOneWidget);
    // مادة بلا حصص بعد: حضر 0 وغاب 0.
    expect(find.text('حضر 0'), findsOneWidget);
    expect(find.text('غاب 0'), findsOneWidget);
  });

  appTest('ابن واحد: لا مبدّل ويُعرض مباشرة', (tester) async {
    await openParent(tester, secondChild: false);
    expect(find.byType(ClayChip), findsNothing);
    expect(find.text('نور بن علي'), findsOneWidget);
    expect(find.text('رياضيات'), findsOneWidget);
  });

  appTest('الاختيار يبقى عند الانتقال بين التبويبات', (tester) async {
    await openParent(tester);
    await tester.tap(find.widgetWithText(ClayChip, 'نور'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الجدول').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('الرئيسية').last);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    expect(container.read(selectedChildProvider)?.id, 's1');
    expect(find.text('نور بن علي'), findsOneWidget);
  });

  appTest('ما بقي عليه: يُجمع ويُعرض بالدينار', (tester) async {
    await openParent(tester);
    // نور: دورة رياضيات ودورة فيزياء لم تُدفعا.
    await tester.tap(find.widgetWithText(ClayChip, 'نور'));
    await tester.pumpAndSettle();
    expect(find.text('المتبقي عليه'), findsOneWidget);
    expect(find.textContaining('دج'), findsWidgets);
  });
}
