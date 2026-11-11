import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// أزرار التعديل والحذف في نهاية صف قائمة، تُخفى حسب الصلاحية.
List<Widget> _rowActions({
  required String name,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) => [
  if (onEdit != null)
    IconButton(
      tooltip: 'تعديل $name',
      icon: const Icon(ClayIcons.edit),
      onPressed: onEdit,
    ),
  if (onDelete != null)
    IconButton(
      tooltip: 'حذف $name',
      icon: const Icon(ClayIcons.delete),
      onPressed: onDelete,
    ),
];

// ---------------------------------------------------------------------------
// المواد
// ---------------------------------------------------------------------------

class SubjectsScreen extends ConsumerWidget {
  const SubjectsScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    List<LevelRow> levels,
    SubjectItem? item,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SubjectDialog(
        initial: item,
        levels: levels,
        onSave: (name, levelId, price) {
          final service = ref.read(subjectServiceProvider);
          return item == null
              ? service.add(name: name, levelId: levelId, monthlyPrice: price)
              : service.update(
                  item.id,
                  name: name,
                  levelId: levelId,
                  monthlyPrice: price,
                );
        },
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SubjectItem item,
  ) async {
    final ok = await showClayConfirm(
      context,
      title: 'حذف المادة',
      message:
          'ستختفي «${item.name}» من القوائم، وتبقى في سجلات المجموعات '
          'والتلاميذ المرتبطين بها.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (ok) await ref.read(subjectServiceProvider).remove(item.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // يُراقَب (لا يُقرأ فقط) حتى تكون المستويات محمّلة حين يُفتح الحوار.
    final levels = ref.watch(levelsProvider).value ?? const <LevelRow>[];
    final canAdd = ref.can(PermissionModule.subjects, PermissionAction.add);
    final canEdit = ref.can(PermissionModule.subjects, PermissionAction.edit);
    final canDelete = ref.can(
      PermissionModule.subjects,
      PermissionAction.delete,
    );
    return ClayListPage<SubjectItem>(
      title: 'المواد',
      data: ref.watch(subjectsProvider),
      emptyTitle: 'لا توجد مواد بعد',
      emptyMessage: 'أضف المواد التي تُدرَّس في المدرسة وسعر شهرها',
      searchHint: 'ابحث عن مادة',
      matches: (item, query) =>
          item.name.contains(query) || (item.levelName ?? '').contains(query),
      onRetry: () => ref.invalidate(subjectsProvider),
      addLabel: 'إضافة مادة',
      onAdd: canAdd ? () => _edit(context, ref, levels, null) : null,
      itemBuilder: (context, item) => ClayListTile(
        title: item.name,
        subtitle:
            '${item.levelName ?? 'كل المستويات'} · ${Money.format(item.monthlyPrice)}',
        onTap: canEdit ? () => _edit(context, ref, levels, item) : null,
        trailing: _rowActions(
          name: item.name,
          onEdit: canEdit ? () => _edit(context, ref, levels, item) : null,
          onDelete: canDelete ? () => _delete(context, ref, item) : null,
        ),
      ),
    );
  }
}

class _SubjectDialog extends StatefulWidget {
  const _SubjectDialog({
    required this.initial,
    required this.levels,
    required this.onSave,
  });

  final SubjectItem? initial;
  final List<LevelRow> levels;
  final Future<Object?> Function(String name, String? levelId, int price)
  onSave;

  @override
  State<_SubjectDialog> createState() => _SubjectDialogState();
}

class _SubjectDialogState extends State<_SubjectDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _price = TextEditingController(
    text: '${widget.initial?.monthlyPrice ?? ''}',
  );
  late String? _levelId = widget.initial?.subject.levelId;
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final price = int.tryParse(_price.text.trim());
    if (price == null) {
      setState(() => _errors = {SubjectService.fieldPrice: 'أدخل سعر الشهر'});
      return;
    }
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      await widget.onSave(_name.text, _levelId, price);
      if (mounted) Navigator.of(context).pop();
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClayDialog(
      title: widget.initial == null ? 'إضافة مادة' : 'تعديل المادة',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClayTextField(
            controller: _name,
            label: 'اسم المادة',
            autofocus: true,
            error: _errors[SubjectService.fieldName],
          ),
          const SizedBox(height: ClaySpacing.md),
          ClayDropdown<String?>(
            label: 'المستوى',
            value: _levelId,
            options: [
              const ClayOption(value: null, label: 'كل المستويات'),
              for (final level in widget.levels)
                ClayOption(value: level.id, label: level.name),
            ],
            onChanged: (value) => setState(() => _levelId = value),
          ),
          const SizedBox(height: ClaySpacing.md),
          ClayTextField(
            controller: _price,
            label: 'سعر الشهر (${Money.currency})',
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            helper: 'السعر الافتراضي عند إنشاء مجموعة',
            error: _errors[SubjectService.fieldPrice],
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        ClayButton(label: 'حفظ', loading: _saving, onPressed: _submit),
        ClayButton(
          label: 'إلغاء',
          kind: ClayButtonKind.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// القاعات
// ---------------------------------------------------------------------------

class RoomsScreen extends ConsumerWidget {
  const RoomsScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, RoomRow? room) =>
      showDialog<void>(
        context: context,
        builder: (_) => _RoomDialog(
          initial: room,
          onSave: (name, capacity) {
            final service = ref.read(roomServiceProvider);
            return room == null
                ? service.add(name: name, capacity: capacity)
                : service.update(room.id, name: name, capacity: capacity);
          },
        ),
      );

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    RoomRow room,
  ) async {
    final ok = await showClayConfirm(
      context,
      title: 'حذف القاعة',
      message:
          'ستختفي «${room.name}» من القوائم، وتبقى في الحصص التي استُعملت '
          'فيها.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (ok) await ref.read(roomServiceProvider).remove(room.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canAdd = ref.can(PermissionModule.rooms, PermissionAction.add);
    final canEdit = ref.can(PermissionModule.rooms, PermissionAction.edit);
    final canDelete = ref.can(PermissionModule.rooms, PermissionAction.delete);
    return ClayListPage<RoomRow>(
      title: 'القاعات',
      data: ref.watch(roomsProvider),
      emptyTitle: 'لا توجد قاعات بعد',
      emptyMessage: 'أضف قاعات المدرسة وسعة كل منها لتُقترح عند إنشاء مجموعة',
      onRetry: () => ref.invalidate(roomsProvider),
      addLabel: 'إضافة قاعة',
      onAdd: canAdd ? () => _edit(context, ref, null) : null,
      itemBuilder: (context, room) => ClayListTile(
        title: room.name,
        subtitle: 'السعة: ${room.capacity} مقعد',
        onTap: canEdit ? () => _edit(context, ref, room) : null,
        trailing: _rowActions(
          name: room.name,
          onEdit: canEdit ? () => _edit(context, ref, room) : null,
          onDelete: canDelete ? () => _delete(context, ref, room) : null,
        ),
      ),
    );
  }
}

class _RoomDialog extends StatefulWidget {
  const _RoomDialog({required this.initial, required this.onSave});

  final RoomRow? initial;
  final Future<Object?> Function(String name, int capacity) onSave;

  @override
  State<_RoomDialog> createState() => _RoomDialogState();
}

class _RoomDialogState extends State<_RoomDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _capacity = TextEditingController(
    text: '${widget.initial?.capacity ?? ''}',
  );
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final capacity = int.tryParse(_capacity.text.trim());
    if (capacity == null) {
      setState(() => _errors = {RoomService.fieldCapacity: 'أدخل السعة'});
      return;
    }
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      await widget.onSave(_name.text, capacity);
      if (mounted) Navigator.of(context).pop();
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClayDialog(
      title: widget.initial == null ? 'إضافة قاعة' : 'تعديل القاعة',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClayTextField(
            controller: _name,
            label: 'اسم القاعة',
            hint: 'مثال: القاعة 1',
            autofocus: true,
            error: _errors[RoomService.fieldName],
          ),
          const SizedBox(height: ClaySpacing.md),
          ClayTextField(
            controller: _capacity,
            label: 'السعة (عدد المقاعد)',
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            error: _errors[RoomService.fieldCapacity],
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        ClayButton(label: 'حفظ', loading: _saving, onPressed: _submit),
        ClayButton(
          label: 'إلغاء',
          kind: ClayButtonKind.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
