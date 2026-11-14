import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/clay_colors.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'clay_container.dart';
import 'clay_display.dart';

/// ألوان سلاسل الرسوم البيانية: متمايزة ومقروءة على سطح التطبيق.
abstract final class ClayChartColors {
  /// ألوان السلاسل بالترتيب: الرئيسي ثم ألوان الحالات.
  static List<Color> series(ClayPalette p) => [
    p.accent,
    p.status.success,
    p.status.warning,
    p.status.excused,
    p.status.info,
    p.status.danger,
  ];

  /// لون السلسلة رقم [index]، ويدور إن زادت عن الألوان.
  static Color at(ClayPalette p, int index) {
    final colors = series(p);
    return colors[index % colors.length];
  }

  /// لون الشبكة والمحاور.
  static Color grid(ClayPalette p) => p.outline.withValues(alpha: 0.5);
}

/// عنصر في دليل الرسم.
class ClayLegendItem {
  const ClayLegendItem({required this.label, required this.color});

  final String label;
  final Color color;
}

/// سلسلة أعمدة واحدة في [ClayBarChart].
class ClayBarSeries {
  const ClayBarSeries({
    required this.label,
    required this.color,
    required this.values,
  });

  final String label;
  final Color color;
  final List<int> values;
}

/// أعمدة مجمّعة بفئات ثابتة؛ مفيد للمقارنة الشهرية وسهل القراءة على الهاتف.
class ClayBarChart extends StatelessWidget {
  ClayBarChart({
    required this.categories,
    required this.series,
    this.valueLabel = _defaultValueLabel,
    this.height = 180,
    super.key,
  }) : assert(series.isNotEmpty),
       assert(series.every((item) => item.values.length == categories.length));

  final List<String> categories;
  final List<ClayBarSeries> series;
  final String Function(int value) valueLabel;
  final double height;

  static String _defaultValueLabel(int value) => '$value';

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    final valuesDescription = [
      for (final item in series)
        '${item.label}: ${item.values.map(valueLabel).join('، ')}',
    ].join('. ');
    return Semantics(
      label: 'مخطط بالأعمدة. $valuesDescription',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // الشهر العربي الكامل يحتاج مساحة كافية كي لا يُقصّ اسم الفئة.
            final width = math.max(
              math.max(600.0, categories.length * 64.0 + 60),
              constraints.maxWidth,
            );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                height: height,
                child: CustomPaint(
                  painter: _ClayBarChartPainter(
                    categories: categories,
                    series: series,
                    gridColor: ClayChartColors.grid(palette),
                    labelStyle: text.labelSmall!.copyWith(
                      color: palette.textMuted,
                    ),
                    valueLabel: valueLabel,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ClayBarChartPainter extends CustomPainter {
  const _ClayBarChartPainter({
    required this.categories,
    required this.series,
    required this.gridColor,
    required this.labelStyle,
    required this.valueLabel,
  });

  final List<String> categories;
  final List<ClayBarSeries> series;
  final Color gridColor;
  final TextStyle labelStyle;
  final String Function(int value) valueLabel;

  @override
  void paint(Canvas canvas, Size size) {
    const right = 6.0;
    const top = 8.0;
    const bottom = 28.0;
    final maxValue = series
        .expand((item) => item.values)
        .fold<int>(0, (max, value) => value > max ? value : max);
    final scale = maxValue == 0 ? 1 : maxValue;
    var left = 54.0;
    for (var tick = 0; tick <= 4; tick++) {
      final label = TextPainter(
        text: TextSpan(
          text: valueLabel((scale * tick / 4).round()),
          style: labelStyle,
        ),
        textDirection: TextDirection.rtl,
        maxLines: 1,
      )..layout();
      left = math.max(left, label.width + 12);
    }
    final plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    if (plot.width <= 0 || plot.height <= 0) return;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var tick = 0; tick <= 4; tick++) {
      final fraction = tick / 4;
      final y = plot.bottom - plot.height * fraction;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _drawLabel(
        canvas,
        valueLabel((scale * fraction).round()),
        Offset(0, y - 7),
        width: left - 8,
        align: TextAlign.end,
      );
    }

    final categoryWidth = plot.width / categories.length;
    final clusterWidth = categoryWidth * 0.74;
    final gap = series.length > 1 ? 3.0 : 0.0;
    final barWidth = math.max(
      2.0,
      (clusterWidth - gap * (series.length - 1)) / series.length,
    );
    for (var category = 0; category < categories.length; category++) {
      final clusterLeft =
          plot.left +
          category * categoryWidth +
          (categoryWidth - clusterWidth) / 2;
      for (var index = 0; index < series.length; index++) {
        final item = series[index];
        final value = item.values[category];
        final barHeight = plot.height * value / scale;
        final rect = Rect.fromLTWH(
          clusterLeft + index * (barWidth + gap),
          plot.bottom - barHeight,
          barWidth,
          math.max(0, barHeight),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()..color = item.color,
        );
      }
      _drawLabel(
        canvas,
        categories[category],
        Offset(plot.left + category * categoryWidth, plot.bottom + 5),
        width: categoryWidth,
        align: TextAlign.center,
      );
    }
  }

  void _drawLabel(
    Canvas canvas,
    String value,
    Offset position, {
    required double width,
    required TextAlign align,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: labelStyle),
      textDirection: TextDirection.rtl,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width);
    painter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _ClayBarChartPainter oldDelegate) =>
      oldDelegate.categories != categories ||
      oldDelegate.series != series ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.valueLabel != valueLabel;
}

/// دليل الرسم: نقطة ملوّنة واسم لكل سلسلة.
class ClayChartLegend extends StatelessWidget {
  const ClayChartLegend({required this.items, super.key});

  final List<ClayLegendItem> items;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: ClaySpacing.lg,
      runSpacing: ClaySpacing.xs,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: ClaySpacing.xs),
              Text(item.label, style: text.bodySmall),
            ],
          ),
      ],
    );
  }
}

