import '../data/local/app_database.dart';

/// مفاتيح قوالب الرسائل القصيرة وصيغها الافتراضية (عربية قصيرة، الاقتراح 61).
///
/// المدير يعدّل أي قالب من شاشة الرسائل (المهمة 5.4)؛ ما لم يُعدَّل يُستعمل
/// الافتراضي هنا. المتغيرات بين قوسين معقوفين مثل `{name}`.
abstract final class SmsTemplateKeys {
  static const String accountCreated = 'account_created';
  static const String passwordReset = 'password_reset';
  static const String attendanceAbsent = 'attendance_absent';
  static const String waitingThreshold = 'waiting_threshold';
  static const String groupCreated = 'group_created';
  static const String cycleCompleted = 'cycle_completed';
  static const String scheduleChange = 'schedule_change';
  static const String requestApproved = 'request_approved';
  static const String requestRejected = 'request_rejected';
  static const String paymentReceipt = 'payment_receipt';
  static const String paymentReminder = 'payment_reminder';
  static const String broadcast = 'broadcast';

  /// القوالب الافتراضية.
  static const Map<String, String> defaults = {
    accountCreated:
        'مرحباً {name}، تم إنشاء حسابك في {school}.\n'
        'البريد: {email}\n'
        'كلمة السر: {password}\n'
        'غيّر كلمة السر عند أول دخول.',
    passwordReset:
        '{school}: كلمة سر جديدة لحسابك.\n'
        'البريد: {email}\n'
        'كلمة السر: {password}\n'
        'غيّرها عند الدخول.',
    attendanceAbsent: '{school}: لم يحضر {name} حصة {subject} يوم {date}.',
    waitingThreshold: '{school}: وصل {name} إلى حد الانتظار في {subject}. سنخبركم عند توفر مكان.',
    groupCreated:
        '{school}: أُنشئت مجموعة {subject} لـ {name}. موعدها: {schedule}.',
    cycleCompleted:
        '{school}: اكتملت دورة {subject} لـ {name}. المستحقات: {amount} دج.',
    scheduleChange: '{school}: تغيّر موعد {subject} لـ {name} إلى {date}، {time}، القاعة {room}.',
    requestApproved:
        '{school}: وافقت الإدارة على طلب الأستاذ بشأن {subject} '
        '(المجموعة {group})؛ {summary}. التلاميذ: {name}.',
    requestRejected:
        '{school}: رُفض طلب الأستاذ {name}: {request}. '
        'ملاحظة الإدارة: {note}.',
    paymentReceipt:
        '{school}: وصل {receipt} بقيمة {amount} للتلميذ {name} عن {item}.',
    paymentReminder:
        '{school}: يرجى تسديد مستحقات {name} في {subject}: {amount} دج.',
    broadcast: '{school}: رسالة إلى {name}.',
  };
}

/// يبني نص الرسالة من قالب (المعدَّل إن وُجد وإلا الافتراضي).
class SmsTemplateRenderer {
  SmsTemplateRenderer(this.db);

  final AppDatabase db;

  /// نص القالب [key] مع تعويض [values]. متغير مجهول يبقى كما هو.
  Future<String> render(String key, Map<String, String> values) async {
    final stored = await (db.select(
      db.smsTemplates,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    final body = stored?.body.trim().isNotEmpty == true
        ? stored!.body
        : (SmsTemplateKeys.defaults[key] ?? '');
    return fill(body, values);
  }

  /// يعوّض `{name}` ونحوها في [template].
  static String fill(String template, Map<String, String> values) =>
      template.replaceAllMapped(
        RegExp(r'\{(\w+)\}'),
        (m) => values[m.group(1)] ?? m.group(0)!,
      );
}
