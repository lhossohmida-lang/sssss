import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'guests_panel.dart';

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
      title: 'الفوج ${item.groupNumber} · ${item.subjectName}',
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

/// ورقة الحضور في الإدارة بصلاحياتها: التسجيل لمن يملك إضافة أو تعديل الحضور،
/// و«غائب برخصة» لهم أيضاً.
class AdminSessionRoster extends ConsumerWidget {
  const AdminSessionRoster({required this.sessionId, super.key});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canWrite =
        ref.can(PermissionModule.attendance, PermissionAction.add) ||
        ref.can(PermissionModule.attendance, PermissionAction.edit);
    return SessionRosterScreen(
      sessionId: sessionId,
      canWrite: canWrite,
      canExcuse: canWrite,
      // تلاميذ لمرة واحدة أو من فوج آخر يحضرون هذه الحصة ويدفعون ثمنها.
      belowHeader: canWrite
          ? (roster) => Column(
              children: [
                GuestsButton(roster: roster),
                SessionActions(roster: roster),
              ],
            )
          : null,
    );
  }
}

/// أزرار الإدارة في ورقة الحصة: دفع الحصة لكل حاضر لم يسدّد دورته، وحذف حضور الحصة كله.
class SessionActions extends ConsumerStatefulWidget {
  const SessionActions({required this.roster, super.key});

  final SessionRoster roster;

  @override
  ConsumerState<SessionActions> createState() => _SessionActionsState();
}

class _SessionActionsState extends ConsumerState<SessionActions> {
  bool _busy = false;

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final message = await action();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on ValidationException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.errors.values.isEmpty ? 'تعذّرت العملية' : e.errors.values.first,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final sure = await showClayDialog<bool>(
      context,
      title: 'حذف حضور الحصة كله؟',
      content: const Text(
        'تعود الحصة بلا تسجيل لكل تلاميذها (ولو كانت مغلقة)، وتُحذف أرصدة الغياب برخصة فيها. '
        'المدفوعات لا تتغير.',
      ),
      actions: [
        Builder(
          builder: (context) => ClayButton(
            label: 'إلغاء',
            kind: ClayButtonKind.secondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ),
        Builder(
          builder: (context) => ClayButton(
            label: 'حذف الحضور',
            kind: ClayButtonKind.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ),
      ],
    );
    if (sure != true || !mounted) return;
    await _run(() async {
      final count = await ref
          .read(attendanceServiceProvider)
          .clearSession(widget.roster.session.id);
      return 'حُذف حضور $count تلميذ في هذه الحصة';
    });
  }

  @override
  Widget build(BuildContext context) {
    final roster = widget.roster;
    if (roster.cancelled) return const SizedBox.shrink();
    final canPay = ref.can(PermissionModule.receiveMoney, PermissionAction.use);
    final marked = roster.students.length - roster.unmarked;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ClaySpacing.screenPadding,
        0,
        ClaySpacing.screenPadding,
        ClaySpacing.md,
      ),
      child: Wrap(
        spacing: ClaySpacing.sm,
        runSpacing: ClaySpacing.sm,
        children: [
          if (canPay && roster.count(AttendanceStatus.present) > 0)
            ClayButton(
              label: 'دفع الحصة للحاضرين',
              icon: ClayIcons.check,
              kind: ClayButtonKind.secondary,
              loading: _busy,
              onPressed: () => _run(() async {
                final count = await ref
                    .read(paymentServiceProvider)
                    .paySessionForPresent(roster.session.id);
                return count == 0
                    ? 'كل الحاضرين سدّدوا دورتهم أو معفون'
                    : 'دُفعت الحصة لـ$count تلميذ';
              }),
            ),
          if (marked > 0)
            ClayButton(
              label: 'حذف حضور الحصة',
              icon: ClayIcons.delete,
              kind: ClayButtonKind.secondary,
              loading: _busy,
              onPressed: _clear,
            ),
        ],
      ),
    );
  }
}