/// بطاقة تغلّف أي رسم بياني: عنوان، دليل، وارتفاع ثابت للرسم.
///
/// الرسم نفسه يأتي من المستدعي (مكتبة الرسوم التي تُعتمد في المهمة 6.5)،
/// وهذا الغلاف يضمن شكلاً واحداً وحالات تحميل وفراغ وخطأ موحّدة.
class ClayChartCard extends StatelessWidget {
  const ClayChartCard({
    required this.title,
    required this.chart,
    this.subtitle,
    this.legend = const [],
    this.height = 220,
    this.loading = false,
    this.isEmpty = false,
    this.error,
    this.onRetry,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget chart;
  final List<ClayLegendItem> legend;
  final double height;
  final bool loading;

  /// لا بيانات لعرضها.
  final bool isEmpty;

  /// رسالة خطأ؛ وجودها يحجب الرسم.
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final chartShown = !loading && error == null && !isEmpty;
    final Widget body;
    if (loading) {
      body = const ClayLoadingView();
    } else if (error != null) {
      body = ClayErrorView(message: error!, onRetry: onRetry);
    } else if (isEmpty) {
      body = const ClayEmptyView(
        title: 'لا توجد بيانات للفترة',
        icon: Icons.bar_chart_rounded,
      );
    } else {
      body = chart;
    }
    return ClayContainer(
      padding: const EdgeInsets.all(ClaySpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(header: true, child: Text(title, style: text.titleMedium)),
          if (subtitle != null)
            Text(
              subtitle!,
              style: text.bodySmall!.copyWith(color: p.textMuted),
            ),
          const SizedBox(height: ClaySpacing.md),
          // حالات الخطأ والفراغ تحتاج مساحة لزر «إعادة المحاولة».
          SizedBox(
            height: chartShown ? height : (height < 260 ? 260 : height),
            child: body,
          ),
          if (legend.isNotEmpty && chartShown) ...[
            const SizedBox(height: ClaySpacing.md),
            ClayChartLegend(items: legend),
          ],
        ],
      ),
    );
  }
}
