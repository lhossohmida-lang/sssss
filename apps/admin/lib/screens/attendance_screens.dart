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
    );
  }
}
