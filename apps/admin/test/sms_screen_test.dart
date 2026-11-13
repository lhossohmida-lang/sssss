import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';
import 'package:school_sms/school_sms.dart';
import 'package:school_ui/school_ui.dart';
import 'package:school_ui/testing.dart';

import 'groups_screens_test.dart' hide main;

const smsViewer = TestAccount(
  id: 'u-sms-viewer',
  email: 'sms-viewer@school.local',
  password: 'sms-viewer-pass-1',
  role: UserRole.worker,
  entityId: 'w-sms',
  displayName: 'عامل الرسائل',
  permissions: '{"sms":["view"]}',
);

void main() {
  appTest('مركز الرسائل يعرض الطابور ويجهز رسالة واحدة لكل وليّ', (
    tester,
  ) async {
    final runtime = await openGroups(tester);
    await runDb(tester, () async {
      await runtime.db.batch((batch) {
        batch.insertAll(runtime.db.students, [
          _student('s1', 'سمير', 'بن علي', '0550123456'),
          _student('s2', 'نور', 'بن علي', '+213550123456'),
        ]);
      });
      await SmsQueueService(
        runtime.db,
        runtime.writer,
      ).enqueue(phone: '0550123457', message: 'تنبيه اختباري');
    });

    await openMoreEntry(tester, 'الرسائل القصيرة');
    expect(find.text('مركز الرسائل القصيرة'), findsOneWidget);
    expect(find.text('تنبيه اختباري'), findsOneWidget);

    await tester.tap(find.text('رسالة جماعية'));
    await tester.pumpAndSettle();
    expect(
      find.text('1 مستلم برقم صالح · 0 رقم غير صالح سيُتجاهل'),
      findsOneWidget,
    );
    await tester.tap(
      find.widgetWithText(ClayButton, 'إضافة الرسائل إلى الطابور'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'إضافة إلى الطابور'));
    await tester.pumpAndSettle();

    final queued = await runDb(
      tester,
      () => runtime.db.select(runtime.db.smsQueue).get(),
    );
    expect(queued, hasLength(2));
    expect(
      queued.any((row) => row.message.contains('سمير بن علي، نور بن علي')),
      isTrue,
    );

    await tester.tap(find.text('القوالب'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      '{school}: أهلاً {name}',
    );
    await tester.tap(find.widgetWithText(ClayButton, 'حفظ القالب'));
    await tester.pumpAndSettle();
    var broadcastTemplate = await runDb(
      tester,
      () => (runtime.db.select(
        runtime.db.smsTemplates,
      )..where((row) => row.key.equals(SmsTemplateKeys.broadcast))).getSingle(),
    );
    expect(broadcastTemplate.body, '{school}: أهلاً {name}');

    await tester.tap(find.widgetWithText(ClayButton, 'استعادة الافتراضي'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ClayButton, 'استعادة'));
    await tester.pumpAndSettle();
    broadcastTemplate = await runDb(
      tester,
      () => (runtime.db.select(
        runtime.db.smsTemplates,
      )..where((row) => row.key.equals(SmsTemplateKeys.broadcast))).getSingle(),
    );
    expect(
      broadcastTemplate.body,
      SmsTemplateKeys.defaults[SmsTemplateKeys.broadcast],
    );
  });

  appTest('عامل العرض يرى الطابور فقط ولا تظهر له أدوات الإرسال', (
    tester,
  ) async {
    await openGroups(tester, account: smsViewer);
    await openMoreEntry(tester, 'الرسائل القصيرة');
    expect(find.text('الطابور'), findsOneWidget);
    expect(find.text('رسالة جماعية'), findsNothing);
    expect(find.text('القوالب'), findsNothing);
  });
}

StudentsCompanion _student(
  String id,
  String firstName,
  String lastName,
  String phone,
) => StudentsCompanion.insert(
  id: id,
  createdAt: 1,
  updatedAt: 1,
  firstName: firstName,
  lastName: lastName,
  parentPhone: phone,
  qrCode: 'QR-$id',
);
