import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// مفتاح الشهر الجاري `YYYY-MM`.
String currentMonthKey() => DateKey.of(DateTime.now()).substring(0, 7);

/// شريط التنقل بين الأشهر: اسم الشهر والسنة وسهما السابق والتالي.
class MonthBar extends StatelessWidget {
  const MonthBar({required this.month, required this.onChanged, super.key});

  final String month;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        IconButton(
          tooltip: 'الشهر السابق',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => onChanged(DateKey.shiftMonth(month, -1)),
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              DateKey.monthLabel(month),
              textAlign: TextAlign.center,
              style: text.titleMedium,
            ),
          ),
        ),
        IconButton(
          tooltip: 'الشهر التالي',
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () => onChanged(DateKey.shiftMonth(month, 1)),
        ),
      ],
    );
  }
}

/// كشف حضور العمال الشهري: لكل عامل أيام الكامل والنصف والغياب وأجر الشهر،
/// وإجمالي الأجور. يُفتح كشف العامل اليومي بالنقر عليه.
class WorkerSheetScreen extends ConsumerStatefulWidget {
  const WorkerSheetScreen({super.key});

  @override
  ConsumerState<WorkerSheetScreen> createState() => _WorkerSheetScreenState();
}

class _WorkerSheetScreenState extends ConsumerState<WorkerSheetScreen> {
  String _month = currentMonthKey();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final today = DateKey.of(DateTime.now());
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
                    return ClayListTile(
                      leading: ClayAvatar(name: w.name),
                      title: w.name,
                      subtitle:
                          '${m.fullDays} يوم كامل · ${m.halfDays} نصف · '
                          '${m.absencesUntil(today)} غياب\n'
                          'تأخر ${m.totalLateMinutes} د',
                      subtitleLines: 2,
                      onTap: () => context.push(
                        '/worker-attendance/${w.workerId}?month=$_month',
                      ),
                      trailing: [
                        Text(Money.format(m.total), style: text.titleSmall),
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

/// كشف عامل لشهر يوماً بيوم: ما يقوله برنامجه وحضوره وما يُدفع عنه، مع
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
                          '${summary.month.absencesUntil(today)} غياب · '
                          'تأخر ${summary.month.totalLateMinutes} د',
                          style: text.bodySmall!.copyWith(color: p.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                    itemCount: summary.month.days.length,
                    itemExtent: 84,
                    itemBuilder: (context, i) {
                      final day = summary.month.days[i];
                      return _DayTile(
                        day: day,
                        today: today,
                        onTap: canEdit ? () => _edit(day) : null,
                        time: _time,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.day,
    required this.today,
    required this.time,
    this.onTap,
  });

  final WorkerDay day;
  final String today;
  final VoidCallback? onTap;
  final String Function(int millis) time;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dayNumber = int.parse(day.date.substring(8));
    final weekday = GroupService.weekdayName(DateKey.weekday(day.date));
    final attendance = day.present
        ? 'حضر ${time(day.checkIn!)}'
              '${day.checkOut == null ? '' : '–${time(day.checkOut!)}'}'
              '${day.lateMinutes > 0 ? ' · تأخر ${day.lateMinutes} د' : ''}'
        : day.scheduled == WorkDayKind.off
        ? 'يوم راحة'
        : day.date.compareTo(today) > 0
        ? 'لم يحن بعد'
        : 'غائب';
    final badge = switch (day.paidKind) {
      WorkDayKind.full => const ClayBadge(
        label: 'يوم كامل',
        tone: ClayTone.success,
      ),
      WorkDayKind.half => const ClayBadge(
        label: 'نصف يوم',
        tone: ClayTone.info,
      ),
      WorkDayKind.off =>
        day.isAbsence && day.date.compareTo(today) <= 0
            ? const ClayBadge(label: 'غياب', tone: ClayTone.danger)
            : null,
    };
    return ClayListTile(
      title:
          '$dayNumber ${DateKey.monthName(int.parse(day.date.substring(5, 7)))}'
          ' · $weekday${day.overridden ? ' (معدَّل)' : ''}',
      subtitle: '${day.scheduled.label} · $attendance',
      onTap: onTap,
      trailing: [
        ?badge,
        const SizedBox(width: ClaySpacing.xs),
        Text(Money.format(day.wage), style: text.titleSmall),
      ],
    );
  }
}
