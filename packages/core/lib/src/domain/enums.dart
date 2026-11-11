/// الأنواع المعدودة المشتركة بين كل التطبيقات.
library;

/// دور المستخدم في النظام.
enum UserRole {
  owner('owner', 'صاحب المدرسة'),
  worker('worker', 'عامل'),
  teacher('teacher', 'أستاذ'),
  parent('parent', 'وليّ');

  const UserRole(this.code, this.label);

  /// القيمة المخزَّنة في القاعدة المحلية وفي الخادم.
  final String code;

  /// النص العربي الظاهر للمستخدم.
  final String label;

  /// هل يستعمل هذا الدور تطبيق الإدارة؟
  bool get usesAdminApp => this == owner || this == worker;

  /// يحوّل القيمة المخزَّنة إلى النوع، ويرمي [ArgumentError] إن كانت مجهولة.
  static UserRole fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(code, 'code', 'قيمة UserRole غير معروفة');
  }
}

/// حالة الحصة.
enum SessionStatus {
  normal('normal', 'عادية'),
  cancelled('cancelled', 'ملغاة'),
  makeup('makeup', 'تعويضية'),
  added('added', 'مضافة');

  const SessionStatus(this.code, this.label);

  /// القيمة المخزَّنة في القاعدة المحلية وفي الخادم.
  final String code;

  /// النص العربي الظاهر للمستخدم.
  final String label;

  /// الحصة الملغاة لا تُحسب ضمن الدورة؛ العادية والتعويضية والمضافة تُحسب.
  bool get countsInCycle => this != cancelled;

  /// يحوّل القيمة المخزَّنة إلى النوع، ويرمي [ArgumentError] إن كانت مجهولة.
  static SessionStatus fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(code, 'code', 'قيمة SessionStatus غير معروفة');
  }
}

/// حالة حضور التلميذ في حصة.
enum AttendanceStatus {
  present('present', 'حاضر'),
  absent('absent', 'غائب'),
  excused('excused', 'غائب برخصة');

  const AttendanceStatus(this.code, this.label);

  /// القيمة المخزَّنة في القاعدة المحلية وفي الخادم.
  final String code;

  /// النص العربي الظاهر للمستخدم.
  final String label;

  /// يحوّل القيمة المخزَّنة إلى النوع، ويرمي [ArgumentError] إن كانت مجهولة.
  static AttendanceStatus fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(code, 'code', 'قيمة AttendanceStatus غير معروفة');
  }
}

/// طريقة تسجيل الحضور.
enum AttendanceMethod {
  qr('qr', 'مسح الرمز'),
  manual('manual', 'يدوي');

  const AttendanceMethod(this.code, this.label);

  /// القيمة المخزَّنة في القاعدة المحلية وفي الخادم.
  final String code;

  /// النص العربي الظاهر للمستخدم.
  final String label;

  /// يحوّل القيمة المخزَّنة إلى النوع، ويرمي [ArgumentError] إن كانت مجهولة.
  static AttendanceMethod fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(code, 'code', 'قيمة AttendanceMethod غير معروفة');
  }
}

/// نوع طلب الأستاذ.
enum SessionRequestType {
  reschedule('reschedule', 'تغيير موعد'),
  addSession('add', 'إضافة حصة'),
  advance('advance', 'تسبيق حصة'),
  cancel('cancel', 'إلغاء حصة');

  const SessionRequestType(this.code, this.label);

  /// القيمة المخزَّنة في القاعدة المحلية وفي الخادم.
  final String code;

  /// النص العربي الظاهر للمستخدم.
  final String label;

  /// هل يحتاج الطلب موعداً جديداً؟ (الإلغاء لا يحتاجه)
  bool get needsNewSlot => this != cancel;

  /// هل يخص الطلب حصة موجودة؟ (إضافة حصة لا تخص حصة موجودة)
  bool get targetsExistingSession => this != addSession;

  /// يحوّل القيمة المخزَّنة إلى النوع، ويرمي [ArgumentError] إن كانت مجهولة.
  static SessionRequestType fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(
      code,
      'code',
      'قيمة SessionRequestType غير معروفة',
    );
  }
}

/// حالة طلب الأستاذ.
enum SessionRequestStatus {
  pending('pending', 'قيد الانتظار'),
  approved('approved', 'مقبول'),
  rejected('rejected', 'مرفوض');

  const SessionRequestStatus(this.code, this.label);

  /// القيمة المخزَّنة في القاعدة المحلية وفي الخادم.
  final String code;

  /// النص العربي الظاهر للمستخدم.
  final String label;

  /// يحوّل القيمة المخزَّنة إلى النوع، ويرمي [ArgumentError] إن كانت مجهولة.
  static SessionRequestStatus fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(
      code,
      'code',
      'قيمة SessionRequestStatus غير معروفة',
    );
  }
}

