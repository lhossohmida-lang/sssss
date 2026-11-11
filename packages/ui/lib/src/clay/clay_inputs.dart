import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'clay_container.dart';

/// تسمية الحقل فوقه ورسالة الخطأ تحته، بنفس الشكل في كل الحقول.
class _FieldFrame extends StatelessWidget {
  const _FieldFrame({
    required this.label,
    required this.error,
    required this.helper,
    required this.child,
  });

  final String? label;
  final String? error;
  final String? helper;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final below = error ?? helper;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: ClaySpacing.xs,
              bottom: ClaySpacing.xs,
            ),
            child: Text(
              label!,
              style: text.labelMedium!.copyWith(color: p.text),
            ),
          ),
        child,
        if (below != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: ClaySpacing.xs,
              top: ClaySpacing.xs,
            ),
            child: Text(
              below,
              style: text.bodySmall!.copyWith(
                color: error != null ? p.status.danger : p.textMuted,
              ),
            ),
          ),
      ],
    );
  }
}

/// حقل نص بسطح غائر. الخطأ يظهر تحته بالأحمر، وللأرقام والبريد يُفرض
/// اتجاه يسار-يمين عبر [textDirection] لتُقرأ كما تُكتب.
class ClayTextField extends StatelessWidget {
  const ClayTextField({
    this.controller,
    this.label,
    this.hint,
    this.error,
    this.helper,
    this.keyboardType,
    this.textInputAction,
    this.textDirection,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.focusNode,
    super.key,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;

  /// رسالة الخطأ؛ وجودها يلوّن الحدّ بالأحمر.
  final String? error;

  /// نص مساعد يظهر تحت الحقل ما دام لا خطأ.
  final String? helper;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  /// اتجاه النص؛ `TextDirection.ltr` للهاتف والبريد والأرقام.
  final TextDirection? textDirection;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final IconData? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final hasError = error != null;
    return _FieldFrame(
      label: label,
      error: error,
      helper: helper,
      child: ClayContainer(
        depth: ClayDepth.pressed,
        radius: ClayRadius.md,
        elevation: 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ClayRadius.md),
            border: hasError
                ? Border.all(color: p.status.danger, width: 1.5)
                : null,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ClaySpacing.minTouchTarget,
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              readOnly: readOnly,
              autofocus: autofocus,
              obscureText: obscureText,
              maxLines: obscureText ? 1 : maxLines,
              maxLength: maxLength,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              textDirection: textDirection,
              textAlign: textDirection == TextDirection.ltr
                  ? TextAlign.left
                  : TextAlign.start,
              inputFormatters: inputFormatters,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              onTap: onTap,
              cursorColor: p.accent,
              style: text.bodyLarge!.copyWith(
                color: enabled ? p.text : p.textMuted,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: text.bodyLarge!.copyWith(color: p.textMuted),
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: ClaySpacing.lg,
                  vertical: ClaySpacing.md,
                ),
                prefixIcon: prefixIcon == null
                    ? null
                    : Icon(prefixIcon, color: p.textMuted, size: 22),
                suffixIcon: suffix,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// خيار في [ClayDropdown].
class ClayOption<T> {
  const ClayOption({required this.value, required this.label});

  final T value;
  final String label;
}

/// قائمة منسدلة بنفس شكل [ClayTextField].
class ClayDropdown<T> extends StatelessWidget {
  const ClayDropdown({
    required this.options,
    required this.onChanged,
    this.value,
    this.label,
    this.hint,
    this.error,
    this.helper,
    super.key,
  });

  final List<ClayOption<T>> options;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? hint;
  final String? error;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final hasError = error != null;
    final enabled = onChanged != null && options.isNotEmpty;
    return _FieldFrame(
      label: label,
      error: error,
      helper: helper,
      child: ClayContainer(
        depth: ClayDepth.pressed,
        radius: ClayRadius.md,
        elevation: 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ClayRadius.md),
            border: hasError
                ? Border.all(color: p.status.danger, width: 1.5)
                : null,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ClaySpacing.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: ClaySpacing.lg),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  isExpanded: true,
                  value: options.any((o) => o.value == value) ? value : null,
                  hint: hint == null
                      ? null
                      : Text(
                          hint!,
                          style: text.bodyLarge!.copyWith(color: p.textMuted),
                        ),
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: enabled ? p.textMuted : p.outline,
                  ),
                  dropdownColor: p.surface,
                  borderRadius: BorderRadius.circular(ClayRadius.md),
                  style: text.bodyLarge!.copyWith(color: p.text),
                  onChanged: enabled ? onChanged : null,
                  items: [
                    for (final option in options)
                      DropdownMenuItem<T>(
                        value: option.value,
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
