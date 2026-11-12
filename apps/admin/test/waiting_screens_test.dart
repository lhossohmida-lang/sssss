import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;

const waitingViewer = TestAccount(
  id: 'u-wviewer',
  email: 'wviewer@school.local',
  password: 'wviewer-pass-1',
  role: UserRole.worker,
  entityId: 'w3',
  displayName: 'عامل عرض',
  permissions: '{"waiting":["view"]}',
);

/// يبذر [count] تلاميذ في قائمة انتظار الرياضيات ثم يفتح «قوائم الانتظار».
Future<AppRuntime> openWaiting(
  WidgetTester tester, {
  int count = 2,
  TestAccount account = owner,
}) async {
  tester.view.physicalSize = const Size(900, 2200);
  final runtime = await openGroups(tester, account: account);
  final db = runtime.db;
  await runDb(tester, () async {
    final enrolments = EnrolmentService(
      db,
      runtime.writer,
      DuesService(db, runtime.writer),
      CycleService(db, runtime.writer),
    );
    final names = ['سمير', 'نور', 'ياسمين'];
    for (var i = 0; i < count; i++) {
      await db
          .into(db.students)
          .insert(
            StudentsCompanion.insert(
              id: 's$i',
              createdAt: 1,
              updatedAt: 1,
              firstName: names[i],
              lastName: 'بن علي',
              parentPhone: '055012345$i',
              qrCode: 'S-s$i',
            ),
          );
      await enrolments.addToWaiting(
        studentId: 's$i',
        subjectId: 'math',
        preferredTeacherId: 't1',
      );
    }
  });
  await tester.tap(find.text('المزيد').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('قوائم الانتظار'));
  await tester.pumpAndSettle();
  return runtime;
}

Future<void> openDetails(WidgetTester tester) async {
  await tester.tap(find.text('رياضيات'));
  await tester.pumpAndSettle();
}

Finder thresholdField() => find.descendant(
  of: find
      .ancestor(of: find.text('حد التنبيه'), matching: find.byType(Column))
      .first,
  matching: find.byType(TextField),
);

void main() {
  appTest('لا أحد في الانتظار: رسالة فارغة', (tester) async {
    await openWaiting(tester, count: 0);
    expect(find.text('لا أحد في الانتظار'), findsOneWidget);
  });

  appTest('القائمة بعدد منتظريها وحدّها وأستاذها المفضّل', (tester) async {
    await openWaiting(tester);
    expect(find.text('رياضيات'), findsOneWidget);
    expect(find.textContaining('2 منتظر · الحد 10'), findsOneWidget);
    expect(find.textContaining('الأستاذ كمال'), findsOneWidget);
    expect(find.text('بلغ الحد'), findsNothing);
  });

  appTest('التفاصيل: المنتظرون بالأقدم أولاً بهواتفهم', (tester) async {
    await openWaiting(tester);
    await openDetails(tester);
    expect(find.text('قائمة الانتظار'), findsOneWidget);
    expect(find.text('2 منتظر من أصل حد 10'), findsOneWidget);
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('نور بن علي'), findsOneWidget);
    expect(find.textContaining('0550123450'), findsOneWidget);
    expect(find.textContaining('الأستاذ المفضّل: كمال'), findsOneWidget);
  });

  appTest('ضبط الحد: بلوغه يُظهر الشارة وينبّه المالك', (tester) async {
    final runtime = await openWaiting(tester);
    await openDetails(tester);
    await tester.enterText(thresholdField(), '2');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ الحد'));
    await tester.pumpAndSettle();
    expect(find.text('بلغ الحد'), findsOneWidget);
    final notes = await runDb(
      tester,
      () => runtime.db.select(runtime.db.notifications).get(),
    );
    expect(notes.where((n) => n.kind == 'waiting_threshold'), hasLength(1));
  });

  appTest('حد غير صالح: رسالة خطأ ولا تغيير', (tester) async {
    await openWaiting(tester);
    await openDetails(tester);
    await tester.enterText(thresholdField(), '0');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ الحد'));
    await tester.pumpAndSettle();
    expect(find.text('الحد بين 1 و500'), findsOneWidget);
    expect(find.text('2 منتظر من أصل حد 10'), findsOneWidget);

    await tester.enterText(thresholdField(), '');
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ الحد'));
    await tester.pumpAndSettle();
    expect(find.text('أدخل رقماً صحيحاً'), findsOneWidget);
  });

  appTest('إخراج منتظر بعد التأكيد', (tester) async {
    await openWaiting(tester);
    await openDetails(tester);
    await tester.tap(find.byTooltip('إخراج سمير بن علي من الانتظار'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'إخراج'));
    await tester.pumpAndSettle();
    expect(find.text('سمير بن علي'), findsNothing);
    expect(find.text('1 منتظر من أصل حد 10'), findsOneWidget);
  });

  appTest('إخراج آخر منتظر يفرغ القائمة', (tester) async {
    await openWaiting(tester, count: 1);
    await openDetails(tester);
    await tester.tap(find.byTooltip('إخراج سمير بن علي من الانتظار'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'إخراج'));
    await tester.pumpAndSettle();
    expect(find.text('لا منتظرين في هذه القائمة'), findsOneWidget);
  });

  appTest('«إنشاء مجموعة» تفتح النموذج بالمادة والأستاذ ونصيبه', (
    tester,
  ) async {
    await openWaiting(tester);
    await openDetails(tester);
    await tester.tap(find.widgetWithText(ClayButton, 'إنشاء مجموعة'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(420, 3200);
    await tester.pumpAndSettle();
    expect(find.text('إنشاء مجموعة'), findsWidgets);
    expect(find.text('رياضيات'), findsOneWidget);
    expect(find.text('كمال'), findsOneWidget);
    final rate = tester
        .widget<TextField>(
          find.descendant(
            of: find
                .ancestor(
                  of: find.text('نصيب الأستاذ لكل تلميذ (دج)'),
                  matching: find.byType(Column),
                )
                .first,
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;
    expect(rate, '800');
  });

  appTest('النقر على منتظر يفتح ملفه', (tester) async {
    await openWaiting(tester);
    await openDetails(tester);
    await tester.tap(find.text('نور بن علي'));
    await tester.pumpAndSettle();
    expect(find.text('قائمة الانتظار'), findsNothing);
    expect(find.textContaining('نور'), findsWidgets);
  });

  appTest('صلاحية العرض فقط: بلا حد ولا إخراج ولا إنشاء مجموعة', (
    tester,
  ) async {
    await openWaiting(tester, account: waitingViewer);
    await openDetails(tester);
    expect(find.text('سمير بن علي'), findsOneWidget);
    expect(find.text('حد التنبيه'), findsNothing);
    expect(find.byIcon(ClayIcons.close), findsNothing);
    expect(find.widgetWithText(ClayButton, 'إنشاء مجموعة'), findsNothing);
  });
}
