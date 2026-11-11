import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';

/// شكل سطح الطين: بارز (يبدو منفوخاً) أو غائر (مضغوط).
enum ClayDepth { raised, pressed }

/// يرسم سطح claymorphism: ظل فاتح من أعلى اليسار وداكن من أسفل اليمين
/// خلف سطح ناعم. الغائر يرسم الظلين داخل السطح.
///
/// الرسم كله في [CustomPainter] واحد (لا طبقات `BoxShadow` متعددة ولا
/// `BackdropFilter`)، ويُغلَّف بـ [RepaintBoundary] فيُخزَّن مرة واحدة ولا
/// يُعاد رسمه عند تحريك ما حوله.
class ClaySurfacePainter extends CustomPainter {
  const ClaySurfacePainter({
    required this.color,
    required this.shadowLight,
    required this.shadowDark,
    required this.radius,
    required this.depth,
    required this.elevation,
  });

  final Color color;
  final Color shadowLight;
  final Color shadowDark;
  final double radius;
  final ClayDepth depth;

  /// إزاحة الظل وتشويشه بالبكسل المنطقي.
  final double elevation;

  /// أقصى ما يتجاوزه الظل خارج حدود السطح، ليحجز [ClayContainer] مكانه.
  static double bleed(double elevation) => elevation * 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(math.min(radius, size.shortestSide / 2)),
    );
    final sigma = elevation * 0.8;
    if (depth == ClayDepth.raised) {
      canvas
        ..drawRRect(
          rrect.shift(Offset(elevation, elevation)),
          Paint()
            ..color = shadowDark
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
        )
        ..drawRRect(
          rrect.shift(Offset(-elevation, -elevation)),
          Paint()
            ..color = shadowLight
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
        )
        ..drawRRect(rrect, Paint()..color = color);
      return;
    }
    // غائر: يُقصّ الرسم داخل السطح، وتُرسم حلقة خارجه ببلورة فتظهر ظلالاً
    // داخلية.
    canvas
      ..save()
      ..clipRRect(rrect)
      ..drawRRect(rrect, Paint()..color = color);
    final outside = Path()
      ..addRect(rrect.outerRect.inflate(bleed(elevation) + 8))
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas
      ..drawPath(
        outside.shift(Offset(elevation, elevation)),
        Paint()
          ..color = shadowDark
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
      )
      ..drawPath(
        outside.shift(Offset(-elevation, -elevation)),
        Paint()
          ..color = shadowLight
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(ClaySurfacePainter old) =>
      old.color != color ||
      old.shadowLight != shadowLight ||
      old.shadowDark != shadowDark ||
      old.radius != radius ||
      old.depth != depth ||
      old.elevation != elevation;
}

/// حاوية بسطح طيني. الاختيار بين النسختين:
///
/// - [ClayContainer]: الأصلية بالظلال المرسومة، للعناصر القليلة (أزرار،
///   بطاقات الرئيسية، حوارات).
/// - [ClayContainer.flat]: المبسّطة (لون وحدّ فقط) لعناصر القوائم الطويلة،
///   فلا يُرسم تشويش لكل صف أثناء التمرير.
class ClayContainer extends StatelessWidget {
  const ClayContainer({
    this.child,
    this.padding,
    this.radius = ClayRadius.lg,
    this.depth = ClayDepth.raised,
    this.color,
    this.elevation = 6,
    this.width,
    this.height,
    this.alignment,
    super.key,
  }) : flat = false;

  /// النسخة المبسطة للقوائم: بلا تشويش ولا ظلال مرسومة.
  const ClayContainer.flat({
    this.child,
    this.padding,
    this.radius = ClayRadius.md,
    this.color,
    this.width,
    this.height,
    this.alignment,
    super.key,
  }) : flat = true,
       depth = ClayDepth.raised,
       elevation = 0;

  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final ClayDepth depth;

  /// يستبدل لون السطح (مثلاً اللون الرئيسي في الأزرار).
  final Color? color;

  /// إزاحة الظل بالبكسل؛ 0 يعني بلا ظل.
  final double elevation;
  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;

  /// هل هي النسخة المبسطة؟
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fill =
        color ?? (depth == ClayDepth.pressed ? p.surfacePressed : p.surface);
    final inner = Container(
      width: width,
      height: height,
      alignment: alignment,
      padding: padding,
      child: child,
    );
    if (flat) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: p.outline.withValues(alpha: 0.5)),
        ),
        child: inner,
      );
    }
    return RepaintBoundary(
      child: Padding(
        // مساحة للظل خارج السطح حتى لا يُقصّ.
        padding: EdgeInsets.all(ClaySurfacePainter.bleed(elevation) / 2),
        child: CustomPaint(
          painter: ClaySurfacePainter(
            color: fill,
            shadowLight: p.shadowLight,
            shadowDark: p.shadowDark,
            radius: radius,
            depth: depth,
            elevation: elevation,
          ),
          child: inner,
        ),
      ),
    );
  }
}

/// بطاقة: [ClayContainer] بحشوة افتراضية، وتتحول إلى زر إن مُرّر [onTap].
class ClayCard extends StatelessWidget {
  const ClayCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(ClaySpacing.lg),
    this.radius = ClayRadius.lg,
    this.flat = false,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// للبطاقات داخل القوائم الطويلة.
  final bool flat;

  /// وصف لقارئ الشاشة عندما تكون البطاقة قابلة للنقر.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final surface = flat
        ? ClayContainer.flat(radius: radius, padding: padding, child: child)
        : ClayContainer(radius: radius, padding: padding, child: child);
    if (onTap == null) return surface;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: surface,
      ),
    );
  }
}