/// نوع الدفعة.
enum PaymentType {
  month('month', 'شهر'),
  transport('transport', 'نقل'),
  registrationFee('registration', 'حقوق تسجيل');

  const PaymentType(this.code, this.label);

  /// القيمة المخزَّنة في القاعدة المحلية وفي الخادم.
  final String code;

  /// النص العربي الظاهر للمستخدم.
  final String label;

  /// يحوّل القيمة المخزَّنة إلى النوع، ويرمي [ArgumentError] إن كانت مجهولة.
  static PaymentType fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(code, 'code', 'قيمة PaymentType غير معروفة');
  }
}

/// نوع تخفيض التلميذ في مجموعة.
enum DiscountType {
  none('none', 'دون تخفيض'),
  percent('percent', 'نسبة مئوية'),
  fixed('fixed', 'مبلغ ثابت'),
  exempt('exempt', 'إعفاء كامل');

  const DiscountType(this.code, this.label);

  /// القيمة المخزَّنة في القاعدة المحلية وفي الخادم.
  final String code;

  /// النص العربي الظاهر للمستخدم.
  final String label;

  /// يحوّل القيمة المخزَّنة إلى النوع، ويرمي [ArgumentError] إن كانت مجهولة.
  static DiscountType fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(code, 'code', 'قيمة DiscountType غير معروفة');
  }
}

/// برنامج عمل العامل في يوم من الأسبوع.
enum WorkDayKind {
  off('off', 'لا يعمل'),
  half('half', 'نصف يوم'),
  full('full', 'يوم كامل');

  const WorkDayKind(this.code, this.label);

  /// القيمة المخزَّنة في القاعدة المحلية وفي الخادم.
  final String code;

  /// النص العربي الظاهر للمستخدم.
  final String label;

  /// يحوّل القيمة المخزَّنة إلى النوع، ويرمي [ArgumentError] إن كانت مجهولة.
  static WorkDayKind fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(code, 'code', 'قيمة WorkDayKind غير معروفة');
  }
}

/// حالة رسالة في طابور الإرسال.
enum SmsStatus {
  pending('pending', 'في الانتظار'),
  sending('sending', 'جارٍ الإرسال'),
  sent('sent', 'أُرسلت'),
  failed('failed', 'فشلت');

  const SmsStatus(this.code, this.label);

  /// القيمة المخزَّنة في القاعدة المحلية وفي الخادم.
  final String code;

  /// النص العربي الظاهر للمستخدم.
  final String label;

  /// يحوّل القيمة المخزَّنة إلى النوع، ويرمي [ArgumentError] إن كانت مجهولة.
  static SmsStatus fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(code, 'code', 'قيمة SmsStatus غير معروفة');
  }
}

/// نوع غرفة المحادثة.
enum ChatRoomType {
  private('private', 'خاص'),
  group('group', 'جماعي');

  const ChatRoomType(this.code, this.label);

  /// القيمة المخزَّنة في القاعدة المحلية وفي الخادم.
  final String code;

  /// النص العربي الظاهر للمستخدم.
  final String label;

  /// يحوّل القيمة المخزَّنة إلى النوع، ويرمي [ArgumentError] إن كانت مجهولة.
  static ChatRoomType fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(code, 'code', 'قيمة ChatRoomType غير معروفة');
  }
}

/// المدة التي تغطيها حقوق التسجيل.
enum FeePeriod {
  year('year', 'سنة دراسية'),
  semester('semester', 'فصل دراسي');

  const FeePeriod(this.code, this.label);

  /// القيمة المخزَّنة في القاعدة المحلية وفي الخادم.
  final String code;

  /// النص العربي الظاهر للمستخدم.
  final String label;

  /// يحوّل القيمة المخزَّنة إلى النوع، ويرمي [ArgumentError] إن كانت مجهولة.
  static FeePeriod fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(code, 'code', 'قيمة FeePeriod غير معروفة');
  }
}

/// الطور الدراسي.
enum EducationStage {
  primary('primary', 'ابتدائي', 5),
  middle('middle', 'متوسط', 4),
  secondary('secondary', 'ثانوي', 3);

  const EducationStage(this.code, this.label, this.defaultGrades);

  /// القيمة المخزَّنة في القاعدة المحلية وفي الخادم.
  final String code;

  /// النص العربي الظاهر للمستخدم.
  final String label;

  /// عدد سنوات الطور في المنهاج الجزائري (الاقتراح المعتمد 32).
  final int defaultGrades;

  /// يحوّل القيمة المخزَّنة إلى النوع، ويرمي [ArgumentError] إن كانت مجهولة.
  static EducationStage fromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(code, 'code', 'قيمة EducationStage غير معروفة');
  }
}
