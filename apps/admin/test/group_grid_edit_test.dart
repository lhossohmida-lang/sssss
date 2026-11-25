import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
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
}
