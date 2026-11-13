import 'package:drift/drift.dart';
import 'package:school_core/school_core.dart';

import 'sms_queue_service.dart';
import 'sms_template_service.dart';

/// فئة المستلمين للرسالة الجماعية.
enum SmsBroadcastAudience {
  parents('أولياء التلاميذ'),
  teachers('الأساتذة'),
  workers('العمال');

  const SmsBroadcastAudience(this.label);

  final String label;
}

/// مستلم واحد بعد توحيد الأرقام وتجميع أفراد الأسرة على هاتف الوليّ.
class SmsBroadcastRecipient {
  const SmsBroadcastRecipient({required this.phone, required this.name});

  final String phone;
  final String name;
}

/// نتيجة فحص الجمهور قبل إضافة الرسائل إلى الطابور.
class SmsBroadcastPreview {
  const SmsBroadcastPreview({
    required this.audience,
    required this.recipients,
    required this.invalidContacts,
  });

  final SmsBroadcastAudience audience;
  final List<SmsBroadcastRecipient> recipients;
  final int invalidContacts;
}

/// ملخص إضافة دفعة رسائل إلى الطابور المحلي.
class SmsBroadcastResult {
  const SmsBroadcastResult({
    required this.audience,
    required this.queued,
    required this.invalidContacts,
    required this.failed,
  });

  final SmsBroadcastAudience audience;
  final int queued;
  final int invalidContacts;
  final int failed;
}

/// يجمع الجمهور ويرندر القالب ويضيف رسالة منفصلة لكل هاتف إلى الطابور.
///
/// لا يرسل الرسائل بنفسه؛ الإرسال يخضع لسياسة الطابور ومشغّل Android.
class SmsBroadcastService {
  SmsBroadcastService(this.db, this.queue, this.templates);

  final AppDatabase db;
  final SmsQueueService queue;
  final SmsTemplateService templates;

  Future<SmsBroadcastPreview> preview(SmsBroadcastAudience audience) async {
    final recipients = <String, _RecipientBuilder>{};
    var invalidContacts = 0;

    void add(String rawPhone, String name) {
      if (!PhoneNumbers.isValid(rawPhone)) {
        invalidContacts++;
        return;
      }
      final phone = PhoneNumbers.toInternational(rawPhone);
      final recipient = recipients.putIfAbsent(
        phone,
        () => _RecipientBuilder(phone),
      );
      recipient.addName(name);
    }

    switch (audience) {
      case SmsBroadcastAudience.parents:
        final students =
            await (db.select(db.students)
                  ..where((row) => row.deletedAt.isNull())
                  ..orderBy([
                    (row) => OrderingTerm.asc(row.lastName),
                    (row) => OrderingTerm.asc(row.firstName),
                  ]))
                .get();
        for (final student in students) {
          add(
            student.parentPhone,
            '${student.firstName} ${student.lastName}'.trim(),
          );
        }
      case SmsBroadcastAudience.teachers:
        final teachers =
            await (db.select(db.teachers)
                  ..where((row) => row.deletedAt.isNull())
                  ..orderBy([(row) => OrderingTerm.asc(row.name)]))
                .get();
        for (final teacher in teachers) {
          add(teacher.phone, teacher.name);
        }
      case SmsBroadcastAudience.workers:
        final workers =
            await (db.select(db.workers)
                  ..where((row) => row.deletedAt.isNull())
                  ..orderBy([(row) => OrderingTerm.asc(row.name)]))
                .get();
        for (final worker in workers) {
          add(worker.phone, worker.name);
        }
    }

    return SmsBroadcastPreview(
      audience: audience,
      recipients: [
        for (final recipient in recipients.values)
          SmsBroadcastRecipient(
            phone: recipient.phone,
            name: recipient.names.join('، '),
          ),
      ],
      invalidContacts: invalidContacts,
    );
  }

  /// يضيف رسالة مخصصة لكل هاتف صالح من جمهور [audience].
  ///
  /// يدعم قالب «رسالة جماعية» المتغيرين `{school}` و`{name}`. تُجمع أسماء
  /// أبناء الوليّ في قيمة واحدة، وتُسجّل أخطاء الكتابة بعدّاد واضح حتى يعرف
  /// المستخدم إن كانت الدفعة جزئية.
  Future<SmsBroadcastResult> enqueue({
    required SmsBroadcastAudience audience,
    required String schoolName,
  }) async {
    final body = (await templates.get(SmsTemplateKeys.broadcast)).body;
    final preview = await this.preview(audience);
    var queued = 0;
    var failed = 0;
    final school = schoolName.trim().isEmpty ? 'المدرسة' : schoolName.trim();
    for (final recipient in preview.recipients) {
      final message = SmsTemplateRenderer.fill(body, {
        'school': school,
        'name': recipient.name,
      });
      try {
        await queue.enqueue(
          phone: recipient.phone,
          message: message,
          kind: SmsTemplateKeys.broadcast,
        );
        queued++;
      } on Exception {
        failed++;
      }
    }
    return SmsBroadcastResult(
      audience: audience,
      queued: queued,
      invalidContacts: preview.invalidContacts,
      failed: failed,
    );
  }
}

class _RecipientBuilder {
  _RecipientBuilder(this.phone);

  final String phone;
  final List<String> names = [];

  void addName(String rawName) {
    final name = rawName.trim();
    if (name.isNotEmpty && !names.contains(name)) names.add(name);
  }
}
