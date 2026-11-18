import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'settings_screen.dart' show displayDate;

/// دليل الهواتف: خانة منفصلة تماماً عن التلاميذ. تُسجَّل فيها أرقام من لا يوجدون عندنا (تلاميذ لحصة
/// واحدة، أو أسماء تركوا أرقامهم ليُتَّصل بهم بعد مدة) بملاحظة وتاريخ تواصل. وتبويب ثانٍ يعرض أرقام تلاميذنا
/// المسجَّلين (للقراءة فقط) فيجتمع كل شيء في مكان واحد.
class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: ClayAppBar(title: 'دليل الهواتف', showBack: true),
        body: Column(
          children: [
            TabBar(
              tabs: [
                Tab(text: 'أرقام مسجَّلة'),
                Tab(text: 'أرقام تلاميذنا'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [_ContactsTab(), _StudentPhonesTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactsTab extends ConsumerStatefulWidget {
  const _ContactsTab();

  @override
  ConsumerState<_ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends ConsumerState<_ContactsTab> {
  Future<void> _edit([ContactRow? contact]) => showDialog<void>(
    context: context,
    builder: (_) => _ContactDialog(initial: contact),
  );

  Future<void> _remove(ContactRow contact) async {
    final ok = await showClayConfirm(
      context,
      title: 'حذف الرقم',
      message:
          'سيُحذف «${contact.name.isEmpty ? contact.phone : contact.name}» من الدليل.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (ok) await ref.read(contactServiceProvider).remove(contact.id);
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = ref.can(PermissionModule.students, PermissionAction.add);
    final canEdit = ref.can(PermissionModule.students, PermissionAction.edit);
    final canDelete = ref.can(
      PermissionModule.students,
      PermissionAction.delete,
    );
    final today = DateKey.of(DateTime.now());
    return _EmbeddedListPage<ContactRow>(
      data: ref.watch(contactsProvider('')),
      emptyTitle: 'لا أرقام مسجَّلة',
      emptyMessage:
          'سجّل رقم هاتف من لا يوجدون عندنا ليُتَّصل بهم لاحقاً: تلميذ لحصة واحدة، '
          'أو اسم ترك رقمه',
      searchHint: 'ابحث بالاسم أو الرقم أو الملاحظة',
      matches: (c, q) =>
          c.name.contains(q) || c.phone.contains(q) || c.note.contains(q),
      onRetry: () => ref.invalidate(contactsProvider),
      addLabel: 'إضافة رقم',
      onAdd: canAdd ? _edit : null,
      itemExtent: 96,
      itemBuilder: (context, c) {
        final due =
            c.followUpDate != null && c.followUpDate!.compareTo(today) <= 0;
        return ClayListTile(
          title: c.name.isEmpty ? 'بلا اسم' : c.name,
          subtitle: [
            c.phone,
            if (c.note.isNotEmpty) c.note,
            if (c.followUpDate != null)
              'التواصل: ${displayDate(c.followUpDate!)}${due ? ' (حان)' : ''}',
          ].join(' · '),
          subtitleLines: 2,
          trailing: [
            if (due)
              const ClayBadge(label: 'حان الاتصال', tone: ClayTone.warning),
            if (c.source == ContactService.sourceOneTime)
              const ClayBadge(label: 'حصة واحدة', tone: ClayTone.info),
            IconButton(
              tooltip: 'نسخ الرقم',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () => Clipboard.setData(ClipboardData(text: c.phone)),
            ),
            if (canEdit)
              IconButton(
                tooltip: 'تعديل',
                icon: const Icon(ClayIcons.edit),
                onPressed: () => _edit(c),
              ),
            if (canDelete)
              IconButton(
                tooltip: 'حذف',
                icon: const Icon(ClayIcons.delete),
                onPressed: () => _remove(c),
              ),
          ],
        );
      },
    );
  }
}

class _StudentPhonesTab extends ConsumerWidget {
  const _StudentPhonesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _EmbeddedListPage<StudentPhone>(
      data: ref.watch(studentPhonesProvider('')),
      emptyTitle: 'لا أرقام لتلاميذ مسجَّلين',
      searchHint: 'ابحث بالاسم أو الرقم',
      matches: (s, q) => s.name.contains(q) || s.phone.contains(q),
      onRetry: () => ref.invalidate(studentPhonesProvider),
      itemExtent: 80,
      itemBuilder: (context, s) => ClayListTile(
        leading: ClayAvatar(name: s.name),
        title: s.name,
        subtitle: 'هاتف الوليّ: ${s.phone}',
        trailing: [
          IconButton(
            tooltip: 'نسخ الرقم',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () => Clipboard.setData(ClipboardData(text: s.phone)),
          ),
        ],
      ),
    );
  }
}

/// قائمة بحث داخل تبويب (بلا شريط عنوان): بحث محلي فوري، وحالات التحميل والفراغ والخطأ وزر الإضافة.
class _EmbeddedListPage<T> extends StatefulWidget {
  const _EmbeddedListPage({
    required this.data,
    required this.itemBuilder,
    required this.emptyTitle,
    required this.searchHint,
    required this.matches,
    this.emptyMessage,
    this.itemExtent = 72,
    this.addLabel,
    this.onAdd,
    this.onRetry,
  });

  final AsyncValue<List<T>> data;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyTitle;
  final String? emptyMessage;
  final String searchHint;
  final bool Function(T item, String query) matches;
  final double itemExtent;
  final String? addLabel;
  final VoidCallback? onAdd;
  final VoidCallback? onRetry;

  @override
  State<_EmbeddedListPage<T>> createState() => _EmbeddedListPageState<T>();
}

class _EmbeddedListPageState<T> extends State<_EmbeddedListPage<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(ClaySpacing.screenPadding),
          child: ClayTextField(
            hint: widget.searchHint,
            prefixIcon: Icons.search_rounded,
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
        ),
        Expanded(
          child: widget.data.when(
            loading: () => const ClaySkeletonList(),
            error: (_, _) => ClayErrorView(
              message: 'تعذّرت القراءة',
              onRetry: widget.onRetry,
            ),
            data: (items) {
              final shown = _query.isEmpty
                  ? items
                  : [
                      for (final item in items)
                        if (widget.matches(item, _query)) item,
                    ];
              if (shown.isEmpty) {
                return ClayEmptyView(
                  title: _query.isEmpty ? widget.emptyTitle : 'لا نتائج',
                  message: _query.isEmpty ? widget.emptyMessage : null,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: ClaySpacing.screenPadding,
                ),
                itemCount: shown.length,
                itemExtent: widget.itemExtent,
                itemBuilder: (context, i) =>
                    widget.itemBuilder(context, shown[i]),
              );
            },
          ),
        ),
        if (widget.onAdd != null && widget.addLabel != null)
          Padding(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            child: ClayButton(
              label: widget.addLabel!,
              icon: ClayIcons.add,
              expand: true,
              onPressed: widget.onAdd,
            ),
          ),
      ],
    );
  }
}

/// إضافة رقم أو تعديله: الاسم (اختياري)، الرقم، الملاحظة، وتاريخ التواصل (اختياري).
class _ContactDialog extends ConsumerStatefulWidget {
  const _ContactDialog({this.initial});

  final ContactRow? initial;

  @override
  ConsumerState<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends ConsumerState<_ContactDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _phone = TextEditingController(text: widget.initial?.phone ?? '');
  late final _note = TextEditingController(text: widget.initial?.note ?? '');
  late String? _followUp = widget.initial?.followUpDate;
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showClayDatePicker(
      context,
      title: 'تاريخ التواصل',
      initial: _followUp == null ? now : DateKey.parse(_followUp!),
    );
    if (picked == null || !mounted) return;
    setState(() => _followUp = DateKey.of(picked));
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _errors = const {};
    });
    final service = ref.read(contactServiceProvider);
    try {
      final initial = widget.initial;
      if (initial == null) {
        await service.add(
          name: _name.text,
          phone: _phone.text,
          note: _note.text,
          followUpDate: _followUp,
        );
      } else {
        await service.update(
          initial.id,
          name: _name.text,
          phone: _phone.text,
          note: _note.text,
          followUpDate: _followUp,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: ClaySpacing.md);
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return ClayDialog(
      title: widget.initial == null ? 'إضافة رقم' : 'تعديل الرقم',
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClayTextField(
              controller: _name,
              label: 'الاسم (اختياري)',
              autofocus: true,
            ),
            gap,
            ClayTextField(
              controller: _phone,
              label: 'رقم الهاتف',
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              error: _errors[ContactService.fieldPhone],
            ),
            gap,
            ClayTextField(
              controller: _note,
              label: 'ملاحظة (مثلاً: اتصل بعد شهر)',
              maxLines: 2,
            ),
            gap,
            Row(
              children: [
                Expanded(
                  child: Text(
                    _followUp == null
                        ? 'بلا تاريخ تواصل'
                        : 'التواصل: ${displayDate(_followUp!)}',
                    style: text.bodyMedium,
                  ),
                ),
                ClayButton(
                  label: _followUp == null ? 'تحديد تاريخ' : 'تغيير',
                  kind: ClayButtonKind.secondary,
                  onPressed: _pickDate,
                ),
                if (_followUp != null)
                  IconButton(
                    tooltip: 'إزالة التاريخ',
                    icon: const Icon(ClayIcons.close),
                    onPressed: () => setState(() => _followUp = null),
                  ),
              ],
            ),
            if (_errors[ContactService.fieldFollowUp] != null)
              Text(
                _errors[ContactService.fieldFollowUp]!,
                style: text.bodySmall!.copyWith(color: p.status.danger),
              ),
          ],
        ),
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
