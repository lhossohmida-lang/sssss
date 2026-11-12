import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// صف في قائمة الجدول: عنوان قسم، أو حصة قادمة، أو خانة أسبوعية.
sealed class _Row {
  const _Row();
}

class _Header extends _Row {
  const _Header(this.title);

  final String title;
}

class _Upcoming extends _Row {
  const _Upcoming(this.session);

  final UpcomingSession session;
}

class _Weekly extends _Row {
  const _Weekly(this.entry);

  final ScheduleEntry entry;
}

/// جدول الابن: حصصه القادمة بمواعيدها الفعلية (بعد أي تغيير أو إلغاء)، ثم
/// جدوله الأسبوعي الثابت مرتباً من السبت.
class ParentScheduleScreen extends ConsumerWidget {
  const ParentScheduleScreen({super.key});

  static const double _headerHeight = 48;
  static const double _rowHeight = 88;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final child = ref.watch(selectedChildProvider);
    if (child == null) {
      return const ClayEmptyView(
        title: 'لا أبناء مرتبطون بحسابك',
        message: 'تواصل مع المدرسة لربط أبنائك بحسابك',
        icon: ClayIcons.students,
      );
    }
    final upcoming = ref.watch(childUpcomingProvider(child.id));
    final weekly = ref.watch(childWeeklyProvider(child.id));
    return Column(
      children: [
        const ChildSwitcher(),
        Expanded(
          child: switch ((upcoming, weekly)) {
            (AsyncData(value: final u), AsyncData(value: final w)) => _content(
              u,
              w,
            ),
            (AsyncError(), _) || (_, AsyncError()) => ClayErrorView(
              message: 'تعذّرت قراءة الجدول',
              onRetry: () {
                ref.invalidate(childUpcomingProvider);
                ref.invalidate(childWeeklyProvider);
              },
            ),
            _ => const ClaySkeletonList(),
          },
        ),
      ],
    );
  }

  Widget _content(List<UpcomingSession> upcoming, WeeklySchedule weekly) {
    if (upcoming.isEmpty && weekly.isEmpty) {
      return const ClayEmptyView(
        title: 'لا حصص في جدوله',
        message: 'تظهر حصصه هنا حين ينتسب إلى مجموعة',
        icon: ClayIcons.schedule,
      );
    }
    final rows = <_Row>[
      if (upcoming.isNotEmpty) ...[
        const _Header('الحصص القادمة'),
        for (final s in upcoming) _Upcoming(s),
      ],
      if (!weekly.isEmpty) ...[
        const _Header('الجدول الأسبوعي'),
        for (final day in GroupService.displayWeekdays)
          for (final e in weekly.entries)
            if (e.weekday == day) _Weekly(e),
      ],
    ];
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: ClaySpacing.screenPadding,
      ),
      itemCount: rows.length,
      itemExtentBuilder: (i, _) =>
          rows[i] is _Header ? _headerHeight : _rowHeight,
      itemBuilder: (context, i) => switch (rows[i]) {
        _Header(:final title) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        _Upcoming(:final session) => _UpcomingTile(session: session),
        _Weekly(:final entry) => ClayListTile(
          title: '${entry.subjectName} · م${entry.groupNumber}',
          subtitle:
              '${GroupService.weekdayName(entry.weekday)} ${entry.timeText} · '
              '${entry.teacherName}'
              '${entry.roomName == null ? '' : ' · ${entry.roomName}'}',
          subtitleLines: 2,
        ),
      },
    );
  }
}

class _UpcomingTile extends StatelessWidget {
  const _UpcomingTile({required this.session});

  final UpcomingSession session;

  @override
  Widget build(BuildContext context) {
    return ClayListTile(
      title: '${session.subjectName} · م${session.groupNumber}',
      subtitle:
          '${teacherDayLabel(session.date)} · ${session.timeText}'
          '${session.roomName == null ? '' : ' · ${session.roomName}'}',
      subtitleLines: 2,
      trailing: [
        if (session.cancelled)
          const ClayBadge(label: 'أُلغيت', tone: ClayTone.danger),
      ],
    );
  }
}
