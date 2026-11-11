import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

Widget host(Widget child, {ThemeMode mode = ThemeMode.light}) => ClayApp(
  app: AppIdentity.admin,
  themeMode: mode,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('ClaySurfacePainter', () {
    ClaySurfacePainter painter({
      Color color = Colors.white,
      double radius = 20,
      ClayDepth depth = ClayDepth.raised,
      double elevation = 6,
    }) => ClaySurfacePainter(
      color: color,
      shadowLight: Colors.white,
      shadowDark: Colors.black,
      radius: radius,
      depth: depth,
      elevation: elevation,
    );

    test('shouldRepaint يتغير مع أي خاصية فقط', () {
      final base = painter();
      expect(base.shouldRepaint(painter()), isFalse);
      expect(base.shouldRepaint(painter(color: Colors.red)), isTrue);
      expect(base.shouldRepaint(painter(radius: 10)), isTrue);
      expect(base.shouldRepaint(painter(depth: ClayDepth.pressed)), isTrue);
      expect(base.shouldRepaint(painter(elevation: 2)), isTrue);
    });

    test('مساحة الظل المحجوزة تتناسب مع الارتفاع', () {
      expect(ClaySurfacePainter.bleed(0), 0);
      expect(ClaySurfacePainter.bleed(6), 12);
    });

    for (final depth in ClayDepth.values) {
      testWidgets('الرسم ${depth.name} لا يرمي حتى بحجم صفري أو صغير', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            Column(
              children: [
                ClayContainer(depth: depth, width: 0, height: 0),
                ClayContainer(depth: depth, width: 4, height: 4, radius: 100),
                ClayContainer(depth: depth, width: 120, height: 60),
              ],
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ClayContainer', () {
    testWidgets(
      'الأصلية: CustomPaint داخل RepaintBoundary، بلا BackdropFilter',
      (tester) async {
        await tester.pumpWidget(
          host(const ClayContainer(width: 100, height: 80, child: Text('أ'))),
        );
        final boundary = find.ancestor(
          of: find.byType(CustomPaint),
          matching: find.byType(RepaintBoundary),
        );
        expect(boundary, findsWidgets);
        expect(
          find.descendant(
            of: find.byType(ClayContainer),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.text('أ'), findsOneWidget);
      },
    );

    testWidgets('المبسّطة: بلا CustomPaint ولا RepaintBoundary إضافي', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ClayContainer.flat(width: 100, height: 40, child: Text('ب')),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(ClayContainer),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(ClayContainer),
          matching: find.byType(RepaintBoundary),
        ),
        findsNothing,
      );
      expect(find.text('ب'), findsOneWidget);
    });

    testWidgets('يعمل في الوضعين الفاتح والداكن', (tester) async {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.pumpWidget(
          host(const ClayContainer(width: 50, height: 50), mode: mode),
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('الحجم يشمل مساحة الظل ويحترم الحجم المطلوب للسطح', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const ClayContainer(width: 100, height: 60, elevation: 6)),
      );
      final size = tester.getSize(find.byType(ClayContainer));
      expect(size.width, 100 + 12);
      expect(size.height, 60 + 12);
    });
  });

  group('ClayCard', () {
    testWidgets('بلا onTap ليست زراً', (tester) async {
      await tester.pumpWidget(host(const ClayCard(child: Text('محتوى'))));
      expect(find.text('محتوى'), findsOneWidget);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('مع onTap تستجيب للنقر وتُعلن كزر', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          ClayCard(
            onTap: () => taps++,
            semanticLabel: 'بطاقة التلميذ',
            child: const Text('محتوى'),
          ),
        ),
      );
      await tester.tap(find.text('محتوى'));
      expect(taps, 1);
      final data = tester
          .getSemantics(find.byType(ClayCard))
          .getSemanticsData();
      expect(data.label, contains('بطاقة التلميذ'));
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
    });

    testWidgets('النسخة المبسطة للقوائم', (tester) async {
      await tester.pumpWidget(
        host(const ClayCard(flat: true, child: Text('صف'))),
      );
      expect(
        find.descendant(
          of: find.byType(ClayCard),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });
  });

  group('ClayButton', () {
    testWidgets('ينقر فيستدعي onPressed مرة واحدة', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(ClayButton(label: 'حفظ', onPressed: () => taps++)),
      );
      await tester.tap(find.text('حفظ'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('مساحة اللمس 48 بكسلاً على الأقل', (tester) async {
      await tester.pumpWidget(host(ClayButton(label: 'ن', onPressed: () {})));
      final size = tester.getSize(find.byType(ClayButton));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    });

    testWidgets('المعطّل (بلا onPressed) لا يستجيب ويُعلن معطّلاً', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const ClayButton(label: 'حفظ', onPressed: null)),
      );
      await tester.tap(find.text('حفظ'));
      await tester.pump();
      expect(
        tester.getSemantics(find.byType(ClayButton)),
        matchesSemantics(
          label: 'حفظ',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
    });

    testWidgets('أثناء التحميل: مؤشر دوّار ولا نقر ثانٍ', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(ClayButton(label: 'حفظ', loading: true, onPressed: () => taps++)),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('حفظ'));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('الأيقونة تظهر قبل النص', (tester) async {
      await tester.pumpWidget(
        host(ClayButton(label: 'إضافة', icon: Icons.add, onPressed: () {})),
      );
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(
        tester.getCenter(find.byIcon(Icons.add)).dx,
        greaterThan(tester.getCenter(find.text('إضافة')).dx),
        reason: 'RTL: الأيقونة على يمين النص',
      );
    });

    testWidgets('حركة الانضغاط: يصغر قليلاً أثناء اللمس ويعود', (tester) async {
      await tester.pumpWidget(host(ClayButton(label: 'ن', onPressed: () {})));
      double scale() =>
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
      expect(scale(), 1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ClayButton)),
      );
      await tester.pump();
      expect(scale(), lessThan(1));
      await gesture.up();
      await tester.pump();
      expect(scale(), 1);
    });

    testWidgets('إلغاء اللمس يعيد الحجم دون نقر', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(ClayButton(label: 'ن', onPressed: () => taps++)),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ClayButton)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, 300));
      await gesture.cancel();
      await tester.pump();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      expect(taps, 0);
    });

    testWidgets('الانضغاط يجعل السطح غائراً', (tester) async {
      await tester.pumpWidget(host(ClayButton(label: 'ن', onPressed: () {})));
      ClayDepth depth() =>
          tester.widget<ClayContainer>(find.byType(ClayContainer)).depth;
      expect(depth(), ClayDepth.raised);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ClayButton)),
      );
      await tester.pump();
      expect(depth(), ClayDepth.pressed);
      await gesture.up();
      await tester.pump();
      expect(depth(), ClayDepth.raised);
    });

    testWidgets('الأنواع الثلاثة بألوان مختلفة', (tester) async {
      final colors = <Color?>[];
      for (final kind in ClayButtonKind.values) {
        await tester.pumpWidget(
          host(ClayButton(label: 'ن', kind: kind, onPressed: () {})),
        );
        colors.add(
          tester.widget<ClayContainer>(find.byType(ClayContainer)).color,
        );
      }
      final p = ClayPalette.of(AppIdentity.admin, Brightness.light);
      expect(colors[0], p.accent);
      expect(colors[1], isNull);
      expect(colors[2], p.status.danger);
    });

    testWidgets('expand يملأ العرض', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 300,
            child: ClayButton(label: 'ن', expand: true, onPressed: () {}),
          ),
        ),
      );
      expect(tester.getSize(find.byType(ClayButton)).width, 300);
    });

    testWidgets('نص طويل لا يفيض', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 120,
            child: ClayButton(
              label: 'نص طويل جداً جداً لا يتسع في الزر أبداً',
              onPressed: () {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
