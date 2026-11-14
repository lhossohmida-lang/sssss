import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// مجموعة أقسام في قائمة «المزيد».
enum MoreSection {
  teaching('التعليم'),
  finance('المالية'),
  team('الفريق'),
  system('النظام');

  const MoreSection(this.title);

  final String title;
}

/// قسم في قائمة «المزيد».
class MoreEntry {
  const MoreEntry({
    required this.label,
    required this.icon,
    required this.path,
    required this.section,
    this.requires,
    this.anyActions,
    this.requiredPermissions = const {},
    this.ownerOnly = false,
  });

  final String label;
  final IconData icon;

  /// مسار صفحته (`AppPage`).
  final String path;

  /// المجموعة التي يُعرض تحت عنوانها.
  final MoreSection section;

  /// الوحدة التي يشترطها ظهور القسم.
  final PermissionModule? requires;

  /// أحد هذه الأفعال يكفي لإظهار هذا القسم.
  final Set<PermissionAction>? anyActions;

  /// صلاحيات إضافية مطلوبة لإظهار القسم عند جمعه بين وحدات.
  final Map<PermissionModule, PermissionAction> requiredPermissions;

  /// الأقسام السحابية الحساسة لصاحب المدرسة وحده.
  final bool ownerOnly;
}

/// أقسام «المزيد» مجمّعة؛ كل مهمة لاحقة تضيف قسمها مع صفحته في `adminPages`.
const List<MoreEntry> moreEntries = [
  MoreEntry(
    label: 'الحضور',
    icon: ClayIcons.attendance,
    path: '/attendance',
    section: MoreSection.teaching,
    requires: PermissionModule.attendance,
  ),
  MoreEntry(
    label: 'الجدول الأسبوعي',
    icon: ClayIcons.schedule,
    path: '/schedule',
    section: MoreSection.teaching,
    requires: PermissionModule.groups,
  ),
  MoreEntry(
    label: 'قوائم الانتظار',
    icon: ClayIcons.waiting,
    path: '/waiting',
    section: MoreSection.teaching,
    requires: PermissionModule.waiting,
  ),
  MoreEntry(
    label: 'الماسح',
    icon: ClayIcons.scan,
    path: '/scanner',
    section: MoreSection.teaching,
    requires: PermissionModule.scanner,
  ),
  MoreEntry(
    label: 'شاشة المدخل',
    icon: ClayIcons.students,
    path: '/entrance',
    section: MoreSection.teaching,
    requires: PermissionModule.scanner,
  ),
  MoreEntry(
    label: 'المستحقات',
    icon: ClayIcons.dues,
    path: '/dues',
    section: MoreSection.finance,
    requires: PermissionModule.payments,
  ),
  MoreEntry(
    label: 'حقوق التسجيل',
    icon: ClayIcons.payments,
    path: '/fees',
    section: MoreSection.finance,
    requires: PermissionModule.payments,
  ),
  MoreEntry(
    label: 'المصاريف',
    icon: ClayIcons.expenses,
    path: '/expenses',
    section: MoreSection.finance,
    requires: PermissionModule.expenses,
    anyActions: {
      PermissionAction.view,
      PermissionAction.add,
      PermissionAction.edit,
      PermissionAction.delete,
    },
  ),
  MoreEntry(
    label: 'التقرير الشهري',
    icon: ClayIcons.payments,
    path: '/monthly-report',
    section: MoreSection.finance,
    requires: PermissionModule.payments,
    anyActions: {PermissionAction.view},
    requiredPermissions: {
      PermissionModule.expenses: PermissionAction.view,
      PermissionModule.payouts: PermissionAction.view,
    },
  ),
  MoreEntry(
    label: 'خلاص الأساتذة',
    icon: ClayIcons.payments,
    path: '/payouts',
    section: MoreSection.finance,
    requires: PermissionModule.payouts,
  ),
  MoreEntry(
    label: 'المحادثات',
    icon: ClayIcons.chat,
    path: '/chat',
    section: MoreSection.team,
    requires: PermissionModule.chat,
    anyActions: {PermissionAction.view, PermissionAction.edit},
  ),
  MoreEntry(
    label: 'طلبات الأساتذة',
    icon: ClayIcons.schedule,
    path: '/requests',
    section: MoreSection.team,
    requires: PermissionModule.requests,
  ),
  MoreEntry(
    label: 'الأساتذة',
    icon: ClayIcons.teachers,
    path: '/teachers',
    section: MoreSection.team,
    requires: PermissionModule.teachers,
  ),
  MoreEntry(
    label: 'حضور الأساتذة',
    icon: ClayIcons.attendance,
    path: '/teacher-attendance',
    section: MoreSection.team,
    requires: PermissionModule.teachers,
  ),
  MoreEntry(
    label: 'العمال',
    icon: ClayIcons.workers,
    path: '/workers',
    section: MoreSection.team,
    requires: PermissionModule.workers,
  ),
  MoreEntry(
    label: 'النقل',
    icon: ClayIcons.transport,
    path: '/transport',
    section: MoreSection.team,
    requires: PermissionModule.transport,
    anyActions: {
      PermissionAction.view,
      PermissionAction.add,
      PermissionAction.edit,
      PermissionAction.delete,
    },
  ),
  MoreEntry(
    label: 'حضور العمال',
    icon: ClayIcons.attendance,
    path: '/worker-attendance',
    section: MoreSection.team,
    requires: PermissionModule.workers,
  ),
  MoreEntry(
    label: 'المواد',
    icon: ClayIcons.subjects,
    path: '/subjects',
    section: MoreSection.system,
    requires: PermissionModule.subjects,
  ),
  MoreEntry(
    label: 'القاعات',
    icon: ClayIcons.rooms,
    path: '/rooms',
    section: MoreSection.system,
    requires: PermissionModule.rooms,
  ),
  MoreEntry(
    label: 'الرسائل القصيرة',
    icon: ClayIcons.sms,
    path: '/sms',
    section: MoreSection.system,
    requires: PermissionModule.sms,
  ),
  MoreEntry(
    label: 'الإعدادات',
    icon: ClayIcons.settings,
    path: '/settings',
    section: MoreSection.system,
    requires: PermissionModule.settings,
  ),
  MoreEntry(
    label: 'Google Drive',
    icon: Icons.cloud_upload_outlined,
    path: '/drive',
    section: MoreSection.system,
    requires: PermissionModule.settings,
    ownerOnly: true,
  ),
];

