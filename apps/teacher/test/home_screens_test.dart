import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';
import 'package:teacher/screens/home_screens.dart';
import 'package:teacher/teacher_tabs.dart';

const teacher = TestAccount(
  id: 'u-teacher',
  email: 'teacher@school.local',
  password: 'teacher-pass-1',
  role: UserRole.teacher,
  entityId: 't1',
  displayName: 'الأستاذ كمال',
);

/// يبذر مجموعتين (الأولى للأستاذ t1 والثانية لـ t2) وحصصاً اليوم، ثم يدخل.
Future<AppRuntime> openTeacher(
  WidgetTester tester, {
  bool seed = true,
  FileSource? fileSource,
  PdfPresenter? pdfPresenter,
}) async {
  final runtime = await bootApp(
    tester,
    teacherTabs,
    app: AppIdentity.teacher,
    accounts: [teacher],
    pages: teacherPages,
    fileSource: fileSource,
    pdfPresenter: pdfPresenter,
  );
  await loginWith(tester, teacher.email, teacher.password);
  if (!seed) return runtime;
  final db = runtime.db;
  await runDb(tester, () async {
    await SettingsService(
      db,
      runtime.writer,
    ).save(const SchoolSettings(schoolName: 'مدرسة النجاح'));
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
    for (final (id, name) in [('t1', 'كمال'), ('t2', 'ياسين')]) {
      await db
          .into(db.teachers)
          .insert(
            TeachersCompanion.insert(
              id: id,
              createdAt: 1,
              updatedAt: 1,
              name: name,
              phone: '066000000${id.substring(1)}',
              email: '$id@school.local',
              qrCode: 'T-$id',
            ),
          );
    }
    for (final (id, number, teacherId) in [
      ('g1', 1, 't1'),
      ('g2', 2, 't2'),
      ('g3', 3, 't1'),
    ]) {
      await db
          .into(db.groups)
          .insert(
            GroupsCompanion.insert(
              id: id,
              createdAt: 1,
              updatedAt: 1,
              number: number,
              subjectId: 'math',
              teacherId: teacherId,
            ),
          );
    }
    await db.customStatement(
      "UPDATE groups SET archived_at = 5 WHERE id = 'g3'",
    );
    final today = DateKey.of(DateTime.now());
    Future<void> session(
      String id,
      String group,
      int start, {
      bool closed = false,
      bool cancelled = false,
    }) => db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: id,
            createdAt: 1,
            updatedAt: 1,
            groupId: group,
            cycleNumber: 1,
            date: today,
            startMinutes: start,
            endMinutes: start + 90,
            status: Value(cancelled ? 'cancelled' : 'normal'),
            closedAt: Value(closed ? 5 : null),
          ),
        );
    await session('se1', 'g1', 480, closed: true);
    await session('se2', 'g1', 600, cancelled: true);
    await session('se3', 'g2', 540, closed: true);
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
              groupId: 'g1',
              studentId: id,
              joinedAt: 1,
              monthlyPrice: 2000,
            ),
          );
    }
    await db
        .into(db.attendance)
        .insert(
          AttendanceCompanion.insert(
            id: 'a1',
            createdAt: 1,
            updatedAt: 1,
            sessionId: 'se1',
            studentId: 's1',
            status: 'present',
            method: 'manual',
          ),
        );
  });
  await tester.pumpAndSettle();
  return runtime;
}

