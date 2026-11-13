/// مفاتيح جدول `settings` (أزواج مفتاح وقيمة تُزامَن بين الأجهزة).
///
/// اسم المدرسة والشعار والعنوان والهاتف تُحدَّد من شاشة الإعدادات ولا
/// تُثبَّت في الكود (الإجابتان 21 و22).
abstract final class SettingKeys {
  static const String schoolName = 'school_name';

  /// مسار الشعار في مخزن الصور على الخادم (يُكتب بعد اكتمال الرفع).
  static const String schoolLogo = 'school_logo';

  /// مسار الشعار على هذا الجهاز؛ يُزامَن لكنه لا يعني شيئاً لجهاز آخر.
  static const String schoolLogoLocal = 'school_logo_local';
  static const String schoolAddress = 'school_address';
  static const String schoolPhone = 'school_phone';

  /// مبلغ حقوق التسجيل بالدينار، ومدتها (`year` أو `semester`).
  static const String registrationFee = 'registration_fee';
  static const String registrationFeePeriod = 'registration_fee_period';

  /// الفصول الدراسية (JSON: قائمة من الاسم وتاريخي البداية والنهاية).
  static const String semesters = 'semesters';

  /// هامش المسح قبل الحصة بالدقائق، ومهلة السماح للتأخر.
  static const String scanMarginMinutes = 'scan_margin_minutes';
  static const String graceMinutes = 'grace_minutes';

  /// عدد الحصص المنعقدة قبل أن يصير عدم دفع الدورة الحالية «مستحقات».
  static const String duesSessionThreshold = 'dues_session_threshold';

  /// الحد الاختياري لرسائل SMS المرسلة خلال شهر تقويمي؛ صفر يعني بلا حد.
  static const String smsMonthlyLimit = 'sms_monthly_limit';
}
