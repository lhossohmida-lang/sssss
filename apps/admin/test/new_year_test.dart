import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'settings_screen_test.dart' hide main;

/// يفتح الإعدادات ويبذر مجموعتين نشطتين بتلميذين منتسبين ودفعة.
Future<AppRuntime> openNewYear(WidgetTester tester, TestAccount account) async {
  final runtime = await openSettings(tester, account);
  await runDb(tester, () async {
    final db = runtime.db;
    await db
        .into(db.subjects)
        .insert(
          SubjectsCompanion.insert(
            id: 'math',
            createdAt: 1,
            updatedAt: 1,
            name: 'رياضيات',
            monthlyPrice: const Value(2000),
          ),
        );
    await db
        .into(db.teachers)
        .insert(
          TeachersCompanion.insert(
            id: 't1',
            createdAt: 1,
            updatedAt: 1,
            name: 'كمال',
            phone: '0660000001',
            email: 't1@school.local',
            qrCode: 'T-t1',
          ),
        );
    for (final (id, number) in [('g1', 1), ('g2', 2)]) {
      await db
          .into(db.groups)
          .insert(
            GroupsCompanion.insert(
              id: id,
              createdAt: 1,
              updatedAt: 1,
              number: number,
              subjectId: 'math',
              teacherId: 't1',
            ),
          );
    }
    for (final id in ['s1', 's2']) {
      await db
          .into(db.students)
          .insert(
            StudentsCompanion.insert(
              id: id,
              createdAt: 1,
              updatedAt: 1,
              firstName: 'تلميذ',
              lastName: id,
              parentPhone: '0550000001',
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
              groupId: id == 's1' ? 'g1' : 'g2',
              studentId: id,
              joinedAt: 1,
              monthlyPrice: 2000,
            ),
          );
    }
  });
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.widgetWithText(ClayButton, 'سنة جديدة'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  return runtime;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump(const Duration(milliseconds: 80));
  }
  await tester.pumpAndSettle();
}

Future<void> openDialog(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ClayButton, 'سنة جديدة'));
  await tester.pumpAndSettle();
  await settle(tester);
}

void main() {
  appTest('القسم: شرح، ولم تُبدأ سنة جديدة بعد', (tester) async {
    await openNewYear(tester, owner);
    expect(find.text('السنة الدراسية'), findsOneWidget);
    expect(find.text('لم تُبدأ سنة جديدة بعد من هذا النظام.'), findsOneWidget);
    expect(find.textContaining('تؤرشف كل المجموعات النشطة'), findsOneWidget);
  });

  appTest('النافذة تعرض ما سيُؤرشف وما سيبقى، والزر معطَّل', (tester) async {
    await openNewYear(tester, owner);
    await openDialog(tester);
    expect(find.textContaining('ستُؤرشف 2 مجموعة نشطة'), findsOneWidget);
    expect(find.textContaining('يبقى 2 تلميذاً'), findsOneWidget);
    final start = tester.widget<ClayButton>(
      find.widgetWithText(ClayButton, 'بدء سنة جديدة'),
    );
    expect(start.onPressed, isNull);
  });

  appTest('عبارة خاطئة تُبقي الزر معطَّلاً، والصحيحة تفعّله', (tester) async {
    await openNewYear(tester, owner);
    await openDialog(tester);
    final phrase = find.byType(TextField).last;
    await tester.enterText(phrase, 'سنة');
    await tester.pump();
    expect(
      tester
          .widget<ClayButton>(find.widgetWithText(ClayButton, 'بدء سنة جديدة'))
          .onPressed,
      isNull,
    );
    await tester.enterText(phrase, 'سنة جديدة');
    await tester.pump();
    expect(
      tester
          .widget<ClayButton>(find.widgetWithText(ClayButton, 'بدء سنة جديدة'))
          .onPressed,
      isNotNull,
    );
  });

  appTest('الإلغاء لا يؤرشف شيئاً', (tester) async {
    final runtime = await openNewYear(tester, owner);
    await openDialog(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'إلغاء'));
    await tester.pumpAndSettle();
    final groups = await runDb(
      tester,
      () => runtime.db.select(runtime.db.groups).get(),
    );
    expect(groups.every((g) => g.archivedAt == null), isTrue);
  });

  appTest('التأكيد يؤرشف المجموعات ويبقي التلاميذ ويعرض الملخص', (
    tester,
  ) async {
    final runtime = await openNewYear(tester, owner);
    await openDialog(tester);
    await tester.enterText(find.byType(TextField).last, 'سنة جديدة');
    await tester.pump();
    await tester.tap(find.widgetWithText(ClayButton, 'بدء سنة جديدة'));
    await settle(tester);

    expect(
      find.text('أُرشفت 2 مجموعة، وبقي 2 تلميذاً بسجلاتهم'),
      findsOneWidget,
    );
    final groups = await runDb(
      tester,
      () => runtime.db.select(runtime.db.groups).get(),
    );
    expect(groups.every((g) => g.archivedAt != null), isTrue);
    final students = await runDb(
      tester,
      () => runtime.db.select(runtime.db.students).get(),
    );
    expect(students.where((s) => s.deletedAt == null), hasLength(2));
    // يظهر وقت آخر تنفيذ بدل «لم تُبدأ».
    expect(find.textContaining('آخر سنة جديدة بدأت في'), findsOneWidget);
  });

  appTest('عامل بصلاحية عرض الإعدادات فقط: الزر معطَّل', (tester) async {
    await openSettings(tester, worker('{"settings":["view"]}'));
    await tester.scrollUntilVisible(
      find.widgetWithText(ClayButton, 'سنة جديدة'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final button = tester.widget<ClayButton>(
      find.widgetWithText(ClayButton, 'سنة جديدة'),
    );
    expect(button.onPressed, isNull);
  });
}
