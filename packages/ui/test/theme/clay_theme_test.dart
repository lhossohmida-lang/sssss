import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// نسبة التباين بين لونين وفق WCAG.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const apps = AppIdentity.values;
  const modes = Brightness.values;

  group('اللوحات', () {
    for (final app in apps) {
      for (final mode in modes) {
        final name = '${app.name} ${mode.name}';
        final p = ClayPalette.of(app, mode);

        test('$name: النص مقروء على الخلفية والسطح (4.5 على الأقل)', () {
          for (final surface in [p.background, p.surface]) {
            expect(contrast(p.text, surface), greaterThanOrEqualTo(4.5));
            expect(contrast(p.textMuted, surface), greaterThanOrEqualTo(4.5));
          }
        });

        test('$name: اللون الرئيسي مقروء كنص وفوقه نص مقروء', () {
          expect(contrast(p.accent, p.background), greaterThanOrEqualTo(4.5));
          expect(contrast(p.accent, p.surface), greaterThanOrEqualTo(4.5));
          expect(contrast(p.onAccent, p.accent), greaterThanOrEqualTo(4.5));
        });

        test('$name: ألوان الحالات مقروءة على السطح والخلفية', () {
          final s = p.status;
          for (final color in [
            s.success,
            s.danger,
            s.warning,
            s.info,
            s.excused,
          ]) {
            expect(contrast(color, p.surface), greaterThanOrEqualTo(4.5));
            expect(contrast(color, p.background), greaterThanOrEqualTo(4.5));
          }
        });

        test('$name: الظل الفاتح أفتح من السطح والداكن أغمق منه', () {
          expect(
            p.shadowLight.computeLuminance(),
            greaterThan(p.surface.computeLuminance()),
          );
          expect(
            p.shadowDark.computeLuminance(),
            lessThan(p.surface.computeLuminance()),
          );
          expect(
            p.surfacePressed.computeLuminance(),
            lessThan(p.surface.computeLuminance()),
          );
        });
      }
    }

    test('لكل تطبيق لون رئيسي مختلف في كل وضع', () {
      for (final mode in modes) {
        final accents = {
          for (final app in apps) ClayPalette.accentFor(app, mode),
        };
        expect(accents.length, apps.length);
      }
    });

    test('الوضع الداكن أغمق من الفاتح', () {
      for (final app in apps) {
        expect(
          ClayPalette.of(app, Brightness.dark).background.computeLuminance(),
          lessThan(
            ClayPalette.of(app, Brightness.light).background.computeLuminance(),
          ),
        );
      }
    });

    test('ألوان الحضور والطلبات تغطي كل الحالات بألوان مختلفة', () {
      const status = ClayStatusColors.light;
      final attendance = {
        for (final s in AttendanceStatus.values) status.forAttendance(s),
      };
      expect(attendance.length, AttendanceStatus.values.length);
      final requests = {
        for (final s in SessionRequestStatus.values) status.forRequest(s),
      };
      expect(requests.length, SessionRequestStatus.values.length);
      expect(status.forAttendance(AttendanceStatus.present), status.success);
      expect(status.forAttendance(AttendanceStatus.absent), status.danger);
    });

    test('lerp بين الفاتح والداكن يبلغ الطرفين', () {
      final a = ClayPalette.of(AppIdentity.admin, Brightness.light);
      final b = ClayPalette.of(AppIdentity.admin, Brightness.dark);
      expect(ClayPalette.lerp(a, b, 0), a);
      expect(ClayPalette.lerp(a, b, 1), b);
      expect(ClayPalette.lerp(a, b, 0.5), isNot(a));
    });
  });

  group('الرموز', () {
    test('المسافات والزوايا متصاعدة ومضاعفات شبكة 4 للمسافات', () {
      const spaces = [
        ClaySpacing.xs,
        ClaySpacing.sm,
        ClaySpacing.md,
        ClaySpacing.lg,
        ClaySpacing.xl,
        ClaySpacing.xxl,
        ClaySpacing.huge,
      ];
      for (var i = 1; i < spaces.length; i++) {
        expect(spaces[i], greaterThan(spaces[i - 1]));
        expect(spaces[i] % 4, 0);
      }
      expect(ClayRadius.sm, lessThan(ClayRadius.md));
      expect(ClayRadius.md, lessThan(ClayRadius.lg));
      expect(ClayRadius.lg, lessThan(ClayRadius.xl));
      expect(ClaySpacing.minTouchTarget, greaterThanOrEqualTo(48));
    });

    test('تحويل وزن الخط إلى FontWeight', () {
      expect(ClayFontWeight.asFontWeight(400), FontWeight.w400);
      expect(ClayFontWeight.asFontWeight(500), FontWeight.w500);
      expect(ClayFontWeight.asFontWeight(600), FontWeight.w600);
      expect(ClayFontWeight.asFontWeight(700), FontWeight.w700);
      expect(ClayFontWeight.asFontWeight(10), FontWeight.w100);
      expect(ClayFontWeight.asFontWeight(2000), FontWeight.w900);
    });
  });

  group('ThemeData', () {
    for (final app in apps) {
      for (final mode in modes) {
        test('${app.name} ${mode.name}: ألوان وخط Cairo وامتداد الرموز', () {
          final theme = ClayThemeData.build(app, mode);
          final p = ClayPalette.of(app, mode);
          expect(theme.brightness, mode);
          expect(theme.colorScheme.primary, p.accent);
          expect(theme.scaffoldBackgroundColor, p.background);
          expect(theme.extension<ClayTheme>()!.app, app);
          expect(theme.extension<ClayTheme>()!.palette, p);
          expect(theme.useMaterial3, isTrue);
          for (final style in [
            theme.textTheme.bodyMedium!,
            theme.textTheme.titleLarge!,
            theme.textTheme.labelSmall!,
          ]) {
            expect(style.fontFamily, contains(clayFontFamily));
            expect(style.fontVariations, isNotEmpty);
          }
        });
      }
    }

    test('النص الأساسي بلون النص، والثانوي بلون النص الباهت', () {
      final p = ClayPalette.of(AppIdentity.teacher, Brightness.light);
      final theme = ClayThemeData.light(AppIdentity.teacher);
      expect(theme.textTheme.bodyMedium!.color, p.text);
      expect(theme.textTheme.bodySmall!.color, p.textMuted);
    });

    test('الخط Cairo مضمَّن في الحزمة ومعلَن في pubspec', () {
      final font = File('assets/fonts/Cairo.ttf');
      expect(font.existsSync(), isTrue);
      expect(font.lengthSync(), greaterThan(100000));
      expect(File('assets/fonts/OFL.txt').existsSync(), isTrue);
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/fonts/Cairo.ttf'));
    });

    test('lerp يبدّل التطبيق والألوان', () {
      final a = ClayTheme.of(AppIdentity.admin, Brightness.light);
      final b = ClayTheme.of(AppIdentity.admin, Brightness.dark);
      expect(a.lerp(b, 1), b);
      expect(a.lerp(b, 0), a);
      expect(a.lerp(null, 0.5), a);
      expect(a.copyWith(app: AppIdentity.student).app, AppIdentity.student);
    });
  });

  group('ClayApp', () {
    for (final app in apps) {
      testWidgets('${app.name}: عربي RTL بثيم التطبيق', (tester) async {
        late BuildContext captured;
        await tester.pumpWidget(
          ClayApp(
            app: app,
            home: Builder(
              builder: (context) {
                captured = context;
                return const Scaffold(body: Text('مرحباً'));
              },
            ),
          ),
        );
        expect(Directionality.of(captured), TextDirection.rtl);
        expect(Localizations.localeOf(captured), AppIdentity.locale);
        expect(captured.clay.app, app);
        expect(
          captured.palette.accent,
          ClayPalette.accentFor(app, Brightness.light),
        );
        expect(find.text('مرحباً'), findsOneWidget);
      });
    }

    testWidgets('الوضع الداكن يطبّق اللوحة الداكنة', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        ClayApp(
          app: AppIdentity.admin,
          themeMode: ThemeMode.dark,
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(captured.palette.isDark, isTrue);
    });

    testWidgets('العنوان الافتراضي اسم التطبيق', (tester) async {
      await tester.pumpWidget(
        const ClayApp(app: AppIdentity.student, home: SizedBox()),
      );
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
        'وليّ التلميذ',
      );
    });

    testWidgets('يدعم routerConfig', (tester) async {
      final router = RouterConfig<Object>(
        routeInformationProvider: PlatformRouteInformationProvider(
          initialRouteInformation: RouteInformation(uri: Uri.parse('/')),
        ),
        routeInformationParser: _Parser(),
        routerDelegate: _Delegate(),
      );
      await tester.pumpWidget(
        ClayApp(app: AppIdentity.admin, routerConfig: router),
      );
      expect(find.text('صفحة'), findsOneWidget);
    });
  });
}

class _Parser extends RouteInformationParser<Object> {
  @override
  Future<Object> parseRouteInformation(
    RouteInformation routeInformation,
  ) async => Object();
}

class _Delegate extends RouterDelegate<Object>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Object> {
  @override
  final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => const Directionality(
    textDirection: TextDirection.rtl,
    child: Text('صفحة'),
  );

  @override
  Future<void> setNewRoutePath(Object configuration) async {}
}
