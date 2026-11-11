import 'package:flutter/material.dart';
import 'package:school_core/school_core.dart';

/// ألوان الحالات: تُستعمل للحضور والمستحقات والتنبيهات بنفس الدلالة في كل
/// التطبيقات (أخضر حاضر، أحمر غائب، بنفسجي برخصة، برتقالي عليه مستحقات).
@immutable
class ClayStatusColors {
  const ClayStatusColors({
    required this.success,
    required this.danger,
    required this.warning,
    required this.info,
    required this.excused,
  });

  /// حاضر، مدفوع، نجاح.
  final Color success;

  /// غائب، خطأ، حذف.
  final Color danger;

  /// عليه مستحقات، تنبيه.
  final Color warning;

  /// معلومة، قيد الانتظار.
  final Color info;

  /// غائب برخصة.
  final Color excused;

  static const light = ClayStatusColors(
    success: Color(0xFF177A41),
    danger: Color(0xFFC62F3A),
    warning: Color(0xFFA85300),
    info: Color(0xFF2A66B3),
    excused: Color(0xFF7A4FC0),
  );

  static const dark = ClayStatusColors(
    success: Color(0xFF5ED08A),
    danger: Color(0xFFFF7B84),
    warning: Color(0xFFFFB257),
    info: Color(0xFF7DB4FF),
    excused: Color(0xFFBC9BFF),
  );

  /// لون حالة حضور التلميذ.
  Color forAttendance(AttendanceStatus status) => switch (status) {
    AttendanceStatus.present => success,
    AttendanceStatus.absent => danger,
    AttendanceStatus.excused => excused,
  };

  /// لون حالة طلب الأستاذ.
  Color forRequest(SessionRequestStatus status) => switch (status) {
    SessionRequestStatus.pending => info,
    SessionRequestStatus.approved => success,
    SessionRequestStatus.rejected => danger,
  };

  static ClayStatusColors lerp(
    ClayStatusColors a,
    ClayStatusColors b,
    double t,
  ) => ClayStatusColors(
    success: Color.lerp(a.success, b.success, t)!,
    danger: Color.lerp(a.danger, b.danger, t)!,
    warning: Color.lerp(a.warning, b.warning, t)!,
    info: Color.lerp(a.info, b.info, t)!,
    excused: Color.lerp(a.excused, b.excused, t)!,
  );

  @override
  bool operator ==(Object other) =>
      other is ClayStatusColors &&
      other.success == success &&
      other.danger == danger &&
      other.warning == warning &&
      other.info == info &&
      other.excused == excused;

  @override
  int get hashCode => Object.hash(success, danger, warning, info, excused);
}

/// لوحة الألوان الكاملة لتطبيق في وضع (فاتح أو داكن).
///
/// الأسلوب claymorphism: سطح ناعم بلون قريب من الخلفية، وظلّان متقابلان
/// (فاتح من أعلى اليسار وداكن من أسفل اليمين) يعطيان إحساس الطين المنفوخ.
@immutable
class ClayPalette {
  const ClayPalette({
    required this.brightness,
    required this.accent,
    required this.onAccent,
    required this.background,
    required this.surface,
    required this.surfacePressed,
    required this.text,
    required this.textMuted,
    required this.outline,
    required this.shadowLight,
    required this.shadowDark,
    required this.status,
  });

  final Brightness brightness;

  /// اللون الرئيسي للتطبيق.
  final Color accent;

  /// لون النص والأيقونات فوق [accent].
  final Color onAccent;

  /// خلفية الشاشة.
  final Color background;

  /// سطح البطاقات والأزرار.
  final Color surface;

  /// السطح أثناء الضغط (غائر).
  final Color surfacePressed;

  final Color text;

  /// النص الثانوي.
  final Color textMuted;

  /// حدود الحقول والفواصل.
  final Color outline;

  /// الظل الفاتح (أعلى اليسار).
  final Color shadowLight;

  /// الظل الداكن (أسفل اليمين).
  final Color shadowDark;

  final ClayStatusColors status;

  bool get isDark => brightness == Brightness.dark;

  /// اللون الرئيسي لكل تطبيق، يميّز التطبيقات الثلاثة بصرياً.
  static Color accentFor(AppIdentity app, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (app) {
      AppIdentity.admin =>
        dark ? const Color(0xFF9EA1FF) : const Color(0xFF4F52C9),
      AppIdentity.teacher =>
        dark ? const Color(0xFF4FD1C0) : const Color(0xFF0A7468),
      AppIdentity.student =>
        dark ? const Color(0xFF7DB8FF) : const Color(0xFF1A66C2),
    };
  }

  /// لوحة تطبيق [app] في الوضع [brightness].
  factory ClayPalette.of(AppIdentity app, Brightness brightness) {
    final accent = accentFor(app, brightness);
    if (brightness == Brightness.dark) {
      return ClayPalette(
        brightness: brightness,
        accent: accent,
        onAccent: const Color(0xFF141824),
        background: const Color(0xFF1B2030),
        surface: const Color(0xFF232A3C),
        surfacePressed: const Color(0xFF1A1F2E),
        text: const Color(0xFFEEF1F8),
        textMuted: const Color(0xFFA3ACC2),
        outline: const Color(0xFF3A435B),
        shadowLight: const Color(0xFF2C3550),
        shadowDark: const Color(0xFF10131D),
        status: ClayStatusColors.dark,
      );
    }
    return ClayPalette(
      brightness: brightness,
      accent: accent,
      onAccent: const Color(0xFFFFFFFF),
      background: const Color(0xFFE9EDF5),
      surface: const Color(0xFFF2F5FA),
      surfacePressed: const Color(0xFFDDE2EE),
      text: const Color(0xFF1E2433),
      textMuted: const Color(0xFF5A6378),
      outline: const Color(0xFFC3CAD9),
      shadowLight: const Color(0xFFFFFFFF),
      shadowDark: const Color(0xFFB8C0D4),
      status: ClayStatusColors.light,
    );
  }

  static ClayPalette lerp(ClayPalette a, ClayPalette b, double t) =>
      ClayPalette(
        brightness: t < 0.5 ? a.brightness : b.brightness,
        accent: Color.lerp(a.accent, b.accent, t)!,
        onAccent: Color.lerp(a.onAccent, b.onAccent, t)!,
        background: Color.lerp(a.background, b.background, t)!,
        surface: Color.lerp(a.surface, b.surface, t)!,
        surfacePressed: Color.lerp(a.surfacePressed, b.surfacePressed, t)!,
        text: Color.lerp(a.text, b.text, t)!,
        textMuted: Color.lerp(a.textMuted, b.textMuted, t)!,
        outline: Color.lerp(a.outline, b.outline, t)!,
        shadowLight: Color.lerp(a.shadowLight, b.shadowLight, t)!,
        shadowDark: Color.lerp(a.shadowDark, b.shadowDark, t)!,
        status: ClayStatusColors.lerp(a.status, b.status, t),
      );

  @override
  bool operator ==(Object other) =>
      other is ClayPalette &&
      other.brightness == brightness &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.background == background &&
      other.surface == surface &&
      other.surfacePressed == surfacePressed &&
      other.text == text &&
      other.textMuted == textMuted &&
      other.outline == outline &&
      other.shadowLight == shadowLight &&
      other.shadowDark == shadowDark &&
      other.status == status;

  @override
  int get hashCode => Object.hash(
    brightness,
    accent,
    onAccent,
    background,
    surface,
    surfacePressed,
    text,
    textMuted,
    outline,
    shadowLight,
    shadowDark,
    status,
  );
}
