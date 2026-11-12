import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// لون حال الحصة في التقويم والقائمة.
ClayTone toneOf(ChildSessionState state) => switch (state) {
  ChildSessionState.present => ClayTone.success,
  ChildSessionState.absent => ClayTone.danger,
  ChildSessionState.excused => ClayTone.excused,
  ChildSessionState.cancelled => ClayTone.neutral,
  ChildSessionState.upcoming => ClayTone.info,
  ChildSessionState.pending => ClayTone.warning,
};

/// الحال الأبرز لخلية يوم فيه عدة حصص: الغياب ثم غير المسجَّل ثم الباقي.
const List<ChildSessionState> _priority = [
  ChildSessionState.absent,
  ChildSessionState.pending,
  ChildSessionState.excused,
  ChildSessionState.present,
  ChildSessionState.upcoming,
  ChildSessionState.cancelled,
];

/// حضور الابن: يختار الوليّ المادة والشهر فيرى تقويماً بحاله في كل حصة
/// (حضر، غاب، برخصة، أُلغيت، قادمة) وقائمة الحصص بأوقاتها.
class ParentAttendanceScreen extends ConsumerStatefulWidget {
  const ParentAttendanceScreen({super.key});

  @override
  ConsumerState<ParentAttendanceScreen> createState() =>
      _ParentAttendanceScreenState();
}

class _ParentAttendanceScreenState
    extends ConsumerState<ParentAttendanceScreen> {
  String? _groupId;
  late String _month = currentMonthKey();

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
    final profile = ref.watch(studentProfileProvider(child.id));
    return Column(
      children: [
        const ChildSwitcher(),
        Expanded(
          child: profile.when(
            loading: () => const ClaySkeletonList(),
            error: (_, _) => ClayErrorView(
              message: 'تعذّرت قراءة بيانات ابنك',
              onRetry: () => ref.invalidate(studentProfileProvider),
            ),
            data: (data) {
              final enrolments = data?.enrolments ?? const <EnrolmentInfo>[];
              if (enrolments.isEmpty) {
                return const ClayEmptyView(
                  title: 'لا مواد بعد',
                  message: 'لم ينتسب بعد إلى أي مجموعة',
                  icon: ClayIcons.subjects,
                );
              }
              final selected = enrolments.firstWhere(
                (e) => e.groupId == _groupId,
                orElse: () => enrolments.first,
              );
              return _SubjectAttendance(
                studentId: child.id,
                enrolments: enrolments,
                selected: selected,
                month: _month,
                onSubject: (id) => setState(() => _groupId = id),
                onMonth: (m) => setState(() => _month = m),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SubjectAttendance extends ConsumerWidget {
  const _SubjectAttendance({
    required this.studentId,
    required this.enrolments,
    required this.selected,
    required this.month,
    required this.onSubject,
    required this.onMonth,
  });

  final String studentId;
  final List<EnrolmentInfo> enrolments;
  final EnrolmentInfo selected;
  final String month;
  final ValueChanged<String> onSubject;
  final ValueChanged<String> onMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final sessions = ref.watch(
      childMonthProvider((
        studentId: studentId,
        groupId: selected.groupId,
        month: month,
      )),
    );
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: ClaySpacing.screenPadding,
                vertical: ClaySpacing.xs,
              ),
              itemCount: enrolments.length,
              separatorBuilder: (_, _) => const SizedBox(width: ClaySpacing.sm),
              itemBuilder: (context, i) {
                final e = enrolments[i];
                return ClayChip(
                  label: '${e.subjectName} · م${e.groupNumber}',
                  selected: e.groupId == selected.groupId,
                  onTap: () => onSubject(e.groupId),
                );
              },
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: ClaySpacing.screenPadding,
          ),
          sliver: SliverToBoxAdapter(
            child: MonthBar(month: month, onChanged: onMonth),
          ),
        ),
        ...sessions.when(
          loading: () => const [SliverFillRemaining(child: ClayLoadingView())],
          error: (_, _) => [
            SliverFillRemaining(
              child: ClayErrorView(
                message: 'تعذّرت قراءة الحضور',
                onRetry: () => ref.invalidate(childMonthProvider),
              ),
            ),
          ],
          data: (list) => [
            SliverPadding(
              padding: const EdgeInsets.all(ClaySpacing.screenPadding),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SummaryRow(
                      summary: ChildAttendanceService.summarize(list),
                    ),
                    const SizedBox(height: ClaySpacing.md),
                    _CalendarGrid(month: month, sessions: list),
                    const SizedBox(height: ClaySpacing.sm),
                    const _Legend(),
                    if (list.isNotEmpty) ...[
                      const SizedBox(height: ClaySpacing.lg),
                      Text('حصص الشهر', style: text.titleSmall),
                    ],
                  ],
                ),
              ),
            ),
            if (list.isEmpty)
              const SliverToBoxAdapter(
                child: ClayEmptyView(
                  title: 'لا حصص في هذا الشهر',
                  icon: ClayIcons.attendance,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ClaySpacing.screenPadding,
                ),
                sliver: SliverFixedExtentList(
                  itemExtent: 80,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => ClayListTile(
                      title: teacherDayLabel(list[i].date),
                      subtitle:
                          '${DateKey.formatMinutes(list[i].startMinutes)} - '
                          '${DateKey.formatMinutes(list[i].endMinutes)}',
                      trailing: [
                        ClayBadge(
                          label: list[i].state.label,
                          tone: toneOf(list[i].state),
                        ),
                      ],
                    ),
                    childCount: list.length,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: ClaySpacing.xl)),
          ],
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});

  final ChildAttendanceSummary summary;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: ClaySpacing.sm,
      runSpacing: ClaySpacing.xs,
      children: [
        ClayBadge(label: 'حضر ${summary.present}', tone: ClayTone.success),
        ClayBadge(label: 'غاب ${summary.absent}', tone: ClayTone.danger),
        ClayBadge(label: 'برخصة ${summary.excused}', tone: ClayTone.excused),
      ],
    );
  }
}

