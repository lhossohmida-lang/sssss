/// مفاتيح جدول `settings` (أزواج مفتاح وقيمة تُزامَن بين الأجهزة).
///
/// اسم المدرسة والشعار والعنوان والهاتف تُحدَّد من شاشة الإعدادات ولا
/// تُثبَّت في الكود (الإجابتان 21 و22).
abstract final class SettingKeys {
  static const String schoolName = 'school_name';
  static const String schoolLogo = 'school_logo';
  static const String schoolAddress = 'school_address';
  static const String schoolPhone = 'school_phone';
}
