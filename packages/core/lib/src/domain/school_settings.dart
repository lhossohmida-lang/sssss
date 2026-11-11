import 'dart:convert';

import 'date_key.dart';
import 'enums.dart';
import 'money.dart';
import 'phone.dart';
import 'setting_keys.dart';

/// فصل دراسي: اسمه وتاريخا بدايته ونهايته (`YYYY-MM-DD`، والنهاية شاملة).
class Semester {
  const Semester({required this.name, required this.start, required this.end});

  final String name;
  final String start;
  final String end;

  Map<String, String> toJson() => {'name': name, 'start': start, 'end': end};

  /// يقرأ فصلاً من JSON، ويعيد `null` إن كان ناقصاً أو تاريخه غير صالح.
  static Semester? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final start = json['start'];
    final end = json['end'];
    if (name is! String || start is! String || end is! String) return null;
    try {
      DateKey.parse(start);
      DateKey.parse(end);
    } on FormatException {
      return null;
    }
    return Semester(name: name, start: start, end: end);
  }

  /// هل [date] (`YYYY-MM-DD`) داخل هذا الفصل؟ (المقارنة النصية صحيحة لهذه الصيغة)
  bool contains(String date) =>
      date.compareTo(start) >= 0 && date.compareTo(end) <= 0;

  @override
  bool operator ==(Object other) =>
      other is Semester &&
      other.name == name &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(name, start, end);
}

/// إعدادات المدرسة كما تُحفظ في جدول `settings` (أزواج مفتاح وقيمة).
///
/// القيم الافتراضية هي الاقتراحات المعتمدة: هامش مسح 30 دقيقة، مهلة سماح
/// 5 دقائق، «عليه مستحقات» بعد الحصة الثانية، حقوق التسجيل لسنة دراسية.
class SchoolSettings {
  const SchoolSettings({
    this.schoolName = '',
    this.schoolAddress = '',
    this.schoolPhone = '',
    this.registrationFee = 0,
    this.registrationFeePeriod = FeePeriod.year,
    this.semesters = const [],
    this.scanMarginMinutes = defaultScanMargin,
    this.graceMinutes = defaultGrace,
    this.duesSessionThreshold = defaultDuesThreshold,
  });

  static const int defaultScanMargin = 30;
  static const int defaultGrace = 5;
  static const int defaultDuesThreshold = 2;

  final String schoolName;
  final String schoolAddress;
  final String schoolPhone;

  /// مبلغ حقوق التسجيل بالدينار؛ 0 يعني بلا حقوق.
  final int registrationFee;
  final FeePeriod registrationFeePeriod;
  final List<Semester> semesters;
  final int scanMarginMinutes;
  final int graceMinutes;
  final int duesSessionThreshold;

  SchoolSettings copyWith({
    String? schoolName,
    String? schoolAddress,
    String? schoolPhone,
    int? registrationFee,
    FeePeriod? registrationFeePeriod,
    List<Semester>? semesters,
    int? scanMarginMinutes,
    int? graceMinutes,
    int? duesSessionThreshold,
  }) => SchoolSettings(
    schoolName: schoolName ?? this.schoolName,
    schoolAddress: schoolAddress ?? this.schoolAddress,
    schoolPhone: schoolPhone ?? this.schoolPhone,
    registrationFee: registrationFee ?? this.registrationFee,
    registrationFeePeriod: registrationFeePeriod ?? this.registrationFeePeriod,
    semesters: semesters ?? this.semesters,
    scanMarginMinutes: scanMarginMinutes ?? this.scanMarginMinutes,
    graceMinutes: graceMinutes ?? this.graceMinutes,
    duesSessionThreshold: duesSessionThreshold ?? this.duesSessionThreshold,
  );