/// عنصر في عرض «المزيد»: عنوان مجموعة أو قسم.
sealed class _Row {
  const _Row();
}

class _Header extends _Row {
  const _Header(this.title);

  final String title;
}

class _Entry extends _Row {
  const _Entry(this.entry);

  final MoreEntry entry;
}

/// قائمة «المزيد»: الأقسام التي لا يتسع لها الشريط السفلي مجمّعة بعناوين،
/// وتظهر لكل مستخدم ما يملك صلاحيته فقط، والمجموعة الفارغة تختفي بعنوانها.
class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  static const double _headerExtent = 48;
  static const double _entryExtent = 84;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider.select((s) => s.value));
    final pendingRequests = ref.watch(pendingRequestsCountProvider).value ?? 0;
    final rows = <_Row>[];
    for (final section in MoreSection.values) {
      final visible = [
        for (final entry in moreEntries)
          if (entry.section == section &&
              session != null &&
              (!entry.ownerOnly || session.role == UserRole.owner) &&
              entry.requiredPermissions.entries.every(
                (requirement) =>
                    session.can(requirement.key, requirement.value),
              ) &&
              (entry.requires == null ||
                  (entry.anyActions?.any(
                        (action) => session.can(entry.requires!, action),
                      ) ??
                      session.policy.canAnyOf(entry.requires!))))
            entry,
      ];
      if (visible.isEmpty) continue;
      rows
        ..add(_Header(section.title))
        ..addAll(visible.map(_Entry.new));
    }
    if (rows.isEmpty) {
      return const ClayEmptyView(
        title: 'لا توجد أقسام متاحة',
        message: 'اطلب من الإدارة تفعيل الصلاحيات لحسابك',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(ClaySpacing.screenPadding),
      itemCount: rows.length,
      itemExtentBuilder: (i, _) =>
          rows[i] is _Header ? _headerExtent : _entryExtent,
      itemBuilder: (context, i) {
        final row = rows[i];
        if (row is _Header) {
          return Align(
            alignment: AlignmentDirectional.bottomStart,
            child: Padding(
              padding: const EdgeInsets.only(bottom: ClaySpacing.xs),
              child: Semantics(
                header: true,
                child: Text(
                  row.title,
                  style: Theme.of(context).textTheme.titleSmall!
                      .copyWith(color: context.palette.textMuted),
                ),
              ),
            ),
          );
        }
        final entry = (row as _Entry).entry;
        return ClayListTile(
          leading: Icon(entry.icon, color: context.palette.accent),
          title: entry.label,
          onTap: () => context.push(entry.path),
          trailing: [
            if (entry.path == '/requests' && pendingRequests > 0)
              ClayBadge(
                label: '$pendingRequests معلّق',
                tone: ClayTone.warning,
              ),
            const Icon(Icons.chevron_left_rounded),
          ],
        );
      },
    );
  }
}
