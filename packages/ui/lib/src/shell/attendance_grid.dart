import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_container.dart';
import '../clay/clay_display.dart';
import '../clay/clay_icons.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'providers.dart';

/// ضغطة على خانة تلميذ في حصة (لتغيير حضوره).
typedef GridCellTap = void Function(SessionRow session, GridStudent student);

/// ضغطة على عنوان حصة (لفتح ورقة حضورها).
typedef GridSessionTap = void Function(SessionRow session);

/// هل تُعدَّل خانات هذه الحصة؟ حصة غير ملغاة تاريخها اليوم أو قبله.
bool gridSessionEditable(SessionRow s, String today) =>
    SessionStatus.fromCode(s.status).countsInCycle &&
    s.date.compareTo(today) <= 0;

/// شبكة حضور دورة مجموعة بتنقل بين الدورات وتقدّم حصصها ودليل الألوان، تُعرض
/// تحت [header] (بطاقة معلومات المجموعة). مشتركة بين الإدارة والأستاذ.
class GroupGridView extends ConsumerStatefulWidget {
  const GroupGridView({
    required this.groupId,
    this.header = const [],
    this.onCellTap,
    this.onSessionTap,
    super.key,
  });

  final String groupId;
  final List<Widget> header;

  /// الإدارة: تغيير حضور تلميذ في حصة مضت أو حصة اليوم بضغط خانته. `null` (الأستاذ): للعرض فقط.
  final GridCellTap? onCellTap;

  /// الإدارة: فتح ورقة حضور الحصة بضغط عنوانها.
  final GridSessionTap? onSessionTap;

  @override
  ConsumerState<GroupGridView> createState() => _GroupGridViewState();
}

class _GroupGridViewState extends ConsumerState<GroupGridView> {
  /// الدورة المعروضة؛ `null` يعني الحالية.
  int? _cycle;

