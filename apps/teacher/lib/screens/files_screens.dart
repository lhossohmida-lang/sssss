import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// «2.5 ك.ب» أو «1.2 م.ب» من حجم بالبايت (أرقام لاتينية).
String fileSizeText(int bytes) {
  if (bytes < 1024) return '$bytes بايت';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} ك.ب';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
}

/// ملفات المجموعة: دروس وتمارين يرفعها الأستاذ لتلاميذه، يفتح كل ملف
/// بالضغط عليه، وتُعاد تسميته أو يُحذف.
class GroupFilesScreen extends ConsumerWidget {
  const GroupFilesScreen({required this.groupId, super.key});

  final String groupId;

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    GroupFileItem item,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(groupFileServiceProvider);
    Uint8List? bytes = await service.readLocal(item.file);
    if (bytes == null) {
      // النسخة المحلية غير موجودة (ملف رُفع من جهاز آخر): يُجلب من الخادم.
      final url = item.file.fileUrl;
      final store = ref.read(runtimeProvider).fileStore;
      if (url != null && store != null) {
        final slash = url.indexOf('/');
        try {
          bytes = await store.download(
            bucket: url.substring(0, slash),
            remotePath: url.substring(slash + 1),
          );
        } on RemoteException {
          bytes = null;
        }
      }
    }
    if (bytes == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تعذّر فتح الملف الآن؛ تحقّق من الاتصال وأعد المحاولة'),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    if (item.isPdf) {
      await ref
          .read(pdfPresenterProvider)
          .show(
            context,
            bytes: bytes,
            fileName: item.fileName,
            title: item.title,
          );
    } else {
      await showClayDialog<void>(
        context,
        title: item.title,
        content: InteractiveViewer(child: Image.memory(bytes)),
      );
    }
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    GroupFileItem item,
  ) async {
    final me = ref.read(myTeacherIdProvider);
    if (me == null) return;
    final title = await showClayDialog<String>(
      context,
      title: 'تعديل العنوان',
      content: _TitleField(initial: item.title),
    );
    if (title == null) return;
    try {
      await ref
          .read(groupFileServiceProvider)
          .rename(item.id, title: title, teacherId: me);
    } on ValidationException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.errors.values.first)));
      }
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    GroupFileItem item,
  ) async {
    final me = ref.read(myTeacherIdProvider);
    final ok = await showClayConfirm(
      context,
      title: 'حذف الملف',
      message: 'سيُحذف «${item.title}» من المجموعة ولن يراه التلاميذ.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || me == null) return;
    await ref.read(groupFileServiceProvider).remove(item.id, teacherId: me);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final group = ref.watch(groupItemProvider(groupId));
    final files = ref.watch(groupFilesProvider(groupId));
    return Scaffold(
      appBar: ClayAppBar(
        title: group == null ? 'الملفات' : 'ملفات المجموعة ${group.number}',
        showBack: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: files.when(
              loading: () => const ClaySkeletonList(),
              error: (_, _) => ClayErrorView(
                message: 'تعذّرت قراءة الملفات',
                onRetry: () => ref.invalidate(groupFilesProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const ClayEmptyView(
                    title: 'لا ملفات بعد',
                    message: 'ارفع دروساً أو تمارين PDF لتلاميذ مجموعتك',
                    icon: ClayIcons.files,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                  itemCount: items.length,
                  itemExtent: 96,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return ClayListTile(
                      title: item.title,
                      subtitle:
                          '${item.fileName} · ${fileSizeText(item.sizeBytes)}',
                      leading: Icon(
                        item.isPdf ? ClayIcons.files : ClayIcons.receipt,
                        color: p.accent,
                      ),
                      onTap: () => _open(context, ref, item),
                      trailing: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            item.uploaded
                                ? const ClayBadge(
                                    label: 'مرفوع',
                                    tone: ClayTone.success,
                                  )
                                : const ClayBadge(
                                    label: 'في الانتظار',
                                    tone: ClayTone.warning,
                                  ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'تعديل العنوان',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(ClayIcons.edit, size: 20),
                                  onPressed: () => _rename(context, ref, item),
                                ),
                                IconButton(
                                  tooltip: 'حذف الملف',
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(
                                    ClayIcons.delete,
                                    size: 20,
                                    color: p.status.danger,
                                  ),
                                  onPressed: () => _delete(context, ref, item),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ملفات PDF أو صور، حتى 10 م.ب للملف',
                  style: text.bodySmall!.copyWith(color: p.textMuted),
                ),
                const SizedBox(height: ClaySpacing.sm),
                ClayButton(
                  label: 'إضافة ملف',
                  icon: ClayIcons.add,
                  expand: true,
                  onPressed: () => context.push('/groups/$groupId/files/new'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// حقل عنوان داخل حوار: يملك متحكّمه، ويعيد النص عند «حفظ».
class _TitleField extends StatefulWidget {
  const _TitleField({required this.initial});

  final String initial;

  @override
  State<_TitleField> createState() => _TitleFieldState();
}

class _TitleFieldState extends State<_TitleField> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClayTextField(controller: _controller, label: 'عنوان الملف'),
        const SizedBox(height: ClaySpacing.md),
        ClayButton(
          label: 'حفظ',
          expand: true,
          onPressed: () => Navigator.of(context).pop(_controller.text),
        ),
        const SizedBox(height: ClaySpacing.sm),
        ClayButton(
          label: 'إلغاء',
          kind: ClayButtonKind.secondary,
          expand: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// إضافة ملف: اختيار الملف من الجهاز، وعنوان (اسم الملف افتراضاً)، ثم حفظ
/// يضعه في المجموعة ويرفعه في الخلفية.
class AddGroupFileScreen extends ConsumerStatefulWidget {
  const AddGroupFileScreen({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<AddGroupFileScreen> createState() => _AddGroupFileScreenState();
}

class _AddGroupFileScreenState extends ConsumerState<AddGroupFileScreen> {
  final _title = TextEditingController();
  PickedFile? _file;
  bool _saving = false;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    PickedFile? picked;
    try {
      picked = await ref
          .read(fileSourceProvider)
          .pick(
            context,
            extensions: GroupFileService.allowedExtensions.toList(),
          );
    } on Exception {
      if (mounted) {
        setState(
          () => _errors = {GroupFileService.fieldFile: 'تعذّرت قراءة الملف'},
        );
      }
      return;
    }
    if (picked == null || !mounted) return;
    setState(() {
      _file = picked;
      _errors = const {};
      // العنوان الافتراضي اسم الملف بلا امتداده، ما لم يكتب الأستاذ عنواناً.
      if (_title.text.trim().isEmpty) {
        final dot = picked!.name.lastIndexOf('.');
        _title.text = dot > 0 ? picked.name.substring(0, dot) : picked.name;
      }
    });
  }

  Future<void> _save() async {
    final me = ref.read(myTeacherIdProvider);
    final file = _file;
    if (me == null || _saving) return;
    if (file == null) {
      setState(
        () => _errors = {GroupFileService.fieldFile: 'اختر الملف أولاً'},
      );
      return;
    }
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      await ref
          .read(groupFileServiceProvider)
          .add(
            groupId: widget.groupId,
            teacherId: me,
            title: _title.text,
            fileName: file.name,
            bytes: file.bytes,
          );
      if (mounted) context.pop();
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final file = _file;
    return Scaffold(
      appBar: const ClayAppBar(title: 'إضافة ملف', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(ClaySpacing.screenPadding),
        children: [
          ClayButton(
            label: file == null ? 'اختيار ملف' : 'تغيير الملف',
            icon: ClayIcons.files,
            kind: ClayButtonKind.secondary,
            expand: true,
            onPressed: _pick,
          ),
          if (file != null)
            Padding(
              padding: const EdgeInsets.only(top: ClaySpacing.sm),
              child: Text(
                '${file.name} · ${fileSizeText(file.bytes.length)}',
                style: text.bodyMedium,
              ),
            ),
          if (_errors[GroupFileService.fieldFile] != null)
            Padding(
              padding: const EdgeInsets.only(top: ClaySpacing.xs),
              child: Text(
                _errors[GroupFileService.fieldFile]!,
                style: text.bodySmall!.copyWith(color: p.status.danger),
              ),
            ),
          if (_errors[GroupFileService.fieldGroup] != null)
            Text(
              _errors[GroupFileService.fieldGroup]!,
              style: text.bodySmall!.copyWith(color: p.status.danger),
            ),
          const SizedBox(height: ClaySpacing.lg),
          ClayTextField(
            controller: _title,
            label: 'عنوان الملف',
            hint: 'مثال: تمارين الفصل الأول',
            error: _errors[GroupFileService.fieldTitle],
          ),
          const SizedBox(height: ClaySpacing.xl),
          ClayButton(
            label: 'حفظ ورفع',
            icon: ClayIcons.check,
            expand: true,
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
