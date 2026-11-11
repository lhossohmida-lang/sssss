import 'package:flutter/material.dart';

import 'clay_button.dart';
import 'clay_calendar.dart';
import 'clay_overlays.dart';

/// منتقي تاريخ بأرقام لاتينية وأسبوع يبدأ بالسبت (المواصفات 37 و71)، فلا
/// يُستعمل منتقي Material الذي يعرض الأرقام الهندية في اللغة العربية.
///
/// يعيد التاريخ المختار (عند منتصف الليل بالتوقيت المحلي)، أو `null` عند
/// الإلغاء.
Future<DateTime?> showClayDatePicker(
  BuildContext context, {
  required String title,
  DateTime? initial,
  DateTime? today,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) =>
        _DatePickerDialog(title: title, initial: initial, today: today),
  );
}

class _DatePickerDialog extends StatefulWidget {
  const _DatePickerDialog({required this.title, this.initial, this.today});

  final String title;
  final DateTime? initial;
  final DateTime? today;

  @override
  State<_DatePickerDialog> createState() => _DatePickerDialogState();
}

class _DatePickerDialogState extends State<_DatePickerDialog> {
  late int _year;
  late int _month;
  int? _day;

  @override
  void initState() {
    super.initState();
    final start = widget.initial ?? widget.today ?? DateTime.now();
    _year = start.year;
    _month = start.month;
    if (widget.initial != null) _day = widget.initial!.day;
  }

  @override
  Widget build(BuildContext context) {
    return ClayDialog(
      title: widget.title,
      content: ClayCalendar(
        year: _year,
        month: _month,
        selectedDay: _day,
        today: widget.today ?? DateTime.now(),
        onMonthChanged: (year, month) => setState(() {
          _year = year;
          _month = month;
          // اليوم المحدد لا ينتقل إلى شهر آخر.
          _day = null;
        }),
        onDayTap: (day) => setState(() => _day = day),
      ),
      actions: [
        ClayButton(
          label: 'تأكيد',
          onPressed: _day == null
              ? null
              : () => Navigator.of(context).pop(DateTime(_year, _month, _day!)),
        ),
        ClayButton(
          label: 'إلغاء',
          kind: ClayButtonKind.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
