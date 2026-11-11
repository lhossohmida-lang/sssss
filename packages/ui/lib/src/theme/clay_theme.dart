import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:school_core/school_core.dart';

import 'clay_colors.dart';
import 'clay_tokens.dart';

/// رموز التصميم كاملة كامتداد لـ [ThemeData]: `ClayTheme.of(context)`.
@immutable
class ClayTheme extends ThemeExtension<ClayTheme> {
  const ClayTheme({required this.app, required this.palette});

  /// يبني الرموز لتطبيق [app] في الوضع [brightness].
  factory ClayTheme.of(AppIdentity app, Brightness brightness) =>
      ClayTheme(app: app, palette: ClayPalette.of(app, brightness));

  final AppIdentity app;
  final ClayPalette palette;

  @override
  ClayTheme copyWith({AppIdentity? app, ClayPalette? palette}) =>
      ClayTheme(app: app ?? this.app, palette: palette ?? this.palette);

  @override
  ClayTheme lerp(ThemeExtension<ClayTheme>? other, double t) {
    if (other is! ClayTheme) return this;
    return ClayTheme(
      app: t < 0.5 ? app : other.app,
      palette: ClayPalette.lerp(palette, other.palette, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClayTheme && other.app == app && other.palette == palette;

  @override
  int get hashCode => Object.hash(app, palette);
}

/// اختصار للوصول إلى رموز التصميم من أي ودجت.
extension ClayContext on BuildContext {
  /// الرموز الحالية. وجود [ClayThemeData.build] في أعلى الشجرة شرط.
  ClayTheme get clay {
    final theme = Theme.of(this).extension<ClayTheme>();
    assert(theme != null, 'استعمل ClayThemeData.build في MaterialApp.theme');
    return theme!;
  }

  /// لوحة الألوان الحالية.
  ClayPalette get palette => clay.palette;
}

/// يبني [ThemeData] لتطبيق من التطبيقات الثلاثة.
abstract final class ClayThemeData {
  /// الوضع الفاتح لتطبيق [app].
  static ThemeData light(AppIdentity app) => build(app, Brightness.light);

  /// الوضع الداكن لتطبيق [app].
  static ThemeData dark(AppIdentity app) => build(app, Brightness.dark);

  /// نمط نص بالخط Cairo مع محور الوزن المتغيّر.
  static TextStyle textStyle({
    required Color color,
    required double size,
    double weight = ClayFontWeight.regular,
    double height = 1.5,
  }) => TextStyle(
    fontFamily: clayFontFamily,
    package: clayFontPackage,
    fontSize: size,
    fontWeight: ClayFontWeight.asFontWeight(weight),
    fontVariations: [FontVariation.weight(weight)],
    height: height,
    color: color,
  );

  static TextTheme _textTheme(ClayPalette p) {
    TextStyle style(double size, double weight, {Color? color}) =>
        textStyle(color: color ?? p.text, size: size, weight: weight);
    return TextTheme(
      displaySmall: style(ClayFontSize.display, ClayFontWeight.bold),
      headlineMedium: style(ClayFontSize.headline, ClayFontWeight.bold),
      headlineSmall: style(ClayFontSize.headline, ClayFontWeight.semiBold),
      titleLarge: style(ClayFontSize.title, ClayFontWeight.bold),
      titleMedium: style(ClayFontSize.bodyLarge, ClayFontWeight.semiBold),
      titleSmall: style(ClayFontSize.body, ClayFontWeight.semiBold),
      bodyLarge: style(ClayFontSize.bodyLarge, ClayFontWeight.regular),
      bodyMedium: style(ClayFontSize.body, ClayFontWeight.regular),
      bodySmall: style(
        ClayFontSize.caption,
        ClayFontWeight.regular,
        color: p.textMuted,
      ),
      labelLarge: style(ClayFontSize.body, ClayFontWeight.semiBold),
      labelMedium: style(ClayFontSize.caption, ClayFontWeight.medium),
      labelSmall: style(
        ClayFontSize.caption,
        ClayFontWeight.medium,
        color: p.textMuted,
      ),
    );
  }

  /// يبني الثيم الكامل. الخط Cairo والاتجاه من اليمين إلى اليسار يضبطهما
  /// [ClayApp] (الاتجاه) وهذا الثيم (الخط والألوان).
  static ThemeData build(AppIdentity app, Brightness brightness) {
    final p = ClayPalette.of(app, brightness);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.accent,
      onPrimary: p.onAccent,
      secondary: p.accent,
      onSecondary: p.onAccent,
      error: p.status.danger,
      onError: p.onAccent,
      surface: p.surface,
      onSurface: p.text,
      outline: p.outline,
      surfaceContainerHighest: p.surfacePressed,
      onSurfaceVariant: p.textMuted,
    );
    final text = _textTheme(p);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      textTheme: text,
      primaryTextTheme: text,
      fontFamily: clayFontFamily,
      package: clayFontPackage,
      fontFamilyFallback: const ['Roboto'],
      dividerColor: p.outline,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      extensions: [ClayTheme(app: app, palette: p)],
    );
  }
}

/// جذر التطبيق: عربي (الجزائر)، من اليمين إلى اليسار، بثيم التطبيق الفاتح
/// أو الداكن حسب نظام الجهاز.
class ClayApp extends StatelessWidget {
  const ClayApp({
    required this.app,
    this.home,
    this.routerConfig,
    this.themeMode = ThemeMode.system,
    this.title,
    super.key,
  }) : assert(
         (home != null) != (routerConfig != null),
         'حدّد home أو routerConfig واحداً منهما',
       );

  final AppIdentity app;
  final Widget? home;
  final RouterConfig<Object>? routerConfig;
  final ThemeMode themeMode;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final common = (
      title: title ?? app.displayName,
      theme: ClayThemeData.light(app),
      darkTheme: ClayThemeData.dark(app),
      themeMode: themeMode,
      locale: AppIdentity.locale,
    );
    Widget rtl(BuildContext context, Widget? child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!);
    if (routerConfig != null) {
      return MaterialApp.router(
        title: common.title,
        theme: common.theme,
        darkTheme: common.darkTheme,
        themeMode: common.themeMode,
        locale: common.locale,
        supportedLocales: const [AppIdentity.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: rtl,
        routerConfig: routerConfig,
        debugShowCheckedModeBanner: false,
      );
    }
    return MaterialApp(
      title: common.title,
      theme: common.theme,
      darkTheme: common.darkTheme,
      themeMode: common.themeMode,
      locale: common.locale,
      supportedLocales: const [AppIdentity.locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: rtl,
      home: home,
      debugShowCheckedModeBanner: false,
    );
  }
}
