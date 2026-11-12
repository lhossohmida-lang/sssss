import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../clay/clay_selection.dart';
import '../theme/clay_tokens.dart';
import 'providers.dart';

/// مبدّل الأبناء: شرائح بأسمائهم الأولى يختار منها الوليّ من تُعرض بياناته.
/// يختفي إن كان للوليّ ابن واحد.
class ChildSwitcher extends ConsumerWidget {
  const ChildSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(childrenProvider).value ?? const [];
    if (children.length < 2) return const SizedBox.shrink();
    final selected = ref.watch(selectedChildProvider.select((s) => s?.id));
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: ClaySpacing.screenPadding,
          vertical: ClaySpacing.xs,
        ),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: ClaySpacing.sm),
        itemBuilder: (context, i) {
          final child = children[i];
          return ClayChip(
            label: child.firstName,
            selected: child.id == selected,
            onTap: () =>
                ref.read(selectedChildIdProvider.notifier).select(child.id),
          );
        },
      ),
    );
  }
}
