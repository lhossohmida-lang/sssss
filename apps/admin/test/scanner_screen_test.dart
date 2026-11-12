import 'package:admin/admin_tabs.dart';
import 'package:admin/screens/scanner_screen.dart';
import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

const _owner = TestAccount(
  id: 'u-owner',
  email: 'owner@school.local',
  password: 'owner-pass-1',
  role: UserRole.owner,
  displayName: 'المدير',
);

const _noScanner = TestAccount(
  id: 'u-noscan',
  email: 'noscan@school.local',
  password: 'noscan-pass-1',
  role: UserRole.worker,
  entityId: 'w9',
  displayName: 'عامل',
  permissions: '{"students":["view"]}',
);

/// يفتح الماسح من «المزيد» بعد بذر بياناته.
/// يبذر مجموعة بحصة جارية الآن وتلميذين (أحدهما منتسب) وأستاذاً.
Future<void> seedScannerData(WidgetTester tester, AppRuntime runtime) async {
  final db = runtime.db;
  await runDb(tester, () async {
    final now = DateTime.now();
    final start = (DateKey.minutesOf(now) - 5).clamp(0, 1430);
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
            qrCode: 'T-KAMAL00001',
          ),
        );
    await db
        .into(db.groups)
        .insert(
          GroupsCompanion.insert(
            id: 'g1',
            createdAt: 1,
            updatedAt: 1,
            number: 1,
            subjectId: 'math',
            teacherId: 't1',
          ),
        );
    await db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: 'se1',
            createdAt: 1,
            updatedAt: 1,
            groupId: 'g1',
            cycleNumber: 1,
            date: DateKey.of(now),
            startMinutes: start,
            endMinutes: (start + 90).clamp(0, 1439),
            sessionNumber: const Value(1),
          ),
        );
    await db
        .into(db.students)
        .insert(
          StudentsCompanion.insert(
            id: 's1',
            createdAt: 1,
            updatedAt: 1,
            firstName: 'سمير',
            lastName: 'بن علي',
            parentPhone: '0550123456',
            qrCode: 'S-SAMIR00001',
          ),
        );
    await db
        .into(db.groupStudents)
        .insert(
          GroupStudentsCompanion.insert(
            id: 'gs1',
            createdAt: 1,
            updatedAt: 1,
            groupId: 'g1',
            studentId: 's1',
            joinedAt: 1,
            monthlyPrice: 2000,
          ),
        );
    await db
        .into(db.students)
        .insert(
          StudentsCompanion.insert(
            id: 's2',
            createdAt: 1,
            updatedAt: 1,
            firstName: 'نور',
            lastName: 'بن علي',
            parentPhone: '0550123457',
            qrCode: 'S-NOUR000001',
          ),
        );
  });
}

Future<({AppRuntime runtime, FakeQrSource? source, RecordingScanFeedback fb})>
openScanner(
  WidgetTester tester, {
  bool camera = true,
  TestAccount account = _owner,
  Duration indexRefresh = const Duration(seconds: 10),
}) async {
  final source = camera ? FakeQrSource() : null;
  final feedback = RecordingScanFeedback();
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: [account],
    pages: [
      AppPage(
        path: '/scanner',
        requires: PermissionModule.scanner,
        action: PermissionAction.use,
        builder: (context, state) =>
            ScannerScreen(indexRefreshAfter: indexRefresh),
      ),
    ],
    qrCamera: source == null ? null : () => source,
    scanFeedback: feedback,
  );
  await loginWith(tester, account.email, account.password);
  await seedScannerData(tester, runtime);
  await tester.tap(find.text('المزيد').last);
  await tester.pumpAndSettle();
  final entry = find.text('الماسح');
  if (entry.evaluate().isNotEmpty) {
    await tester.tap(entry);
    await tester.pumpAndSettle();
  }
  return (runtime: runtime, source: source, fb: feedback);
}

/// يمسح [code] ويدع المعالجة تكتمل.
Future<void> scan(WidgetTester tester, FakeQrSource source, String code) async {
  source.emit(code);
  await tester.pumpAndSettle();
}

