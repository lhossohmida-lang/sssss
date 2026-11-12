import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// تفاصيل المجموعة: أستاذها وجدولها وقاعتها، وشبكة حضور الدورة (صفوف
/// التلاميذ وأعمدة الحصص) مع التنقل بين الدورات.
class GroupDetailsScreen extends ConsumerStatefulWidget {
  const GroupDetailsScreen({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends ConsumerState<GroupDetailsScreen> {
  /// الدورة المعروضة؛ `null` يعني الحالية.
  int? _cycle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final item = ref.watch(groupItemProvider(widget.groupId));
    final canEdit = ref.can(PermissionModule.groups, PermissionAction.edit);
    final grid = ref.watch(
      groupGridProvider((groupId: widget.groupId, cycle: _cycle)),
    );

    return Scaffold(
      appBar: ClayAppBar(
        title: item == null ? 'المجموعة' : 'المجموعة ${item.number}',
        showBack: true,
        actions: [
          if (canEdit && item != null)
            IconButton(
              tooltip: 'تعديل المجموعة',
              icon: const Icon(ClayIcons.edit),
              onPressed: () => context.push('/groups/${item.id}/edit'),
            ),
        ],
      ),
      body: grid.when(
        loading: () => const ClayLoadingView(),
        error: (_, _) => ClayErrorView(
          message: 'تعذّرت قراءة المجموعة',
          onRetry: () => ref.invalidate(groupGridProvider),
        ),
        data: (g) {
          if (g == null) {
            return const ClayEmptyView(title: 'هذه المجموعة غير موجودة');
          }
          return ListView(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            children: [
              if (item != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: ClaySpacing.lg),
                  child: ClayCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.subjectName, style: text.titleLarge),
                        const SizedBox(height: ClaySpacing.xs),
                        Text(
                          '${item.teacherName} · ${item.roomName ?? 'بلا قاعة'} '
                          '· ${item.studentCount} تلميذ',
                          style: text.bodyMedium,
                        ),
                        const SizedBox(height: ClaySpacing.xs),
                        Text(
                          item.scheduleText,
                          style: text.bodySmall!.copyWith(color: p.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              _CycleBar(
                grid: g,
                onChanged: (cycle) => setState(
                  () => _cycle = cycle == g.group.currentCycleNumber
                      ? null
                      : cycle,
                ),
              ),
              const SizedBox(height: ClaySpacing.md),
              if (g.sessions.isEmpty)
                const ClayEmptyView(
                  title: 'لا حصص في هذه الدورة',
                  icon: ClayIcons.schedule,
                )
              else if (g.students.isEmpty)
                const ClayEmptyView(
                  title: 'لا تلاميذ في هذه المجموعة',
                  message: 'يُنسب التلاميذ إليها من استمارة التسجيل أو ملفهم',
                  icon: ClayIcons.students,
                )
              else
                AttendanceGridTable(grid: g),
              const SizedBox(height: ClaySpacing.lg),
              const _Legend(),
            ],
          );
        },
      ),
    );
  }
}

/// شريط الدورة: رقمها والتنقل بين الدورات، وتقدّم حصصها.
class _CycleBar extends StatelessWidget {
  const _CycleBar({required this.grid, required this.onChanged});

  final GroupGrid grid;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cycle = grid.cycleNumber;
    final current = grid.group.currentCycleNumber;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'الدورة السابقة',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: cycle > 1 ? () => onChanged(cycle - 1) : null,
            ),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  grid.isCurrent ? 'الدورة $cycle (الحالية)' : 'الدورة $cycle',
                  textAlign: TextAlign.center,
                  style: text.titleMedium,
                ),
              ),
            ),
            IconButton(
              tooltip: 'الدورة التالية',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: cycle < current ? () => onChanged(cycle + 1) : null,
            ),
          ],
        ),
        ClayProgress(
          value: grid.group.sessionsPerCycle == 0
              ? 0
              : grid.heldSessions / grid.group.sessionsPerCycle,
          semanticLabel: 'حصص الدورة المنعقدة',
        ),
        const SizedBox(height: ClaySpacing.xs),
        Text(
          'انعقدت ${grid.heldSessions} من ${grid.group.sessionsPerCycle} حصة',
          style: text.bodySmall,
        ),
      ],
    );
  }
}

/// جدول الحضور: عمود للتلميذ وعمود لكل حصة، وخلية بحالته. يتمرر أفقياً إن
/// ضاق العرض، والصفوف في `ListView.builder` بارتفاع ثابت.
class AttendanceGridTable extends StatelessWidget {
  const AttendanceGridTable({required this.grid, super.key});

