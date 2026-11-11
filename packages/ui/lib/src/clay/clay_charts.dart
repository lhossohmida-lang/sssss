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
