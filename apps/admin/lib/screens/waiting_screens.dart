import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// قوائم الانتظار: لكل (مادة + مستوى) قائمة، والبالغة حدّها أولاً.
class WaitingListsScreen extends ConsumerWidget {
  const WaitingListsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClayListPage<WaitingListItem>(
      title: 'قوائم الانتظار',
      data: ref.watch(waitingListsProvider),
      emptyTitle: 'لا أحد في الانتظار',
      emptyMessage: 'يظهر هنا التلاميذ الذين سُجّلوا دون مجموعة متاحة',
      itemExtent: 112,
      onRetry: () => ref.invalidate(waitingListsProvider),
      itemBuilder: (context, item) => ClayListTile(
        title: item.title,
        subtitle:
            '${item.count} منتظر · الحد ${item.threshold}\n'
            '${item.preferredTeacherName == null ? 'بلا أستاذ مفضّل' : 'الأستاذ ${item.preferredTeacherName}'}',
        subtitleLines: 2,
        onTap: () => context.push('/waiting/${item.id}'),
        trailing: [
          if (item.reachedThreshold)
            const ClayBadge(label: 'بلغ الحد', tone: ClayTone.success),
        ],
      ),
    );
  }
}

/// تفاصيل قائمة انتظار: حدّها، منتظروها، وإنشاء مجموعة لهم.
class WaitingDetailsScreen extends ConsumerStatefulWidget {
  const WaitingDetailsScreen({required this.listId, super.key});

  final String listId;

  @override
  ConsumerState<WaitingDetailsScreen> createState() =>
      _WaitingDetailsScreenState();
}

class _WaitingDetailsScreenState extends ConsumerState<WaitingDetailsScreen> {
  final _threshold = TextEditingController();
  int? _loadedThreshold;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _threshold.dispose();
    super.dispose();
  }

  Future<void> _saveThreshold() async {
    final value = int.tryParse(_threshold.text.trim());
    if (value == null) {
      setState(() => _error = 'أدخل رقماً صحيحاً');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(waitingServiceProvider).setThreshold(widget.listId, value);
    } on ValidationException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(WaitingStudent student) async {
    final ok = await showClayConfirm(
      context,
      title: 'إخراج من الانتظار',
      message: 'سيُزال ${student.name} من هذه القائمة، ويبقى ملفه كما هو.',
      confirmLabel: 'إخراج',
      danger: true,
    );
    if (!ok) return;
    await ref
        .read(waitingServiceProvider)
        .remove(listId: widget.listId, studentId: student.studentId);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final list = ref.watch(waitingListProvider(widget.listId));
    final students = ref.watch(waitingStudentsProvider(widget.listId));
    final canEdit = ref.can(PermissionModule.waiting, PermissionAction.edit);
    final canCreateGroup = ref.can(
      PermissionModule.groups,
      PermissionAction.add,
    );

    return Scaffold(
      appBar: const ClayAppBar(title: 'قائمة الانتظار', showBack: true),
      body: list.when(
        loading: () => const ClayLoadingView(),
        error: (_, _) => ClayErrorView(
          message: 'تعذّرت قراءة القائمة',
          onRetry: () => ref.invalidate(waitingListProvider),
        ),
        data: (item) {
          if (item == null) {
            return const ClayEmptyView(
              title: 'لا منتظرين في هذه القائمة',
              icon: ClayIcons.students,
            );
          }
          if (_loadedThreshold != item.threshold) {
            _loadedThreshold = item.threshold;
            _threshold.text = '${item.threshold}';
          }
          final people = students.value ?? const <WaitingStudent>[];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                child: ClayCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(item.title, style: text.titleMedium),
                          ),
                          if (item.reachedThreshold)
                            const ClayBadge(
                              label: 'بلغ الحد',
                              tone: ClayTone.success,
                            ),
                        ],
                      ),
                      const SizedBox(height: ClaySpacing.xs),
                      Text(
                        '${item.count} منتظر من أصل حد ${item.threshold}',
                        style: text.bodyMedium,
                      ),
                      Text(
                        item.preferredTeacherName == null
                            ? 'بلا أستاذ مفضّل'
                            : 'الأستاذ المفضّل: ${item.preferredTeacherName}',
                        style: text.bodySmall!.copyWith(color: p.textMuted),
                      ),
                      if (canEdit) ...[
                        const SizedBox(height: ClaySpacing.md),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClayTextField(
                                controller: _threshold,
                                label: 'حد التنبيه',
                                error: _error,
                                keyboardType: TextInputType.number,
                                textDirection: TextDirection.ltr,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                              ),
                            ),
                            const SizedBox(width: ClaySpacing.sm),
                            Padding(
                              padding: const EdgeInsets.only(top: 22),
                              child: ClayButton(
                                label: 'حفظ الحد',
                                kind: ClayButtonKind.secondary,
                                loading: _saving,
                                onPressed: _saveThreshold,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (canCreateGroup) ...[
                        const SizedBox(height: ClaySpacing.md),
                        ClayButton(
                          label: 'إنشاء مجموعة',
                          icon: ClayIcons.groups,
                          onPressed: () => context.push(
                            Uri(
                              path: '/groups/new',
                              queryParameters: {
                                'subject': item.list.subjectId,
                                if (item.list.preferredTeacherId != null)
                                  'teacher': item.list.preferredTeacherId!,
                              },
                            ).toString(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ClaySpacing.screenPadding,
                  ),
                  itemCount: people.length,
                  itemExtent: 88,
                  itemBuilder: (context, i) {
                    final s = people[i];
                    return ClayListTile(
                      title: s.name,
                      subtitle:
                          '${s.parentPhone} · منذ '
                          '${DateKey.of(DateTime.fromMillisecondsSinceEpoch(s.addedAt))}',
                      onTap: () => context.push('/students/${s.studentId}'),
                      trailing: [
                        if (canEdit)
                          IconButton(
                            tooltip: 'إخراج ${s.name} من الانتظار',
                            icon: const Icon(ClayIcons.close),
                            onPressed: () => _remove(s),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
