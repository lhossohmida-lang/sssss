import 'dart:math';

import '../domain/phone.dart';

/// بريد دخول وكلمة سر مولَّدان لحساب جديد.
class GeneratedCredentials {
  const GeneratedCredentials({required this.email, required this.password});

  final String email;
  final String password;

  @override
  bool operator ==(Object other) =>
      other is GeneratedCredentials &&
      other.email == email &&
      other.password == password;

  @override
  int get hashCode => Object.hash(email, password);

  @override
  String toString() => 'GeneratedCredentials($email)';
}

/// بيانات الدخول: توليدها عند إنشاء الحساب، والتحقق منها عند الدخول.
///
/// كل الحسابات تُنشأ من تطبيق الإدارة (إجابة ب1): البريد يُبنى من رقم
/// الهاتف، وكلمة السر ثمانية رموز عشوائية تُرسل في رسالة قصيرة.
abstract final class LoginCredentials {
  /// نطاق البريد المولَّد؛ لا يُرسل إليه بريد فعلاً، فهو اسم دخول فقط.
  static const String emailDomain = 'school.local';

  /// طول كلمة السر المولَّدة.
  static const int generatedPasswordLength = 8;

  /// أقصر كلمة سر يقبلها النظام (ومثلها الحد الأدنى على الخادم).
  static const int minPasswordLength = 8;

  /// حروف وأرقام دون الملتبسة (0 و O، 1 و I و L)، فتُقرأ في الرسالة بلا خطأ.
  static const String passwordAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  static final RegExp _email = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$',
  );

  /// يوحّد صيغة البريد قبل مقارنته أو إرساله إلى الخادم.
  static String normalizeEmail(String email) => email.trim().toLowerCase();

  /// هل البريد مكتوب بصيغة صالحة؟
  static bool isValidEmail(String email) =>
      _email.hasMatch(normalizeEmail(email));

  /// بريد الدخول المبني على رقم الهاتف، مثل `0550123456@school.local`.
  ///
  /// يرمي [FormatException] إن لم يكن الرقم هاتفاً جزائرياً صالحاً.
  static String emailForPhone(String phone) {
    final local = PhoneNumbers.normalize(phone);
    if (!PhoneNumbers.isValid(local)) {
      throw FormatException('رقم هاتف غير صالح', phone);
    }
    return '$local@$emailDomain';
  }

  /// كلمة سر عشوائية من [generatedPasswordLength] رمزاً.
  static String generatePassword({Random? random}) {
    final source = random ?? Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < generatedPasswordLength; i++) {
      buffer.write(passwordAlphabet[source.nextInt(passwordAlphabet.length)]);
    }
    return buffer.toString();
  }

  /// بيانات دخول كاملة لصاحب الرقم [phone].
  static GeneratedCredentials generateFor(String phone, {Random? random}) =>
      GeneratedCredentials(
        email: emailForPhone(phone),
        password: generatePassword(random: random),
      );

  /// سبب رفض كلمة السر بالعربية، أو `null` إن كانت مقبولة.
  static String? passwordProblem(String password) {
    if (password.isEmpty) return 'أدخل كلمة السر';
    if (password.trim().length != password.length) {
      return 'كلمة السر لا تبدأ ولا تنتهي بمسافة';
    }
    if (password.length < minPasswordLength) {
      return 'كلمة السر $minPasswordLength رموز على الأقل';
    }
    return null;
  }

  /// سبب رفض البريد بالعربية، أو `null` إن كان مقبولاً.
  static String? emailProblem(String email) {
    if (normalizeEmail(email).isEmpty) return 'أدخل البريد';
    if (!isValidEmail(email)) return 'البريد غير مكتوب بصيغة صحيحة';
    return null;
  }
}
