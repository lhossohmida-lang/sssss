import '../data/local/app_database.dart';

/// مفاتيح قوالب الرسائل القصيرة وصيغها الافتراضية (عربية قصيرة، الاقتراح 61).
///
/// المدير يعدّل أي قالب من شاشة الرسائل (المهمة 5.4)؛ ما لم يُعدَّل يُستعمل
/// الافتراضي هنا. المتغيرات بين قوسين معقوفين مثل `{name}`.
abstract final class SmsTemplateKeys {
  static const String accountCreated = 'account_created';
  static const String passwordReset = 'password_reset';

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
