import 'package:flutter/material.dart';

import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'clay_container.dart';

/// نوع الزر.
enum ClayButtonKind {
  /// بلون التطبيق الرئيسي (الإجراء الأساسي في الشاشة).
  primary,

  /// بسطح عادي (إجراء ثانوي).
  secondary,

  /// بلون الخطر (حذف، إلغاء).
  danger,
}

/// زر بحركة انضغاط: يهبط قليلاً ويصير سطحه غائراً عند اللمس.
///
/// الحجم الأدنى 48 بكسلاً (مساحة لمس مريحة). أثناء [loading] يُعطَّل النقر
/// ويظهر مؤشر دوّار، فلا يُرسل المستخدم العملية مرتين. دون [onPressed] يكون
/// الزر معطّلاً وباهتاً.
class ClayButton extends StatefulWidget {
  const ClayButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = ClayButtonKind.primary,
    this.loading = false,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ClayButtonKind kind;
  final bool loading;

  /// يملأ عرض الأب (أزرار النماذج).
  final bool expand;

  bool get enabled => onPressed != null && !loading;

  @override
  State<ClayButton> createState() => _ClayButtonState();
}

class _ClayButtonState extends State<ClayButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !widget.enabled) return;
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(ClayButton old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && _pressed) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (Color? fill, Color content) = switch (widget.kind) {
      ClayButtonKind.primary => (p.accent, p.onAccent),
      ClayButtonKind.secondary => (null, p.text),
      ClayButtonKind.danger => (p.status.danger, p.onAccent),
    };
    final shown = widget.enabled ? content : p.textMuted;
    final pressed = _pressed && widget.enabled;
    final label = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelLarge!.copyWith(color: shown),
    );
    final leading = widget.loading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: shown),
          )
        : widget.icon == null
        ? null
        : Icon(widget.icon, size: 20, color: shown);

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onPressed : null,
          child: AnimatedScale(
            scale: pressed ? 0.97 : 1,
            duration: ClayDuration.press,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: ClaySpacing.minTouchTarget,
                minWidth: ClaySpacing.minTouchTarget,
              ),
              child: ClayContainer(
                radius: ClayRadius.pill,
                depth: pressed ? ClayDepth.pressed : ClayDepth.raised,
                color: widget.enabled || fill == null ? fill : p.surfacePressed,
                elevation: pressed ? 3 : 5,
                padding: const EdgeInsets.symmetric(
                  horizontal: ClaySpacing.xl,
                  vertical: ClaySpacing.md,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: widget.expand
                      ? MainAxisSize.max
                      : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (leading != null) ...[
                      leading,
                      const SizedBox(width: ClaySpacing.sm),
                    ],
                    Flexible(child: label),
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
