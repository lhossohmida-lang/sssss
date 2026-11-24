import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'settings_screen.dart' show displayDate;
import 'sms_auto_sender.dart';

/// دليل الهواتف: خانة منفصلة تماماً عن التلاميذ. تُسجَّل فيها أرقام من لا يوجدون عندنا (تلاميذ لحصة
/// واحدة، أو أسماء تركوا أرقامهم ليُتَّصل بهم بعد مدة) بملاحظة وسنة دراسية وتاريخ تواصل. وتبويب ثانٍ يعرض
/// أرقام تلاميذنا المسجَّلين (للقراءة فقط) فيجتمع كل شيء في مكان واحد. وفي كلا التبويبين: تصنيف حسب السنة
/// الدراسية، وتحديد الكل أو عدد من القائمة المعروضة، وكتابة رسالة SMS لكل المحدَّدين دفعة واحدة.
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
    final levels = {
      for (final l in ref.watch(levelsProvider).value ?? const <LevelRow>[])
        l.id: l.name,
    };
    final today = DateKey.of(DateTime.now());
    return _PhoneList<ContactRow>(
      data: ref.watch(contactsProvider('')),
      idOf: (c) => c.id,
      nameOf: (c) => c.name,
      phoneOf: (c) => c.phone,
      levelIdOf: (c) => c.levelId,
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
      itemBuilder: (context, c, selected, toggle) {
        final due =
            c.followUpDate != null && c.followUpDate!.compareTo(today) <= 0;
        final level = c.levelId == null ? null : levels[c.levelId];
        return ClayListTile(
          leading: ClayCheckbox(
            value: selected,
            semanticLabel: c.name.isEmpty ? c.phone : c.name,
            onChanged: (_) => toggle(),
          ),
          title: c.name.isEmpty ? 'بلا اسم' : c.name,
          subtitle: [
            c.phone,
            ?level,
            if (c.note.isNotEmpty) c.note,
            if (c.followUpDate != null)
              'التواصل: ${displayDate(c.followUpDate!)}${due ? ' (حان)' : ''}',
          ].join(' · '),
          subtitleLines: 2,
          onTap: toggle,
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
    return _PhoneList<StudentPhone>(
      data: ref.watch(studentPhonesProvider('')),
      idOf: (s) => s.studentId,
      nameOf: (s) => s.name,
      phoneOf: (s) => s.phone,
      levelIdOf: (s) => s.levelId,
      emptyTitle: 'لا أرقام لتلاميذ مسجَّلين',
      searchHint: 'ابحث بالاسم أو الرقم',
      matches: (s, q) => s.name.contains(q) || s.phone.contains(q),
      onRetry: () => ref.invalidate(studentPhonesProvider),
      itemExtent: 80,
      itemBuilder: (context, s, selected, toggle) => ClayListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClayCheckbox(
              value: selected,
              semanticLabel: s.name,
              onChanged: (_) => toggle(),
            ),
            const SizedBox(width: ClaySpacing.sm),
            ClayAvatar(name: s.name),
          ],
        ),
        title: s.name,
        subtitle: ['هاتف الوليّ: ${s.phone}', ?s.levelName].join(' · '),
        onTap: toggle,
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

/// مفاتيح مرشّح السنة: كل السنوات، ومن بلا سنة؛ وغيرهما معرّف السنة.
const String _allYears = 'all';
const String _noYear = 'none';

/// قائمة أرقام داخل تبويب (بلا شريط عنوان): بحث محلي فوري، وتصنيف بالسنة الدراسية، وتحديد الكل أو عدد من
/// المعروض، ورسالة SMS للمحدَّدين، وحالات التحميل والفراغ والخطأ وزر الإضافة.
class _PhoneList<T> extends ConsumerStatefulWidget {
  const _PhoneList({
    required this.data,
    required this.idOf,
    required this.nameOf,
    required this.phoneOf,
    required this.levelIdOf,
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
  final String Function(T item) idOf;
  final String Function(T item) nameOf;
  final String Function(T item) phoneOf;
  final String? Function(T item) levelIdOf;

  /// يبني صف عنصر: [selected] هل هو محدَّد، و[toggle] يبدّل تحديده.
  final Widget Function(
    BuildContext context,
    T item,
    bool selected,
    VoidCallback toggle,
  )
  itemBuilder;
  final String emptyTitle;
  final String? emptyMessage;
  final String searchHint;
  final bool Function(T item, String query) matches;
  final double itemExtent;
  final String? addLabel;
  final VoidCallback? onAdd;
  final VoidCallback? onRetry;

  @override
  ConsumerState<_PhoneList<T>> createState() => _PhoneListState<T>();
}

class _PhoneListState<T> extends ConsumerState<_PhoneList<T>> {
  String _query = '';
  String _year = _allYears;
  final Set<String> _selected = {};

  List<T> _shown(List<T> items) => [
    for (final item in items)
      if (_matchesYear(item) &&
          (_query.isEmpty || widget.matches(item, _query)))
        item,
  ];

  bool _matchesYear(T item) {
    final level = widget.levelIdOf(item);
    return switch (_year) {
      _allYears => true,
      _noYear => level == null,
      _ => level == _year,
    };
  }

  void _toggle(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  void _toggleAll(List<T> shown) => setState(() {
    final ids = [for (final item in shown) widget.idOf(item)];
    if (ids.every(_selected.contains)) {
      _selected.removeAll(ids);
    } else {
      _selected.addAll(ids);
    }
  });

  Future<void> _pickCount(List<T> shown) async {
    final count = await showDialog<int>(
      context: context,
      builder: (_) => SelectCountDialog(max: shown.length),
    );
    if (count == null || !mounted) return;
    setState(() {
      _selected
        ..clear()
        ..addAll([for (final item in shown.take(count)) widget.idOf(item)]);
    });
  }

  Future<void> _compose(List<T> all) async {
    final chosen = [
      for (final item in all)
        if (_selected.contains(widget.idOf(item))) item,
    ];
    final recipients = <String, SmsRecipient>{};
    var invalid = 0;
    for (final item in chosen) {
      final phone = widget.phoneOf(item);
      if (!PhoneNumbers.isValid(phone)) {
        invalid++;
        continue;
      }
      final key = PhoneNumbers.toInternational(phone);
      final name = widget.nameOf(item).trim();
      final existing = recipients[key];
      if (existing == null) {
        recipients[key] = SmsRecipient(
          phone: phone,
          names: [?name.isEmpty ? null : name],
        );
      } else if (name.isNotEmpty && !existing.names.contains(name)) {
        existing.names.add(name);
      }
    }
    final sent = await showDialog<int>(
      context: context,
      builder: (_) => BulkSmsDialog(
        recipients: recipients.values.toList(),
        invalid: invalid,
      ),
    );
    if (sent == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'أُضيفت $sent رسالة إلى طابور الرسائل؛ تُرسل من هاتف الإرسال المعيَّن '
          '(مركز الرسائل ← الطابور)',
        ),
      ),
    );
    setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final canSms = ref.can(PermissionModule.sms, PermissionAction.add);
    final levels = ref.watch(levelsProvider).value ?? const <LevelRow>[];
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
              final shown = _shown(items);
              final children = <Widget>[
                if (items.isNotEmpty) _filterBar(items, levels, shown, canSms),
                Expanded(child: _list(items, shown)),
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
              ];
              return Column(children: children);
            },
          ),
        ),
      ],
    );
  }

  /// مرشّح السنة، وعدّادا المعروض والمحدَّد، وأزرار التحديد والرسالة.
  Widget _filterBar(
    List<T> items,
    List<LevelRow> levels,
    List<T> shown,
    bool canSms,
  ) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    int countOf(bool Function(String? level) test) =>
        items.where((item) => test(widget.levelIdOf(item))).length;
    final options = <ClayOption<String>>[
      ClayOption(value: _allYears, label: 'كل السنوات (${items.length})'),
      for (final level in levels)
        if (countOf((l) => l == level.id) > 0 || _year == level.id)
          ClayOption(
            value: level.id,
            label: '${level.name} (${countOf((l) => l == level.id)})',
          ),
      if (countOf((l) => l == null) > 0 || _year == _noYear)
        ClayOption(
          value: _noYear,
          label: 'بلا سنة (${countOf((l) => l == null)})',
        ),
    ];
    final allShown =
        shown.isNotEmpty &&
        shown.every((item) => _selected.contains(widget.idOf(item)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ClaySpacing.screenPadding,
        0,
        ClaySpacing.screenPadding,
        ClaySpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClayDropdown<String>(
            label: 'السنة الدراسية',
            searchable: false,
            value: _year,
            options: options,
            onChanged: (value) => setState(() => _year = value ?? _allYears),
          ),
          const SizedBox(height: ClaySpacing.sm),
          Text(
            'المعروض ${shown.length} · المحدَّد ${_selected.length}',
            style: text.bodySmall!.copyWith(color: p.textMuted),
          ),
          if (canSms) ...[
            const SizedBox(height: ClaySpacing.sm),
            Wrap(
              spacing: ClaySpacing.sm,
              runSpacing: ClaySpacing.sm,
              children: [
                ClayButton(
                  label: allShown ? 'إلغاء تحديد الكل' : 'تحديد الكل',
                  kind: ClayButtonKind.secondary,
                  onPressed: shown.isEmpty ? null : () => _toggleAll(shown),
                ),
                ClayButton(
                  label: 'تحديد عدد',
                  kind: ClayButtonKind.secondary,
                  onPressed: shown.isEmpty ? null : () => _pickCount(shown),
                ),
                if (_selected.isNotEmpty)
                  ClayButton(
                    label: 'مسح التحديد',
                    kind: ClayButtonKind.secondary,
                    onPressed: () => setState(_selected.clear),
                  ),
                ClayButton(
                  label: _selected.isEmpty
                      ? 'رسالة SMS للمحدَّدين'
                      : 'رسالة SMS إلى المحدَّدين (${_selected.length})',
                  icon: ClayIcons.sms,
                  onPressed: _selected.isEmpty ? null : () => _compose(items),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _list(List<T> items, List<T> shown) {
    if (shown.isEmpty) {
      final searching = _query.isNotEmpty || _year != _allYears;
      return ClayEmptyView(
        title: searching ? 'لا نتائج' : widget.emptyTitle,
        message: searching ? null : widget.emptyMessage,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: ClaySpacing.screenPadding,
      ),
      itemCount: shown.length,
      itemExtent: widget.itemExtent,
      itemBuilder: (context, i) {
        final item = shown[i];
        final id = widget.idOf(item);
        return widget.itemBuilder(
          context,
          item,
          _selected.contains(id),
          () => _toggle(id),
        );
      },
    );
  }
}

/// مستلم رسالة: رقمه وأسماء أصحابه (إخوة بهاتف وليّ واحد يأخذون رسالة واحدة).
class SmsRecipient {
  SmsRecipient({required this.phone, required this.names});

  final String phone;
  final List<String> names;
}

/// عدد الأرقام التي تُحدَّد من أول القائمة المعروضة.
class SelectCountDialog extends StatefulWidget {
  const SelectCountDialog({required this.max, super.key});

  final int max;

  @override
  State<SelectCountDialog> createState() => _SelectCountDialogState();
}

class _SelectCountDialogState extends State<SelectCountDialog> {
  late final _count = TextEditingController(
    text: '${widget.max < 10 ? widget.max : 10}',
  );
  String? _error;

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_count.text.trim());
    if (value == null || value < 1 || value > widget.max) {
      setState(() => _error = 'اكتب عدداً من 1 إلى ${widget.max}');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => ClayDialog(
    title: 'تحديد عدد من القائمة',
    content: ClayTextField(
      controller: _count,
      label: 'عدد الأرقام (من أول القائمة المعروضة)',
      helper: 'المعروض ${widget.max}',
      keyboardType: TextInputType.number,
      textDirection: TextDirection.ltr,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      autofocus: true,
      error: _error,
    ),
    actions: [
      ClayButton(label: 'تحديد', onPressed: _submit),
      ClayButton(
        label: 'إلغاء',
        kind: ClayButtonKind.secondary,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );
}

/// نص الرسالة إلى المحدَّدين: يُضاف لكل رقم صالح رسالة منفصلة إلى طابور الرسائل (تُرسل من هاتف الإرسال
/// المعيَّن وبساعات الهدوء المعتادة). `{name}` يُستبدل باسم صاحب الرقم و`{school}` باسم المدرسة.
class BulkSmsDialog extends ConsumerStatefulWidget {
  const BulkSmsDialog({
    required this.recipients,
    required this.invalid,
    super.key,
  });

  final List<SmsRecipient> recipients;
  final int invalid;

  @override
  ConsumerState<BulkSmsDialog> createState() => _BulkSmsDialogState();
}

class _BulkSmsDialogState extends ConsumerState<BulkSmsDialog> {
  final _message = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  String _render(String body, SmsRecipient recipient, String school) =>
      SmsTemplateRenderer.fill(body, {
        'school': school.isEmpty ? 'المدرسة' : school,
        'name': recipient.names.join(' و '),
      });

  Future<void> _send() async {
    final body = _message.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'اكتب نص الرسالة');
      return;
    }
    if (widget.recipients.isEmpty) {
      setState(() => _error = 'لا رقم صالح بين المحدَّدين');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final queue = ref.read(smsQueueServiceProvider);
    final school = ref.read(schoolNameProvider).value ?? '';
    var queued = 0;
    for (final recipient in widget.recipients) {
      try {
        await queue.enqueue(
          phone: recipient.phone,
          message: _render(body, recipient, school),
          kind: SmsTemplateKeys.broadcast,
        );
        queued++;
      } on Object {
        // رقم أو نص مرفوض: يُتجاهل وتُعدّ الرسائل التي أُضيفت فقط.
      }
    }
    if (mounted) Navigator.of(context).pop(queued);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final school = ref.watch(schoolNameProvider).value ?? '';
    final first = widget.recipients.isEmpty ? null : widget.recipients.first;
    final preview = first == null || _message.text.trim().isEmpty
        ? null
        : _render(_message.text.trim(), first, school);
    return ClayDialog(
      title: 'رسالة SMS إلى ${widget.recipients.length} رقماً',
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.invalid > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: ClaySpacing.sm),
                child: Text(
                  'يُتجاهل ${widget.invalid} رقم غير صالح للرسائل (جوال جزائري: 05 أو 06 أو 07 ثم 8 أرقام).',
                  style: text.bodySmall!.copyWith(color: p.status.warning),
                ),
              ),
            ClayTextField(
              controller: _message,
              label: 'نص الرسالة',
              helper: 'اكتب {name} ليُستبدل باسم صاحب الرقم، و{school} باسم المدرسة',
              maxLines: 5,
              autofocus: true,
              error: _error,
              onChanged: (_) => setState(() {}),
            ),
            if (preview != null) ...[
              const SizedBox(height: ClaySpacing.md),
              Text('معاينة:', style: text.labelLarge),
              Text(preview, style: text.bodyMedium),
            ],
          ],
        ),
      ),
      actions: [
        ClayButton(
          label: 'إضافة إلى طابور الرسائل',
          icon: ClayIcons.sms,
          loading: _saving,
          onPressed: _send,
        ),
        ClayButton(
          label: 'إلغاء',
          kind: ClayButtonKind.secondary,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// إضافة رقم أو تعديله: الاسم (اختياري)، الرقم، السنة الدراسية (اختيارية)، الملاحظة، وتاريخ التواصل (اختياري).
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
  late String? _levelId = widget.initial?.levelId;
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
          levelId: _levelId,
        );
      } else {
        await service.update(
          initial.id,
          name: _name.text,
          phone: _phone.text,
          note: _note.text,
          followUpDate: _followUp,
          levelId: _levelId,
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
    final levels = ref.watch(levelsProvider).value ?? const <LevelRow>[];
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
            ClayDropdown<String?>(
              label: 'السنة الدراسية (اختياري)',
              searchable: false,
              value: _levelId,
              options: [
                const ClayOption(value: null, label: 'بلا سنة'),
                for (final l in levels) ClayOption(value: l.id, label: l.name),
              ],
              onChanged: (value) => setState(() => _levelId = value),
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
