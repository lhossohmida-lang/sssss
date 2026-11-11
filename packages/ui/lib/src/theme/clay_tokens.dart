import 'dart:ui';

/// المسافات بالبكسل المنطقي (شبكة 4).
abstract final class ClaySpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;

  /// هامش الشاشة الجانبي على الهاتف.
  static const double screenPadding = 16;

  /// أصغر مساحة لمس مريحة (إرشادات Material و Apple).
  static const double minTouchTarget = 48;
}

/// أنصاف أقطار الزوايا: دائرية سميكة بأسلوب claymorphism.
abstract final class ClayRadius {
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double xl = 32;

  /// للأزرار الحبّية والشارات.
  static const double pill = 999;
}

/// أحجام الخط. كل الأرقام لاتينية (المواصفات 71).
abstract final class ClayFontSize {
  static const double caption = 12;
  static const double body = 14;
  static const double bodyLarge = 16;
  static const double title = 18;
  static const double headline = 22;
  static const double display = 28;
}

/// أوزان الخط. الخط Cairo متغيّر المحور `wght` فيُحدَّد الوزن بدقة.
abstract final class ClayFontWeight {
  static const double regular = 400;
  static const double medium = 500;
  static const double semiBold = 600;
  static const double bold = 700;

  /// الوزن كقيمة [FontWeight] مع محور الخط المتغيّر.
  static FontWeight asFontWeight(double weight) =>
      FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)];
}

/// مدد الحركة. قصيرة حتى لا تُشعر المستخدم ببطء على الأجهزة المتواضعة.
abstract final class ClayDuration {
  static const Duration press = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 220);
}

/// اسم عائلة الخط المضمَّن في الحزمة.
const String clayFontFamily = 'Cairo';

/// اسم الحزمة التي تضم الخط، ليجده أي تطبيق يستعمل `school_ui`.
const String clayFontPackage = 'school_ui';
