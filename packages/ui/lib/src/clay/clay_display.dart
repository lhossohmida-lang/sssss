import 'package:flutter/material.dart';

import '../theme/clay_colors.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'clay_button.dart';

/// دلالة لون الشارة.
enum ClayTone { neutral, success, danger, warning, info, excused }

/// شارة صغيرة بخلفية ملوّنة: حالة حضور، دفع، طلب...
///
/// الخلفية بلون الحالة والنص بلون [ClayPalette.onAccent]، فيبقى التباين
/// أعلى من 4.5 في الوضعين.
class ClayBadge extends StatelessWidget {
  const ClayBadge({
    required this.label,
    this.tone = ClayTone.neutral,
    this.icon,
    super.key,
  });

  final String label;
  final ClayTone tone;
  final IconData? icon;

  /// لون الخلفية لدلالة [tone] في اللوحة الحالية.
  static Color colorOf(ClayPalette p, ClayTone tone) => switch (tone) {
    ClayTone.neutral => p.textMuted,
    ClayTone.success => p.status.success,
    ClayTone.danger => p.status.danger,
    ClayTone.warning => p.status.warning,
    ClayTone.info => p.status.info,
    ClayTone.excused => p.status.excused,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final background = colorOf(p, tone);
    final style = Theme.of(context).textTheme.labelMedium!
        .copyWith(color: p.onAccent);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(ClayRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ClaySpacing.md,
          vertical: ClaySpacing.xxs + 1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: p.onAccent),
              const SizedBox(width: ClaySpacing.xs),
            ],
            Text(label, style: style),
          ],
        ),
      ),
    );
  }
}

/// صورة دائرية للشخص، وإن لم توجد (أو فشل تحميلها) فالحرفان الأولان من
/// اسمه. الصور تُصغَّر عند فك الترميز إلى حجمها الفعلي فلا تستهلك الذاكرة.
class ClayAvatar extends StatelessWidget {
  const ClayAvatar({required this.name, this.image, this.size = 44, super.key});

  final String name;
  final ImageProvider? image;
  final double size;

  /// الحرف الأول من أول كلمتين في [name]؛ `؟` إن كان الاسم فارغاً.
  static String initialsOf(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '؟';
    final letters = words
        .take(2)
        .map((w) => String.fromCharCode(w.runes.first));
    return letters.join();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fallback = Center(
      child: Text(
        initialsOf(name),
        style: Theme.of(context).textTheme.titleSmall!
            .copyWith(color: p.accent, fontSize: size * 0.34),
      ),
    );
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return Semantics(
      image: true,
      label: name,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child: ColoredBox(
            color: p.accent.withValues(alpha: 0.16),
            child: image == null
                ? fallback
                : Image(
                    image: ResizeImage(
                      image!,
                      width: pixels,
                      height: pixels,
                      policy: ResizeImagePolicy.fit,
                    ),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => fallback,
                  ),
          ),
        ),
      ),
    );
  }
}

/// شريط تقدم: مجرى غائر وتعبئة بلون التطبيق. [value] بين 0 و1.
class ClayProgress extends StatelessWidget {
  const ClayProgress({
    required this.value,
    this.height = 12,
    this.semanticLabel,
    super.key,
  });

  final double value;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(clamped * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ClayRadius.pill),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: p.surfacePressed)),
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: clamped,
                  child: ColoredBox(color: p.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ينبض بشفافية متكررة لأبنائه من [ClaySkeleton]. متحكم واحد للمجموعة كلها
/// بدل متحكم لكل عنصر، ويتوقف إن عطّل المستخدم الحركة.
class ClayPulse extends StatefulWidget {
  const ClayPulse({required this.child, super.key});

  final Widget child;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PulseScope>()?.animation;

  @override
  State<ClayPulse> createState() => _ClayPulseState();
}

class _ClayPulseState extends State<ClayPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _PulseScope(animation: _controller, child: widget.child);
}

class _PulseScope extends InheritedWidget {
  const _PulseScope({required this.animation, required super.child});

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_PulseScope old) => old.animation != animation;
}

/// مستطيل رمادي يحجز مكان محتوى قيد التحميل.
class ClaySkeleton extends StatelessWidget {
  const ClaySkeleton({
    this.width,
    this.height = 16,
    this.radius = ClayRadius.sm,
    super.key,
  });

  /// دائرة بقطر [size] (مكان صورة).
  const ClaySkeleton.circle({required double size, super.key})
    : width = size,
      height = size,
      radius = ClayRadius.pill;

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: p.outline.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: SizedBox(width: width, height: height),
    );
    final pulse = ClayPulse.maybeOf(context);
    if (pulse == null) return box;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(pulse),
      child: box,
    );
  }
}

/// قائمة صفوف هيكلية بانتظار البيانات.
class ClaySkeletonList extends StatelessWidget {
  const ClaySkeletonList({this.count = 6, this.itemExtent = 72, super.key});

  final int count;
  final double itemExtent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'جارٍ التحميل',
      child: ExcludeSemantics(
        child: ClayPulse(
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: count,
            itemExtent: itemExtent,
            padding: const EdgeInsets.symmetric(
              horizontal: ClaySpacing.screenPadding,
            ),
            itemBuilder: (_, _) => const Row(
              children: [
                ClaySkeleton.circle(size: 44),
                SizedBox(width: ClaySpacing.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClaySkeleton(width: 160, height: 14),
                      SizedBox(height: ClaySpacing.sm),
                      ClaySkeleton(width: 100, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// حالة تحميل بمؤشر دوّار في وسط الشاشة.
class ClayLoadingView extends StatelessWidget {
  const ClayLoadingView({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Semantics(
        liveRegion: true,
        label: message ?? 'جارٍ التحميل',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: p.accent),
            if (message != null) ...[
              const SizedBox(height: ClaySpacing.lg),
              Text(
                message!,
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(color: p.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ClaySpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: iconColor),
            const SizedBox(height: ClaySpacing.lg),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: ClaySpacing.sm),
              Text(
                message!,
                style: text.bodyMedium!.copyWith(color: p.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: ClaySpacing.xl),
              ClayButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// حالة «لا توجد بيانات» مع إجراء اختياري (مثل «إضافة تلميذ»).
class ClayEmptyView extends StatelessWidget {
  const ClayEmptyView({
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => _MessageView(
    icon: icon,
    iconColor: context.palette.textMuted,
    title: title,
    message: message,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

/// حالة خطأ مع زر «إعادة المحاولة».
class ClayErrorView extends StatelessWidget {
  const ClayErrorView({
    required this.message,
    this.onRetry,
    this.title = 'تعذّر التحميل',
    super.key,
  });

  final String title;
  final String message;

  /// دونه لا يظهر زر إعادة المحاولة.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => _MessageView(
    icon: Icons.error_outline_rounded,
    iconColor: context.palette.status.danger,
    title: title,
    message: message,
    actionLabel: onRetry == null ? null : 'إعادة المحاولة',
    onAction: onRetry,
  );
}
