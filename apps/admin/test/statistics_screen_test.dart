import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/testing.dart';

import 'catalog_screens_test.dart' show openSection, owner;

const studentReader = TestAccount(
  id: 'u-stats-student-reader',
  email: 'stats-students@school.local',
  password: 'stats-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'قارئ التلاميذ',
  permissions: '{"students":["view"]}',
);

const paymentReader = TestAccount(
  id: 'u-stats-payment-reader',
  email: 'stats-payments@school.local',
  password: 'stats-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'قارئ المدفوعات',
  permissions: '{"payments":["view"]}',
);

Future<void> seedStudent(AppRuntime runtime, {required int createdAt}) async {
  await runtime.db
      .into(runtime.db.students)
      .insert(
        StudentsCompanion.insert(
          id: 's-stat',
          createdAt: createdAt,
          updatedAt: createdAt,
          firstName: 'سليم',
          lastName: 'الإحصاء',
          parentPhone: '0550123456',
          qrCode: 'S-STAT',
        ),
      );
}

void main() {
  appTest('يعرض المخططات السنوية ويغيّر السنة', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    final runtime = await openSection(tester, owner, 'الإحصائيات');
    final now = DateTime.now();
    final yearStart = DateTime(now.year, 1);
    await runDb(tester, () async {
      await seedStudent(runtime, createdAt: yearStart.millisecondsSinceEpoch);
      await runtime.db
          .into(runtime.db.subjects)
          .insert(
            SubjectsCompanion.insert(
              id: 'sub-stat',
              createdAt: 1,
              updatedAt: 1,
              name: 'رياضيات',
            ),
          );
      await runtime.db
          .into(runtime.db.teachers)
          .insert(
            TeachersCompanion.insert(
              id: 't-stat',
              createdAt: 1,
              updatedAt: 1,
              name: 'الأستاذ',
              phone: '0770000000',
              email: 't-stat@school.local',
              qrCode: 'T-STAT',
            ),
          );
      await runtime.db
          .into(runtime.db.groups)
          .insert(
            GroupsCompanion.insert(
              id: 'g-stat',
              createdAt: yearStart.millisecondsSinceEpoch,
              updatedAt: 1,
              number: 1,
              subjectId: 'sub-stat',
              teacherId: 't-stat',
            ),
          );
      await runtime.db
          .into(runtime.db.sessions)
          .insert(
            SessionsCompanion.insert(
              id: 'session-stat',
              createdAt: 1,
              updatedAt: 1,
              groupId: 'g-stat',
              cycleNumber: 1,
              sessionNumber: const Value(1),
              date: '${now.year}-01-05',
              startMinutes: 600,
              endMinutes: 690,
            ),
          );
      await runtime.db
          .into(runtime.db.attendance)
          .insert(
            AttendanceCompanion.insert(
              id: 'attendance-stat',
              createdAt: 1,
              updatedAt: 1,
              sessionId: 'session-stat',
              studentId: 's-stat',
              status: 'present',
              method: 'manual',
            ),
          );
      await runtime.db
          .into(runtime.db.payments)
          .insert(
            PaymentsCompanion.insert(
              id: 'payment-stat',
              createdAt: yearStart.millisecondsSinceEpoch,
              updatedAt: 1,
              studentId: 's-stat',
              type: PaymentType.month.code,
              amount: 1250,
              receivedBy: owner.id,
              receiptNumber: 'STAT-000001',
            ),
          );
      final category = await ExpenseService(
        runtime.db,
        runtime.writer,
      ).addCategory('قرطاسية');
      await ExpenseService(runtime.db, runtime.writer).addExpense(
        categoryId: category,
        amount: 300,
        date: '${now.year}-01-10',
      );
      await runtime.db
          .into(runtime.db.teacherPayouts)
          .insert(
            TeacherPayoutsCompanion.insert(
              id: 'payout-stat',
              createdAt: 1,
              updatedAt: 1,
              teacherId: 't-stat',
              groupId: 'g-stat',
              cycleNumber: 1,
              amount: 400,
              paidAt: Value(yearStart.millisecondsSinceEpoch),
              paidBy: const Value('u-owner'),
            ),
          );
    });
    await tester.pumpAndSettle();

    expect(find.text('الحركة المالية الشهرية'), findsOneWidget);
    expect(find.text('حضور التلاميذ حسب الشهر'), findsOneWidget);
    expect(find.text('التسجيلات الشهرية'), findsOneWidget);
    expect(find.textContaining(Money.format(1250)), findsOneWidget);
    expect(find.textContaining(Money.format(300)), findsOneWidget);
    expect(find.textContaining(Money.format(400)), findsOneWidget);
    expect(find.text('التلاميذ النشطون'), findsOneWidget);
    expect(find.text('الأفواج النشطة'), findsOneWidget);

    await tester.tap(find.byTooltip('السنة السابقة'));
    await tester.pumpAndSettle();
    expect(find.text('السنة ${now.year - 1}'), findsOneWidget);
    await tester.tap(find.byTooltip('السنة التالية'));
    await tester.pumpAndSettle();
    expect(find.text('السنة ${now.year}'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('السنة التالية'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  appTest('قارئ التلاميذ يرى نمو التسجيلات فقط', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    final runtime = await openSection(tester, studentReader, 'الإحصائيات');
    await runDb(
      tester,
      () => seedStudent(
        runtime,
        createdAt: DateTime(DateTime.now().year, 2).millisecondsSinceEpoch,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('التسجيلات الشهرية'), findsOneWidget);
    expect(find.text('الحركة المالية الشهرية'), findsNothing);
    expect(find.text('حضور التلاميذ حسب الشهر'), findsNothing);
    expect(find.text('التلاميذ النشطون'), findsOneWidget);
  });

  appTest('قارئ المدفوعات يرى الحركة المالية دون إحصاءات التلاميذ', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    await openSection(tester, paymentReader, 'الإحصائيات');

    expect(find.text('الحركة المالية الشهرية'), findsOneWidget);
    expect(find.text('المقبوضات 0 دج'), findsOneWidget);
    expect(find.text('التسجيلات الشهرية'), findsNothing);
    expect(find.text('حضور التلاميذ حسب الشهر'), findsNothing);
    expect(find.text('التلاميذ النشطون'), findsNothing);
  });
}
