import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// كم يوماً للخلف تُنبَّه الحصص التي لم يحضرها أستاذها.
const int missedAlertDays = 7;

/// «14 نوفمبر · السبت».
String _dayLabel(String date) {
  final month = DateKey.monthName(int.parse(date.substring(5, 7)));
  return '${int.parse(date.substring(8))} $month · '
      '${GroupService.weekdayName(DateKey.weekday(date))}';
}

/// كشف حضور الأساتذة الشهري: لكل أستاذ ما حضره من حصصه وما غاب عنه وتأخره،
/// وفي أعلاه تنبيه الحصص التي لم يحضرها أستاذها في آخر أيام.
class TeacherSheetScreen extends ConsumerStatefulWidget {
  const TeacherSheetScreen({super.key});

  @override
  ConsumerState<TeacherSheetScreen> createState() => _TeacherSheetScreenState();
}

class _TeacherSheetScreenState extends ConsumerState<TeacherSheetScreen> {
  String _month = currentMonthKey();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final since = DateKey.of(
      DateTime.now().subtract(const Duration(days: missedAlertDays)),
    );
    final missed = ref.watch(missedSessionsProvider(since)).value ?? const [];
    final sheet = ref.watch(teacherSheetProvider(_month));

    return Scaffold(
      appBar: const ClayAppBar(title: 'حضور الأساتذة', showBack: true),
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
          if (missed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ClaySpacing.screenPadding,
                vertical: ClaySpacing.xs,
              ),
              child: ClayCard(
                flat: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(ClayIcons.close, color: p.status.danger),
                        const SizedBox(width: ClaySpacing.sm),
                        Expanded(
                          child: Text(
                            'حصص لم يحضرها أستاذها في آخر $missedAlertDays '
                            'أيام: ${missed.length}',
                            style: text.titleSmall!.copyWith(
                              color: p.status.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                    for (final m in missed.take(3))
                      InkWell(
                        onTap: () => context.push(
                          '/teacher-attendance/${m.teacherId}'
                          '?month=${m.date.substring(0, 7)}',
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: ClaySpacing.xs,
                          ),
                          child: Text(
                            '${m.teacherName} — المجموعة ${m.groupNumber} '
                            '(${m.subjectName}) ${_dayLabel(m.date)}',
                            style: text.bodySmall,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: sheet.when(
              loading: () => const ClaySkeletonList(),
              error: (_, _) => ClayErrorView(
                message: 'تعذّرت قراءة كشف الأساتذة',
                onRetry: () => ref.invalidate(teacherSheetProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const ClayEmptyView(
                    title: 'لا حصص في هذا الشهر',
                    message: 'تظهر هنا حصص الأساتذة بحضورها',
                    icon: ClayIcons.teachers,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                  itemCount: items.length,
                  itemExtent: 96,
                  itemBuilder: (context, i) {
                    final t = items[i];
                    return ClayListTile(
                      leading: ClayAvatar(name: t.name),
                      title: t.name,
                      subtitle:
                          'حضر ${t.attended} من ${t.held} حصة منتهية · '
                          'غاب ${t.missed}\nتأخر ${t.totalLateMinutes} د',
                      subtitleLines: 2,
                      onTap: () => context.push(
                        '/teacher-attendance/${t.teacherId}?month=$_month',
                      ),
                      trailing: [
                        if (t.missed > 0)
                          ClayBadge(
                            label: 'غاب ${t.missed}',
                            tone: ClayTone.danger,
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

/// كشف أستاذ لشهر في الإدارة: مع تسجيل حضوره يدوياً لمن يملك تعديل الأساتذة.
class AdminTeacherMonth extends ConsumerWidget {
  const AdminTeacherMonth({required this.teacherId, this.month, super.key});

  final String teacherId;
  final String? month;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TeacherMonthScreen(
    teacherId: teacherId,
    month: month,
    canMark: ref.can(PermissionModule.teachers, PermissionAction.edit),
  );
}
