import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../clay/clay_button.dart';
import '../clay/clay_container.dart';
import '../clay/clay_display.dart';
import '../clay/clay_icons.dart';
import '../clay/clay_inputs.dart';
import '../clay/clay_navigation.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';

/// صف في قائمة: عنوان، سطر ثانٍ، وإجراءات في نهايته. الصف كله قابل للنقر
/// إن مُرّر [onTap].
class ClayListTile extends StatelessWidget {
  const ClayListTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing = const [],
    this.onTap,
    this.subtitleLines = 1,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// عدد أسطر السطر الثاني (يُقتطع بعدها)؛ الصف يحتاج ارتفاعاً يتسع لها.
  final int subtitleLines;
  final Widget? leading;
  final List<Widget> trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
      child: ClayCard(
        flat: true,
        onTap: onTap,
        semanticLabel: subtitle == null ? title : '$title، $subtitle',
        padding: const EdgeInsets.symmetric(
          horizontal: ClaySpacing.md,
          vertical: ClaySpacing.xs,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: ClaySpacing.md),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: subtitleLines,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall!.copyWith(color: p.textMuted),
                    ),
                ],
              ),
            ),
            ...trailing,
          ],
        ),
      ),
    );
  }
}

/// صفحة قائمة قياسية: شريط عنوان، بحث اختياري، قائمة بارتفاع ثابت
/// (`ListView.builder`)، حالات التحميل والفراغ والخطأ، وزر إضافة.
class ClayListPage<T> extends StatefulWidget {
  const ClayListPage({
    required this.title,
    required this.data,
    required this.itemBuilder,
    required this.emptyTitle,
    this.emptyMessage,
    this.itemExtent = 72,
    this.addLabel,
    this.onAdd,
    this.searchHint,
    this.matches,
    this.onRetry,
    super.key,
  }) : assert(
         (searchHint == null) == (matches == null),
         'البحث يحتاج searchHint و matches معاً',
       );

  final String title;
  final AsyncValue<List<T>> data;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyTitle;
  final String? emptyMessage;
  final double itemExtent;

  /// نص زر الإضافة؛ يظهر الزر إن وُجد مع [onAdd] غير الفارغ.
  final String? addLabel;
  final VoidCallback? onAdd;

  /// يفعّل البحث: النص التلميحي، ودالة تقرر إن كان العنصر يطابق الاستعلام.
  final String? searchHint;
  final bool Function(T item, String query)? matches;
  final VoidCallback? onRetry;

  @override
  State<ClayListPage<T>> createState() => _ClayListPageState<T>();
}

class _ClayListPageState<T> extends State<ClayListPage<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final canAdd = widget.addLabel != null && widget.onAdd != null;
    return Scaffold(
      appBar: ClayAppBar(title: widget.title, showBack: true),
      body: Column(
        children: [
          if (widget.searchHint != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ClaySpacing.screenPadding,
                0,
                ClaySpacing.screenPadding,
                ClaySpacing.sm,
              ),
              child: ClayTextField(
                hint: widget.searchHint,
                prefixIcon: ClayIcons.search,
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
          Expanded(
            child: widget.data.when(
              loading: () => const ClayLoadingView(),
              error: (_, _) => ClayErrorView(
                message: 'تعذّرت قراءة البيانات من القاعدة المحلية',
                onRetry: widget.onRetry,
              ),
              data: (items) {
                final shown = widget.matches == null || _query.isEmpty
                    ? items
                    : [
                        for (final item in items)
                          if (widget.matches!(item, _query)) item,
                      ];
                if (shown.isEmpty) {
                  return ClayEmptyView(
                    title: items.isEmpty
                        ? widget.emptyTitle
                        : 'لا نتائج مطابقة للبحث',
                    message: items.isEmpty ? widget.emptyMessage : null,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ClaySpacing.screenPadding,
                  ),
                  itemCount: shown.length,
                  itemExtent: widget.itemExtent,
                  itemBuilder: (context, i) =>
                      widget.itemBuilder(context, shown[i]),
                );
              },
            ),
          ),
          if (canAdd)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                child: ClayButton(
                  label: widget.addLabel!,
                  icon: ClayIcons.add,
                  expand: true,
                  onPressed: widget.onAdd,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
