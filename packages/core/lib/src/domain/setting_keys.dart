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

  /// خانة الشريحة المختارة لإرسال SMS على هاتف الإدارة.
  static const String smsSimSlotIndex = 'sms_sim_slot_index';

  /// معرّف جهاز الإدارة الذي يرسل رسائل SMS تلقائياً (هاتف Android الذي فيه
  /// الشريحة). يُزامَن ليعرف كل جهاز إن كان هو المرسل، فلا تُرسل رسالة من جهازين.
  static const String smsSenderDevice = 'sms_sender_device';

  /// وقت آخر تنفيذ لزر «سنة جديدة» بالمللي ثانية (UTC).
  static const String lastNewYearAt = 'last_new_year_at';

  /// مدة العمل بالدقائق التي يُحسب بها يوم العامل «نصف يوم» ثم «يوماً كاملاً». العمال بلا أيام
  /// محددة: يأتي العامل يوماً نصف يوم وأسبوعاً بعده يوماً كاملاً، فيُحسب يومه من وقت دخوله
  /// وخروجه الممسوحين لا من برنامج أسبوعي.
  static const String workerHalfDayMinutes = 'worker_half_day_minutes';
  static const String workerFullDayMinutes = 'worker_full_day_minutes';

  /// أنواع رسائل SMS المعطَّلة: JSON قائمة من مفاتيح القوالب (`payment_receipt`...). الرسالة
  /// من نوع معطَّل لا تُوضع في الطابور أصلاً.
  static const String smsDisabledKinds = 'sms_disabled_kinds';
}
