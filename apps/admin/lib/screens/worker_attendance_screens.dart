import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'workers_screens.dart' show durationText;

export 'package:school_ui/school_ui.dart' show MonthBar, currentMonthKey;

/// كشف حضور العمال الشهري: لكل عامل أيام الكامل والنصف والأيام بلا خروج وأجر الشهر،
/// وإجمالي الأجور. يُفتح كشف العامل اليومي بالنقر عليه.
class WorkerSheetScreen extends ConsumerStatefulWidget {
  const WorkerSheetScreen({super.key});

  @override
  ConsumerState<WorkerSheetScreen> createState() => _WorkerSheetScreenState();
}

class _WorkerSheetScreenState extends ConsumerState<WorkerSheetScreen> {
  String _month = currentMonthKey();

  Future<void> _recordAsExpense(WorkerMonthSummary worker) async {
    final wasRecorded = worker.wageExpenseId != null;
    try {
      await ref
          .read(wageServiceProvider)
          .recordAsExpense(workerId: worker.workerId, month: _month);
      if (!mounted) return;
      ref.invalidate(workerSheetProvider(_month));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              wasRecorded
                  ? 'حُدّث مصروف أجر العامل'
                  : 'سُجّل أجر العامل كمصروف',
            ),
          ),
        );
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is StateError
          ? error.message.toString()
          : 'تعذّر تسجيل الأجر كمصروف: $error';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final today = DateKey.of(DateTime.now());
    final canRecordExpense = ref.can(
      PermissionModule.expenses,
      PermissionAction.add,
    );
    final sheet = ref.watch(workerSheetProvider(_month));
    return Scaffold(
      appBar: const ClayAppBar(title: 'حضور العمال', showBack: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaySpacing.screenPadding,
            ),
            child: MonthBar(
              month: _month,
              onChanged: (m) => setState(() => _month = m),
            ),
          ),
          if (sheet.value != null && sheet.value!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ClaySpacing.screenPadding,
              ),
              child: ClayCard(
                flat: true,
                child: Row(
                  children: [
                    Expanded(
                      child: Text('إجمالي أجور الشهر', style: text.titleSmall),
                    ),
                    Text(
                      Money.format(
                        sheet.value!.fold(0, (s, w) => s + w.month.total),
                      ),
                      style: text.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: sheet.when(
              loading: () => const ClaySkeletonList(),
              error: (_, _) => ClayErrorView(
                message: 'تعذّرت قراءة كشف العمال',
                onRetry: () => ref.invalidate(workerSheetProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const ClayEmptyView(
                    title: 'لا يوجد عمال',
                    message: 'أضف العمال من «المزيد ← العمال»',
                    icon: ClayIcons.workers,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                  itemCount: items.length,
                  itemExtent: 96,
                  itemBuilder: (context, i) {
                    final w = items[i];
                    final m = w.month;
                    final needsUpdate =
                        w.wageExpenseId != null && !w.wageExpenseIsCurrent;
                    return ClayListTile(
                      leading: ClayAvatar(name: w.name),
                      title: w.name,
                      subtitle:
                          '${m.fullDays} يوم كامل · ${m.halfDays} نصف · '
                          '${m.openDaysBefore(today)} بلا خروج\n'
                          'عمل ${durationText(m.totalWorkedMinutes)}',
                      subtitleLines: 2,
                      onTap: () => context.push(
                        '/worker-attendance/${w.workerId}?month=$_month',
                      ),
                      trailing: [
                        Text(Money.format(m.total), style: text.titleSmall),
                        if (canRecordExpense)
                          IconButton(
                            tooltip: w.wageExpenseId == null
                                ? 'تسجيل الأجر كمصروف'
                                : needsUpdate
                                ? 'تحديث مصروف الأجر'
                                : 'الأجر مسجّل كمصروف',
                            onPressed: m.total <= 0 || w.wageExpenseIsCurrent
                                ? null
                                : () => _recordAsExpense(w),
                            icon: Icon(
                              w.wageExpenseId == null
                                  ? Icons.add_card_outlined
                                  : needsUpdate
                                  ? Icons.sync_rounded
                                  : Icons.check_circle_outline_rounded,
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// نتيجة اختيار التعديل: نوع اليوم، أو `null` لإلغاء التعديل.
typedef OverrideChoice = ({WorkDayKind? kind});

/// كشف عامل لشهر يوماً بيوم: دخوله وخروجه ومدة عمله وما يُدفع عنه، مع
/// تعديل يدوي لكل يوم (كامل / نصف / غائب أو إلغاء التعديل).
class WorkerMonthScreen extends ConsumerStatefulWidget {
  const WorkerMonthScreen({required this.workerId, this.month, super.key});

  final String workerId;

  /// الشهر الابتدائي `YYYY-MM`؛ الجاري إن لم يُحدَّد.
  final String? month;

  @override
  ConsumerState<WorkerMonthScreen> createState() => _WorkerMonthScreenState();
}

class _WorkerMonthScreenState extends ConsumerState<WorkerMonthScreen> {
  late String _month = widget.month ?? currentMonthKey();

  static String _time(int millis) {
    final t = DateTime.fromMillisecondsSinceEpoch(
      millis,
      isUtc: true,
    ).toLocal();
    return DateKey.formatMinutes(DateKey.minutesOf(t));
  }

  Future<void> _edit(WorkerDay day) async {
    final choice = await showDialog<OverrideChoice>(
      context: context,
      builder: (context) => ClayDialog(
        title: 'تعديل يوم ${day.date}',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final kind in [
              WorkDayKind.full,
              WorkDayKind.half,
              WorkDayKind.off,
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: ClaySpacing.sm),
                child: ClayButton(
                  label: kind == WorkDayKind.off
                      ? 'غائب (بلا أجر)'
                      : kind.label,
                  kind: ClayButtonKind.secondary,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop((kind: kind)),
                ),
              ),
            if (day.overridden)
              ClayButton(
                label: 'إلغاء التعديل',
                kind: ClayButtonKind.danger,
                expand: true,
                onPressed: () => Navigator.of(context).pop((kind: null)),
              ),
          ],
        ),
        actions: [
          ClayButton(
            label: 'إغلاق',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await ref
        .read(wageServiceProvider)
        .setOverride(
          workerId: widget.workerId,
          date: day.date,
          kind: choice.kind,
        );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final today = DateKey.of(DateTime.now());
    final canEdit = ref.can(PermissionModule.workers, PermissionAction.edit);
    final sheet = ref.watch(workerSheetProvider(_month));
    final summary = sheet.value
        ?.where((s) => s.workerId == widget.workerId)
        .firstOrNull;

    return Scaffold(
      appBar: ClayAppBar(title: summary?.name ?? 'كشف العامل', showBack: true),
      body: summary == null
          ? (sheet.isLoading
                ? const ClayLoadingView()
                : const ClayEmptyView(title: 'هذا العامل غير موجود'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ClaySpacing.screenPadding,
                  ),
                  child: MonthBar(
                    month: _month,
                    onChanged: (m) => setState(() => _month = m),
                  ),
                ),
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
                          'أجر الشهر ${Money.format(summary.month.total)}',
                          style: text.titleSmall,
                        ),
                        Text(
                          '${summary.month.fullDays} يوم كامل · '
                          '${summary.month.halfDays} نصف · '
                          '${summary.month.openDaysBefore(today)} بلا خروج · '
                          'عمل ${durationText(summary.month.totalWorkedMinutes)}',
                          style: text.bodySmall!.copyWith(color: p.textMuted),
                        ),
                        const SizedBox(height: ClaySpacing.xs),
                        const _Legend(),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                    child: WorkerMonthGrid(
                      month: _month,
                      days: summary.month.days,
                      today: today,
                      time: _time,
                      onTap: canEdit ? _edit : null,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// ألوان التقويم وما تعنيه.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    Widget item(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: text.bodySmall),
      ],
    );
    return Wrap(
      spacing: ClaySpacing.md,
      runSpacing: ClaySpacing.xs,
      children: [
        item(p.status.success, 'أكمل نصف يوم أو يوماً'),
        item(p.status.warning, 'حضر أقل من ذلك أو بلا خروج'),
        item(p.status.danger, 'غائب'),
      ],
    );
  }
}

/// شهر العامل كورقة تقويم: سبعة مربعات في كل سطر بدءاً من السبت. في كل مربع التاريخ وأجر اليوم وكل
/// دخول وخروج فيه (ولو دخل وخرج أكثر من مرة)، ولونه: أحمر إن غاب، وأخضر إن أكمل نصف يوم أو يوماً
/// كاملاً، وبرتقالي إن حضر أقل من ذلك أو لم يمسح خروجه.
class WorkerMonthGrid extends StatelessWidget {
  const WorkerMonthGrid({
    required this.month,
    required this.days,
    required this.today,
    required this.time,
    this.onTap,
    super.key,
  });

  /// `YYYY-MM`.
  final String month;
  final List<WorkerDay> days;
  final String today;
  final String Function(int millis) time;
  final void Function(WorkerDay day)? onTap;

  /// أقل عرض لمربع اليوم؛ على الشاشة الضيقة يُمرَّر التقويم أفقياً.
  static const double minCellWidth = 92;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final year = int.parse(month.substring(0, 4));
    final monthNumber = int.parse(month.substring(5, 7));
    final blanks = ClayCalendarMath.leadingBlanks(year, monthNumber);
    final cells = <WorkerDay?>[for (var i = 0; i < blanks; i++) null, ...days];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = constraints.maxWidth / 7;
        final cellWidth = fit < minCellWidth ? minCellWidth : fit;
        final table = Table(
          defaultColumnWidth: FixedColumnWidth(cellWidth),
          children: [
            TableRow(
              children: [
                for (final name in ClayCalendarMath.weekdayNames)
                  Padding(
                    padding: const EdgeInsets.only(bottom: ClaySpacing.xs),
                    child: Text(
                      name,
                      textAlign: TextAlign.center,
                      style: text.labelMedium,
                    ),
                  ),
              ],
            ),
            for (var r = 0; r < cells.length; r += 7)
              TableRow(
                children: [
                  for (final day in cells.sublist(r, r + 7))
                    Padding(
                      padding: const EdgeInsets.all(2),
                      child: day == null
                          ? const SizedBox.shrink()
                          : _DayCell(
                              key: ValueKey('worker-day-${day.date}'),
                              day: day,
                              today: today,
                              time: time,
                              onTap: onTap == null ? null : () => onTap!(day),
                            ),
                    ),
                ],
              ),
          ],
        );
        if (cellWidth * 7 <= constraints.maxWidth) return table;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: table,
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.today,
    required this.time,
    this.onTap,
    super.key,
  });

  final WorkerDay day;
  final String today;
  final String Function(int millis) time;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final status = day.statusOn(today);
    final color = switch (status) {
      WorkDayStatus.absent => p.status.danger,
      WorkDayStatus.complete => p.status.success,
      WorkDayStatus.short => p.status.warning,
      WorkDayStatus.working => p.status.info,
      WorkDayStatus.future => p.textMuted,
    };
    final future = status == WorkDayStatus.future;
    final dayNumber = int.parse(day.date.substring(8));
    final small = text.bodySmall!.copyWith(fontSize: 11);
    final worked = day.workedMinutes;
    return Semantics(
      label: 'يوم $dayNumber',
      button: onTap != null,
      child: Material(
        color: future ? Colors.transparent : color.withValues(alpha: 0.16),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: color.withValues(alpha: future ? 0.25 : 0.7)),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('$dayNumber', style: text.titleSmall),
                      const Spacer(),
                      if (day.overridden)
                        Icon(Icons.edit_rounded, size: 12, color: p.textMuted),
                    ],
                  ),
                  if (!future || day.present)
                    Text(
                      Money.format(day.wage),
                      style: small.copyWith(fontWeight: FontWeight.bold),
                    ),
                  for (final punch in day.punches)
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        '${time(punch.inAt)}–'
                        '${punch.outAt == null ? '…' : time(punch.outAt!)}',
                        style: small,
                      ),
                    ),
                  if (worked != null && day.punches.length > 1)
                    Text(durationText(worked), style: small),
                  if (status == WorkDayStatus.absent && !day.overridden)
                    Text('غائب', style: small),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
