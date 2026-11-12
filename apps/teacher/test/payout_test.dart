import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/testing.dart';

import 'home_screens_test.dart' hide main;

/// دورة مكتملة من حصتين: حضرها التلميذان ودفع s1 فقط، فيستحق الأستاذ 1000
/// ويبقى 1000 معلّقاً (نصيبه 1000 للتلميذ الكامل).
Future<AppRuntime> openPayout(
  WidgetTester tester, {
  bool withCycle = true,
}) async {
  final runtime = await openTeacher(tester);
  if (withCycle) {
    final db = runtime.db;
    await runDb(tester, () async {
      await db.customStatement(
        'UPDATE groups SET sessions_per_cycle = 2, rate_per_student = 1000 '
        "WHERE id = 'g1'",
      );
      await db.customStatement(
        "UPDATE sessions SET session_number = 1 WHERE id = 'se1'",
      );
      await db.customStatement(
        'INSERT INTO sessions (id, created_at, updated_at, group_id, '
        'cycle_number, date, start_minutes, end_minutes, status, closed_at, '
        "session_number) VALUES ('se6', 1, 1, 'g1', 1, "
        "'${DateKey.of(DateTime.now())}', 700, 790, 'normal', 5, 2)",
      );
      for (final session in ['se1', 'se6']) {
        for (final student in ['s1', 's2']) {
          await db.customStatement(
            'INSERT OR REPLACE INTO attendance (id, created_at, updated_at, '
            'session_id, student_id, status, method) VALUES '
            "('a-$session-$student', 1, 1, '$session', '$student', 'present', "
            "'manual')",
          );
        }
      }
      final dues = DuesService(db, runtime.writer);
      await dues.recordMonthPayment(
        studentId: 's1',
        groupId: 'g1',
        cycleNumber: 1,
        amount: 2000,
        receivedBy: 'u-teacher',
        receiptNumber: 'AAA-000001',
      );
      await PayoutService(db, runtime.writer, dues).createCyclePayout('g1', 1);
    });
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('خلاصي').last);
  await tester.pumpAndSettle();
  return runtime;
}

void main() {
  appTest('لا خلاصات: رسالة', (tester) async {
    await openPayout(tester, withCycle: false);
    expect(find.text('لا خلاصات بعد'), findsOneWidget);
  });

  appTest('خلاصي: المستحق والمعلّق وقائمة الخلاصات', (tester) async {
    await openPayout(tester);
    expect(find.text('يُسلَّم لي'), findsOneWidget);
    expect(find.text(Money.format(1000)), findsWidgets);
    expect(
      find.textContaining(
        'سُلِّم ${Money.format(0)} · معلّق ${Money.format(1000)}',
      ),
      findsOneWidget,
    );
    expect(find.text('رياضيات · المجموعة 1 · الدورة 1'), findsOneWidget);
    expect(find.text('غير مسلَّم'), findsOneWidget);
  });

  appTest('التفصيل: نصيب كل تلميذ والمعلّق', (tester) async {
    await openPayout(tester);
    await tester.tap(find.text('رياضيات · المجموعة 1 · الدورة 1'));
    await tester.pumpAndSettle();
    expect(find.text('تفصيل الخلاص'), findsOneWidget);
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('نور بن علي'), findsOneWidget);
    expect(find.text('حضر 2 · غطّى دفعه 2 حصة'), findsOneWidget);
    expect(find.text('حضر 2 · غطّى دفعه 0 حصة'), findsOneWidget);
    expect(
      find.text('معلّق حتى يدفع التلاميذ: ${Money.format(1000)}'),
      findsOneWidget,
    );
    expect(find.text('لم يُسلَّم بعد'), findsOneWidget);
  });

  appTest('بعد تسليم الإدارة: مسلَّم بتاريخه', (tester) async {
    final runtime = await openPayout(tester);
    await runDb(tester, () async {
      final db = runtime.db;
      final payout = (await db.select(db.teacherPayouts).get()).single;
      await PayoutService(
        db,
        runtime.writer,
        DuesService(db, runtime.writer),
      ).markPaid(payout.id, paidBy: 'u-owner');
    });
    await tester.tap(find.text('رياضيات · المجموعة 1 · الدورة 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('سُلِّم 20'), findsOneWidget);
  });
}