/// تقويم الشهر: أيامه في أسبوع يبدأ السبت، ويلوَّن يوم الحصة بحاله فيها.
class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({required this.month, required this.sessions});

  final String month;
  final List<ChildSession> sessions;

  /// أيام الأسبوع بترتيب الجزائر: السبت أولاً (أرقامها كما في `DateTime`).
  static const List<int> _weekdays = [6, 7, 1, 2, 3, 4, 5];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final first = DateKey.parse('$month-01');
    final days = DateTime(first.year, first.month + 1, 0).day;
    final offset = _weekdays.indexOf(first.weekday);
    final byDay = <int, ChildSessionState>{};
    for (final s in sessions) {
      final current = byDay[s.day];
      if (current == null ||
          _priority.indexOf(s.state) < _priority.indexOf(current)) {
        byDay[s.day] = s.state;
      }
    }
    final cells = <Widget>[
      for (final w in _weekdays)
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              GroupService.weekdayName(w),
              style: text.labelSmall!.copyWith(color: p.textMuted),
            ),
          ),
        ),
      for (var i = 0; i < offset; i++) const SizedBox.shrink(),
      for (var day = 1; day <= days; day++)
        _DayCell(day: day, state: byDay[day]),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: ClaySpacing.xs,
      crossAxisSpacing: ClaySpacing.xs,
      children: cells,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.state});

  final int day;
  final ChildSessionState? state;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final s = state;
    final color = s == null ? null : ClayBadge.colorOf(p, toneOf(s));
    return Semantics(
      label: s == null ? '$day' : '$day، ${s.label}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color?.withValues(alpha: 0.22),
          border: color == null ? null : Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(ClayRadius.sm),
        ),
        child: Center(
          child: Text(
            '$day',
            style: text.bodyMedium!.copyWith(
              color: color == null ? p.textMuted : p.text,
              fontWeight: color == null ? null : FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// دليل الألوان.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: ClaySpacing.sm,
      runSpacing: ClaySpacing.xs,
      children: [
        for (final s in ChildSessionState.values)
          ClayBadge(label: s.label, tone: toneOf(s)),
      ],
    );
  }
}
