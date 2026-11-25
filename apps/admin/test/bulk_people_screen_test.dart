import 'dart:convert';

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

class Opened {
  Opened(this.runtime, this.provisioner, this.presenter);

  final AppRuntime runtime;
  final FakeAccountProvisioner provisioner;
  final FakePdfPresenter presenter;
}

Future<Opened> boot(WidgetTester tester) async {
  final provisioner = FakeAccountProvisioner();
  final presenter = FakePdfPresenter();
  final runtime = await bootApp(
    tester,
    adminTabs,
    app: AppIdentity.admin,
    accounts: [_owner],
    pages: adminPages,
    provisioner: provisioner,
    pdfPresenter: presenter,
  );
  await loginWith(tester, _owner.email, _owner.password);
  // شاشة طويلة حتى تظهر كل الأزرار والصفوف.
  tester.view.physicalSize = const Size(900, 2400);
  await tester.pumpAndSettle();
  return Opened(runtime, provisioner, presenter);
}

/// ثلاثة أساتذة بحساباتهم ثم صفحة التحديد من قائمة الأساتذة.
Future<Opened> openTeachers(WidgetTester tester) async {
  final o = await boot(tester);
  final service = TeacherService(
    o.runtime.db,
    o.runtime.writer,
    AccountService(o.runtime.db, o.runtime.writer, o.provisioner),
  );
  await runDb(tester, () async {
    for (final (name, phone) in [
      ('أمين', '0550000001'),
      ('بلال', '0550000002'),
      ('جمال', '0550000003'),
    ]) {
      await service.add(
        name: name,
        phone: phone,
        subjectIds: const {},
        ratePerStudent: 500,
      );
    }
  });
  await openMoreEntry(tester, 'الأساتذة');
  await tester.tap(find.byTooltip('تحديد للطباعة والرسائل'));
  await tester.pumpAndSettle();
  return o;
}

/// ينتظر عملاً يجري في الزمن الحقيقي (قراءة الخط وبناء PDF وطلبات الحسابات).
Future<void> waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 60 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

int pageCount(List<int> pdf) =>
    RegExp(r'/Type\s*/Page\b')
        .allMatches(latin1.decode(pdf, allowInvalid: true))
        .length;

