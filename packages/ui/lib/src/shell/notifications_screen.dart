import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';

import '../clay/clay_container.dart';
import '../clay/clay_display.dart';
import '../clay/clay_icons.dart';
import '../clay/clay_navigation.dart';
import '../theme/clay_theme.dart';
import '../theme/clay_tokens.dart';
import 'providers.dart';

/// شاشة الإشعارات: الأحدث أولاً، والضغط على إشعار يعلّمه مقروءاً.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  /// تاريخ ووقت بأرقام لاتينية، مثل `10/11/2026 14:30` (المواصفات 71).
  static String formatTime(int millis) {
    final t = DateTime.fromMillisecondsSinceEpoch(
      millis,
      isUtc: true,
    ).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _markRead(WidgetRef ref, NotificationRow row) async {
    if (row.readAt != null) return;
    final writer = ref.read(runtimeProvider).writer;
    await writer.patch(
      writer.db.notifications,
      key: {'id': row.id},
      values: {'read_at': writer.now()},
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: const ClayAppBar(title: 'الإشعارات', showBack: true),
      body: notifications.when(
        loading: () => const ClayLoadingView(),
        error: (error, _) => ClayErrorView(
          message: 'تعذّرت قراءة الإشعارات',
          onRetry: () => ref.invalidate(notificationsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const ClayEmptyView(
              title: 'لا توجد إشعارات',
              message: 'ستظهر هنا طلبات الأساتذة وتنبيهات النظام',
              icon: ClayIcons.notifications,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaySpacing.screenPadding,
              vertical: ClaySpacing.sm,
            ),
            itemCount: rows.length,
            itemExtent: 92,
            itemBuilder: (context, i) => _NotificationTile(
              row: rows[i],
              onTap: () => _markRead(ref, rows[i]),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.row, required this.onTap});

  final NotificationRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final unread = row.readAt == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
      child: Semantics(
        button: true,
        label: '${unread ? 'غير مقروء: ' : ''}${row.title}',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ClayContainer.flat(
            padding: const EdgeInsets.all(ClaySpacing.md),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: unread ? p.accent : Colors.transparent,
                  ),
                ),
                const SizedBox(width: ClaySpacing.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: unread ? text.titleSmall : text.bodyMedium,
                      ),
                      Text(
                        row.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: ClaySpacing.sm),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    NotificationsScreen.formatTime(row.createdAt),
                    style: text.labelSmall,
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
