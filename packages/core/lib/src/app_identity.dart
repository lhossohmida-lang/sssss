import 'dart:ui';

/// هوية كل تطبيق من تطبيقات النظام الثلاثة.
enum AppIdentity {
  admin(displayName: 'الإدارة', packageId: 'dz.school.admin'),
  teacher(displayName: 'الأستاذ', packageId: 'dz.school.teacher'),
  student(displayName: 'وليّ التلميذ', packageId: 'dz.school.student');

  const AppIdentity({required this.displayName, required this.packageId});

  /// الاسم الظاهر تحت أيقونة التطبيق.
  final String displayName;

  /// اسم حزمة Android، ولا يتغير بعد النشر.
  final String packageId;

  /// لغة الواجهة الوحيدة: العربية (الجزائر).
  static const Locale locale = Locale('ar', 'DZ');
}
