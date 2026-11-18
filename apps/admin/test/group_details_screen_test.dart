import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;
import 'support/groups_nav.dart';

/// ينشئ مجموعة وتلميذين وحضوراً، ثم يفتح تفاصيلها من القائمة.
Future<AppRuntime> openDetails(
  WidgetTester tester, {
  TestAccount account = owner,
  bool withStudents = true,

  /// بيانات إضافية تُكتب قبل فتح التفاصيل (دفعات أو حصص مراجعة مثلاً).
  Future<void> Function(AppDatabase db, GroupRow group)? seed,
}) async {
  final runtime = await openGroups(tester, account: account);
  final db = runtime.db;
  await runDb(tester, () async {
    await GroupService(
      db,
      runtime.writer,
      ScheduleService(db),
      CycleService(db, runtime.writer),
    ).create(
      subjectId: 'math',
      teacherId: 't1',
      roomId: 'r1',
      slots: const [
        GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690),
      ],
      startDate: '2026-11-07',
    );
    if (!withStudents) return;
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
    final sessions = await (db.select(
      db.sessions,
    )..orderBy([(s) => OrderingTerm(expression: s.date)])).get();
    Future<void> mark(int i, String student, String status) => db
        .into(db.attendance)
        .insert(
          AttendanceCompanion.insert(
            id: 'a$i$student',
            createdAt: 1,
            updatedAt: 1,
            sessionId: sessions[i].id,
            studentId: student,
            status: status,
            method: 'manual',
          ),
        );
    await mark(0, 's1', 'present');
    await mark(1, 's1', 'absent');
    await mark(2, 's1', 'excused');
    await mark(0, 's2', 'present');
    await seed?.call(db, group);
  });
  await tapGroup(tester);
  return runtime;
}

