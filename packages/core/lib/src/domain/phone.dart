/// أرقام الهاتف الجزائرية: `05` / `06` / `07` متبوعة بثمانية أرقام.
abstract final class PhoneNumbers {
  static final RegExp _local = RegExp(r'^0[567]\d{8}$');

  /// الأرقام العربية-الهندية (٠–٩) والفارسية (۰–۹) التي تنتجها بعض لوحات المفاتيح.
  static final RegExp _nonLatinDigits = RegExp('[٠-٩۰-۹]');

  /// علامات اتجاه ومسافات صفرية خفية تُضاف عند النسخ من الرسائل أو الكتابة بالعربية.
  static final RegExp _invisible = RegExp(
    '[\u{200B}-\u{200F}\u{202A}-\u{202E}\u{2066}-\u{2069}\u{FEFF}]',
  );

  /// يوحّد الرقم: يحوّل الأرقام العربية إلى لاتينية، ويزيل العلامات الخفية
  /// والمسافات والفواصل، ويحوّل الصيغة الدولية إلى المحلية.
  static String normalize(String raw) {
    var digits = raw
        .replaceAll(_invisible, '')
        .replaceAllMapped(_nonLatinDigits, _toLatin)
        .replaceAll(RegExp(r'[\s\-.()]'), '');
    if (digits.startsWith('+213')) {
      digits = '0${digits.substring(4)}';
    } else if (digits.startsWith('00213')) {
      digits = '0${digits.substring(5)}';
    }
    return digits;
  }

  static String _toLatin(Match match) {
    final unit = match.group(0)!.codeUnitAt(0);
    final base = unit >= 0x06F0 ? 0x06F0 : 0x0660;
    return String.fromCharCode(0x30 + unit - base);
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