void main() {
  appTest('بلا كاميرا: رسالة بدل المعاينة', (tester) async {
    await openScanner(tester, camera: false);
    expect(find.text('الكاميرا غير متاحة على هذا الجهاز'), findsOneWidget);
  });

  appTest('الكاميرا تبدأ عند فتح الشاشة وتُغلق عند مغادرتها', (tester) async {
    final env = await openScanner(tester);
    expect(env.source!.started, isTrue);
    expect(find.text('وجّه الكاميرا نحو الرمز'), findsOneWidget);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(env.source!.disposed, isTrue);
  });

  appTest('تلميذ منتسب: حاضر أخضر بمجموعته، ويُسجَّل حضوره بمسح الرمز', (
    tester,
  ) async {
    final env = await openScanner(tester);
    await scan(tester, env.source!, 'S-SAMIR00001');
    expect(find.text('سمير بن علي'), findsWidgets);
    expect(find.text('حاضر'), findsNWidgets(2));
    expect(find.textContaining('المجموعة 1 · رياضيات'), findsOneWidget);
    expect(env.fb.events, ['success']);
    final rows = await runDb(
      tester,
      () => env.runtime.db.select(env.runtime.db.attendance).get(),
    );
    expect(rows.single.status, 'present');
    expect(rows.single.method, 'qr');
  });

  appTest('تلميذ بلا حصة الآن: أحمر ولا يُسجَّل شيء', (tester) async {
    final env = await openScanner(tester);
    await scan(tester, env.source!, 'S-NOUR000001');
    expect(find.text('لا حصة له الآن'), findsNWidgets(2));
    expect(env.fb.events, ['failure']);
    final rows = await runDb(
      tester,
      () => env.runtime.db.select(env.runtime.db.attendance).get(),
    );
    expect(rows, isEmpty);
  });

  appTest('رمز مجهول: أحمر برسالة', (tester) async {
    final env = await openScanner(tester);
    await scan(tester, env.source!, 'https://example.com/x');
    // في لوحة النتيجة وفي السجل.
    expect(find.text('رمز غير معروف'), findsNWidgets(2));
    expect(env.fb.events, ['failure']);
  });

  appTest('القراءة المزدوجة لنفس الرمز لا تُعرض مرتين', (tester) async {
    final env = await openScanner(tester);
    await scan(tester, env.source!, 'S-SAMIR00001');
    await scan(tester, env.source!, 'S-SAMIR00001');
    expect(env.fb.events, ['success']);
    // صف واحد في السجل: اسمه في اللوحة والسجل فقط.
    expect(find.text('سمير بن علي'), findsNWidgets(2));
  });

  appTest('الأستاذ: دخول لحصته بتأخره', (tester) async {
    final env = await openScanner(tester);
    await scan(tester, env.source!, 'T-KAMAL00001');
    expect(find.text('دخول الأستاذ'), findsNWidgets(2));
    expect(find.textContaining('المجموعة 1'), findsOneWidget);
    expect(env.fb.events, ['success']);
  });

  appTest('عدة رموز متتابعة تُسجَّل في السجل الأحدث أولاً', (tester) async {
    final env = await openScanner(tester);
    await scan(tester, env.source!, 'S-NOUR000001');
    await scan(tester, env.source!, 'S-SAMIR00001');
    // آخر نتيجة في اللوحة والسجل، والسابقة في السجل وحده.
    expect(find.text('نور بن علي'), findsOneWidget);
    expect(find.text('سمير بن علي'), findsNWidgets(2));
    final firstTile = tester.getTopLeft(find.text('سمير بن علي').last).dy;
    final secondTile = tester.getTopLeft(find.text('نور بن علي').last).dy;
    expect(firstTile, lessThan(secondTile), reason: 'الأحدث أولاً');
  });

  appTest('تلميذ سُجّل بعد فتح الشاشة: يُحدَّث الفهرس ويُقبل رمزه', (
    tester,
  ) async {
    final env = await openScanner(tester, indexRefresh: Duration.zero);
    final db = env.runtime.db;
    await runDb(tester, () async {
      await db
          .into(db.students)
          .insert(
            StudentsCompanion.insert(
              id: 's3',
              createdAt: 1,
              updatedAt: 1,
              firstName: 'ياسمين',
              lastName: 'حداد',
              parentPhone: '0550123458',
              qrCode: 'S-YASMIN0001',
            ),
          );
    });
    await scan(tester, env.source!, 'S-YASMIN0001');
    // معروف الآن (بلا حصة)، لا «غير معروف».
    expect(find.text('رمز غير معروف'), findsNothing);
    expect(find.text('لا حصة له الآن'), findsNWidgets(2));
  });

  appTest('من لا يملك صلاحية الماسح لا يرى القسم', (tester) async {
    await openScanner(tester, account: _noScanner);
    expect(find.text('الماسح'), findsNothing);
  });
}
