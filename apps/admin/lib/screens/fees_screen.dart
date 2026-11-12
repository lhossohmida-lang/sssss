import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// حقوق التسجيل: مرة لكل تلميذ في الفترة (سنة أو فصل) مهما كانت موادّه.
/// تُعرض لفترة مختارة (الجارية افتراضياً) بحالة كل تلميذ، وملخص المطلوب
/// والمحصَّل والباقي، وزر دفع لمن بقي عليه شيء.
class FeesScreen extends ConsumerStatefulWidget {
  const FeesScreen({super.key});

  @override
  ConsumerState<FeesScreen> createState() => _FeesScreenState();
}

class _FeesScreenState extends ConsumerState<FeesScreen> {
  Timer? _debounce;
  String _query = '';
  String? _period;
  bool _unpaidOnly = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final settings = ref.watch(schoolSettingsProvider).value;
    final stored = ref.watch(feePeriodsProvider).value ?? const <String>[];
    final current = settings?.feePeriodKey(DateKey.of(DateTime.now()));
    // الفترة الجارية أولاً حتى لو لم تُسجَّل فيها حقوق بعد.
    final periods = <String>{?current, ...stored}.toList()
      ..sort((a, b) => b.compareTo(a));
    final period = _period ?? current ?? (stored.isEmpty ? null : stored.first);
    final canReceive = ref.can(
      PermissionModule.receiveMoney,
      PermissionAction.use,
    );
    final report = period == null
        ? null
        : ref.watch(
            feeReportProvider((
              period: period,
              unpaidOnly: _unpaidOnly,
              query: _query,
            )),
          );

    return Scaffold(
      appBar: const ClayAppBar(title: 'حقوق التسجيل', showBack: true),
      body: period == null
          ? const ClayEmptyView(
              title: 'لا فترات بعد',
              message: 'تظهر الفترة بعد تسجيل أول تلميذ',
              icon: ClayIcons.payments,
            )
          : Column(
              children: [
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: ClaySpacing.screenPadding,
                    ),
                    children: [
                      for (final key in periods)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            end: ClaySpacing.sm,
                          ),
                          child: ClayChip(
                            label: key == current ? '$key (الجارية)' : key,
                            selected: key == period,
                            onTap: () => setState(() => _period = key),
                          ),
                        ),
                    ],
                  ),
                ),
                if (report?.value != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ClaySpacing.screenPadding,
                    ),
                    child: ClayCard(
                      flat: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'المطلوب ${Money.format(report!.value!.totalAmount)}'
                            ' · المحصَّل ${Money.format(report.value!.totalPaid)}',
                            style: text.bodyMedium,
                          ),
                          Text(
                            'الباقي ${Money.format(report.value!.totalRemaining)}'
                            ' عند ${report.value!.unpaidCount} تلميذ',
                            style: text.titleSmall!.copyWith(
                              color: report.value!.totalRemaining > 0
                                  ? p.status.danger
                                  : p.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                  child: ClayTextField(
                    hint: 'ابحث باسم التلميذ أو هاتف الوليّ',
                    prefixIcon: ClayIcons.search,
                    onChanged: _search,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ClaySpacing.screenPadding,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ClayChip(
                      label: 'غير المسدَّد فقط',
                      selected: _unpaidOnly,
                      onTap: () => setState(() => _unpaidOnly = !_unpaidOnly),
                    ),
                  ),
                ),
                Expanded(
                  child: report!.when(
                    loading: () => const ClaySkeletonList(),
                    error: (_, _) => ClayErrorView(
                      message: 'تعذّرت قراءة حقوق التسجيل',
                      onRetry: () => ref.invalidate(feeReportProvider),
                    ),
                    data: (data) {
                      if (data.isEmpty) {
                        final filtered = _query.isNotEmpty || _unpaidOnly;
                        return ClayEmptyView(
                          title: filtered
                              ? 'لا نتائج مطابقة'
                              : 'لا حقوق في الفترة',
                          message: filtered
                              ? 'جرّب إلغاء التصفية أو اسماً آخر'
                              : 'تُسجَّل الحقوق عند تسجيل التلميذ',
                          icon: ClayIcons.payments,
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ClaySpacing.screenPadding,
                        ),
                        itemCount: data.items.length,
                        itemExtent: 88,
                        itemBuilder: (context, i) => _FeeTile(
                          item: data.items[i],
                          canReceive: canReceive,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _FeeTile extends StatelessWidget {
  const _FeeTile({required this.item, required this.canReceive});

  final FeeItem item;
  final bool canReceive;

  @override
  Widget build(BuildContext context) {
    return ClayListTile(
      title: item.name,
      subtitle: item.isSettled
          ? '${Money.format(item.amount)} · ${item.parentPhone}'
          : 'دُفع ${Money.format(item.paid)} من ${Money.format(item.amount)}'
                ' · ${item.parentPhone}',
      onTap: () => context.push('/students/${item.studentId}'),
      trailing: [
        if (item.isSettled)
          const ClayBadge(label: 'مسدَّد', tone: ClayTone.success)
        else ...[
          ClayBadge(
            label: 'الباقي ${Money.format(item.remaining)}',
            tone: ClayTone.danger,
          ),
          if (canReceive)
            IconButton(
              tooltip: 'تسجيل دفعة لـ ${item.name}',
              icon: const Icon(ClayIcons.payments),
              onPressed: () =>
                  context.push('/payments/new?student=${item.studentId}'),
            ),
        ],
      ],
    );
  }
}