  @override
  Widget build(BuildContext context) {
    final grid = ref.watch(
      groupGridProvider((groupId: widget.groupId, cycle: _cycle)),
    );
    return grid.when(
      loading: () => const ClayLoadingView(),
      error: (_, _) => ClayErrorView(
        message: 'تعذّرت قراءة الفوج',
        onRetry: () => ref.invalidate(groupGridProvider),
      ),
      data: (g) {
        if (g == null) {
          return const ClayEmptyView(title: 'هذا الفوج غير موجود');
        }
        return ListView(
          padding: const EdgeInsets.all(ClaySpacing.screenPadding),
          children: [
            ...widget.header,
            _CycleBar(
              grid: g,
              onChanged: (cycle) => setState(
                () =>
                    _cycle = cycle == g.group.currentCycleNumber ? null : cycle,
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
                title: 'لا تلاميذ في هذا الفوج',
                message: 'يُنسب التلاميذ إليها من استمارة التسجيل أو ملفهم',
                icon: ClayIcons.students,
              )
            else ...[
              if (widget.onCellTap != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: ClaySpacing.sm),
                  child: Text(
                    'اضغط خانة تلميذ لتغيير حضوره في حصة مضت (ولو أُغلقت)، أو رقم '
                    'الحصة لفتح ورقة حضورها.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              AttendanceGridTable(
                grid: g,
                onCellTap: widget.onCellTap,
                onSessionTap: widget.onSessionTap,
              ),
            ],
            const SizedBox(height: ClaySpacing.lg),
            _Legend(
              showPayment: g.students.any((s) => s.coveredSessions != null),
              showReview: g.reviewSessions.isNotEmpty,
            ),
          ],
        );
      },
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
  const AttendanceGridTable({
    required this.grid,
    this.onCellTap,
    this.onSessionTap,
    super.key,
  });

  final GroupGrid grid;
  final GridCellTap? onCellTap;
  final GridSessionTap? onSessionTap;

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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // على الشاشات العريضة تتمدد خانات الحصص لتملأ العرض.
      final shown = grid.sessions.length + grid.reviewSessions.length;
      final sessionCount = shown == 0 ? 1 : shown;
      final spare = box.maxWidth - nameWidth - totalsWidth;
      final cell = spare / sessionCount > cellWidth
          ? spare / sessionCount
          : cellWidth;
      return _table(context, cell);
    },
  );

  Widget _table(BuildContext context, double cellWidth) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final sessions = grid.sessions;
    // أعمدة الدورة بالترتيب الزمني: حصصها، وحصص المراجعة التي حضرها بعض تلاميذ الفوج (تُعدّ حصصاً من
    // دورتهم فتقع بين حصصها بحسب تاريخها).
    final columns = _GridColumn.merge(sessions, grid.reviewSessions);
    final tableWidth = nameWidth + columns.length * cellWidth + totalsWidth;
    final today = DateKey.of(DateTime.now());

    Widget header(SessionRow s) {
      final cancelled = !SessionStatus.fromCode(s.status).countsInCycle;
      final open = onSessionTap;
      final box = SizedBox(
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
      if (open == null || !gridSessionEditable(s, today)) return box;
      return InkWell(
        key: ValueKey('grid-session-${s.id}'),
        onTap: () => open(s),
        child: box,
      );
    }

    // حصة مراجعة حضرها بعض تلاميذ الفوج ضيوفاً: حصة من دورتهم بعنوان «م» بدل رقم الحصة.
    Widget reviewHeader(SessionRow s) => SizedBox(
      width: cellWidth,
      height: headerHeight,
      child: Semantics(
        label: 'حصة مراجعة ${_shortDate(s.date)}',
        excludeSemantics: true,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('م', style: text.labelLarge!.copyWith(color: p.accent)),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(_shortDate(s.date), style: text.labelSmall),
            ),
          ],
        ),
      ),
    );

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
                    for (final c in columns)
                      c.review ? reviewHeader(c.session) : header(c.session),
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
                  itemBuilder: (context, i) => _GridRow(
                    student: grid.students[i],
                    sessions: sessions,
                    columns: columns,
                    cellWidth: cellWidth,
                    today: today,
                    onCellTap: onCellTap,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// عمود في الشبكة: حصة من حصص الدورة أو حصة مراجعة هي حصة من دورة من حضرها ضيفاً.
class _GridColumn {
  const _GridColumn(this.session, {required this.review});

  final SessionRow session;
  final bool review;

  /// الأعمدة بالترتيب الزمني (التاريخ ثم وقت البداية، ثم الحصة العامة قبل المراجعة، ثم المعرّف).
  static List<_GridColumn> merge(
    List<SessionRow> sessions,
    List<SessionRow> reviews,
  ) =>
      [
        for (final s in sessions) _GridColumn(s, review: false),
        for (final s in reviews) _GridColumn(s, review: true),
      ]..sort((a, b) {
        final byDate = a.session.date.compareTo(b.session.date);
        if (byDate != 0) return byDate;
        final byStart = a.session.startMinutes.compareTo(
          b.session.startMinutes,
        );
        if (byStart != 0) return byStart;
        if (a.review != b.review) return a.review ? 1 : -1;
        return a.session.id.compareTo(b.session.id);
      });
}

class _GridRow extends StatelessWidget {
  const _GridRow({
    required this.student,
    required this.sessions,
    required this.columns,
    required this.cellWidth,
    required this.today,
    this.onCellTap,
  });

  final GridStudent student;
  final String today;
  final GridCellTap? onCellTap;

  /// حصص الدورة العامة (للمجموع)، و[columns] كل أعمدة الشبكة بترتيبها الزمني.
  final List<SessionRow> sessions;
  final List<_GridColumn> columns;
  final double cellWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final counted = sessions
        .where((s) => SessionStatus.fromCode(s.status).countsInCycle)
        .length;
    // الحصص المحسوبة (غير الملغاة) بالترتيب: من دفع شهره تُدفع أولى حصصه بقدر ما دفع. وحصة المراجعة
    // خلية لمن هو ضيف فيها (حصة من دورته)، وفراغ لغيره، ولا تدخل ترتيب التسديد.
    var position = 0;
    final cells = <Widget>[];
    // خانة تُضغط لتغيير الحضور (الإدارة): حصة اليوم أو ما قبله غير ملغاة.
    Widget tappable(SessionRow s, Widget cell) {
      final tap = onCellTap;
      if (tap == null || !gridSessionEditable(s, today)) return cell;
      // الصف يبقى وحدة واحدة لقارئ الشاشة؛ وتغيير الحضور له من ورقة الحصة (عنوان العمود).
      return GestureDetector(
        key: ValueKey('grid-cell-${s.id}-${student.studentId}'),
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () => tap(s, student),
        child: cell,
      );
    }

    for (final c in columns) {
      final s = c.session;
      if (c.review) {
        cells.add(
          student.reviewSessionIds.contains(s.id)
              ? tappable(
                  s,
                  _Cell(
                    width: cellWidth,
                    status: student.cells[s.id],
                    cancelled: false,
                    review: true,
                  ),
                )
              : SizedBox(width: cellWidth),
        );
        continue;
      }
      final cancelled = !SessionStatus.fromCode(s.status).countsInCycle;
      cells.add(
        tappable(
          s,
          _Cell(
            width: cellWidth,
            status: student.cells[s.id],
            cancelled: cancelled,
            paid: cancelled ? null : student.paidAt(position),
          ),
        ),
      );
      if (!cancelled) position++;
    }
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
          ...cells,
          SizedBox(
            width: AttendanceGridTable.totalsWidth,
            child: Center(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  '${student.presentTotal(sessions)}/${student.sessionsTotal(counted)}',
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

/// خلية حضور: مربع تدل علامته على الحضور (✓ حاضر، ✗ غائب، رمز «برخصة»)، ولونه على الدفع:
/// **أزرق** لحصة مدفوعة (حتى قبل أن يحضرها)، و**أحمر** لمن حضر ولم يدفع، وبلا لون لما سوى ذلك.
/// حيث لا تُحسب المدفوعات (تطبيق الأستاذ) تبقى العلامة وحدها. والحصة الملغاة خلية فارغة. الحالة
/// تُقرأ أيضاً بقارئ الشاشة لا باللون فقط.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.width,
    required this.status,
    required this.cancelled,
    this.paid,
    this.review = false,
  });

  final double width;
  final AttendanceStatus? status;
  final bool cancelled;

  /// حصة مراجعة هي حصة من دورة التلميذ (تُذكر لقارئ الشاشة).
  final bool review;

  /// هل الحصة مدفوعة؟ `null` إن لم تُحسب المدفوعات.
  final bool? paid;

  static const double _box = 34;

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
    final unpaidAttended = paid == false && status == AttendanceStatus.present;
    final Color? fill = cancelled
        ? null
        : paid == true
        ? p.status.info
        : unpaidAttended
        ? p.status.danger
        : null;
    final payment = cancelled || paid == null
        ? ''
        : paid!
        ? ' · مدفوعة'
        : unpaidAttended
        ? ' · لم يدفع'
        : '';
    return SizedBox(
      width: width,
      child: Center(
        child: Semantics(
          label: '${look.$3}$payment${review ? ' · حصة مراجعة' : ''}',
          excludeSemantics: true,
          child: fill != null
              ? Container(
                  width: _box,
                  height: _box,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(ClayRadius.sm),
                  ),
                  child: look.$1 == null
                      ? null
                      : Icon(look.$1, color: Colors.white, size: 22),
                )
              : look.$1 == null
              ? Text('·', style: TextStyle(color: look.$2, fontSize: 20))
              : Icon(look.$1, color: look.$2, size: 24),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({this.showPayment = false, this.showReview = false});

  /// هل تُحسب المدفوعات؟ فيُشرح لونا المربعين.
  final bool showPayment;

  /// هل في الدورة حصة مراجعة؟ فيُشرح عنوانها «م».
  final bool showReview;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: ClaySpacing.sm,
      runSpacing: ClaySpacing.xs,
      children: [
        const ClayBadge(label: 'حاضر', tone: ClayTone.success),
        const ClayBadge(label: 'غائب', tone: ClayTone.danger),
        const ClayBadge(label: 'غائب برخصة', tone: ClayTone.excused),
        if (showPayment) ...const [
          ClayBadge(label: 'مربع أزرق: حصة مدفوعة', tone: ClayTone.info),
          ClayBadge(label: 'مربع أحمر: حضر ولم يدفع', tone: ClayTone.danger),
        ],
        if (showReview)
          const ClayBadge(
            label: 'م: حصة مراجعة من دورة من حضرها',
            tone: ClayTone.info,
          ),
      ],
    );
  }
}
