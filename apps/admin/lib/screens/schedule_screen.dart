import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// الجدول الأسبوعي: لكل قاعة أو أستاذ شبكة أيام الأسبوع (السبت أولاً)
/// بمحور ساعات أفقي، وكل حصة ثابتة مستطيل على محورها.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  ScheduleAxis _axis = ScheduleAxis.room;

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(weeklyScheduleProvider);
    return Scaffold(
      appBar: const ClayAppBar(title: 'الجدول الأسبوعي', showBack: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaySpacing.screenPadding,
            ),
            child: Wrap(
              spacing: ClaySpacing.sm,
              children: [
                for (final axis in ScheduleAxis.values)
                  ClayChip(
                    label: axis.label,
                    selected: _axis == axis,
                    onTap: () => setState(() => _axis = axis),
                  ),
              ],
            ),
          ),
          Expanded(
            child: schedule.when(
              loading: () => const ClayLoadingView(),
              error: (_, _) => ClayErrorView(
                message: 'تعذّرت قراءة الجدول',
                onRetry: () => ref.invalidate(weeklyScheduleProvider),
              ),
              data: (data) {
                if (data.isEmpty) {
                  return const ClayEmptyView(
                    title: 'لا حصص في الجدول',
                    message: 'تظهر هنا حصص المجموعات بعد إنشائها',
                    icon: ClayIcons.schedule,
                  );
                }
                final resources = data.by(_axis);
                return ListView.builder(
                  padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                  itemCount: resources.length,
                  itemExtent: _ResourceGrid.height + ClaySpacing.md,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: ClaySpacing.md),
                    child: _ResourceGrid(
                      resource: resources[i],
                      axis: _axis,
                      firstMinute: data.firstMinute,
                      lastMinute: data.lastMinute,
                    ),
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

/// بطاقة مورد واحد: عنوانه ثم شبكته الأسبوعية.
class _ResourceGrid extends StatelessWidget {
  const _ResourceGrid({
    required this.resource,
    required this.axis,
    required this.firstMinute,
    required this.lastMinute,
  });

  final ResourceSchedule resource;
  final ScheduleAxis axis;
  final int firstMinute;
  final int lastMinute;

  static const double titleHeight = 44;
  static const double headerHeight = 28;
  static const double rowHeight = 52;
  static const double dayWidth = 72;
  static const double hourWidth = 72;

  /// ارتفاع البطاقة: عنوان، رأس الساعات، سبعة أيام، وحشوة البطاقة وإطارها.
  static const double height =
      titleHeight + headerHeight + rowHeight * 7 + ClaySpacing.md * 2 + 16;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final startHour = firstMinute ~/ 60;
    final endHour = (lastMinute + 59) ~/ 60;
    final hours = endHour - startHour;
    final gridWidth = hours * hourWidth;

    return ClayCard(
      padding: const EdgeInsets.all(ClaySpacing.md),
      child: Column(
        children: [
          SizedBox(
            height: titleHeight,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                axis == ScheduleAxis.room
                    ? resource.name
                    : 'الأستاذ ${resource.name}',
                style: text.titleMedium,
              ),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: dayWidth,
                  child: Column(
                    children: [
                      const SizedBox(height: headerHeight),
                      for (final day in GroupService.displayWeekdays)
                        SizedBox(
                          height: rowHeight,
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              GroupService.weekdayName(day),
                              style: text.labelMedium,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: gridWidth,
                      child: Column(
                        children: [
                          SizedBox(
                            height: headerHeight,
                            child: Row(
                              children: [
                                for (var h = startHour; h < endHour; h++)
                                  SizedBox(
                                    width: hourWidth,
                                    child: Directionality(
                                      textDirection: TextDirection.ltr,
                                      child: Text(
                                        DateKey.formatMinutes(h * 60),
                                        style: text.labelSmall!.copyWith(
                                          color: p.textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          for (final day in GroupService.displayWeekdays)
                            _DayRow(
                              entries: resource.on(day),
                              axis: axis,
                              startMinute: startHour * 60,
                              width: gridWidth,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// صف يوم: خلفية بخطوط الساعات وفوقها مستطيلات الحصص.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.entries,
    required this.axis,
    required this.startMinute,
    required this.width,
  });

  final List<ScheduleEntry> entries;
  final ScheduleAxis axis;
  final int startMinute;
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: _ResourceGrid.rowHeight,
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: p.outline.withValues(alpha: 0.4)),
          ),
        ),
        child: Stack(
          children: [
            for (final e in entries)
              PositionedDirectional(
                start:
                    (e.startMinutes - startMinute) /
                    60 *
                    _ResourceGrid.hourWidth,
                top: 3,
                bottom: 3,
                width:
                    (e.endMinutes - e.startMinutes) /
                    60 *
                    _ResourceGrid.hourWidth,
                child: _Block(entry: e, axis: axis),
              ),
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.entry, required this.axis});

  final ScheduleEntry entry;
  final ScheduleAxis axis;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    // القاعة تظهر في عرض الأستاذ، والأستاذ في عرض القاعة.
    final other = axis == ScheduleAxis.room
        ? entry.teacherName
        : (entry.roomName ?? 'بلا قاعة');
    final label = '${entry.label} · $other';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: p.accent,
          borderRadius: BorderRadius.circular(ClayRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(ClayRadius.sm),
            onTap: () => context.push('/groups/${entry.groupId}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ClaySpacing.xs,
                vertical: 2,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'م${entry.groupNumber} · ${entry.subjectName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium!.copyWith(color: p.onAccent),
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      entry.timeText,
                      maxLines: 1,
                      style: text.labelSmall!.copyWith(color: p.onAccent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
