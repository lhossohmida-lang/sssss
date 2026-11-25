import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'group_details_screen_test.dart' hide main;

void main() {
  appTest('المدير يغيّر حضور تلميذ في حصة مضت من الشبكة، ولو كانت مغلقة', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    final runtime = await openDetails(tester);
    await tester.pumpAndSettle();
    final db = runtime.db;
    final sessions = await runDb(
      tester,
      () => (db.select(
        db.sessions,
      )..orderBy([(s) => OrderingTerm(expression: s.date)])).get(),
    );
    // تُغلق الحصة الثانية (غياب سمير فيها) فيبقى تغييرها ممكناً.
    await runDb(
      tester,
      () => (db.update(db.sessions)..where((s) => s.id.equals(sessions[1].id)))
          .write(const SessionsCompanion(closedAt: Value(1))),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('اضغط خانة تلميذ لتغيير حضوره'), findsOneWidget);
    // خانة سمير في الحصة الثانية (غيابه).
    await tester.tap(find.byKey(ValueKey('grid-cell-${sessions[1].id}-s1')));
    await tester.pumpAndSettle();
    expect(find.text('الحالي'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('حاضر'),
      ),
    );
    await tester.pumpAndSettle();
    final row = await runDb(
      tester,
      () =>
          (db.select(db.attendance)..where(
                (a) =>
                    a.sessionId.equals(sessions[1].id) &
                    a.studentId.equals('s1'),
              ))
              .getSingle(),
    );
    expect(row.status, AttendanceStatus.present.code);
    expect(find.text('سمير بن علي: حاضر'), findsOneWidget);
  });

  appTest('عنوان حصة مضت يفتح ورقة حضورها', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    final runtime = await openDetails(tester);
    await tester.pumpAndSettle();
    final first = await runDb(
      tester,
      () =>
          (runtime.db.select(runtime.db.sessions)
                ..orderBy([(s) => OrderingTerm(expression: s.date)])
                ..limit(1))
              .getSingle(),
    );
    await tester.tap(find.byKey(ValueKey('grid-session-${first.id}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('حاضر 2 · غائب 0'), findsOneWidget);
  });

  appTest('دفع حصة من خانة التلميذ في الشبكة', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    final runtime = await openDetails(tester);
    await tester.pumpAndSettle();
    final db = runtime.db;
    final first = await runDb(
      tester,
      () =>
          (db.select(db.sessions)
                ..orderBy([(s) => OrderingTerm(expression: s.date)])
                ..limit(1))
              .getSingle(),
    );
    await tester.tap(find.byKey(ValueKey('grid-cell-${first.id}-s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'دفع هذه الحصة'));
    await tester.pumpAndSettle();
    final paid = await runDb(tester, () => db.select(db.payments).get());
    expect(paid, hasLength(1));
    expect(paid.single.studentId, 's1');
    expect(find.textContaining('دُفعت حصة'), findsOneWidget);
  });

  appTest('ورقة الحصة: حذف حضورها كله بعد التأكيد', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    final runtime = await openDetails(tester);
    await tester.pumpAndSettle();
    final db = runtime.db;
    final first = await runDb(
      tester,
      () =>
          (db.select(db.sessions)
                ..orderBy([(s) => OrderingTerm(expression: s.date)])
                ..limit(1))
              .getSingle(),
    );
    await tester.tap(find.byKey(ValueKey('grid-session-${first.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حذف حضور الحصة'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حذف الحضور'));
    await tester.pumpAndSettle();
    final left = await runDb(
      tester,
      () =>
          (db.select(db.attendance)..where(
                (a) => a.sessionId.equals(first.id) & a.deletedAt.isNull(),
              ))
              .get(),
    );
    expect(left, isEmpty);
    expect(find.textContaining('بلا تسجيل 2'), findsOneWidget);
  });

  appTest('الضغط الثاني على دفع الحصة يلغي دفعها', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    final runtime = await openDetails(tester);
    await tester.pumpAndSettle();
    final db = runtime.db;
    final first = await runDb(
      tester,
      () =>
          (db.select(db.sessions)
                ..orderBy([(s) => OrderingTerm(expression: s.date)])
                ..limit(1))
              .getSingle(),
    );
    final cell = find.byKey(ValueKey('grid-cell-${first.id}-s1'));
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'دفع هذه الحصة'));
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'إلغاء دفع هذه الحصة'));
    await tester.pumpAndSettle();
    final paid = await runDb(
      tester,
      () => (db.select(db.payments)..where((p) => p.deletedAt.isNull())).get(),
    );
    expect(paid, isEmpty);
  });

  appTest('حذف حضور الفوج كله من الشبكة', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    final runtime = await openDetails(tester);
    await tester.pumpAndSettle();
    final db = runtime.db;
    await tester.ensureVisible(
      find.widgetWithText(ClayButton, 'حذف حضور الفوج'),
    );
    await tester.tap(find.widgetWithText(ClayButton, 'حذف حضور الفوج'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'كل الدورات'));
    await tester.pumpAndSettle();
    final left = await runDb(
      tester,
      () =>
          (db.select(db.attendance)..where((a) => a.deletedAt.isNull())).get(),
    );
    expect(left, isEmpty);
  });
}