  final GroupGrid grid;

  static const double nameWidth = 150;
  static const double cellWidth = 56;
  static const double rowHeight = 52;
  static const double headerHeight = 64;
  static const double totalsWidth = 64;

  static String _shortDate(String key) {
    final parts = key.split('-');
    return '${parts[2]}/${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final sessions = grid.sessions;
    final tableWidth = nameWidth + sessions.length * cellWidth + totalsWidth;

    Widget header(SessionRow s) {
      final cancelled = !SessionStatus.fromCode(s.status).countsInCycle;
      return SizedBox(
        width: cellWidth,
        height: headerHeight,
        child: Semantics(
          label: cancelled
              ? 'حصة ملغاة ${_shortDate(s.date)}'
              : 'حصة ${s.sessionNumber ?? ''} ${_shortDate(s.date)}',
          excludeSemantics: true,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                cancelled ? '—' : '${s.sessionNumber ?? ''}',
                style: text.labelLarge!.copyWith(
                  color: cancelled ? p.textMuted : p.text,
                ),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  _shortDate(s.date),
                  style: text.labelSmall!.copyWith(
                    decoration: cancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ClayContainer.flat(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          height: headerHeight + grid.students.length * rowHeight,
          child: Column(
            children: [
              Container(
                height: headerHeight,
                color: p.surfacePressed,
                child: Row(
                  children: [
                    const SizedBox(
                      width: nameWidth,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: ClaySpacing.md,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text('التلميذ'),
                        ),
                      ),
                    ),
                    for (final s in sessions) header(s),
                    SizedBox(
                      width: totalsWidth,
                      child: Center(
                        child: Text('حضور', style: text.labelMedium),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: grid.students.length,
                  itemExtent: rowHeight,
                  itemBuilder: (context, i) =>
                      _GridRow(student: grid.students[i], sessions: sessions),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridRow extends StatelessWidget {
  const _GridRow({required this.student, required this.sessions});

  final GridStudent student;
  final List<SessionRow> sessions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final counted = sessions
        .where((s) => SessionStatus.fromCode(s.status).countsInCycle)
        .length;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: p.outline.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: AttendanceGridTable.nameWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: ClaySpacing.md),
              child: Text(
                student.leftGroup ? '${student.name} (غادر)' : student.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium!.copyWith(
                  color: student.leftGroup ? p.textMuted : p.text,
                ),
              ),
            ),
          ),
          for (final s in sessions)
            _Cell(
              status: student.cells[s.id],
              cancelled: !SessionStatus.fromCode(s.status).countsInCycle,
            ),
          SizedBox(
            width: AttendanceGridTable.totalsWidth,
            child: Center(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  '${student.count(AttendanceStatus.present)}/$counted',
                  style: text.labelMedium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// خلية حضور: حاضر أخضر، غائب أحمر، برخصة بنفسجي، لا تسجيل شرطة باهتة،
/// والحصة الملغاة خلية فارغة. الحالة تُقرأ أيضاً بقارئ الشاشة لا باللون فقط.
class _Cell extends StatelessWidget {
  const _Cell({required this.status, required this.cancelled});

  final AttendanceStatus? status;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (IconData?, Color, String) look = cancelled
        ? (null, p.outline, 'ملغاة')
        : switch (status) {
            AttendanceStatus.present => (
              ClayIcons.check,
              p.status.success,
              'حاضر',
            ),
            AttendanceStatus.absent => (
              ClayIcons.close,
              p.status.danger,
              'غائب',
            ),
            AttendanceStatus.excused => (
              Icons.remove_circle_outline_rounded,
              p.status.excused,
              'غائب برخصة',
            ),
            null => (null, p.outline, 'لم يُسجَّل'),
          };
    return SizedBox(
      width: AttendanceGridTable.cellWidth,
      child: Center(
        child: Semantics(
          label: look.$3,
          excludeSemantics: true,
          child: look.$1 == null
              ? Text('·', style: TextStyle(color: look.$2, fontSize: 20))
              : Icon(look.$1, color: look.$2, size: 24),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: ClaySpacing.sm,
      runSpacing: ClaySpacing.xs,
      children: [
        ClayBadge(label: 'حاضر', tone: ClayTone.success),
        ClayBadge(label: 'غائب', tone: ClayTone.danger),
        ClayBadge(label: 'غائب برخصة', tone: ClayTone.excused),
      ],
    );
  }
}