  /// يبني الإعدادات من أزواج الجدول. المفاتيح الغائبة أو التالفة تأخذ القيمة
  /// الافتراضية فلا يتعطل التطبيق بإعداد خاطئ.
  factory SchoolSettings.fromMap(Map<String, String> values) {
    int number(String key, int fallback) =>
        int.tryParse((values[key] ?? '').trim()) ?? fallback;

    final period = values[SettingKeys.registrationFeePeriod];
    var parsedPeriod = FeePeriod.year;
    for (final candidate in FeePeriod.values) {
      if (candidate.code == period) parsedPeriod = candidate;
    }

    final semesters = <Semester>[];
    final raw = values[SettingKeys.semesters];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            final semester = Semester.fromJson(item);
            if (semester != null) semesters.add(semester);
          }
        }
      } on FormatException {
        // قائمة تالفة تُعامل كأنها فارغة.
      }
    }

    return SchoolSettings(
      schoolName: (values[SettingKeys.schoolName] ?? '').trim(),
      schoolAddress: (values[SettingKeys.schoolAddress] ?? '').trim(),
      schoolPhone: (values[SettingKeys.schoolPhone] ?? '').trim(),
      registrationFee: number(SettingKeys.registrationFee, 0),
      registrationFeePeriod: parsedPeriod,
      semesters: semesters,
      scanMarginMinutes: number(
        SettingKeys.scanMarginMinutes,
        defaultScanMargin,
      ),
      graceMinutes: number(SettingKeys.graceMinutes, defaultGrace),
      duesSessionThreshold: number(
        SettingKeys.duesSessionThreshold,
        defaultDuesThreshold,
      ),
    );
  }

  /// أزواج الجدول لهذه الإعدادات.
  Map<String, String> toMap() => {
    SettingKeys.schoolName: schoolName.trim(),
    SettingKeys.schoolAddress: schoolAddress.trim(),
    SettingKeys.schoolPhone: schoolPhone.trim(),
    SettingKeys.registrationFee: '$registrationFee',
    SettingKeys.registrationFeePeriod: registrationFeePeriod.code,
    SettingKeys.semesters: jsonEncode([for (final s in semesters) s.toJson()]),
    SettingKeys.scanMarginMinutes: '$scanMarginMinutes',
    SettingKeys.graceMinutes: '$graceMinutes',
    SettingKeys.duesSessionThreshold: '$duesSessionThreshold',
  };

  /// الفصل الذي يضم [date]، أو `null`.
  Semester? semesterOn(String date) {
    for (final semester in semesters) {
      if (semester.contains(date)) return semester;
    }
    return null;
  }

  /// أخطاء التحقق بالعربية: مفتاح الإعداد ← الرسالة. فارغة إن كان كل شيء سليماً.
  ///
  /// أخطاء الفصول تحت المفتاح [SettingKeys.semesters] برقم الفصل في الرسالة.
  Map<String, String> validate() {
    final errors = <String, String>{};
    if (schoolPhone.trim().isNotEmpty && !PhoneNumbers.isValid(schoolPhone)) {
      errors[SettingKeys.schoolPhone] =
          'رقم الهاتف يبدأ بـ 05 أو 06 أو 07 ويتبعه 8 أرقام';
    }
    if (registrationFee < 0) {
      errors[SettingKeys.registrationFee] = 'المبلغ لا يكون سالباً';
    } else if (registrationFee % 10 != 0) {
      errors[SettingKeys.registrationFee] =
          'المبلغ من مضاعفات 10 ${Money.currency}';
    }
    if (scanMarginMinutes < 0 || scanMarginMinutes > 180) {
      errors[SettingKeys.scanMarginMinutes] = 'الهامش من 0 إلى 180 دقيقة';
    }
    if (graceMinutes < 0 || graceMinutes > 60) {
      errors[SettingKeys.graceMinutes] = 'المهلة من 0 إلى 60 دقيقة';
    }
    if (duesSessionThreshold < 0 || duesSessionThreshold > 12) {
      errors[SettingKeys.duesSessionThreshold] = 'العدد من 0 إلى 12 حصة';
    }
    final semesterError = _validateSemesters();
    if (semesterError != null) errors[SettingKeys.semesters] = semesterError;
    return errors;
  }

  String? _validateSemesters() {
    for (var i = 0; i < semesters.length; i++) {
      final s = semesters[i];
      final n = i + 1;
      if (s.name.trim().isEmpty) return 'الفصل $n: أدخل الاسم';
      if (s.start.compareTo(s.end) > 0) {
        return 'الفصل $n: بداية الفصل بعد نهايته';
      }
    }
    final ordered = [...semesters]..sort((a, b) => a.start.compareTo(b.start));
    for (var i = 1; i < ordered.length; i++) {
      if (ordered[i].start.compareTo(ordered[i - 1].end) <= 0) {
        return 'الفصلان «${ordered[i - 1].name}» و«${ordered[i].name}» متداخلان';
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (other is! SchoolSettings) return false;
    final mine = toMap();
    final theirs = other.toMap();
    for (final key in mine.keys) {
      if (mine[key] != theirs[key]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(toMap().values);
}
