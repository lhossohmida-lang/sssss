import 'package:admin/admin_tabs.dart';
import 'package:admin/screens/entrance_screen.dart';
import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'scanner_screen_test.dart' hide main;

const _owner = TestAccount(
  id: 'u-owner',
  email: 'owner@school.local',
  password: 'owner-pass-1',
  role: UserRole.owner,
  displayName: 'المدير',
);

/// يفتح شاشة المدخل من «المزيد» بعد بذر بيانات الماسح.
Future<({AppRuntime runtime, FakeQrSource usb, RecordingScanFeedback fb})>
openEntrance(
  WidgetTester tester, {
  Duration cardLifetime = const Duration(seconds: 20),
  int maxCards = 8,
}) async {
  final usb = FakeQrSource();
  final feedback = RecordingScanFeedback();
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: const [_owner],
    pages: [
      AppPage(
        path: '/entrance',
        requires: PermissionModule.scanner,
        action: PermissionAction.use,
        builder: (context, state) =>
            EntranceScreen(cardLifetime: cardLifetime, maxCards: maxCards),
      ),
    ],
    usbReader: () => usb,
    scanFeedback: feedback,
  );
  await loginWith(tester, _owner.email, _owner.password);
  await seedScannerData(tester, runtime);
  await openMoreEntry(tester, 'شاشة المدخل');
  return (runtime: runtime, usb: usb, fb: feedback);
}

Future<void> scan(WidgetTester tester, FakeQrSource usb, String code) async {
  usb.emit(code);
  await tester.pumpAndSettle();
}

void main() {
  appTest('شاشة ترحيب قبل أي مسح، والقارئ يبدأ', (tester) async {
    final env = await openEntrance(tester);
    expect(find.text('مرّر رمزك على القارئ'), findsOneWidget);
    expect(env.usb.started, isTrue);
  });

  appTest('مسح قارئ USB: بطاقة كبيرة بالاسم والحالة والمجموعة', (tester) async {
    final env = await openEntrance(tester);
    await scan(tester, env.usb, 'S-SAMIR00001');
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('حاضر'), findsOneWidget);
    expect(find.textContaining('المجموعة 1 · رياضيات'), findsOneWidget);
    expect(find.text('مرّر رمزك على القارئ'), findsNothing);
    expect(env.fb.events, ['success']);
  });

  appTest('عدة بطاقات معاً: حاضر وأحمر وأستاذ، والأحدث أولاً', (tester) async {
    final env = await openEntrance(tester);
    await scan(tester, env.usb, 'S-SAMIR00001');
    await scan(tester, env.usb, 'S-NOUR000001');
    await scan(tester, env.usb, 'T-KAMAL00001');
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('نور بن علي'), findsOneWidget);
    expect(find.text('لا حصة له الآن'), findsOneWidget);
    expect(find.text('دخول الأستاذ'), findsOneWidget);
    final newest = tester.getTopLeft(find.text('دخول الأستاذ')).dy;
    final oldest = tester.getTopLeft(find.text('حاضر')).dy;
    // عرض الهاتف عمود واحد: الأحدث في الأعلى.
    expect(newest, lessThan(oldest));
    expect(env.fb.events, ['success', 'failure', 'success']);
  });

  appTest('الرمز المجهول بطاقة حمراء', (tester) async {
    final env = await openEntrance(tester);
    await scan(tester, env.usb, 'XYZ-000');
    expect(find.text('رمز غير معروف'), findsOneWidget);
    expect(env.fb.events, ['failure']);
  });

  appTest('مسح الهاتف: بطاقة لحظة وصول سجله إلى القاعدة', (tester) async {
    final env = await openEntrance(tester);
    final db = env.runtime.db;
    await runDb(tester, () async {
      final session = (await db.select(db.sessions).get()).single;
      await db
          .into(db.attendance)
          .insert(
            AttendanceCompanion.insert(
              id: 'phone-1',
              createdAt: 1,
              updatedAt: 1,
              sessionId: session.id,
              studentId: 's1',
              status: 'present',
              scannedAt: Value(DateTime.now().millisecondsSinceEpoch),
              method: 'qr',
            ),
          );
    });
    await tester.pumpAndSettle();
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('حاضر'), findsOneWidget);
    expect(env.fb.events, ['success']);
  });

  appTest('مسح القارئ لا يظهر مرتين حين يعود سجله من القاعدة', (tester) async {
    final env = await openEntrance(tester);
    await scan(tester, env.usb, 'S-SAMIR00001');
    await tester.pumpAndSettle();
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(env.fb.events, ['success']);
  });

  appTest('سجل حضور يدوي لا يظهر في المدخل', (tester) async {
    final env = await openEntrance(tester);
    final db = env.runtime.db;
    await runDb(tester, () async {
      final session = (await db.select(db.sessions).get()).single;
      await db
          .into(db.attendance)
          .insert(
            AttendanceCompanion.insert(
              id: 'manual-1',
              createdAt: 1,
              updatedAt: 1,
              sessionId: session.id,
              studentId: 's1',
              status: 'present',
              method: 'manual',
            ),
          );
    });
    await tester.pumpAndSettle();
    expect(find.text('سمير بن علي'), findsNothing);
  });

  appTest('البطاقات لا تتجاوز الحد الأقصى', (tester) async {
    final env = await openEntrance(tester, maxCards: 2);
    await scan(tester, env.usb, 'S-SAMIR00001');
    await scan(tester, env.usb, 'S-NOUR000001');
    await scan(tester, env.usb, 'T-KAMAL00001');
    expect(find.text('سمير بن علي'), findsNothing);
    expect(find.text('نور بن علي'), findsOneWidget);
    expect(find.text('دخول الأستاذ'), findsOneWidget);
  });

  appTest('البطاقة تزول بعد مدتها', (tester) async {
    final env = await openEntrance(tester, cardLifetime: Duration.zero);
    await scan(tester, env.usb, 'S-SAMIR00001');
    expect(find.text('سمير بن علي'), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('سمير بن علي'), findsNothing);
    expect(find.text('مرّر رمزك على القارئ'), findsOneWidget);
  });

  appTest('مغادرة الشاشة تُغلق القارئ', (tester) async {
    final env = await openEntrance(tester);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(env.usb.disposed, isTrue);
  });
}
