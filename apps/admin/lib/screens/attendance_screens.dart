import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// الحضور: حصص يوم محدد (اليوم افتراضياً)، ومنها إلى ورقة حضور الحصة.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  late DateTime _date = _today();

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _shift(int days) => setState(
    () => _date = DateTime(_date.year, _date.month, _date.day + days),
  );

  Future<void> _pick() async {
    final picked = await showClayDatePicker(
      context,
      title: 'يوم الحصص',
      initial: _date,
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final key = DateKey.of(_date);
    final isToday = key == DateKey.of(DateTime.now());
    final sessions = ref.watch(daySessionsProvider(key));

    return Scaffold(
      appBar: const ClayAppBar(title: 'الحضور', showBack: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaySpacing.screenPadding,
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'اليوم السابق',
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => _shift(-1),
                ),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Column(
                      children: [
                        Text(
                          GroupService.weekdayName(_date.weekday),
                          textAlign: TextAlign.center,
                          style: text.titleMedium,
                        ),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            key,
                            style: text.bodySmall!.copyWith(color: p.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'اليوم التالي',
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () => _shift(1),
                ),
                IconButton(
                  tooltip: 'اختيار يوم',
                  icon: const Icon(ClayIcons.schedule),
                  onPressed: _pick,
                ),
              ],
            ),
          ),
          if (!isToday)
            Padding(
              padding: const EdgeInsets.only(bottom: ClaySpacing.xs),
              child: ClayChip(
                label: 'العودة إلى اليوم',
                icon: ClayIcons.check,
                onTap: () => setState(() => _date = _today()),
              ),
            ),
          Expanded(
            child: sessions.when(
              loading: () => const ClayLoadingView(),
              error: (_, _) => ClayErrorView(
                message: 'تعذّرت قراءة حصص اليوم',
                onRetry: () => ref.invalidate(daySessionsProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const ClayEmptyView(
                    title: 'لا حصص في هذا اليوم',
                    icon: ClayIcons.schedule,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ClaySpacing.screenPadding,
                  ),
                  itemCount: items.length,
                  itemExtent: 112,
                  itemBuilder: (context, i) => _SessionTile(item: items[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.item});

  final DaySession item;

  @override
  Widget build(BuildContext context) {
    final s = item.session;
    final times =
        '${DateKey.formatMinutes(s.startMinutes)}–'
        '${DateKey.formatMinutes(s.endMinutes)}';
    final badge = item.cancelled
        ? const ClayBadge(label: 'ملغاة', tone: ClayTone.danger)
        : item.closed
        ? const ClayBadge(label: 'مغلقة', tone: ClayTone.neutral)
        : item.students > 0 && item.unmarked == 0
        ? const ClayBadge(label: 'مكتملة', tone: ClayTone.success)
        : ClayBadge(
            label: item.students == 0
                ? 'بلا تلاميذ'
                : '${item.unmarked} بلا تسجيل',
            tone: ClayTone.warning,
          );
    return ClayListTile(
      title: 'المجموعة ${item.groupNumber} · ${item.subjectName}',
      subtitle:
          '$times · ${item.teacherName} · ${item.roomName ?? 'بلا قاعة'}\n'
          'حاضر ${item.present} · غائب ${item.absent} · '
          'برخصة ${item.excused}',
      subtitleLines: 2,
      onTap: () => context.push('/attendance/${item.id}'),
      trailing: [badge],
    );
  }
}

/// ورقة حضور حصة: حالة كل تلميذ بنقرة، وتسجيل الكل حاضراً دفعة واحدة.
class SessionRosterScreen extends ConsumerStatefulWidget {
  const SessionRosterScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  ConsumerState<SessionRosterScreen> createState() =>
      _SessionRosterScreenState();
}

class _SessionRosterScreenState extends ConsumerState<SessionRosterScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      await action();
    } on ValidationException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final roster = ref.watch(sessionRosterProvider(widget.sessionId));
    final canWrite =
        ref.can(PermissionModule.attendance, PermissionAction.add) ||
        ref.can(PermissionModule.attendance, PermissionAction.edit);
    final service = ref.watch(attendanceServiceProvider);

    return Scaffold(
      appBar: const ClayAppBar(title: 'ورقة الحضور', showBack: true),
      body: roster.when(
        loading: () => const ClayLoadingView(),
        error: (_, _) => ClayErrorView(
          message: 'تعذّرت قراءة ورقة الحضور',
          onRetry: () => ref.invalidate(sessionRosterProvider),
        ),
        data: (r) {
          if (r == null) {
            return const ClayEmptyView(title: 'هذه الحصة غير موجودة');
          }
          final s = r.session;
          final editable = canWrite && !r.cancelled;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                child: ClayCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'المجموعة ${r.groupNumber} · ${r.subjectName}',
                              style: text.titleMedium,
                            ),
                          ),
                          if (r.cancelled)
                            const ClayBadge(
                              label: 'ملغاة',
                              tone: ClayTone.danger,
                            )
                          else if (r.closed)
                            const ClayBadge(
                              label: 'مغلقة',
                              tone: ClayTone.neutral,
                            ),
                        ],
                      ),
                      const SizedBox(height: ClaySpacing.xs),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          '${s.date}  ${DateKey.formatMinutes(s.startMinutes)}'
                          '–${DateKey.formatMinutes(s.endMinutes)}',
                          style: text.bodySmall!.copyWith(color: p.textMuted),
                        ),
                      ),
                      Text(r.teacherName, style: text.bodyMedium),
                      const SizedBox(height: ClaySpacing.sm),
                      Text(
                        'حاضر ${r.count(AttendanceStatus.present)} · '
                        'غائب ${r.count(AttendanceStatus.absent)} · '
                        'برخصة ${r.count(AttendanceStatus.excused)} · '
                        'بلا تسجيل ${r.unmarked}',
                        style: text.bodySmall,
                      ),
                      if (editable && !r.closed && r.unmarked > 0) ...[
                        const SizedBox(height: ClaySpacing.md),
                        ClayButton(
                          label: 'تسجيل الكل حاضراً',
                          icon: ClayIcons.check,
                          loading: _busy,
                          onPressed: () =>
                              _run(() async => service.markAllPresent(s.id)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: r.students.isEmpty
                    ? const ClayEmptyView(
                        title: 'لا تلاميذ في هذه الحصة',
                        message: 'يُنسب التلاميذ إلى المجموعة من ملفهم',
                        icon: ClayIcons.students,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ClaySpacing.screenPadding,
                        ),
                        itemCount: r.students.length,
                        itemExtent: 112,
                        itemBuilder: (context, i) => _StudentRow(
                          student: r.students[i],
                          editable: editable,
                          closed: r.closed,
                          busy: _busy,
                          onMark: (status) => _run(
                            () => service.mark(
                              sessionId: s.id,
                              studentId: r.students[i].studentId,
                              status: status,
                              canExcuse: canWrite,
                            ),
                          ),
                          onClear: () => _run(
                            () => service.clear(
                              sessionId: s.id,
                              studentId: r.students[i].studentId,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.student,
    required this.editable,
    required this.closed,
    required this.busy,
    required this.onMark,
    required this.onClear,
  });

  final RosterStudent student;
  final bool editable;
  final bool closed;
  final bool busy;
  final ValueChanged<AttendanceStatus> onMark;
  final VoidCallback onClear;

  static const _tones = {
    AttendanceStatus.present: ClayTone.success,
    AttendanceStatus.absent: ClayTone.danger,
    AttendanceStatus.excused: ClayTone.excused,
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final current = student.status;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
      child: ClayCard(
        flat: true,
        padding: const EdgeInsets.symmetric(
          horizontal: ClaySpacing.md,
          vertical: ClaySpacing.xs,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    student.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                ),
                if (current != null && !editable)
                  ClayBadge(label: current.label, tone: _tones[current]!),
                if (current != null &&
                    student.method == AttendanceMethod.qr &&
                    editable)
                  const ClayBadge(label: 'مسح الرمز', tone: ClayTone.info),
              ],
            ),
            if (editable)
              Wrap(
                spacing: ClaySpacing.sm,
                children: [
                  for (final status in AttendanceStatus.values)
                    ClayChip(
                      label: status.label,
                      selected: current == status,
                      onTap: busy
                          ? null
                          : () {
                              if (current != status) {
                                onMark(status);
                              } else if (!closed) {
                                onClear();
                              }
                            },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
