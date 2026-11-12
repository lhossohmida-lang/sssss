import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// «2026-11-14 10:30» من وقت بالمللي ثانية.
String _dateText(int millis) {
  final t = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
  return '${DateKey.of(t)} '
      '${DateKey.formatMinutes(DateKey.minutesOf(t))}';
}

/// خلاصي: ما يستحقه الأستاذ من نصيبه عن دوراته المكتملة وما سُلِّم له وما
/// بقي معلّقاً حتى يسدّد التلاميذ، مع قائمة خلاصاته وتفصيلها.
class TeacherPayoutScreen extends ConsumerWidget {
  const TeacherPayoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final me = ref.watch(myTeacherIdProvider);
    if (me == null) return const ClayLoadingView();
    final summary = ref.watch(payoutSummaryProvider(me)).value;
    final payouts = ref.watch(
      payoutsProvider((status: PayoutStatus.all, teacherId: me)),
    );
    return Column(
      children: [
        if (summary != null)
          Padding(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            child: ClayCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('يُسلَّم لي', style: text.bodyMedium),
                  Text(
                    Money.format(summary.unpaid),
                    style: text.headlineSmall!.copyWith(
                      color: summary.unpaid > 0 ? p.status.warning : p.text,
                    ),
                  ),
                  const SizedBox(height: ClaySpacing.xs),
                  Text(
                    'سُلِّم ${Money.format(summary.paid)} · '
                    'معلّق ${Money.format(summary.pending)}',
                    style: text.bodySmall!.copyWith(color: p.textMuted),
                  ),
                  if (summary.pending > 0)
                    Text(
                      'المعلّق نصيب تلاميذ لم يسدّدوا بعد؛ يُضاف إلى خلاصك '
                      'حين يدفعون',
                      style: text.bodySmall!.copyWith(color: p.textMuted),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: payouts.when(
            loading: () => const ClaySkeletonList(),
            error: (_, _) => ClayErrorView(
              message: 'تعذّرت قراءة خلاصاتك',
              onRetry: () => ref.invalidate(payoutsProvider),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const ClayEmptyView(
                  title: 'لا خلاصات بعد',
                  message: 'يظهر خلاصك عند اكتمال دورة مجموعة من مجموعاتك',
                  icon: ClayIcons.payments,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: ClaySpacing.screenPadding,
                ),
                itemCount: items.length,
                itemExtent: 104,
                itemBuilder: (context, i) {
                  final item = items[i];
                  return ClayListTile(
                    title: item.groupLabel,
                    subtitle: item.kindLabel,
                    onTap: () => context.push('/payouts/${item.id}'),
                    trailing: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            Money.format(item.amount),
                            style: text.titleSmall,
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
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// تفصيل خلاص الأستاذ: نصيبه من كل تلميذ (حضوره وما غطّاه دفعه) والمعلّق.
class TeacherPayoutDetailsScreen extends ConsumerWidget {
  const TeacherPayoutDetailsScreen({required this.payoutId, super.key});

  final String payoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final me = ref.watch(myTeacherIdProvider);
    final detail = ref.watch(payoutDetailProvider(payoutId));
    return Scaffold(
      appBar: const ClayAppBar(title: 'تفصيل الخلاص', showBack: true),
      body: detail.when(
        loading: () => const ClayLoadingView(),
        error: (_, _) => ClayErrorView(
          message: 'تعذّرت قراءة الخلاص',
          onRetry: () => ref.invalidate(payoutDetailProvider),
        ),
        data: (d) {
          if (d == null || d.item.payout.teacherId != me) {
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
                      Text(item.groupLabel, style: text.titleMedium),
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
                        'نصيبك من التلميذ الكامل '
                        '${Money.format(d.ratePerStudent)}',
                        style: text.bodySmall!.copyWith(color: p.textMuted),
                      ),
                      if (d.pending > 0)
                        Text(
                          'معلّق حتى يدفع التلاميذ: ${Money.format(d.pending)}',
                          style: text.bodyMedium!.copyWith(
                            color: p.status.warning,
                          ),
                        ),
                      Text(
                        item.isPaid
                            ? 'سُلِّم ${_dateText(item.payout.paidAt!)}'
                            : 'لم يُسلَّم بعد',
                        style: text.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ClaySpacing.screenPadding,
                  ),
                  itemCount: d.lines.length,
                  itemExtent: 88,
                  itemBuilder: (context, i) {
                    final l = d.lines[i].line;
                    return ClayListTile(
                      title: d.lines[i].name,
                      subtitle:
                          'حضر ${l.attended} · غطّى دفعه ${l.covered} حصة',
                      trailing: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              Money.format(l.earned),
                              style: text.titleSmall,
                            ),
                            if (l.pending > 0)
                              ClayBadge(
                                label: 'معلّق ${Money.format(l.pending)}',
                                tone: ClayTone.warning,
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
