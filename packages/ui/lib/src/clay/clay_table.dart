import 'package:flutter/material.dart';

import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'clay_container.dart';
import 'clay_display.dart';

/// عمود في [ClayTable]. [flex] عرض نسبي، و[width] عرض ثابت يتقدم عليه.
class ClayColumn<T> {
  const ClayColumn({
    required this.title,
    required this.cell,
    this.flex = 1,
    this.width,
    this.numeric = false,
  });

  final String title;

  /// يبني خلية الصف. للنص البسيط استعمل `Text`.
  final Widget Function(BuildContext context, T row) cell;
  final int flex;
  final double? width;

  /// الأرقام تُحاذى إلى نهاية الخلية وتُكتب يسار-يمين.
  final bool numeric;
}

/// جدول عريض لنسخة Windows: رأس ثابت وصفوف في `ListView.builder` بارتفاع
/// ثابت (فيبقى التمرير سلساً مهما كثرت الصفوف).
class ClayTable<T> extends StatelessWidget {
  const ClayTable({
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.rowHeight = 52,
    this.emptyTitle = 'لا توجد بيانات',
    super.key,
  }) : assert(rowHeight >= 40, 'ارتفاع الصف 40 على الأقل');

  final List<ClayColumn<T>> columns;
  final List<T> rows;
  final ValueChanged<T>? onRowTap;
  final double rowHeight;
  final String emptyTitle;

  Widget _cells(BuildContext context, T? row, {required TextStyle? style}) {
    return Row(
      children: [
        for (final column in columns)
          _sized(
            column,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ClaySpacing.sm),
              child: Align(
                alignment: column.numeric
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: row == null
                    ? Text(
                        column.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      )
                    : Directionality(
                        textDirection: column.numeric
                            ? TextDirection.ltr
                            : Directionality.of(context),
                        child: column.cell(context, row),
                      ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sized(ClayColumn<T> column, Widget child) => column.width != null
      ? SizedBox(width: column.width, child: child)
      : Expanded(flex: column.flex, child: child);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return ClayContainer(
      padding: const EdgeInsets.all(ClaySpacing.xs),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: p.surfacePressed,
                borderRadius: BorderRadius.circular(ClayRadius.md),
              ),
              child: Semantics(
                header: true,
                child: _cells(
                  context,
                  null,
                  style: text.labelLarge!.copyWith(color: p.textMuted),
                ),
              ),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? ClayEmptyView(title: emptyTitle)
                : ListView.builder(
                    itemCount: rows.length,
                    itemExtent: rowHeight,
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      final content = DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: p.outline.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                        child: _cells(context, row, style: null),
                      );
                      if (onRowTap == null) return content;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onRowTap!(row),
                        child: content,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
