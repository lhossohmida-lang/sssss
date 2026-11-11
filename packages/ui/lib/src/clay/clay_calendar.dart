import 'package:flutter/material.dart';

import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'clay_container.dart';
import 'clay_display.dart';

/// حساب شبكة الشهر: الأسبوع يبدأ يوم السبت (المواصفات 37).
abstract final class ClayCalendarMath {
  /// أسماء أيام الأسبوع بدءاً من السبت.
  static const List<String> weekdayNames = [
    'السبت',
    'الأحد',
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
  ];

  /// رمز حرفي لكل يوم لرأس الجدول (يتسع في 7 أعمدة على الهاتف).
  static const List<String> weekdayLetters = [
    'س',
    'ح',
    'ن',
    'ث',
    'ر',
    'خ',
    'ج',
  ];

  /// أسماء الأشهر الميلادية كما تُكتب في الجزائر.
  static const List<String> monthNames = [
    'جانفي',
    'فيفري',
    'مارس',
    'أفريل',
    'ماي',
    'جوان',
    'جويلية',
    'أوت',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  /// عدد أيام الشهر [month] من السنة [year].
  static int daysInMonth(int year, int month) =>
      DateTime.utc(year, month + 1, 0).day;

  /// عدد الخانات الفارغة قبل اليوم الأول (السبت = 0 … الجمعة = 6).
  static int leadingBlanks(int year, int month) =>
      (DateTime.utc(year, month, 1).weekday + 1) % 7;

  /// عدد صفوف الشهر (4 إلى 6).
  static int weekCount(int year, int month) =>
      ((leadingBlanks(year, month) + daysInMonth(year, month)) / 7).ceil();

  /// ترتيب اليوم في الأسبوع بدءاً من السبت (0 … 6) لتاريخ.
  static int weekdayIndex(DateTime date) => (date.weekday + 1) % 7;

  /// عنوان الشهر مثل «نوفمبر 2026».
  static String title(int year, int month) => '${monthNames[month - 1]} $year';
}

/// تقويم شهري يلوّن كل يوم بحالته (حاضر، غائب، برخصة...).
///
/// [statuses] من رقم اليوم في الشهر إلى دلالته؛ الأيام التي لا تظهر فيها
/// بلا علامة. التنقل بين الأشهر يتم عبر [onMonthChanged].
class ClayCalendar extends StatelessWidget {
  const ClayCalendar({
    required this.year,
    required this.month,
    required this.onMonthChanged,
    this.statuses = const {},
    this.selectedDay,
    this.onDayTap,
    this.today,
    super.key,
  }) : assert(month >= 1 && month <= 12, 'الشهر من 1 إلى 12');

  final int year;
  final int month;

  /// يُستدعى بالسنة والشهر الجديدين عند الضغط على السهمين.
  final void Function(int year, int month) onMonthChanged;

  /// دلالة كل يوم (مفتاحها رقم اليوم).
  final Map<int, ClayTone> statuses;
  final int? selectedDay;

  /// يُستدعى برقم اليوم المضغوط.
  final ValueChanged<int>? onDayTap;

  /// اليوم الحالي ليُميَّز؛ يُعطى من الخارج حتى يبقى التقويم قابلاً للاختبار.
  final DateTime? today;

  void _shift(int delta) {
    final moved = DateTime.utc(year, month + delta);
    onMonthChanged(moved.year, moved.month);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final blanks = ClayCalendarMath.leadingBlanks(year, month);
    final days = ClayCalendarMath.daysInMonth(year, month);
    final weeks = ClayCalendarMath.weekCount(year, month);
    final isTodayMonth =
        today != null && today!.year == year && today!.month == month;

    return ClayContainer(
      padding: const EdgeInsets.all(ClaySpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'الشهر السابق',
                // في RTL السهم الأيمن يرجع إلى الشهر السابق.
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () => _shift(-1),
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    ClayCalendarMath.title(year, month),
                    textAlign: TextAlign.center,
                    style: text.titleMedium,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'الشهر التالي',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => _shift(1),
              ),
            ],
          ),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: ClaySpacing.xs,
                    ),
                    child: Text(
                      ClayCalendarMath.weekdayLetters[i],
                      textAlign: TextAlign.center,
                      semanticsLabel: ClayCalendarMath.weekdayNames[i],
                      style: text.labelSmall!.copyWith(color: p.textMuted),
                    ),
                  ),
                ),
            ],
          ),
          for (var week = 0; week < weeks; week++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _DayCell(
                      day: week * 7 + col - blanks + 1,
                      days: days,
                      tone: statuses[week * 7 + col - blanks + 1],
                      selected: selectedDay == week * 7 + col - blanks + 1,
                      isToday:
                          isTodayMonth &&
                          today!.day == week * 7 + col - blanks + 1,
                      onTap: onDayTap,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.days,
    required this.tone,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final int day;
  final int days;
  final ClayTone? tone;
  final bool selected;
  final bool isToday;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    if (day < 1 || day > days) return const SizedBox(height: 48);
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final marker = tone == null ? null : ClayBadge.colorOf(p, tone!);
    final cell = SizedBox(
      height: 48,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? p.accent : null,
            border: isToday && !selected
                ? Border.all(color: p.accent, width: 1.5)
                : null,
          ),
          child: SizedBox.square(
            dimension: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '$day',
                  style: text.bodyMedium!.copyWith(
                    color: selected ? p.onAccent : p.text,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (marker != null)
                  PositionedDirectional(
                    bottom: 4,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? p.onAccent : marker,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '$day',
      excludeSemantics: true,
      child: onTap == null
          ? cell
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap!(day),
              child: cell,
            ),
    );
  }
}
