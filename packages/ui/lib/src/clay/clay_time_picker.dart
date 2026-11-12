import 'package:flutter/material.dart';

import '../theme/clay_tokens.dart';
import 'clay_button.dart';
import 'clay_inputs.dart';
import 'clay_overlays.dart';

/// منتقي وقت بأرقام لاتينية بنظام 24 ساعة، فلا يُستعمل منتقي Material الذي
/// يعرض الأرقام الهندية في العربية.
///
/// يعيد الوقت بالدقائق منذ منتصف الليل، أو `null` عند الإلغاء. الدقائق بخطوة
/// [minuteStep] (5 افتراضياً)، ويُقرَّب [initial] إلى أقرب خطوة.
Future<int?> showClayTimePicker(
  BuildContext context, {
  required String title,
  int initial = 600,
  int minuteStep = 5,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) =>
        _TimePickerDialog(title: title, initial: initial, step: minuteStep),
  );
}

class _TimePickerDialog extends StatefulWidget {
  const _TimePickerDialog({
    required this.title,
    required this.initial,
    required this.step,
  });

  final String title;
  final int initial;
  final int step;

  @override
  State<_TimePickerDialog> createState() => _TimePickerDialogState();
}

class _TimePickerDialogState extends State<_TimePickerDialog> {
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    final total = widget.initial.clamp(0, 24 * 60 - 1);
    _hour = total ~/ 60;
    // أقرب خطوة دقائق، دون تجاوز الساعة.
    final rounded = ((total % 60) / widget.step).round() * widget.step;
    _minute = rounded >= 60 ? 60 - widget.step : rounded;
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final minutes = [for (var m = 0; m < 60; m += widget.step) m];
    return ClayDialog(
      title: widget.title,
      content: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            Expanded(
              child: ClayDropdown<int>(
                label: 'الساعة',
                value: _hour,
                options: [
                  for (var h = 0; h < 24; h++)
                    ClayOption(value: h, label: _two(h)),
                ],
                onChanged: (value) => setState(() => _hour = value ?? _hour),
              ),
            ),
            const SizedBox(width: ClaySpacing.md),
            Expanded(
              child: ClayDropdown<int>(
                label: 'الدقيقة',
                value: _minute,
                options: [
                  for (final m in minutes) ClayOption(value: m, label: _two(m)),
                ],
                onChanged: (value) =>
                    setState(() => _minute = value ?? _minute),
              ),
            ),
          ],
        ),
      ),
      actions: [
        ClayButton(
          label: 'تأكيد',
          onPressed: () => Navigator.of(context).pop(_hour * 60 + _minute),
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