void main() {
  group('حالة الحصة', () {
    DaySession day({bool closed = false, bool cancelled = false}) => DaySession(
      session: SessionRow(
        id: 's',
        createdAt: 1,
        updatedAt: 1,
        groupId: 'g',
        cycleNumber: 1,
        date: '2026-11-14',
        startMinutes: 600,
        endMinutes: 690,
        status: cancelled ? 'cancelled' : 'normal',
        closedAt: closed ? 5 : null,
      ),
      groupNumber: 1,
      subjectName: 'م',
      teacherName: 'أ',
      students: 0,
      present: 0,
      absent: 0,
      excused: 0,
    );

    test('بحسب الوقت: لم تبدأ ثم جارية ثم انتهت', () {
      final s = day();
      expect(
        SessionPhase.of(s, DateTime(2026, 11, 14, 9, 59)),
        SessionPhase.upcoming,
      );
      expect(
        SessionPhase.of(s, DateTime(2026, 11, 14, 10)),
        SessionPhase.ongoing,
      );
      expect(
        SessionPhase.of(s, DateTime(2026, 11, 14, 11, 29)),
        SessionPhase.ongoing,
      );
      expect(
        SessionPhase.of(s, DateTime(2026, 11, 14, 11, 30)),
        SessionPhase.finished,
      );
    });

    test('المغلقة والملغاة تغلبان الوقت', () {
      final at = DateTime(2026, 11, 14, 10, 30);
      expect(SessionPhase.of(day(closed: true), at), SessionPhase.closed);
      expect(SessionPhase.of(day(cancelled: true), at), SessionPhase.cancelled);
    });
  });

  appTest('الرئيسية: حصص الأستاذ وحده بحالتها وعدّاداتها', (tester) async {
    await openTeacher(tester);
    expect(find.text('أهلاً الأستاذ كمال'), findsOneWidget);
    expect(find.textContaining('مدرسة النجاح'), findsOneWidget);
    expect(find.text('حصص اليوم'), findsOneWidget);
    // حصتا g1 فقط؛ حصة g2 لأستاذ آخر.
    expect(find.text('المجموعة 1 · رياضيات'), findsNWidgets(2));
    expect(find.text('المجموعة 2 · رياضيات'), findsNothing);
    expect(find.text('مغلقة'), findsOneWidget);
    expect(find.text('ملغاة'), findsOneWidget);
    expect(
      find.textContaining('حاضر 1 · غائب 0 · بلا تسجيل 1'),
      findsOneWidget,
    );
    expect(find.textContaining('08:00–09:30'), findsOneWidget);
  });

  appTest('الرئيسية بلا حصص: رسالة', (tester) async {
    await openTeacher(tester, seed: false);
    expect(find.text('لا حصص لك اليوم'), findsOneWidget);
  });

  appTest('مجموعاتي: المجموعات النشطة للأستاذ فقط', (tester) async {
    await openTeacher(tester);
    await tester.tap(find.text('مجموعاتي').last);
    await tester.pumpAndSettle();
    expect(find.text('المجموعة 1 · رياضيات'), findsOneWidget);
    expect(find.text('المجموعة 2 · رياضيات'), findsNothing);
    expect(find.text('المجموعة 3 · رياضيات'), findsNothing);
    expect(find.textContaining('2 تلميذ'), findsOneWidget);
  });

  appTest('مجموعاتي بلا مجموعات: رسالة', (tester) async {
    await openTeacher(tester, seed: false);
    await tester.tap(find.text('مجموعاتي').last);
    await tester.pumpAndSettle();
    expect(find.text('لا مجموعات لك بعد'), findsOneWidget);
  });

  appTest('تفاصيل المجموعة: معلوماتها وشبكة الحضور', (tester) async {
    await openTeacher(tester);
    await tester.tap(find.text('مجموعاتي').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('المجموعة 1 · رياضيات'));
    await tester.pumpAndSettle();
    expect(find.text('المجموعة 1'), findsOneWidget);
    expect(find.text('الدورة 1 (الحالية)'), findsOneWidget);
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('نور بن علي'), findsOneWidget);
  });

  appTest('النقر على حصة ملغاة من الرئيسية يفتح مجموعتها', (tester) async {
    await openTeacher(tester);
    await tester.tap(find.text('ملغاة'));
    await tester.pumpAndSettle();
    expect(find.text('الدورة 1 (الحالية)'), findsOneWidget);
  });
}
