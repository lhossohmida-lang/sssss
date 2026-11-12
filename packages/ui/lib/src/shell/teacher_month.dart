import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_container.dart';
import '../clay/clay_display.dart';
import '../clay/clay_icons.dart';
import '../clay/clay_navigation.dart';
import '../clay/clay_overlays.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'list_page.dart';
import 'providers.dart';

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

/// «14 نوفمبر · السبت».
String teacherDayLabel(String date) {
  final month = DateKey.monthName(int.parse(date.substring(5, 7)));
  return '${int.parse(date.substring(8))} $month · '
      '${GroupService.weekdayName(DateKey.weekday(date))}';
}

/// كشف أستاذ لشهر حصة بحصة، مع تسجيل حضوره يدوياً لحصة نسي مسحها.
class TeacherMonthScreen extends ConsumerStatefulWidget {
  const TeacherMonthScreen({
    required this.teacherId,
    this.month,
    this.canMark = false,
    super.key,
  });

  final String teacherId;
  final String? month;

  /// هل يسجّل المستخدم حضور الأستاذ يدوياً لحصة فائتة؟ (للإدارة.)
  final bool canMark;

  @override
  ConsumerState<TeacherMonthScreen> createState() => _TeacherMonthScreenState();
}

class _TeacherMonthScreenState extends ConsumerState<TeacherMonthScreen> {
  late String _month = widget.month ?? currentMonthKey();

  Future<void> _markPresent(TeacherSessionRow row, String name) async {
    final ok = await showClayConfirm(
      context,
      title: 'تسجيل حضور الأستاذ',
      message:
          'تسجيل حضور $name لحصة ${row.groupLabel} يوم ${row.date} '
          'يدوياً (نسي مسح رمزه)؟',
      confirmLabel: 'تسجيل الحضور',
    );
    if (!ok) return;
    await ref.read(teacherAttendanceProvider).markPresent(row.sessionId);
  }

  static String _time(int millis) {
    final t = DateTime.fromMillisecondsSinceEpoch(
      millis,
      isUtc: true,
    ).toLocal();
    return DateKey.formatMinutes(DateKey.minutesOf(t));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final canEdit = widget.canMark;
    final sheet = ref.watch(teacherSheetProvider(_month));
    final month = sheet.value
        ?.where((m) => m.teacherId == widget.teacherId)
        .firstOrNull;

    return Scaffold(
      appBar: ClayAppBar(title: month?.name ?? 'كشف الأستاذ', showBack: true),
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
          Expanded(
            child: month == null
                ? (sheet.isLoading
                      ? const ClayLoadingView()
                      : const ClayEmptyView(
                          title: 'لا حصص لهذا الأستاذ في هذا الشهر',
                          icon: ClayIcons.teachers,
                        ))
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ClaySpacing.screenPadding,
                        ),
                        child: ClayCard(
                          flat: true,
                          child: Text(
                            'حضر ${month.attended} من ${month.held} حصة '
                            'منتهية · غاب ${month.missed} · '
                            'تأخر ${month.totalLateMinutes} د',
                            style: text.titleSmall,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(
                            ClaySpacing.screenPadding,
                          ),
                          itemCount: month.sessions.length,
                          itemExtent: 96,
                          itemBuilder: (context, i) {
                            final s = month.sessions[i];
                            final badge = switch (s.status) {
                              TeacherSessionStatus.present => const ClayBadge(
                                label: 'حضر',
                                tone: ClayTone.success,
                              ),
                              TeacherSessionStatus.absent => const ClayBadge(
                                label: 'لم يحضر',
                                tone: ClayTone.danger,
                              ),
                              TeacherSessionStatus.pending => const ClayBadge(
                                label: 'لم تنتهِ',
                                tone: ClayTone.neutral,
                              ),
                            };
                            final detail =
                                s.status == TeacherSessionStatus.present
                                ? 'دخل ${_time(s.checkIn!)}'
                                      '${s.checkOut == null ? '' : ' وخرج ${_time(s.checkOut!)}'}'
                                      '${s.lateMinutes > 0 ? ' · تأخر ${s.lateMinutes} د' : ''}'
                                : '${DateKey.formatMinutes(s.startMinutes)}–'
                                      '${DateKey.formatMinutes(s.endMinutes)}';
                            return ClayListTile(
                              title:
                                  '${teacherDayLabel(s.date)} · ${s.groupLabel}',
                              subtitle: detail,
                              onTap:
                                  canEdit &&
                                      s.status == TeacherSessionStatus.absent
                                  ? () => _markPresent(s, month.name)
                                  : null,
                              trailing: [
                                badge,
                                if (canEdit &&
                                    s.status == TeacherSessionStatus.absent)
                                  Icon(
                                    ClayIcons.check,
                                    color: p.textMuted,
                                    semanticLabel: 'تسجيل الحضور يدوياً',
                                  ),
                              ],
                            );
                          },
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
