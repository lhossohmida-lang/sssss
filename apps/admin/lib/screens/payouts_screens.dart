import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'payments_screens.dart' show paymentDateText;

/// خلاص الأساتذة: ما يستحقونه من نصيبهم عن الدورات المكتملة (بقدر ما سدّد
/// التلاميذ وحضروا)، وما أُفرج عنه لاحقاً حين دفع المتأخرون، مع تسليم المال.
class PayoutsScreen extends ConsumerStatefulWidget {
  const PayoutsScreen({super.key});

  @override
  ConsumerState<PayoutsScreen> createState() => _PayoutsScreenState();
}

class _PayoutsScreenState extends ConsumerState<PayoutsScreen> {
  PayoutStatus _status = PayoutStatus.unpaid;
  String? _teacherId;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final teachers =
        ref.watch(teacherOptionsProvider).value ?? const <TeacherRow>[];
    final summary = ref.watch(payoutSummaryProvider(_teacherId)).value;
    final payouts = ref.watch(
      payoutsProvider((status: _status, teacherId: _teacherId)),
    );

    return Scaffold(
      appBar: const ClayAppBar(title: 'خلاص الأساتذة', showBack: true),
      body: Column(
        children: [
          if (summary != null)
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
                      'يُسلَّم للأساتذة ${Money.format(summary.unpaid)}',
                      style: text.titleSmall!.copyWith(
                        color: summary.unpaid > 0 ? p.status.warning : p.text,
                      ),
                    ),
                    Text(
                      'سُلِّم ${Money.format(summary.paid)}'
                      ' · معلّق ${Money.format(summary.pending)}',
                      style: text.bodySmall!.copyWith(color: p.textMuted),
                    ),
                    if (summary.pending > 0)
                      Text(
                        'المعلّق ينتظر تسديد تلاميذ لم يدفعوا، ويُفرج عنه '
                        'تلقائياً حين يدفعون',
                        style: text.bodySmall!.copyWith(color: p.textMuted),
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            child: ClayDropdown<String?>(
              label: 'الأستاذ',
              value: _teacherId,
              options: [
                const ClayOption(value: null, label: 'كل الأساتذة'),
                for (final t in teachers)
                  ClayOption(value: t.id, label: t.name),
              ],
              onChanged: (value) => setState(() => _teacherId = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaySpacing.screenPadding,
            ),
            child: Wrap(
              spacing: ClaySpacing.sm,
              children: [
                for (final status in PayoutStatus.values)
                  ClayChip(
                    label: status.label,
                    selected: _status == status,
                    onTap: () => setState(() => _status = status),
                  ),
              ],
            ),
          ),
          Expanded(
            child: payouts.when(
              loading: () => const ClaySkeletonList(),
              error: (_, _) => ClayErrorView(
                message: 'تعذّرت قراءة الخلاصات',
                onRetry: () => ref.invalidate(payoutsProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return ClayEmptyView(
                    title: _status == PayoutStatus.unpaid
                        ? 'لا خلاص ينتظر التسليم'
                        : 'لا خلاصات',
                    message: 'يظهر خلاص الأستاذ عند اكتمال دورة مجموعته',
                    icon: ClayIcons.payments,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ClaySpacing.screenPadding,
                  ),
                  itemCount: items.length,
                  itemExtent: 104,
                  itemBuilder: (context, i) => _PayoutTile(item: items[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PayoutTile extends StatelessWidget {
  const _PayoutTile({required this.item});

  final PayoutItem item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ClayListTile(
      title: item.teacherName,
      subtitle: '${item.groupLabel}\n${item.kindLabel}',
      subtitleLines: 2,
      onTap: () => context.push('/payouts/${item.id}'),
      trailing: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(Money.format(item.amount), style: text.titleSmall),
            item.isPaid
                ? const ClayBadge(label: 'مسلَّم', tone: ClayTone.success)
                : const ClayBadge(label: 'غير مسلَّم', tone: ClayTone.warning),
          ],
        ),
      ],
    );
  }
}

/// تفصيل خلاص: نصيب الأستاذ من كل تلميذ (حضوره وما غطّاه دفعه)، والنصيب
/// المعلّق، وزر تسليم المال للأستاذ.
class PayoutDetailsScreen extends ConsumerStatefulWidget {
  const PayoutDetailsScreen({required this.payoutId, super.key});

  final String payoutId;

  @override
  ConsumerState<PayoutDetailsScreen> createState() =>
      _PayoutDetailsScreenState();
}

class _PayoutDetailsScreenState extends ConsumerState<PayoutDetailsScreen> {
  bool _saving = false;

  Future<void> _deliver(PayoutDetail detail) async {
    final ok = await showClayConfirm(
      context,
      title: 'تسليم المبلغ للأستاذ',
      message:
          'تأكيد تسليم ${Money.format(detail.item.amount)} إلى '
          '${detail.item.teacherName} عن ${detail.item.groupLabel}؟ '
          'لا يمكن التراجع عن التسليم.',
      confirmLabel: 'تسليم',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      final userId = ref.read(sessionProvider).value?.accountId;
      if (userId != null) {
        await ref
            .read(payoutServiceProvider)
            .markPaid(detail.item.id, paidBy: userId);
      }
      ref.invalidate(payoutDetailProvider(widget.payoutId));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final detail = ref.watch(payoutDetailProvider(widget.payoutId));
    final canDeliver = ref.can(PermissionModule.payouts, PermissionAction.edit);
    return Scaffold(
      appBar: const ClayAppBar(title: 'تفصيل الخلاص', showBack: true),
      body: detail.when(
        loading: () => const ClayLoadingView(),
        error: (_, _) => ClayErrorView(
          message: 'تعذّرت قراءة الخلاص',
          onRetry: () => ref.invalidate(payoutDetailProvider),
        ),
        data: (d) {
          if (d == null) {
            return const ClayEmptyView(title: 'هذا الخلاص غير موجود');
          }
          final item = d.item;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                child: ClayCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.teacherName,
                              style: text.titleMedium,
                            ),
                          ),
                          item.isPaid
                              ? const ClayBadge(
                                  label: 'مسلَّم',
                                  tone: ClayTone.success,
                                )
                              : const ClayBadge(
                                  label: 'غير مسلَّم',
                                  tone: ClayTone.warning,
                                ),
                        ],
                      ),
                      Text(item.groupLabel, style: text.bodyMedium),
                      Text(
                        item.kindLabel,
                        style: text.bodySmall!.copyWith(color: p.textMuted),
                      ),
                      const SizedBox(height: ClaySpacing.sm),
                      Text(
                        Money.format(item.amount),
                        style: text.headlineSmall!.copyWith(color: p.accent),
                      ),
                      Text(
                        'نصيبه من التلميذ الكامل ${Money.format(d.ratePerStudent)}',
                        style: text.bodySmall!.copyWith(color: p.textMuted),
                      ),
                      if (d.pending > 0)
                        Text(
                          'معلّق حتى يدفع التلاميذ: ${Money.format(d.pending)}',
                          style: text.bodyMedium!.copyWith(
                            color: p.status.warning,
                          ),
                        ),
                      if (item.isPaid)
                        Text(
                          'سُلِّم ${paymentDateText(item.payout.paidAt!)}'
                          ' — ${d.paidByName ?? ''}',
                          style: text.bodyMedium,
                        ),
                      if (!item.isPaid && canDeliver) ...[
                        const SizedBox(height: ClaySpacing.md),
                        ClayButton(
                          label: 'تسليم المبلغ للأستاذ',
                          icon: ClayIcons.check,
                          expand: true,
                          loading: _saving,
                          onPressed: () => _deliver(d),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: d.lines.isEmpty
                    ? const ClayEmptyView(
                        title: 'لا تلاميذ في هذا الخلاص',
                        icon: ClayIcons.students,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ClaySpacing.screenPadding,
                        ),
                        itemCount: d.lines.length,
                        itemExtent: 88,
                        itemBuilder: (context, i) =>
                            _LineTile(line: d.lines[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line});

  final PayoutDetailLine line;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final l = line.line;
    return ClayListTile(
      title: line.name,
      subtitle: 'حضر ${l.attended} · غطّى دفعه ${l.covered} حصة',
      trailing: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(Money.format(l.earned), style: text.titleSmall),
            if (l.pending > 0)
              ClayBadge(
                label: 'معلّق ${Money.format(l.pending)}',
                tone: ClayTone.warning,
              ),
          ],
        ),
      ],
    );
  }
}
