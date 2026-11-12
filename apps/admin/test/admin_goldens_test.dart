import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;
import 'payments_screens_test.dart' hide main;
import 'support/golden_support.dart';

/// لقطات golden لشاشات الإدارة الأساسية بمحتوى ثابت (بلا تواريخ اليوم)، على
/// حجم الهاتف وعلى حجم Windows (قائمة جانبية). تُقارَن بتسامح يعتمد المنصة.
void main() {
  setUpAll(setUpGoldens);

  void size(WidgetTester tester, double w, double h, Brightness b) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = b;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  appTest('التلاميذ: هاتف فاتح', (tester) async {
    size(tester, 420, 900, Brightness.light);
    await openPayments(tester);
    await tester.tap(find.text('التلاميذ').last);
    await tester.pumpAndSettle();
    await shoot(tester, 'students_phone_light');
  });

  appTest('المستحقات: هاتف داكن', (tester) async {
    size(tester, 420, 900, Brightness.dark);
    await openPayments(tester);
    await openMoreEntry(tester, 'المستحقات');
    await shoot(tester, 'dues_phone_dark');
  });

  appTest('الجدول الأسبوعي: Windows فاتح', (tester) async {
    size(tester, 1280, 900, Brightness.light);
    final runtime = await openGroups(tester);
    final db = runtime.db;
    await runDb(tester, () async {
      final service = GroupService(
        db,
        runtime.writer,
        ScheduleService(db),
        CycleService(db, runtime.writer),
      );
      await service.create(
        subjectId: 'math',
        teacherId: 't1',
        roomId: 'r1',
        slots: const [
          GroupSlotInput(weekday: 6, startMinutes: 600, endMinutes: 690),
          GroupSlotInput(weekday: 2, startMinutes: 960, endMinutes: 1050),
        ],
        startDate: '2026-11-07',
      );
    });
    await openMoreEntry(tester, 'الجدول الأسبوعي');
    await shoot(tester, 'schedule_windows_light');
  });

  appTest('تفاصيل المجموعة وشبكة الحضور: Windows فاتح', (tester) async {
    size(tester, 1280, 900, Brightness.light);
    final runtime = await openPayments(tester);
    final group = await runDb(
      tester,
      () => runtime.db.select(runtime.db.groups).getSingle(),
    );
    await tester.tap(find.text('المجموعات').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('المجموعة ${group.number} · رياضيات'));
    await shoot(tester, 'group_details_windows_light');
  });

  appTest('المزيد: Windows داكن', (tester) async {
    size(tester, 1280, 900, Brightness.dark);
    await openPayments(tester);
    await tester.tap(find.text('المزيد').last);
    await shoot(tester, 'more_windows_dark');
  });
}
