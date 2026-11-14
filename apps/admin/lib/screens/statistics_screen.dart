import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// إحصائيات السنة بحسب صلاحيات المشاهد.
class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  int _year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final scope = StatisticsScope(
      payments: ref.can(PermissionModule.payments, PermissionAction.view),
      expenses: ref.can(PermissionModule.expenses, PermissionAction.view),
      payouts: ref.can(PermissionModule.payouts, PermissionAction.view),
      attendance: ref.can(PermissionModule.attendance, PermissionAction.view),
      students: ref.can(PermissionModule.students, PermissionAction.view),
      groups: ref.can(PermissionModule.groups, PermissionAction.view),
    );
    if (!scope.hasAny) {
      return const Scaffold(
        appBar: ClayAppBar(title: 'الإحصائيات', showBack: true),
        body: ClayEmptyView(
          title: 'الصلاحية غير متاحة',
          message: 'تحتاج إلى صلاحية عرض إحدى وحدات المدرسة',
          icon: Icons.query_stats_rounded,
        ),
      );
    }
    final stats = ref.watch(
      statisticsProvider((
        year: _year,
        payments: scope.payments,
        expenses: scope.expenses,
        payouts: scope.payouts,
        attendance: scope.attendance,
        students: scope.students,
        groups: scope.groups,
      )),
    );
    return Scaffold(
      appBar: const ClayAppBar(title: 'الإحصائيات', showBack: true),
      body: Column(
        children: [
          _YearPicker(
            year: _year,
            canGoNext: _year < DateTime.now().year,
            onPrevious: () => setState(() => _year--),
            onNext: () => setState(() => _year++),
          ),
          Expanded(
            child: stats.when(
              loading: () => const ClaySkeletonList(count: 3, itemExtent: 280),
              error: (_, _) => ClayErrorView(
                message: 'تعذّرت قراءة إحصائيات السنة',
                onRetry: () => ref.invalidate(statisticsProvider),
              ),
              data: (data) => _StatisticsBody(snapshot: data),
            ),
          ),
        ],
      ),
    );
  }
}

class _YearPicker extends StatelessWidget {
  const _YearPicker({
    required this.year,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  final int year;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(
      ClaySpacing.screenPadding,
      ClaySpacing.sm,
      ClaySpacing.screenPadding,
      0,
    ),
    child: ClayCard(
      flat: true,
      child: Row(
        children: [
          IconButton(
            tooltip: 'السنة السابقة',
            onPressed: year <= 1 ? null : onPrevious,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          Expanded(
            child: Text(
              'السنة $year',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'السنة التالية',
            onPressed: canGoNext ? onNext : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
        ],
      ),
    ),
  );
}

class _StatisticsBody extends StatelessWidget {
  const _StatisticsBody({required this.snapshot});

  final StatisticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final months = snapshot.months;
    final financeSeries = <ClayBarSeries>[
      if (snapshot.scope.payments)
        ClayBarSeries(
          label: 'المقبوضات',
          color: palette.status.success,
          values: [for (final month in months) month.receipts],
        ),
      if (snapshot.scope.expenses)
        ClayBarSeries(
          label: 'المصاريف',
          color: palette.status.warning,
          values: [for (final month in months) month.expenses],
        ),
      if (snapshot.scope.payouts)
        ClayBarSeries(
          label: 'خلاص الأساتذة',
          color: palette.status.info,
          values: [for (final month in months) month.payouts],
        ),
    ];
    final attendanceSeries = <ClayBarSeries>[
      ClayBarSeries(
        label: 'حاضر',
        color: palette.status.success,
        values: [for (final month in months) month.present],
      ),
      ClayBarSeries(
        label: 'غائب',
        color: palette.status.danger,
        values: [for (final month in months) month.absent],
      ),
      ClayBarSeries(
        label: 'برخصة',
        color: palette.status.excused,
        values: [for (final month in months) month.excused],
      ),
    ];
    final enrollmentSeries = <ClayBarSeries>[
      if (snapshot.scope.students)
        ClayBarSeries(
          label: 'تلاميذ جدد',
          color: palette.accent,
          values: [for (final month in months) month.newStudents],
        ),
      if (snapshot.scope.groups)
        ClayBarSeries(
          label: 'مجموعات جديدة',
          color: palette.status.info,
          values: [for (final month in months) month.newGroups],
        ),
    ];
    const monthLabels = [
      'جانفي',
      'فيفري',
      'مارس',
      'أفريل',
      'ماي',
      'جوان',
      'جويلية',
      'أوت',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    final financeSummary = [
      if (snapshot.scope.payments)
        'المقبوضات ${Money.format(snapshot.receivedTotal)}',
      if (snapshot.scope.expenses)
        'المصاريف ${Money.format(snapshot.expenseTotal)}',
      if (snapshot.scope.payouts)
        'خلاص الأساتذة ${Money.format(snapshot.payoutTotal)}',
    ].join(' · ');
    final enrollmentSummary = [
      if (snapshot.scope.students) '${snapshot.activeStudents} تلميذ نشط',
      if (snapshot.scope.groups) '${snapshot.activeGroups} مجموعة نشطة',
    ].join(' · ');

    return ListView(
      padding: const EdgeInsets.all(ClaySpacing.screenPadding),
      children: [
        if (snapshot.scope.hasEnrollment) ...[
          Wrap(
            spacing: ClaySpacing.md,
            runSpacing: ClaySpacing.md,
            children: [
              if (snapshot.scope.students)
                _TotalCard(
                  label: 'التلاميذ النشطون',
                  value: '${snapshot.activeStudents}',
                ),
              if (snapshot.scope.groups)
                _TotalCard(
                  label: 'المجموعات النشطة',
                  value: '${snapshot.activeGroups}',
                ),
            ],
          ),
          const SizedBox(height: ClaySpacing.lg),
        ],
        if (snapshot.scope.hasFinance) ...[
          ClayChartCard(
            title: 'الحركة المالية الشهرية',
            subtitle: financeSummary,
            legend: [
              for (final item in financeSeries)
                ClayLegendItem(label: item.label, color: item.color),
            ],
            chart: ClayBarChart(
              categories: monthLabels,
              series: financeSeries,
              valueLabel: Money.format,
            ),
            isEmpty: financeSeries.every(
              (item) => item.values.every((value) => value == 0),
            ),
          ),
          const SizedBox(height: ClaySpacing.lg),
        ],
        if (snapshot.scope.attendance) ...[
          ClayChartCard(
            title: 'حضور التلاميذ حسب الشهر',
            subtitle: 'عدد حالات الحضور والغياب المسجّلة في الحصص',
            legend: [
              for (final item in attendanceSeries)
                ClayLegendItem(label: item.label, color: item.color),
            ],
            chart: ClayBarChart(
              categories: monthLabels,
              series: attendanceSeries,
            ),
            isEmpty: snapshot.attendanceTotal == 0,
          ),
          const SizedBox(height: ClaySpacing.lg),
        ],
        if (snapshot.scope.hasEnrollment)
          ClayChartCard(
            title: 'التسجيلات الشهرية',
            subtitle: enrollmentSummary,
            legend: [
              for (final item in enrollmentSeries)
                ClayLegendItem(label: item.label, color: item.color),
            ],
            chart: ClayBarChart(
              categories: monthLabels,
              series: enrollmentSeries,
            ),
            isEmpty: enrollmentSeries.every(
              (item) => item.values.every((value) => value == 0),
            ),
          ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    child: ClayCard(
      flat: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: ClaySpacing.xs),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    ),
  );
}
