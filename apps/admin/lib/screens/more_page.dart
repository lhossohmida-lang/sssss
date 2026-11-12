import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// قسم في قائمة «المزيد».
class MoreEntry {
  const MoreEntry({
    required this.label,
    required this.icon,
    required this.path,
    this.requires,
  });

  final String label;
  final IconData icon;

  /// مسار صفحته (`AppPage`).
  final String path;

  /// الوحدة التي يشترطها ظهور القسم.
  final PermissionModule? requires;
}

/// أقسام «المزيد»؛ كل مهمة لاحقة تضيف قسمها هنا مع صفحته في `adminPages`.
const List<MoreEntry> moreEntries = [
  MoreEntry(
    label: 'خلاص الأساتذة',
    icon: ClayIcons.payments,
    path: '/payouts',
    requires: PermissionModule.payouts,
  ),
  MoreEntry(
    label: 'حقوق التسجيل',
    icon: ClayIcons.payments,
    path: '/fees',
    requires: PermissionModule.payments,
  ),
  MoreEntry(
    label: 'المستحقات',
    icon: ClayIcons.dues,
    path: '/dues',
    requires: PermissionModule.payments,
  ),
  MoreEntry(
    label: 'شاشة المدخل',
    icon: ClayIcons.students,
    path: '/entrance',
    requires: PermissionModule.scanner,
  ),
  MoreEntry(
    label: 'الماسح',
    icon: ClayIcons.scan,
    path: '/scanner',
    requires: PermissionModule.scanner,
  ),
  MoreEntry(
    label: 'الحضور',
    icon: ClayIcons.attendance,
    path: '/attendance',
    requires: PermissionModule.attendance,
  ),
  MoreEntry(
    label: 'قوائم الانتظار',
    icon: ClayIcons.waiting,
    path: '/waiting',
    requires: PermissionModule.waiting,
  ),
  MoreEntry(
    label: 'الجدول الأسبوعي',
    icon: ClayIcons.schedule,
    path: '/schedule',
    requires: PermissionModule.groups,
  ),
  MoreEntry(
    label: 'الأساتذة',
    icon: ClayIcons.teachers,
    path: '/teachers',
    requires: PermissionModule.teachers,
  ),
  MoreEntry(
    label: 'المواد',
    icon: ClayIcons.subjects,
    path: '/subjects',
    requires: PermissionModule.subjects,
  ),
  MoreEntry(
    label: 'القاعات',
    icon: ClayIcons.rooms,
    path: '/rooms',
    requires: PermissionModule.rooms,
  ),
  MoreEntry(
    label: 'الإعدادات',
    icon: ClayIcons.settings,
    path: '/settings',
    requires: PermissionModule.settings,
  ),
];

/// قائمة «المزيد»: الأقسام التي لا يتسع لها الشريط السفلي، حسب صلاحيات
/// المستخدم.
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider.select((s) => s.value));
    final entries = [
      for (final entry in moreEntries)
        if (session != null &&
            (entry.requires == null ||
                session.policy.canAnyOf(entry.requires!)))
          entry,
    ];
    if (entries.isEmpty) {
      return const ClayEmptyView(
        title: 'لا توجد أقسام متاحة',
        message: 'اطلب من الإدارة تفعيل الصلاحيات لحسابك',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(ClaySpacing.screenPadding),
      itemCount: entries.length,
      itemExtent: 84,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
          child: ClayCard(
            flat: true,
            semanticLabel: entry.label,
            onTap: () => context.push(entry.path),
            child: Row(
              children: [
                Icon(entry.icon, color: context.palette.accent),
                const SizedBox(width: ClaySpacing.lg),
                Expanded(
                  child: Text(
                    entry.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Icon(Icons.chevron_left_rounded),
              ],
            ),
          ),
        );
      },
    );
  }
}
