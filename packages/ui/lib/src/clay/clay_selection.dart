import 'package:flutter/material.dart';

import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'clay_container.dart';

/// شريحة اختيار (مستوى، مادة، حالة). المحددة بلون التطبيق الرئيسي.
class ClayChip extends StatelessWidget {
  const ClayChip({
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.color,
    super.key,
  });

  final String label;
  final bool selected;

  /// دونه تكون الشريحة للعرض فقط (وسم).
  final VoidCallback? onTap;
  final IconData? icon;

  /// لون مخصص للوسم (مثلاً لون حالة)، يستبدل لون التحديد.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final tone = color ?? p.accent;
    final filled = selected && color == null;
    final foreground = filled ? p.onAccent : (color ?? p.text);
    final chip = ClayContainer.flat(
      radius: ClayRadius.pill,
      color: filled ? p.accent : null,
      padding: const EdgeInsets.symmetric(
        horizontal: ClaySpacing.md,
        vertical: ClaySpacing.xs,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: selected ? foreground : tone),
              const SizedBox(width: ClaySpacing.xs),
            ],
            Text(label, style: text.labelMedium!.copyWith(color: foreground)),
          ],
        ),
      ),
    );
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          // مساحة لمس 48 دون تكبير الشكل المرسوم.
          constraints: const BoxConstraints(
            minHeight: ClaySpacing.minTouchTarget,
          ),
          child: Center(widthFactor: 1, child: chip),
        ),
      ),
    );
  }
}

/// مفتاح تشغيل وإيقاف.
class ClayToggle extends StatelessWidget {
  const ClayToggle({
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  final bool value;

  /// دونه يكون المفتاح معطّلاً.
  final ValueChanged<bool>? onChanged;

  /// وصف لقارئ الشاشة (ماذا يشغّل المفتاح).
  final String? semanticLabel;

  static const double width = 52;
  static const double height = 30;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: SizedBox(
          width: ClaySpacing.minTouchTarget + 8,
          height: ClaySpacing.minTouchTarget,
          child: Center(
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedContainer(
                      duration: ClayDuration.fast,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(height),
                        color: value && enabled
                            ? p.accent.withValues(alpha: 0.35)
                            : p.surfacePressed,
                        border: Border.all(
                          color: p.outline.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                  AnimatedAlign(
                    duration: ClayDuration.fast,
                    curve: Curves.easeOut,
                    // الاتجاه RTL: «مشغّل» نحو اليسار (نهاية السطر) تلقائياً.
                    alignment: value
                        ? AlignmentDirectional.centerEnd
                        : AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: enabled
                              ? (value ? p.accent : p.surface)
                              : p.outline,
                          boxShadow: [
                            BoxShadow(
                              color: p.shadowDark.withValues(alpha: 0.6),
                              blurRadius: 3,
                              offset: const Offset(1, 1),
                            ),
                          ],
                        ),
                        child: const SizedBox.square(dimension: height - 6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// مربع اختيار.
class ClayCheckbox extends StatelessWidget {
  const ClayCheckbox({
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  static const double size = 28;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onChanged != null;
    return Semantics(
      checked: value,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: SizedBox.square(
          dimension: ClaySpacing.minTouchTarget,
          child: Center(
            child: AnimatedContainer(
              duration: ClayDuration.fast,
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ClayRadius.sm / 1.5),
                color: value
                    ? (enabled ? p.accent : p.outline)
                    : p.surfacePressed,
                border: Border.all(
                  color: value ? Colors.transparent : p.outline,
                  width: 1.5,
                ),
              ),
              child: value
                  ? Icon(Icons.check_rounded, size: 20, color: p.onAccent)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