void main() {
  appTest('الأساتذة: تحديد الكل ثم طباعة بطاقاتهم في ورقة واحدة', (
    tester,
  ) async {
    final o = await openTeachers(tester);
    expect(find.text('تحديد الأساتذة'), findsOneWidget);
    expect(find.text('المعروض 3 · المحدَّد 0'), findsOneWidget);
    await tester.tap(find.text('تحديد الكل'));
    await tester.pumpAndSettle();
    expect(find.text('المعروض 3 · المحدَّد 3'), findsOneWidget);
    await tester.tap(find.text('طباعة البطاقات'));
    await waitFor(tester, () => o.presenter.shown.isNotEmpty);
    final shown = o.presenter.shown.single;
    expect(shown.title, 'بطاقات الأساتذة (3)');
    expect(shown.fileName, 'cards-teacher-3.pdf');
    expect(pageCount(shown.bytes), 1);
  });

  appTest('تحديد واحد بالنقر وتحديد عدد من أول القائمة', (tester) async {
    await openTeachers(tester);
    await tester.tap(find.text('بلال'));
    await tester.pumpAndSettle();
    expect(find.text('المعروض 3 · المحدَّد 1'), findsOneWidget);
    await tester.tap(find.text('تحديد عدد'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(ClayDialog),
        matching: find.byType(TextField),
      ),
      '2',
    );
    await tester.tap(find.widgetWithText(ClayButton, 'تحديد'));
    await tester.pumpAndSettle();
    expect(find.text('المعروض 3 · المحدَّد 2'), findsOneWidget);
    expect(find.text('رسالة'), findsOneWidget);
  });

  appTest('إرسال بيانات الدخول: كلمة سر جديدة ورسالة لكل أستاذ محدَّد', (
    tester,
  ) async {
    final o = await openTeachers(tester);
    await tester.tap(find.text('تحديد الكل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بيانات الدخول'));
    await tester.pumpAndSettle();
    expect(find.textContaining('كلمات السر القديمة لن تعمل'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'توليد وإرسال'));
    await waitFor(tester, () => o.provisioner.resets.length == 3);
    expect(find.text('بيانات الدخول الجديدة (3)'), findsOneWidget);
    expect(find.textContaining('وُضعت 3 رسالة'), findsOneWidget);
    expect(o.provisioner.resets, hasLength(3));
    final resets = await runDb(
      tester,
      () => (o.runtime.db.select(
        o.runtime.db.smsQueue,
      )..where((q) => q.kind.equals(SmsTemplateKeys.passwordReset))).get(),
    );
    expect(resets, hasLength(3));
    for (final password in o.provisioner.resets.values) {
      expect(find.textContaining(password), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(ClayButton, 'تم'));
    await tester.pumpAndSettle();
    expect(find.text('المعروض 3 · المحدَّد 0'), findsOneWidget);
  });

  appTest('رسالة مكتوبة واحدة لكل المحدَّدين', (tester) async {
    final o = await openTeachers(tester);
    await tester.tap(find.text('تحديد الكل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('رسالة'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(ClayDialog),
        matching: find.byType(TextField),
      ),
      'اجتماع الأساتذة غداً يا {name}',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(ClayButton, 'إضافة إلى طابور الرسائل'),
    );
    await tester.pumpAndSettle();
    final queued = await runDb(
      tester,
      () => (o.runtime.db.select(
        o.runtime.db.smsQueue,
      )..where((q) => q.kind.equals(SmsTemplateKeys.broadcast))).get(),
    );
    expect(queued, hasLength(3));
    expect(
      queued.map((q) => q.message),
      contains('اجتماع الأساتذة غداً يا أمين'),
    );
  });

  appTest('العمال: 12 عاملاً تأخذ بطاقاتهم ورقتين (10 في الورقة)', (
    tester,
  ) async {
    final o = await boot(tester);
    await runDb(tester, () async {
      for (var i = 0; i < 12; i++) {
        await o.runtime.db
            .into(o.runtime.db.workers)
            .insert(
              WorkersCompanion.insert(
                id: 'w$i',
                createdAt: 1,
                updatedAt: 1,
                name: 'عامل ${i.toString().padLeft(2, '0')}',
                phone: '066000000${i % 10}',
                email: 'w$i@school.local',
                qrCode: 'W-AAAAAAAA${i.toString().padLeft(2, '0')}',
              ),
            );
      }
    });
    await openMoreEntry(tester, 'العمال');
    await tester.tap(find.byTooltip('تحديد للطباعة والرسائل'));
    await tester.pumpAndSettle();
    expect(find.text('تحديد العمال'), findsOneWidget);
    await tester.tap(find.text('تحديد الكل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('طباعة البطاقات'));
    await waitFor(tester, () => o.presenter.shown.isNotEmpty);
    expect(pageCount(o.presenter.shown.single.bytes), 2);
    // لا حسابات لهؤلاء العمال: الإرسال يُرفض برسالة.
    await tester.tap(find.text('بيانات الدخول'));
    await tester.pumpAndSettle();
    expect(find.text('لا حساب دخول بين المحدَّدين'), findsOneWidget);
  });

  appTest('التلاميذ: الإخوة بحساب وليّ واحد يأخذون رسالة دخول واحدة', (
    tester,
  ) async {
    final o = await boot(tester);
    final db = o.runtime.db;
    await runDb(tester, () async {
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
            ),
          );
      final dues = DuesService(db, o.runtime.writer);
      final registration = RegistrationService(
        db,
        o.runtime.writer,
        accounts: AccountService(db, o.runtime.writer, o.provisioner),
        enrolments: EnrolmentService(
          db,
          o.runtime.writer,
          dues,
          CycleService(db, o.runtime.writer),
        ),
        dues: dues,
      );
      for (final first in ['أحمد', 'سارة']) {
        await registration.register(
          RegistrationRequest(
            firstName: first,
            lastName: 'بن علي',
            parentName: 'علي بن علي',
            parentPhone: '0550123456',
            date: '2026-11-10',
            choices: const [
              SubjectChoice(
                subjectId: 'math',
                groupId: 'g1',
                monthlyPrice: 2000,
              ),
            ],
          ),
          settings: const SchoolSettings(),
        );
      }
    });
    await tester.tap(find.text('التلاميذ').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تحديد وطباعة'));
    await tester.pumpAndSettle();
    expect(find.text('تحديد التلاميذ'), findsOneWidget);
    await tester.tap(find.text('تحديد الكل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('طباعة البطاقات'));
    await waitFor(tester, () => o.presenter.shown.isNotEmpty);
    expect(o.presenter.shown.single.title, 'بطاقات التلاميذ (2)');
    expect(pageCount(o.presenter.shown.single.bytes), 1);

    await tester.tap(find.text('بيانات الدخول'));
    await tester.pumpAndSettle();
    expect(find.textContaining('لـ 1 وليّ'), findsOneWidget);
    await tester.tap(find.widgetWithText(ClayButton, 'توليد وإرسال'));
    await waitFor(tester, () => o.provisioner.resets.isNotEmpty);
    expect(o.provisioner.resets, hasLength(1));
    expect(find.text('بيانات الدخول الجديدة (1)'), findsOneWidget);
  });
}
