import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// التقرير المالي الشهري: المقبوضات، المصاريف، وخلاص الأساتذة المسلّم.
class MonthlyReportScreen extends ConsumerStatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  ConsumerState<MonthlyReportScreen> createState() =>
      _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends ConsumerState<MonthlyReportScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _exporting = false;

  String get _monthKey =>
      '${_month.year.toString().padLeft(4, '0')}-'
      '${_month.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final canView =
        ref.can(PermissionModule.payments, PermissionAction.view) &&
        ref.can(PermissionModule.expenses, PermissionAction.view) &&
        ref.can(PermissionModule.payouts, PermissionAction.view);
    if (!canView) {
      return const Scaffold(
        appBar: ClayAppBar(title: 'التقرير الشهري', showBack: true),
        body: ClayEmptyView(
          title: 'الصلاحية غير متاحة',
          message: 'يتطلب التقرير صلاحية عرض المدفوعات والمصاريف والخلاص',
          icon: Icons.lock_outline,
        ),
      );
    }

    final report = ref.watch(monthlyFinanceReportProvider(_monthKey));
    return Scaffold(
      appBar: ClayAppBar(
        title: 'التقرير الشهري',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'تصدير التقرير PDF',
            onPressed: report.value == null || _exporting
                ? null
                : () => _export(report.value!),
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          _MonthPicker(
            month: _month,
            onPrevious: () => setState(
              () => _month = DateTime(_month.year, _month.month - 1),
            ),
            onNext: _isCurrentMonth
                ? null
                : () => setState(
                    () => _month = DateTime(_month.year, _month.month + 1),
                  ),
          ),
          Expanded(
            child: report.when(
              loading: () => const ClaySkeletonList(),
              error: (_, _) => ClayErrorView(
                message: 'تعذّرت قراءة التقرير الشهري',
                onRetry: () => ref.invalidate(monthlyFinanceReportProvider),
              ),
              data: (data) => _ReportBody(report: data),
            ),
          ),
        ],
      ),
    );
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  Future<void> _export(MonthlyFinanceReport report) async {
    setState(() => _exporting = true);
    try {
      final font = await rootBundle.load(
        'packages/school_ui/assets/fonts/Cairo.ttf',
      );
      final settings = await ref.read(settingsServiceProvider).load();
      final bytes = await MonthlyFinanceReportPdf.build(
        MonthlyFinanceReportPdfData(
          report: report,
          schoolName: settings.schoolName,
          schoolAddress: settings.schoolAddress,
          schoolPhone: settings.schoolPhone,
          generatedAt: DateTime.now(),
        ),
        fontData: font.buffer.asUint8List(
          font.offsetInBytes,
          font.lengthInBytes,
        ),
      );
      if (!mounted) return;
      await ref
          .read(pdfPresenterProvider)
          .show(
            context,
            bytes: bytes,
            fileName: 'monthly-finance-${report.month}.pdf',
            title: 'التقرير المالي ${_monthLabel(_month)}',
          );
    } on Object catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر إنشاء التقرير PDF')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

class _MonthPicker extends StatelessWidget {
  const _MonthPicker({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

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
            tooltip: 'الشهر السابق',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_right),
          ),
          Expanded(
            child: Text(
              _monthLabel(month),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'الشهر التالي',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_left),
          ),
        ],
      ),
    ),
  );
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});

  final MonthlyFinanceReport report;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(ClaySpacing.screenPadding),
    children: [
      _SummaryTile(
        title: 'إجمالي المقبوضات',
        amount: report.receivedAmount,
        subtitle: '${report.receiptCount} وصل',
        icon: Icons.south_west,
        tone: ClayTone.success,
      ),
      const SizedBox(height: ClaySpacing.sm),
      _SummaryTile(
        title: 'إجمالي الخارج',
        amount: report.outgoingAmount,
        subtitle:
            '${report.expenseCount} مصروف · ${report.teacherPayoutCount} خلاص أستاذ',
        icon: Icons.north_east,
        tone: ClayTone.danger,
      ),
      const SizedBox(height: ClaySpacing.sm),
      _SummaryTile(
        title: 'الصافي',
        amount: report.netAmount,
        subtitle: 'المقبوضات ناقص الخارج',
        icon: Icons.account_balance_wallet_outlined,
        tone: report.netAmount < 0 ? ClayTone.danger : ClayTone.info,
      ),
      const SizedBox(height: ClaySpacing.md),
      _BreakdownCard(
        title: 'المقبوضات حسب نوع الدفع',
        emptyText: 'لا توجد وصولات في هذا الشهر',
        rows: [
          for (final item in report.payments)
            _BreakdownRow(
              label: item.type.label,
              amount: item.amount,
              count: item.count,
            ),
        ],
        totalLabel: 'المجموع',
        total: report.receivedAmount,
      ),
      const SizedBox(height: ClaySpacing.sm),
      _BreakdownCard(
        title: 'المصاريف حسب النوع',
        emptyText: 'لا توجد مصاريف في هذا الشهر',
        rows: [
          for (final item in report.expenses)
            _BreakdownRow(
              label: item.categoryName,
              amount: item.amount,
              count: item.count,
            ),
        ],
        totalLabel: 'المجموع',
        total: report.expenseAmount,
      ),
      const SizedBox(height: ClaySpacing.sm),
      _BreakdownCard(
        title: 'خلاص الأساتذة المسلّم',
        emptyText: 'لم يُسلَّم خلاص خلال هذا الشهر',
        rows: [
          if (report.teacherPayoutCount > 0)
            _BreakdownRow(
              label: 'عمليات التسليم',
              amount: report.teacherPayoutAmount,
              count: report.teacherPayoutCount,
            ),
        ],
        totalLabel: 'المجموع',
        total: report.teacherPayoutAmount,
      ),
      const SizedBox(height: ClaySpacing.md),
      Text(
        'يُحتسب الوصل بتاريخ قبضه، والمصروف بتاريخ تسجيله، وخلاص الأستاذ '
        'بتاريخ تسليم المال.',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.palette.textMuted),
      ),
    ],
  );
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.icon,
    required this.tone,
  });

  final String title;
  final int amount;
  final String subtitle;
  final IconData icon;
  final ClayTone tone;

  @override
  Widget build(BuildContext context) => ClayCard(
    flat: true,
    child: Row(
      children: [
        Icon(icon, color: context.palette.accent),
        const SizedBox(width: ClaySpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodyMedium),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        ClayBadge(label: Money.format(amount), tone: tone),
      ],
    ),
  );
}

class _BreakdownRow {
  const _BreakdownRow({
    required this.label,
    required this.amount,
    required this.count,
  });

  final String label;
  final int amount;
  final int count;
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.title,
    required this.emptyText,
    required this.rows,
    required this.totalLabel,
    required this.total,
  });

  final String title;
  final String emptyText;
  final List<_BreakdownRow> rows;
  final String totalLabel;
  final int total;

  @override
  Widget build(BuildContext context) => ClayCard(
    flat: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: ClaySpacing.xs),
        if (rows.isEmpty)
          Text(emptyText, style: Theme.of(context).textTheme.bodySmall)
        else
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
              child: Row(
                children: [
                  Expanded(child: Text(row.label)),
                  Text('${row.count}'),
                  const SizedBox(width: ClaySpacing.md),
                  Text(Money.format(row.amount)),
                ],
              ),
            ),
        const Divider(height: ClaySpacing.md),
        Row(
          children: [
            Expanded(child: Text(totalLabel)),
            Text(
              Money.format(total),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ],
    ),
  );
}

String _monthLabel(DateTime month) {
  const names = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];
  return '${names[month.month - 1]} ${month.year}';
}
