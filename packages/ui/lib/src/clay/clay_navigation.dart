import 'package:flutter/material.dart';

import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'clay_container.dart';

/// وجهة في شريط التنقل أو القائمة الجانبية.
class ClayDestination {
  const ClayDestination({
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.badge = 0,
  });

  final String label;
  final IconData icon;

  /// أيقونة الحالة المحددة (الافتراضي [icon]).
  final IconData? selectedIcon;

  /// عدد التنبيهات غير المقروءة؛ 0 يعني بلا شارة.
  final int badge;
}

/// نقاط التحول بين الهاتف والحاسوب.
abstract final class ClayBreakpoints {
  /// من هذا العرض فما فوق تُستعمل القائمة الجانبية بدل الشريط السفلي.
  static const double desktop = 840;
}

/// شارة عدد التنبيهات.
class _Badge extends StatelessWidget {
  const _Badge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: p.status.danger,
        borderRadius: BorderRadius.circular(ClayRadius.pill),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall!
            .copyWith(color: p.onAccent, fontSize: 11, height: 1.2),
      ),
    );
  }
}

/// الشريط السفلي للهاتف: من 2 إلى 5 وجهات.
class ClayBottomNav extends StatelessWidget {
  const ClayBottomNav({
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
    super.key,
  }) : assert(
         destinations.length >= 2 && destinations.length <= 5,
         'الشريط السفلي من 2 إلى 5 وجهات',
       );

  final List<ClayDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ClaySpacing.md,
          ClaySpacing.xs,
          ClaySpacing.md,
          ClaySpacing.sm,
        ),
        child: ClayContainer(
          radius: ClayRadius.xl,
          elevation: 5,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: _BottomItem(
                      destination: destinations[i],
                      selected: i == currentIndex,
                      onTap: () => onSelected(i),
                      color: i == currentIndex ? p.accent : p.textMuted,
                      style: text.labelSmall!,
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

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.color,
    required this.style,
  });

  final ClayDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      selected
          ? (destination.selectedIcon ?? destination.icon)
          : destination.icon,
      color: color,
      size: 26,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                icon,
                if (destination.badge > 0)
                  PositionedDirectional(
                    top: -6,
                    end: -10,
                    child: _Badge(destination.badge),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// القائمة الجانبية للحاسوب (نسخة Windows).
class ClaySidebar extends StatelessWidget {
  const ClaySidebar({
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
    this.header,
    this.footer,
    this.width = 260,
    super.key,
  });

  final List<ClayDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  /// أعلى القائمة (شعار واسم المدرسة).
  final Widget? header;

  /// أسفلها (المستخدم الحالي وزر الخروج).
  final Widget? footer;
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: width,
      child: ColoredBox(
        color: p.background,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(ClaySpacing.md),
            child: ClayContainer(
              radius: ClayRadius.lg,
              elevation: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (header != null)
                    Padding(
                      padding: const EdgeInsets.all(ClaySpacing.lg),
                      child: header,
                    ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ClaySpacing.md,
                        vertical: ClaySpacing.xs,
                      ),
                      itemCount: destinations.length,
                      itemExtent: 52,
                      itemBuilder: (context, i) => _SidebarItem(
                        destination: destinations[i],
                        selected: i == currentIndex,
                        onTap: () => onSelected(i),
                      ),
                    ),
                  ),
                  if (footer != null)
                    Padding(
                      padding: const EdgeInsets.all(ClaySpacing.lg),
                      child: footer,
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

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final ClayDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final color = selected ? p.onAccent : p.text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: destination.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? p.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(ClayRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: ClaySpacing.md),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? (destination.selectedIcon ?? destination.icon)
                        : destination.icon,
                    color: color,
                    size: 22,
                  ),
                  const SizedBox(width: ClaySpacing.md),
                  Expanded(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall!.copyWith(color: color),
                    ),
                  ),
                  if (destination.badge > 0) _Badge(destination.badge),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// شريط العنوان: بلا ظل، بعنوان في الوسط وإجراءات.
class ClayAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ClayAppBar({
    required this.title,
    this.leading,
    this.actions = const [],
    this.showBack = false,
    super.key,
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;

  /// يضيف زر الرجوع تلقائياً عند وجود صفحة سابقة.
  final bool showBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 8);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final canPop = showBack && (ModalRoute.of(context)?.canPop ?? false);
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: preferredSize.height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: ClaySpacing.sm),
          child: Row(
            children: [
              SizedBox(
                width: ClaySpacing.minTouchTarget,
                child:
                    leading ??
                    (canPop
                        ? IconButton(
                            tooltip: 'رجوع',
                            // Flutter يعكس السهم تلقائياً في RTL فيشير يميناً.
                            icon: Icon(Icons.arrow_back_rounded, color: p.text),
                            onPressed: () => Navigator.of(context).maybePop(),
                          )
                        : null),
              ),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: ClaySpacing.minTouchTarget,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// هيكل متكيّف: شريط سفلي على الهاتف، وقائمة جانبية على الحاسوب.
class ClayAdaptiveScaffold extends StatelessWidget {
  const ClayAdaptiveScaffold({
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
    required this.body,
    this.appBar,
    this.sidebarHeader,
    this.sidebarFooter,
    this.floatingActionButton,
    super.key,
  });

  final List<ClayDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? sidebarHeader;
  final Widget? sidebarFooter;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= ClayBreakpoints.desktop;
    if (wide) {
      return Scaffold(
        floatingActionButton: floatingActionButton,
        body: Row(
          children: [
            ClaySidebar(
              destinations: destinations,
              currentIndex: currentIndex,
              onSelected: onSelected,
              header: sidebarHeader,
              footer: sidebarFooter,
            ),
            Expanded(
              child: Column(
                children: [
                  ?appBar,
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: appBar,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: ClayBottomNav(
        destinations: destinations,
        currentIndex: currentIndex,
        onSelected: onSelected,
      ),
    );
  }
}
