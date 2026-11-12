import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// بطاقة رقم في لوحة التحكم.
class _Kpi {
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.path,
    this.sub,
    this.tone = ClayTone.neutral,
    this.isTab = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String path;
  final String? sub;
  final ClayTone tone;

  /// هل المسار تبويب (يُنتقل إليه) لا صفحة (تُدفع)؟
  final bool isTab;
}

/// إجراء سريع.
class _Quick {
  const _Quick({required this.icon, required this.label, required this.path});

  final IconData icon;
  final String label;
  final String path;
}

/// لوحة التحكم: أرقام اليوم (حصص وحضور ومقبوضات ومستحقات وخلاص وانتظار)
/// وإجراءات سريعة ورسم مقبوضات الأسبوع. لا يظهر لكل مستخدم إلا ما يملك
/// صلاحية عرضه؛ والعامل بلا صلاحيات يرى رسالة بدل الأرقام.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final session = ref.watch(sessionProvider.select((s) => s.value));
    final school = ref.watch(schoolNameProvider).value ?? '';
    final stats = ref.watch(dashboardProvider);
    if (session == null) return const ClayLoadingView();
    final policy = session.policy;
    bool can(PermissionModule m) => policy.canAnyOf(m);
    bool use(PermissionModule m, PermissionAction a) => policy.can(m, a);

    final today = DateTime.now();
    final header = Padding(
      padding: const EdgeInsets.only(bottom: ClaySpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('أهلاً ${session.displayName}', style: text.headlineSmall),
          Text(
            [
              if (school.isNotEmpty) school,
              '${GroupService.weekdayName(today.weekday)} ${DateKey.of(today)}',
            ].join(' · '),
            style: text.bodyMedium!.copyWith(color: p.textMuted),
          ),
        ],
      ),
    );

    final quick = <_Quick>[
      if (use(PermissionModule.students, PermissionAction.add))
        const _Quick(
          icon: ClayIcons.add,
          label: 'تسجيل تلميذ',
          path: '/students/new',
        ),
      if (use(PermissionModule.receiveMoney, PermissionAction.use))
        const _Quick(
          icon: ClayIcons.payments,
          label: 'تسجيل دفعة',
          path: '/payments/new',
        ),
      if (use(PermissionModule.scanner, PermissionAction.use))
        const _Quick(icon: ClayIcons.scan, label: 'الماسح', path: '/scanner'),
      if (can(PermissionModule.attendance))
        const _Quick(
          icon: ClayIcons.attendance,
          label: 'الحضور',
          path: '/attendance',
        ),
      if (use(PermissionModule.scanner, PermissionAction.use))
        const _Quick(
          icon: ClayIcons.students,
          label: 'شاشة المدخل',
          path: '/entrance',
        ),
    ];

    Widget body(DashboardStats s) {
      final kpis = <_Kpi>[
        if (can(PermissionModule.attendance))
          _Kpi(
            icon: ClayIcons.attendance,
            label: 'حصص اليوم',
            value: '${s.todaySessions}',
            sub: 'حاضرون ${s.todayPresent}',
            path: '/attendance',
          ),
        if (can(PermissionModule.students))
          _Kpi(
            icon: ClayIcons.students,
            label: 'التلاميذ',
            value: '${s.students}',
            sub: '${s.activeGroups} مجموعة نشطة',
            path: '/students',
            isTab: true,
          ),
        if (can(PermissionModule.payments))
          _Kpi(
            icon: ClayIcons.payments,
            label: 'استُلم اليوم',
            value: Money.format(s.receivedToday),
            sub: 'الشهر ${Money.format(s.receivedMonth)}',
            path: '/payments',
            isTab: true,
            tone: ClayTone.success,
          ),
        if (can(PermissionModule.payments))
          _Kpi(
            icon: ClayIcons.dues,
            label: 'المستحقات',
            value: Money.format(s.duesTotal),
            sub: '${s.duesStudents} تلميذ',
            path: '/dues',
            tone: s.duesTotal > 0 ? ClayTone.warning : ClayTone.neutral,
          ),
        if (can(PermissionModule.payouts))
          _Kpi(
            icon: ClayIcons.payments,
            label: 'خلاص الأساتذة',
            value: Money.format(s.payoutsUnpaid),
            sub: '${s.payoutsUnpaidCount} ينتظر التسليم',
            path: '/payouts',
            tone: s.payoutsUnpaid > 0 ? ClayTone.warning : ClayTone.neutral,
          ),
        if (can(PermissionModule.waiting))
          _Kpi(
            icon: ClayIcons.waiting,
            label: 'انتظار بلغ حدّه',
            value: '${s.waitingReady}',
            sub: 'يمكن فتح مجموعة',
            path: '/waiting',
            tone: s.waitingReady > 0 ? ClayTone.info : ClayTone.neutral,
          ),
        if (can(PermissionModule.teachers))
          _Kpi(
            icon: ClayIcons.teachers,
            label: 'حصص لم يحضرها أستاذها',
            value: '${s.missedSessions}',
            sub: 'آخر ${DashboardQueries.windowDays} أيام',
            path: '/teacher-attendance',
            tone: s.missedSessions > 0 ? ClayTone.danger : ClayTone.neutral,
          ),
      ];
      if (kpis.isEmpty && quick.isEmpty) {
        return const ClayEmptyView(
          title: 'لا توجد بيانات متاحة',
          message: 'اطلب من الإدارة تفعيل الصلاحيات لحسابك',
          icon: ClayIcons.settings,
        );
      }
      return LayoutBuilder(
        builder: (context, box) {
          final columns = box.maxWidth >= 900
              ? 4
              : box.maxWidth >= 600
              ? 3
              : 2;
          const gap = ClaySpacing.md;
          final width =
              (box.maxWidth -
                  ClaySpacing.screenPadding * 2 -
                  gap * (columns - 1)) /
              columns;
          return ListView(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            children: [
              header,
              if (quick.isNotEmpty) ...[
                Wrap(
                  spacing: ClaySpacing.sm,
                  runSpacing: ClaySpacing.sm,
                  children: [
                    for (final q in quick)
                      ClayButton(
                        label: q.label,
                        icon: q.icon,
                        kind: ClayButtonKind.secondary,
                        onPressed: () => context.push(q.path),
                      ),
                  ],
                ),
                const SizedBox(height: ClaySpacing.lg),
              ],
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final k in kpis)
                    SizedBox(
                      width: width,
                      child: _KpiCard(
                        kpi: k,
                        onTap: () =>
                            k.isTab ? context.go(k.path) : context.push(k.path),
                      ),
                    ),
                ],
              ),
              if (can(PermissionModule.payments)) ...[
                const SizedBox(height: ClaySpacing.lg),
                _WeekChart(stats: s),
              ],
            ],
          );
        },
      );
    }

    return stats.when(
      loading: () => const ClaySkeletonList(count: 4, itemExtent: 120),
      error: (_, _) => ClayErrorView(
        message: 'تعذّر حساب أرقام اللوحة',
        onRetry: () => ref.invalidate(dashboardProvider),
      ),
      data: body,
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.kpi, required this.onTap});

  final _Kpi kpi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final color = switch (kpi.tone) {
      ClayTone.success => p.status.success,
      ClayTone.warning => p.status.warning,
      ClayTone.danger => p.status.danger,
      ClayTone.info => p.status.info,
      ClayTone.excused => p.status.excused,
      ClayTone.neutral => p.accent,
    };
    return ClayCard(
      onTap: onTap,
      semanticLabel:
          '${kpi.label}: ${kpi.value}'
          '${kpi.sub == null ? '' : '، ${kpi.sub}'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(kpi.icon, color: color),
          const SizedBox(height: ClaySpacing.sm),
          Text(
            kpi.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.headlineSmall,
          ),
          Text(kpi.label, style: text.titleSmall),
          if (kpi.sub != null)
            Text(kpi.sub!, style: text.bodySmall!.copyWith(color: p.textMuted)),
        ],
      ),
    );
  }
}

/// أعمدة مقبوضات آخر 7 أيام، اليوم آخرها.
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final max = stats.weekReceipts.fold<int>(
      0,
      (m, d) => d.amount > m ? d.amount : m,
    );
    return ClayChartCard(
      title: 'مقبوضات آخر ${DashboardQueries.windowDays} أيام',
      subtitle: 'المجموع ${Money.format(stats.weekTotal)}',
      isEmpty: stats.weekTotal == 0,
      height: 160,
      chart: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in stats.weekReceipts)
            Expanded(
              child: Semantics(
                label:
                    '${GroupService.weekdayName(DateKey.weekday(day.date))}: '
                    '${Money.format(day.amount)}',
                excludeSemantics: true,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: max == 0
                              ? 0.02
                              : (day.amount / max).clamp(0.02, 1.0),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: p.accent,
                              borderRadius: BorderRadius.circular(
                                ClayRadius.sm,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: ClaySpacing.xs),
                    Text(
                      '${int.parse(day.date.substring(8))}',
                      style: text.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
