import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// مدفوعات الابن: ما بقي عليه موزَّعاً على موادّه وحقوق التسجيل والنقل، ثم
/// قائمة ما دُفع عنه بوصولاتها؛ والضغط على دفعة يعرض وصلها PDF.
class ParentPaymentsScreen extends ConsumerStatefulWidget {
  const ParentPaymentsScreen({super.key});

  @override
  ConsumerState<ParentPaymentsScreen> createState() =>
      _ParentPaymentsScreenState();
}

class _ParentPaymentsScreenState extends ConsumerState<ParentPaymentsScreen> {
  int _limit = PaymentService.pageSize;

  Future<void> _openReceipt(String paymentId) async {
    final messenger = ScaffoldMessenger.of(context);
    final detail = await ref.read(paymentServiceProvider).detail(paymentId);
    if (!mounted) return;
    if (detail == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر العثور على هذا الوصل')),
      );
      return;
    }
    await showReceipt(context, ref, detail);
  }

  @override
  Widget build(BuildContext context) {
    final child = ref.watch(selectedChildProvider);
    if (child == null) {
      return const ClayEmptyView(
        title: 'لا أبناء مرتبطون بحسابك',
        message: 'تواصل مع المدرسة لربط أبنائك بحسابك',
        icon: ClayIcons.students,
      );
    }
    final profile = ref.watch(studentProfileProvider(child.id)).value;
    final payments = ref.watch(
      childPaymentsProvider((studentId: child.id, limit: _limit)),
    );
    return Column(
      children: [
        const ChildSwitcher(),
        Expanded(
          child: payments.when(
            loading: () => const ClaySkeletonList(),
            error: (_, _) => ClayErrorView(
              message: 'تعذّرت قراءة المدفوعات',
              onRetry: () => ref.invalidate(childPaymentsProvider),
            ),
            data: (page) => CustomScrollView(
              slivers: [
                if (profile != null)
                  SliverPadding(
                    padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                    sliver: SliverToBoxAdapter(
                      child: _Remaining(profile: profile),
                    ),
                  ),
                if (page.items.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: ClayEmptyView(
                      title: 'لا مدفوعات بعد',
                      message: 'تظهر هنا دفعاته ووصولاتها',
                      icon: ClayIcons.receipt,
                    ),
                  )
                else ...[
                  const SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: ClaySpacing.screenPadding,
                    ),
                    sliver: SliverToBoxAdapter(child: _ListTitle()),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ClaySpacing.screenPadding,
                    ),
                    sliver: SliverFixedExtentList(
                      itemExtent: 104,
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _PaymentTile(
                          item: page.items[i],
                          onTap: () => _openReceipt(page.items[i].id),
                        ),
                        childCount: page.items.length,
                      ),
                    ),
                  ),
                  if (page.hasMore)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(
                          ClaySpacing.screenPadding,
                        ),
                        child: ClayButton(
                          label: 'عرض المزيد',
                          kind: ClayButtonKind.secondary,
                          expand: true,
                          onPressed: () =>
                              setState(() => _limit += PaymentService.pageSize),
                        ),
                      ),
                    ),
                ],
                const SliverToBoxAdapter(
                  child: SizedBox(height: ClaySpacing.xl),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ListTitle extends StatelessWidget {
  const _ListTitle();

  @override
  Widget build(BuildContext context) =>
      Text('الدفعات', style: Theme.of(context).textTheme.titleSmall);
}

/// ما بقي على الابن: بند لكل مادة عليه فيها باقٍ، وحقوق التسجيل، والنقل.
class _Remaining extends StatelessWidget {
  const _Remaining({required this.profile});

  final StudentProfile profile;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final lines = <({String label, int amount})>[
      for (final e in profile.enrolments)
        if (e.remaining > 0)
          (
            label: '${e.subjectName} · المجموعة ${e.groupNumber}',
            amount: e.remaining,
          ),
      if (profile.registrationFeeRemaining > 0)
        (label: 'حقوق التسجيل', amount: profile.registrationFeeRemaining),
      if (profile.transportRemaining > 0)
        (label: 'النقل', amount: profile.transportRemaining),
    ];
    return ClayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lines.isEmpty)
            Row(
              children: [
                Icon(ClayIcons.check, color: p.status.success, size: 20),
                const SizedBox(width: ClaySpacing.xs),
                Text(
                  'لا مبالغ متبقية على ${profile.student.firstName}',
                  style: text.bodyMedium!.copyWith(color: p.status.success),
                ),
              ],
            )
          else ...[
            Text('المتبقي عليه', style: text.bodyMedium),
            Text(
              Money.format(profile.totalRemaining),
              style: text.headlineSmall!.copyWith(color: p.status.warning),
            ),
            const SizedBox(height: ClaySpacing.sm),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(line.label, style: text.bodyMedium)),
                    Text(Money.format(line.amount), style: text.bodyMedium),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.item, required this.onTap});

  final PaymentListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ClayListTile(
      title: item.description,
      subtitle:
          '${item.payment.receiptNumber} · '
          '${paymentDateText(item.payment.createdAt)}',
      subtitleLines: 2,
      leading: Icon(ClayIcons.receipt, color: context.palette.accent),
      onTap: onTap,
      trailing: [
        Text(Money.format(item.payment.amount), style: text.titleSmall),
      ],
    );
  }
}
