import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;

const payoutsViewer = TestAccount(
  id: 'u-yviewer',
  email: 'yviewer@school.local',
  password: 'yviewer-pass-1',
  role: UserRole.worker,
  entityId: 'w5',
  displayName: 'عامل عرض',
  permissions: '{"payouts":["view"]}',
);

/// يفتح «خلاص الأساتذة»؛ [withCycle] يكمل دورة من حصتين حضرها التلميذان
/// ودفع أحدهما فقط (نصيب الأستاذ 1000 للتلميذ الكامل).
Future<AppRuntime> openPayouts(
  WidgetTester tester, {
  bool withCycle = true,
  TestAccount account = owner,
}) async {
  final runtime = await openGroups(tester, account: account);
  if (withCycle) {
    final db = runtime.db;
    await runDb(tester, () async {
      final cycles = CycleService(db, runtime.writer);
      final dues = DuesService(db, runtime.writer);
      await GroupService(
        db,
        runtime.writer,
        ScheduleService(db),
        cycles,
      ).create(
        subjectId: 'math',
        teacherId: 't1',
        slots: const [
          GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690),
        ],
        startDate: '2026-11-07',
        sessionsPerCycle: 2,
        ratePerStudent: 1000,
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
      final attendance = AttendanceService(db, runtime.writer, cycles, dues);
      for (final s in await cycles.cycleSessions(group.id, 1)) {
        await attendance.markAllPresent(s.id);
      }
      await PaymentService(
        db,
        runtime.writer,
        dues,
        DeviceInfoStore(db),
      ).record(
        studentId: 's1',
        type: PaymentType.month,
        groupId: group.id,
        cycleNumber: 1,
        amount: 2000,
      );
      await attendance.closeDueSessions(DateTime(2026, 12, 1));
    });
  }
  await openMoreEntry(tester, 'خلاص الأساتذة');
  return runtime;
}

void main() {
  appTest('لا خلاصات: رسالة فارغة', (tester) async {
    await openPayouts(tester, withCycle: false);
    expect(find.text('لا خلاص ينتظر التسليم'), findsOneWidget);
  });

  appTest('اكتمال الدورة: خلاص غير مسلَّم بملخصه والمعلّق', (tester) async {
    await openPayouts(tester);
    expect(find.text('يُسلَّم للأساتذة ${Money.format(1000)}'), findsOneWidget);
    expect(
      find.text('سُلِّم ${Money.format(0)} · معلّق ${Money.format(1000)}'),
      findsOneWidget,
    );
    expect(find.text('كمال'), findsWidgets);
    expect(
      find.textContaining('رياضيات · المجموعة 1 · الدورة 1'),
      findsOneWidget,
    );
    expect(find.textContaining('اكتمال الدورة'), findsOneWidget);
    // الشارة وشريحة التصفية.
    expect(find.text('غير مسلَّم'), findsNWidgets(2));
    expect(find.text(Money.format(1000)), findsWidgets);
  });

  appTest('مرشّح الحالة', (tester) async {
    await openPayouts(tester);
    await tester.tap(find.widgetWithText(ClayChip, 'مسلَّم'));
    await tester.pumpAndSettle();
    expect(find.text('لا خلاصات'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayChip, 'الكل'));
    await tester.pumpAndSettle();
    expect(find.textContaining('اكتمال الدورة'), findsOneWidget);
  });

  appTest('الحصر بأستاذ آخر يُفرغ القائمة', (tester) async {
    await openPayouts(tester);
    await pick(tester, 'الأستاذ', 'ياسين');
    expect(find.text('لا خلاص ينتظر التسليم'), findsOneWidget);
  });

  appTest('التفصيل: نصيب كل تلميذ والمعلّق ثم تسليم المبلغ', (tester) async {
    final runtime = await openPayouts(tester);
    await tester.tap(find.textContaining('اكتمال الدورة'));
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

    await tester.tap(find.widgetWithText(ClayButton, 'تسليم المبلغ للأستاذ'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'تسليم'));
    await tester.pumpAndSettle();

    expect(find.text('مسلَّم'), findsOneWidget);
    expect(
      find.widgetWithText(ClayButton, 'تسليم المبلغ للأستاذ'),
      findsNothing,
    );
    final rows = await runDb(
      tester,
      () => runtime.db.select(runtime.db.teacherPayouts).get(),
    );
    expect(rows.single.paidAt, isNotNull);
    expect(rows.single.paidBy, 'u-owner');
  });

  appTest('تسديد المتأخر يُظهر إفراجاً جديداً غير مسلَّم', (tester) async {
    final runtime = await openPayouts(tester);
    await runDb(tester, () async {
      final db = runtime.db;
      final group = (await db.select(db.groups).get()).single;
      await PaymentService(
        db,
        runtime.writer,
        DuesService(db, runtime.writer),
        DeviceInfoStore(db),
      ).record(
        studentId: 's2',
        type: PaymentType.month,
        groupId: group.id,
        cycleNumber: 1,
        amount: 2000,
      );
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('إفراج عن نصيب معلّق'), findsOneWidget);
    expect(find.text('يُسلَّم للأساتذة ${Money.format(2000)}'), findsOneWidget);
  });

  appTest('صلاحية العرض فقط: لا زر تسليم', (tester) async {
    await openPayouts(tester, account: payoutsViewer);
    await tester.tap(find.textContaining('اكتمال الدورة'));
    await tester.pumpAndSettle();
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(
      find.widgetWithText(ClayButton, 'تسليم المبلغ للأستاذ'),
      findsNothing,
    );
  });
}
