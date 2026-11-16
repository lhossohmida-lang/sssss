import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// تفاصيل المجموعة: أستاذها وجدولها وقاعتها، وشبكة حضور الدورة (صفوف
/// التلاميذ وأعمدة الحصص) مع التنقل بين الدورات.
class GroupDetailsScreen extends ConsumerWidget {
  const GroupDetailsScreen({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final item = ref.watch(groupItemProvider(groupId));
    final canEdit = ref.can(PermissionModule.groups, PermissionAction.edit);
    final canPast = ref.can(PermissionModule.attendance, PermissionAction.edit);
    return Scaffold(
      appBar: ClayAppBar(
        title: item == null ? 'الفوج' : 'الفوج ${item.number}',
        showBack: true,
        actions: [
          if (canPast && item != null)
            IconButton(
              tooltip: 'تسجيل الحضور السابق',
              icon: const Icon(ClayIcons.attendance),
              onPressed: () => context.push('/groups/${item.id}/past'),
            ),
          if (canEdit && item != null)
            IconButton(
              tooltip: 'تعديل الفوج',
              icon: const Icon(ClayIcons.edit),
              onPressed: () => context.push('/groups/${item.id}/edit'),
            ),
        ],
      ),
      body: GroupGridView(
        groupId: groupId,
        header: [
          if (item != null)
            Padding(
              padding: const EdgeInsets.only(bottom: ClaySpacing.lg),
              child: ClayCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.subjectName, style: text.titleLarge),
                    const SizedBox(height: ClaySpacing.xs),
                    Text(
                      '${item.teacherName} · ${item.roomName ?? 'بلا قاعة'} '
                      '· ${item.studentCount} تلميذ',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: ClaySpacing.xs),
                    Text(
                      item.scheduleText,
                      style: text.bodySmall!.copyWith(color: p.textMuted),
                    ),
                    if (canPast) ...[
                      const SizedBox(height: ClaySpacing.md),
                      ClayButton(
                        label: 'تسجيل الحضور السابق',
                        icon: ClayIcons.attendance,
                        kind: ClayButtonKind.secondary,
                        expand: true,
                        onPressed: () =>
                            context.push('/groups/${item.id}/past'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
