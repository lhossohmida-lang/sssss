import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'home_screens_test.dart' hide main;

void main() {
  appTest('رمزي: اسم الأستاذ ورمزه وتعليمات المسح', (tester) async {
    await openTeacher(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'رمزي'));
    await tester.pumpAndSettle();
    expect(find.text('كمال'), findsOneWidget);
    expect(find.text('T-t1'), findsOneWidget);
    expect(find.byType(ClayQrCode), findsOneWidget);
    expect(
      find.textContaining('المسح الأول دخول والثاني خروج'),
      findsOneWidget,
    );
  });

  appTest('حضوري: ما حضرتُه وما غبتُ عنه بدخولي وتأخري', (tester) async {
    final runtime = await openTeacher(tester);
    final db = runtime.db;
    await runDb(tester, () async {
      final today = DateKey.of(DateTime.now());
      await db.customStatement(
        'INSERT INTO sessions (id, created_at, updated_at, group_id, '
        'cycle_number, date, start_minutes, end_minutes, status, closed_at) '
        "VALUES ('se5', 1, 1, 'g1', 1, '$today', 1000, 1090, 'normal', 5)",
      );
      await db.customStatement(
        'INSERT INTO teacher_attendance (id, created_at, updated_at, '
        'teacher_id, session_id, date, check_in, late_minutes) VALUES '
        "('ta1', 1, 1, 't1', 'se1', '$today', "
        '${DateTime(2026, 1, 1, 8, 7).toUtc().millisecondsSinceEpoch}, 7)',
      );
    });
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'حضوري'));
    await tester.pumpAndSettle();
    expect(find.text('كمال'), findsOneWidget);
    expect(
      find.textContaining('حضر 1 من 2 حصة منتهية · غاب 1'),
      findsOneWidget,
    );
    expect(find.text('حضر'), findsOneWidget);
    expect(find.text('لم يحضر'), findsOneWidget);
    expect(find.textContaining('دخل 08:07 · تأخر 7 د'), findsOneWidget);
    // لا تسجيل يدوي لحضور الأستاذ من تطبيقه.
    await tester.tap(find.text('لم يحضر'));
    await tester.pumpAndSettle();
    expect(find.text('تسجيل حضور الأستاذ'), findsNothing);
  });
}
