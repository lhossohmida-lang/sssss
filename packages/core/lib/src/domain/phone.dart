/// أرقام الهاتف الجزائرية: `05` / `06` / `07` متبوعة بثمانية أرقام.
abstract final class PhoneNumbers {
  static final RegExp _local = RegExp(r'^0[567]\d{8}$');

  /// يزيل المسافات والفواصل ويحوّل الصيغة الدولية إلى المحلية.
  static String normalize(String raw) {
    var digits = raw.replaceAll(RegExp(r'[\s\-.()]'), '');
    if (digits.startsWith('+213')) {
      digits = '0${digits.substring(4)}';
    } else if (digits.startsWith('00213')) {
      digits = '0${digits.substring(5)}';
    }
    return digits;
  }

  /// هل الرقم هاتف نقال جزائري صالح؟
  static bool isValid(String raw) => _local.hasMatch(normalize(raw));

  /// الصيغة الدولية لإرسال الرسائل، مثل `+213550123456`.
  static String toInternational(String raw) {
    final local = normalize(raw);
    if (!_local.hasMatch(local)) {
      throw FormatException('رقم هاتف غير صالح', raw);
    }
    return '+213${local.substring(1)}';
  }
}