void main() {
  appTest('التفاصيل: معلومات الفوج والدورة وتقدّمها', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    await openDetails(tester);
    expect(find.text('رياضيات'), findsWidgets);
    expect(find.textContaining('كمال · القاعة 1 · 2 تلميذ'), findsOneWidget);
    expect(find.text('الدورة 1 (الحالية)'), findsOneWidget);
    expect(find.text('انعقدت 0 من 8 حصة'), findsOneWidget);
    expect(find.byTooltip('تعديل الفوج'), findsOneWidget);
  });

  appTest('الشبكة: صفوف التلاميذ وخلاياهم بحالاتها', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    final semantics = tester.ensureSemantics();
    await openDetails(tester);
    await tester.pumpAndSettle();
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('نور بن علي'), findsOneWidget);
    // الصف يُقرأ وحدة واحدة: الاسم ثم حالة كل حصة بنص لا باللون وحده.
    final first = tester.getSemantics(find.text('سمير بن علي')).label;
    expect(first, contains('حاضر'));
    expect(first, contains('غائب'));
    expect(first, contains('غائب برخصة'));
    expect(first, contains('لم يُسجَّل'));
    final second = tester.getSemantics(find.text('نور بن علي')).label;
    expect(second, contains('حاضر'));
    expect(second, isNot(contains('غائب')));
    // مجموع الحضور من عدد الحصص المحسوبة.
    expect(find.text('1/8'), findsNWidgets(2));
    semantics.dispose();
  });

  appTest(
    'الشبكة: الحصص المسدَّدة زرقاء ولو لم تُحضَر، وما حُضر ولم يُسدَّد أحمر',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      final semantics = tester.ensureSemantics();
      await openDetails(
        tester,
        // سمير دفع نصف الشهر (1000 من 2000) فتغطي دفعته 4 من 8 حصص.
        seed: (db, group) => db
            .into(db.payments)
            .insert(
              PaymentsCompanion.insert(
                id: 'p1',
                createdAt: 1,
                updatedAt: 1,
                studentId: 's1',
                type: PaymentType.month.code,
                groupId: Value(group.id),
                cycleNumber: const Value(1),
                amount: 1000,
                receivedBy: 'u-owner',
                receiptNumber: 'A-000001',
              ),
            ),
      );
      await tester.pumpAndSettle();
      // حصصه الأربع الأولى مسدَّدة: حضرها أو غاب أو لم تُسجَّل بعد (الرابعة لم تُسجَّل).
      final paid = tester.getSemantics(find.text('سمير بن علي')).label;
      expect(paid, contains('حاضر · مدفوعة'));
      expect(paid, contains('غائب · مدفوعة'));
      expect(paid, contains('غائب برخصة · مدفوعة'));
      expect(paid, contains('لم يُسجَّل · مدفوعة'));
      expect(RegExp('مدفوعة').allMatches(paid), hasLength(4));
      expect(paid, isNot(contains('لم يدفع')));
      // نور لم تدفع: حضرت الأولى فمربعها أحمر، وبقية حصصها بلا لون ولا «مدفوعة».
      final unpaid = tester.getSemantics(find.text('نور بن علي')).label;
      expect(unpaid, contains('حاضر · لم يدفع'));
      expect(unpaid, isNot(contains('مدفوعة')));
      // مفتاح الألوان تحت الشبكة.
      expect(find.text('مربع أزرق: حصة مدفوعة'), findsOneWidget);
      expect(find.text('مربع أحمر: حضر ولم يدفع'), findsOneWidget);
      semantics.dispose();
    },
  );

  appTest(
    'الشبكة: حصة مراجعة حضرها تلميذ من الفوج عمود إضافي لا يدخل حصص الدورة',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      final semantics = tester.ensureSemantics();
      await openDetails(
        tester,
        seed: (db, group) async {
          await db
              .into(db.groups)
              .insert(
                GroupsCompanion.insert(
                  id: 'rev',
                  createdAt: 1,
                  updatedAt: 1,
                  number: 2,
                  subjectId: 'math',
                  teacherId: 't1',
                  sessionsPerCycle: const Value(1),
                  isReview: const Value(true),
                ),
              );
          await db
              .into(db.sessions)
              .insert(
                SessionsCompanion.insert(
                  id: 'rev-s',
                  createdAt: 1,
                  updatedAt: 1,
                  groupId: 'rev',
                  cycleNumber: 1,
                  sessionNumber: const Value(1),
                  date: '2026-11-12',
                  startMinutes: 600,
                  endMinutes: 780,
                ),
              );
          await db
              .into(db.sessionGuests)
              .insert(
                SessionGuestsCompanion.insert(
                  id: 'sg1',
                  createdAt: 1,
                  updatedAt: 1,
                  sessionId: 'rev-s',
                  studentId: 's1',
                ),
              );
          await db
              .into(db.attendance)
              .insert(
                AttendanceCompanion.insert(
                  id: 'a-rev',
                  createdAt: 1,
                  updatedAt: 1,
                  sessionId: 'rev-s',
                  studentId: 's1',
                  status: 'present',
                  method: 'manual',
                ),
              );
        },
      );
      await tester.pumpAndSettle();
      // عنوان العمود «م» بتسمية «حصة مراجعة»، ولسمير وحده خلية فيه.
      expect(find.text('م'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^حصة مراجعة')), findsOneWidget);
      final first = tester.getSemantics(find.text('سمير بن علي')).label;
      expect(RegExp('حاضر').allMatches(first), hasLength(2));
      final second = tester.getSemantics(find.text('نور بن علي')).label;
      expect(RegExp('حاضر').allMatches(second), hasLength(1));
      // مجموع الدورة لا يشمل المراجعة: 1 من 8 لكليهما.
      expect(find.text('1/8'), findsNWidgets(2));
      semantics.dispose();
    },
  );

  appTest('فوج بلا تلاميذ: رسالة فارغة', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    await openDetails(tester, withStudents: false);
    expect(find.text('لا تلاميذ في هذا الفوج'), findsOneWidget);
  });

  appTest('الدورة الأولى لا سابقة لها ولا لاحقة', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    await openDetails(tester);
    final prev = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
    );
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
    );
    expect(prev.onPressed, isNull);
    expect(next.onPressed, isNull);
  });

  appTest('التنقل إلى دورة سابقة وعودة إلى الحالية', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    final runtime = await openDetails(tester);
    await runDb(
      tester,
      () => runtime.db.customUpdate(
        'UPDATE groups SET current_cycle_number = 2',
        updates: {runtime.db.groups},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('الدورة 2 (الحالية)'), findsOneWidget);
    expect(find.text('لا حصص في هذه الدورة'), findsOneWidget);

    await tester.tap(find.byTooltip('الدورة السابقة'));
    await tester.pumpAndSettle();
    expect(find.text('الدورة 1'), findsOneWidget);
    expect(find.text('سمير بن علي'), findsOneWidget);

    await tester.tap(find.byTooltip('الدورة التالية'));
    await tester.pumpAndSettle();
    expect(find.text('الدورة 2 (الحالية)'), findsOneWidget);
  });

  appTest('زر التعديل يفتح نموذج الفوج', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    await openDetails(tester);
    await tester.tap(find.byTooltip('تعديل الفوج'));
    await tester.pumpAndSettle();
    expect(find.text('تعديل الفوج'), findsOneWidget);
  });

  appTest('صلاحية العرض فقط: الشبكة ظاهرة بلا زر تعديل', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    await openDetails(tester, account: viewer);
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.byTooltip('تعديل الفوج'), findsNothing);
  });
}
