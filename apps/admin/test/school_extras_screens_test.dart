import 'dart:io';

import 'package:admin/admin_tabs.dart';
import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter/material.dart';
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

TestAccount _worker(String permissions) => TestAccount(
  id: 'u-w',
  email: 'w@school.local',
  password: 'w-pass-1',
  role: UserRole.worker,
  entityId: 'w1',
  displayName: 'عامل',
  permissions: permissions,
);

Future<AppRuntime> boot(
  WidgetTester tester, {
  TestAccount account = _owner,
  FakeDirectorySource? directorySource,
}) async {
  tester.view.physicalSize = const Size(420, 3600);
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: [account],
    pages: adminPages,
    directorySource: directorySource,
  );
  await loginWith(tester, account.email, account.password);
  return runtime;
}

Finder field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

/// ينتظر عملية تخلط ملفاً حقيقياً بقاعدة المنطقة الوهمية: مرات من تأخير حقيقي ثم إطار.
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

void main() {
  group('اللوحة: الأساتذة والعمال', () {
    appTest('بطاقتا الأساتذة والعمال بأعدادهما وحضورهما اليوم', (tester) async {
      final runtime = await boot(tester);
      final db = runtime.db;
      final today = DateKey.of(DateTime.now());
      await runDb(tester, () async {
        for (final id in ['t1', 't2']) {
          await db
              .into(db.teachers)
              .insert(
                TeachersCompanion.insert(
                  id: id,
                  createdAt: 1,
                  updatedAt: 1,
                  name: 'أستاذ $id',
                  phone: '0660000001',
                  email: '$id@school.local',
                  qrCode: 'T-$id',
                ),
              );
        }
        for (final id in ['w1', 'w2', 'w3']) {
          await db
              .into(db.workers)
              .insert(
                WorkersCompanion.insert(
                  id: id,
                  createdAt: 1,
                  updatedAt: 1,
                  name: 'عامل $id',
                  phone: '0660000002',
                  email: '$id@school.local',
                  qrCode: 'W-$id',
                ),
              );
        }
        await db
            .into(db.teacherAttendance)
            .insert(
              TeacherAttendanceCompanion.insert(
                id: 'ta1',
                createdAt: 1,
                updatedAt: 1,
                teacherId: 't1',
                date: today,
                checkIn: const Value(100),
              ),
            );
        // عاملان حضرا: أحدهما خرج والآخر ما زال في عمله.
        await db
            .into(db.workerAttendance)
            .insert(
              WorkerAttendanceCompanion.insert(
                id: 'wa1',
                createdAt: 1,
                updatedAt: 1,
                workerId: 'w1',
                date: today,
                checkIn: const Value(100),
                checkOut: const Value(200),
              ),
            );
        await db
            .into(db.workerAttendance)
            .insert(
              WorkerAttendanceCompanion.insert(
                id: 'wa2',
                createdAt: 1,
                updatedAt: 1,
                workerId: 'w2',
                date: today,
                checkIn: const Value(100),
              ),
            );
      });
      await tester.pumpAndSettle();
      expect(find.text('الأساتذة'), findsOneWidget);
      expect(find.text('حضر اليوم 1'), findsOneWidget);
      expect(find.text('العمال'), findsOneWidget);
      expect(find.text('في العمل الآن 1 · حضر اليوم 2'), findsOneWidget);
      // الضغط على بطاقة العمال يفتح قائمتهم.
      await tester.tap(find.text('العمال'));
      await tester.pumpAndSettle();
      expect(find.text('إضافة عامل'), findsOneWidget);
    });

    appTest('عامل بلا صلاحية الأساتذة والعمال لا يرى البطاقتين', (
      tester,
    ) async {
      await boot(tester, account: _worker('{"students":["view"]}'));
      expect(find.text('الأساتذة'), findsNothing);
      expect(find.text('العمال'), findsNothing);
    });

    appTest('أفواج منتظِرة اكتمل عددها: بطاقة تحثّ على تحديد التاريخ', (
      tester,
    ) async {
      final runtime = await boot(tester);
      final db = runtime.db;
      await runDb(tester, () async {
        await db
            .into(db.subjects)
            .insert(
              SubjectsCompanion.insert(
                id: 'math',
                createdAt: 1,
                updatedAt: 1,
                name: 'رياضيات',
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
                qrCode: 'T-1',
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
                waitingTarget: const Value(1),
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
                qrCode: 'S-1',
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
      });
      await tester.pumpAndSettle();
      expect(find.text('أفواج منتظِرة'), findsOneWidget);
      expect(find.textContaining('اكتمل عددها من 1'), findsOneWidget);
    });
  });

  group('الإعدادات', () {
    Future<AppRuntime> openSettings(
      WidgetTester tester, {
      FakeDirectorySource? directory,
    }) async {
      final runtime = await boot(tester, directorySource: directory);
      await openMoreEntry(tester, 'الإعدادات');
      tester.view.physicalSize = const Size(420, 5200);
      await tester.pumpAndSettle();
      return runtime;
    }

    appTest('مدتا نصف اليوم واليوم الكامل للعمال تُعرضان وتُحفظان', (
      tester,
    ) async {
      final runtime = await openSettings(tester);
      expect(field('مدة نصف اليوم (دقيقة)').evaluate(), isNotEmpty);
      expect(
        tester
            .widget<TextField>(field('مدة نصف اليوم (دقيقة)'))
            .controller!
            .text,
        '240',
      );
      expect(
        tester
            .widget<TextField>(field('مدة اليوم الكامل (دقيقة)'))
            .controller!
            .text,
        '480',
      );
      expect(find.textContaining('= 4 ساعات'), findsOneWidget);

      await tester.enterText(field('مدة نصف اليوم (دقيقة)'), '150');
      await tester.enterText(field('مدة اليوم الكامل (دقيقة)'), '330');
      await tester.pumpAndSettle();
      expect(find.textContaining('= ساعتان و30 دقيقة'), findsOneWidget);
      await tester.tap(find.widgetWithText(ClayButton, 'حفظ الإعدادات'));
      await tester.pumpAndSettle();

      final saved = await runDb(
        tester,
        () => SettingsService(runtime.db, runtime.writer).load(),
      );
      expect(saved.workerHalfDayMinutes, 150);
      expect(saved.workerFullDayMinutes, 330);
      expect(find.text('تم حفظ الإعدادات'), findsOneWidget);
    });

    appTest('اليوم الكامل أقصر من نصفه: خطأ ولا حفظ', (tester) async {
      final runtime = await openSettings(tester);
      await tester.enterText(field('مدة نصف اليوم (دقيقة)'), '300');
      await tester.enterText(field('مدة اليوم الكامل (دقيقة)'), '200');
      await tester.tap(find.widgetWithText(ClayButton, 'حفظ الإعدادات'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('مدة اليوم الكامل أطول من مدة نصف اليوم'),
        findsOneWidget,
      );
      final saved = await runDb(
        tester,
        () => SettingsService(runtime.db, runtime.writer).load(),
      );
      expect(saved.workerFullDayMinutes, 480, reason: 'لم يُحفظ');
    });

    appTest('أرشيف سجل الحضور: اختيار المجلد وإيقافه', (tester) async {
      final dir = Directory.systemTemp.createTempSync('archive_ui_test');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final source = FakeDirectorySource(dir.path);
      final runtime = await openSettings(tester, directory: source);
      expect(
        find.text('لم يُحدَّد مجلد: الأرشفة متوقفة على هذا الجهاز'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(ClayButton, 'اختيار المجلد'));
      // الكتابة في المجلد حقيقية (تُنتظر خارج المنطقة الوهمية) وكتابة القاعدة تحتاج إطاراً.
      await settleIo(tester);
      expect(source.requests, 1);
      expect(find.text(dir.path), findsOneWidget);
      expect(
        find.text('تم ضبط المجلد؛ تُنسخ الحصص التي تنتهي من الآن'),
        findsOneWidget,
      );
      final stored = await runDb(
        tester,
        () =>
            DevicePreferences(runtime.db)
                .read(AttendanceArchiveService.folderKey),
      );
      expect(stored, dir.path);

      await tester.tap(find.widgetWithText(ClayButton, 'إيقاف الأرشفة'));
      await tester.pumpAndSettle();
      expect(find.text('أُوقفت الأرشفة'), findsOneWidget);
      expect(
        await runDb(
          tester,
          () =>
              DevicePreferences(runtime.db)
                  .read(AttendanceArchiveService.folderKey),
        ),
        isNull,
      );
    });

    appTest('الطور «أخرى» لدورات ومواد بلا سنة دراسية', (tester) async {
      await openSettings(tester);
      expect(find.text('أخرى (دورات ومواد خاصة)'), findsOneWidget);
      expect(
        find.textContaining('لا ترتبط بسنة دراسية ولا بعمر'),
        findsOneWidget,
      );
    });
  });

  group('مركز الرسائل: أنواع الرسائل', () {
    appTest('إيقاف نوع وتفعيله من تبويب الأنواع', (tester) async {
      final runtime = await boot(tester);
      await openMoreEntry(tester, 'الرسائل القصيرة');
      await tester.tap(find.text('الأنواع'));
      await tester.pumpAndSettle();
      expect(find.textContaining('أوقف أي نوع من الرسائل'), findsOneWidget);

      Finder toggleOf(String title) => find.descendant(
        of: find.ancestor(
          of: find.text(title),
          matching: find.byType(ClayListTile),
        ),
        matching: find.byType(ClayToggle),
      );
      expect(tester.widget<ClayToggle>(toggleOf('وصل الدفع')).value, isTrue);
      await tester.tap(toggleOf('وصل الدفع'));
      await tester.pumpAndSettle();
      expect(
        await runDb(
          tester,
          () => SmsKindPolicy(runtime.db, runtime.writer).disabled(),
        ),
        {SmsTemplateKeys.paymentReceipt},
      );
      expect(find.text('موقوف: لا تُرسل رسائل هذا النوع'), findsOneWidget);
      expect(tester.widget<ClayToggle>(toggleOf('وصل الدفع')).value, isFalse);

      await tester.tap(toggleOf('وصل الدفع'));
      await tester.pumpAndSettle();
      expect(
        await runDb(
          tester,
          () => SmsKindPolicy(runtime.db, runtime.writer).disabled(),
        ),
        isEmpty,
      );
    });

    appTest('القالب الجديد لاكتمال فوج منتظِر في قائمة الأنواع', (
      tester,
    ) async {
      await boot(tester);
      await openMoreEntry(tester, 'الرسائل القصيرة');
      await tester.tap(find.text('الأنواع'));
      await tester.pumpAndSettle();
      expect(find.text('اكتمال فوج منتظِر (إلى هاتف المدير)'), findsOneWidget);
      expect(
        find.text('تحديد موعد فوج منتظِر (إلى أولياء تلاميذه)'),
        findsOneWidget,
      );
    });
  });
}
