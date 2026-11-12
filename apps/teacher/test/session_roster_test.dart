import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'home_screens_test.dart' hide main;

Finder chip(String name, String label) => find.descendant(
  of: find.ancestor(of: find.text(name), matching: find.byType(ClayCard)).first,
  matching: find.text(label),
);

Future<void> openRoster(WidgetTester tester) async {
  await tester.tap(find.text('مغلقة'));
  await tester.pumpAndSettle();
}

void main() {
  appTest('حصة من الرئيسية: ورقة الحضور بحاضر وغائب فقط', (tester) async {
    await openTeacher(tester);
    await openRoster(tester);
    expect(find.text('ورقة الحضور'), findsOneWidget);
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('نور بن علي'), findsOneWidget);
    expect(find.text('حاضر'), findsWidgets);
    expect(find.text('غائب'), findsWidgets);
    expect(find.text('غائب برخصة'), findsNothing);
  });

  appTest('تسجيل تلميذ حاضراً يدوياً', (tester) async {
    final runtime = await openTeacher(tester);
    await openRoster(tester);
    await tester.tap(chip('نور بن علي', 'حاضر'));
    await tester.pumpAndSettle();
    final rows = await runDb(
      tester,
      () => runtime.db.select(runtime.db.attendance).get(),
    );
    final nour = rows.firstWhere((r) => r.studentId == 's2');
    expect(nour.status, 'present');
    expect(nour.method, 'manual');
  });

  appTest('تسجيل الكل حاضراً في حصة مفتوحة', (tester) async {
    final runtime = await openTeacher(tester);
    final db = runtime.db;
    await runDb(tester, () async {
      await db.customStatement(
        'INSERT INTO sessions (id, created_at, updated_at, group_id, '
        'cycle_number, date, start_minutes, end_minutes, status) VALUES '
        "('se4', 1, 1, 'g1', 1, '${DateKey.of(DateTime.now())}', 1000, 1090, "
        "'normal')",
      );
    });
    await tester.pumpAndSettle();
    unawaited(
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .push('/attendance/se4'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'تسجيل الكل حاضراً'));
    await tester.pumpAndSettle();
    final rows = await runDb(
      tester,
      () => (db.select(
        db.attendance,
      )..where((a) => a.sessionId.equals('se4'))).get(),
    );
    expect(rows.map((r) => r.status).toSet(), {'present'});
    expect(rows, hasLength(2));
  });

  appTest('غياب برخصة منحته الإدارة لا يغيّره الأستاذ', (tester) async {
    final runtime = await openTeacher(tester);
    final db = runtime.db;
    await runDb(tester, () async {
      await db.customStatement(
        'INSERT INTO attendance (id, created_at, updated_at, session_id, '
        'student_id, status, method) VALUES '
        "('a2', 1, 1, 'se1', 's2', 'excused', 'manual')",
      );
    });
    await tester.pumpAndSettle();
    await openRoster(tester);
    // برخصة: شارة بلا شرائح في صفه.
    expect(find.text('غائب برخصة'), findsOneWidget);
    expect(chip('نور بن علي', 'حاضر'), findsNothing);
    expect(chip('سمير بن علي', 'حاضر'), findsOneWidget);
  });

  appTest('حصة أستاذ آخر برابط مباشر: ليست من حصصك', (tester) async {
    await openTeacher(tester);
    unawaited(
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .push('/attendance/se3'),
    );
    await tester.pumpAndSettle();
    expect(find.text('هذه الحصة ليست من حصصك'), findsOneWidget);
    expect(find.text('ورقة الحضور'), findsOneWidget);
  });
}
