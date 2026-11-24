import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'contacts_screen.dart'
    show BulkSmsDialog, SelectCountDialog, SmsRecipient;

/// كل التلاميذ أو الأساتذة أو العمال للتحديد الجماعي، ويتحدثون لحظياً.
final bulkPeopleProvider = StreamProvider.autoDispose
    .family<List<BulkPerson>, PersonKind>(
      (ref, kind) => PeopleDirectory(ref.watch(runtimeProvider).db).watch(kind),
    );

/// مفاتيح مرشّح السنة: كل السنوات، ومن بلا سنة؛ وغيرهما معرّف السنة.
const String _allYears = 'all';
const String _noYear = 'none';

/// تحديد مجموعة من التلاميذ أو الأساتذة أو العمال (الكل، أو عدد من أول القائمة، أو واحداً واحداً)، ثم:
/// طباعة بطاقاتهم معاً في ورقة A4 (10 بطاقات في الورقة)، أو إرسال بيانات دخولهم برسالة SMS لكل واحد
/// (بكلمة سر جديدة)، أو رسالة مكتوبة واحدة لهم جميعاً.
class BulkPeopleScreen extends ConsumerStatefulWidget {
  const BulkPeopleScreen({required this.kind, super.key});

  final PersonKind kind;

  @override
  ConsumerState<BulkPeopleScreen> createState() => _BulkPeopleScreenState();
}

class _BulkPeopleScreenState extends ConsumerState<BulkPeopleScreen> {
  String _query = '';
  String _year = _allYears;
  final Set<String> _selected = {};
  bool _busy = false;

  PersonKind get _kind => widget.kind;

  PermissionModule get _module => switch (_kind) {
    PersonKind.student => PermissionModule.students,
    PersonKind.teacher => PermissionModule.teachers,
    PersonKind.worker => PermissionModule.workers,
  };

  List<BulkPerson> _shown(List<BulkPerson> items) => [
    for (final item in items)
      if (_matchesYear(item) &&
          (_query.isEmpty ||
              item.name.contains(_query) ||
              item.phone.contains(_query) ||
              (item.subtitle?.contains(_query) ?? false)))
        item,
  ];

  bool _matchesYear(BulkPerson item) => switch (_year) {
    _allYears => true,
    _noYear => item.levelId == null,
    _ => item.levelId == _year,
  };

  List<BulkPerson> _chosen(List<BulkPerson> all) => [
    for (final item in all)
      if (_selected.contains(item.id)) item,
  ];

  void _toggle(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  void _toggleAll(List<BulkPerson> shown) => setState(() {
    final ids = [for (final item in shown) item.id];
    if (ids.every(_selected.contains)) {
      _selected.removeAll(ids);
    } else {
      _selected.addAll(ids);
    }
  });

  Future<void> _pickCount(List<BulkPerson> shown) async {
    final count = await showDialog<int>(
      context: context,
      builder: (_) => SelectCountDialog(max: shown.length),
    );
    if (count == null || !mounted) return;
    setState(() {
      _selected
        ..clear()
        ..addAll([for (final item in shown.take(count)) item.id]);
    });
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  /// بطاقات المحدَّدين في ورقة A4 واحدة (10 بطاقات في الورقة) للمعاينة والطباعة.
  Future<void> _printCards(List<BulkPerson> chosen) async {
    setState(() => _busy = true);
    try {
      final settings = await ref.read(settingsServiceProvider).load();
      // نسخة الويب بلا ملفات محلية: البطاقات دون الشعار والصور.
      final logoFile = kIsWeb
          ? null
          : await ref.read(logoServiceProvider).resolve();
      final logo = logoFile == null ? null : await logoFile.readAsBytes();
      final school = settings.schoolName.isEmpty
          ? 'المدرسة'
          : settings.schoolName;
      final cards = <PrintableCard>[];
      for (final person in chosen) {
        final path = person.photoLocalPath;
        final photo = kIsWeb || path == null || path.isEmpty
            ? null
            : File(path);
        cards.add(
          PrintableCard(
            schoolName: school,
            name: person.name,
            qrCode: person.qrCode,
            caption: _kind == PersonKind.student
                ? 'يُمسح الرمز عند الدخول'
                : 'يُمسح الرمز عند الدخول والخروج',
            subtitle: person.subtitle,
            phone: person.phone,
            logo: logo,
            photo: photo != null && photo.existsSync()
                ? await photo.readAsBytes()
                : null,
          ),
        );
      }
      final font = await rootBundle.load(
        'packages/school_ui/assets/fonts/Cairo.ttf',
      );
      final bytes = await CardSheet.build(
        cards,
        fontData: font.buffer.asUint8List(
          font.offsetInBytes,
          font.lengthInBytes,
        ),
        title: 'بطاقات ${_kind.plural}',
        author: school,
      );
      if (!mounted) return;
      await ref
          .read(pdfPresenterProvider)
          .show(
            context,
            bytes: bytes,
            fileName: 'cards-${_kind.name}-${cards.length}.pdf',
            title: 'بطاقات ${_kind.plural} (${cards.length})',
          );
    } on Object catch (e) {
      if (mounted) _snack('تعذّر تجهيز البطاقات: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// كلمة سر جديدة لكل حساب محدَّد، تُرسل لصاحبه برسالة SMS مع رقم دخوله. الإخوة يشتركون في حساب
  /// وليّهم فيأخذ رسالة واحدة.
  Future<void> _sendCredentials(List<BulkPerson> chosen) async {
    final accounts = <String, BulkPerson>{};
    var withoutAccount = 0;
    for (final person in chosen) {
      final id = person.accountId;
      if (id == null) {
        withoutAccount++;
      } else {
        accounts.putIfAbsent(id, () => person);
      }
    }
    if (accounts.isEmpty) {
      _snack('لا حساب دخول بين المحدَّدين', error: true);
      return;
    }
    final owner = _kind == PersonKind.student ? 'وليّ' : 'حساب';
    final ok = await showClayConfirm(
      context,
      title: 'إرسال بيانات الدخول',
      message:
          'ستُولَّد كلمة سر جديدة لـ ${accounts.length} $owner، وتُرسل لكل واحد '
          'رسالة SMS برقم دخوله وكلمة سره الجديدة. كلمات السر القديمة لن تعمل '
          'بعد الآن.'
          '${withoutAccount > 0 ? '\nيُتجاهل $withoutAccount بلا حساب دخول.' : ''}',
      confirmLabel: 'توليد وإرسال',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final service = ref.read(accountServiceProvider);
    final done = <(BulkPerson, ProvisionedAccount)>[];
    var failed = 0;
    for (final entry in accounts.entries) {
      try {
        done.add((entry.value, await service.resetPassword(entry.key)));
      } on Object {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.clear();
    });
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _CredentialsListDialog(kind: _kind, results: done, failed: failed),
    );
  }

  Future<void> _compose(List<BulkPerson> chosen) async {
    final recipients = <String, SmsRecipient>{};
    var invalid = 0;
    for (final person in chosen) {
      if (!PhoneNumbers.isValid(person.phone)) {
        invalid++;
        continue;
      }
      final key = PhoneNumbers.toInternational(person.phone);
      final existing = recipients[key];
      if (existing == null) {
        recipients[key] = SmsRecipient(
          phone: person.phone,
          names: [person.name],
        );
      } else if (!existing.names.contains(person.name)) {
        existing.names.add(person.name);
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
    _snack(
      'أُضيفت $sent رسالة إلى طابور الرسائل؛ تُرسل من هاتف الإرسال المعيَّن '
      '(مركز الرسائل ← الطابور)',
    );
    setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(bulkPeopleProvider(_kind));
    return Scaffold(
      appBar: ClayAppBar(title: 'تحديد ${_kind.plural}', showBack: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ClaySpacing.screenPadding,
              0,
              ClaySpacing.screenPadding,
              ClaySpacing.sm,
            ),
            child: ClayTextField(
              hint: 'ابحث بالاسم أو الهاتف',
              prefixIcon: ClayIcons.search,
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
          ),
          Expanded(
            child: data.when(
              loading: () => const ClaySkeletonList(),
              error: (_, _) => ClayErrorView(
                message: 'تعذّرت القراءة',
                onRetry: () => ref.invalidate(bulkPeopleProvider(_kind)),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return ClayEmptyView(title: 'لا يوجد ${_kind.plural} بعد');
                }
                final shown = _shown(items);
                return Column(
                  children: [
                    _controls(items, shown),
                    Expanded(child: _list(shown)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// مرشّح السنة (للتلاميذ)، والعدّادان، وأزرار التحديد، والأفعال على المحدَّدين.
  Widget _controls(List<BulkPerson> items, List<BulkPerson> shown) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final levels = ref.watch(levelsProvider).value ?? const <LevelRow>[];
    final canSms = ref.can(PermissionModule.sms, PermissionAction.add);
    final canReset = ref.can(_module, PermissionAction.edit);
    final allShown =
        shown.isNotEmpty && shown.every((item) => _selected.contains(item.id));
    final chosen = _chosen(items);
    final count = chosen.length;
    int countOf(bool Function(String? level) test) =>
        items.where((item) => test(item.levelId)).length;
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
          if (_kind == PersonKind.student) ...[
            ClayDropdown<String>(
              label: 'السنة الدراسية',
              searchable: false,
              value: _year,
              options: [
                ClayOption(
                  value: _allYears,
                  label: 'كل السنوات (${items.length})',
                ),
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
              ],
              onChanged: (value) => setState(() => _year = value ?? _allYears),
            ),
            const SizedBox(height: ClaySpacing.sm),
          ],
          Text(
            'المعروض ${shown.length} · المحدَّد $count',
            style: text.bodySmall!.copyWith(color: p.textMuted),
          ),
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
            ],
          ),
          const SizedBox(height: ClaySpacing.sm),
          Wrap(
            spacing: ClaySpacing.sm,
            runSpacing: ClaySpacing.sm,
            children: [
              ClayButton(
                label: 'طباعة البطاقات ($count)',
                icon: ClayIcons.print,
                loading: _busy,
                onPressed: count == 0 || _busy
                    ? null
                    : () => _printCards(chosen),
              ),
              if (canReset)
                ClayButton(
                  label: 'إرسال بيانات الدخول ($count)',
                  icon: Icons.key_rounded,
                  kind: ClayButtonKind.secondary,
                  onPressed: count == 0 || _busy
                      ? null
                      : () => _sendCredentials(chosen),
                ),
              if (canSms)
                ClayButton(
                  label: 'رسالة مكتوبة ($count)',
                  icon: ClayIcons.sms,
                  kind: ClayButtonKind.secondary,
                  onPressed: count == 0 || _busy
                      ? null
                      : () => _compose(chosen),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _list(List<BulkPerson> shown) {
    if (shown.isEmpty) return const ClayEmptyView(title: 'لا نتائج');
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: ClaySpacing.screenPadding,
      ),
      itemCount: shown.length,
      itemExtent: 76,
      itemBuilder: (context, i) {
        final person = shown[i];
        final selected = _selected.contains(person.id);
        return ClayListTile(
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClayCheckbox(
                value: selected,
                semanticLabel: person.name,
                onChanged: (_) => _toggle(person.id),
              ),
              const SizedBox(width: ClaySpacing.sm),
              ClayAvatar(
                name: person.name,
                image: localPhoto(person.photoLocalPath),
              ),
            ],
          ),
          title: person.name,
          subtitle: [?person.subtitle, person.phone].join(' · '),
          onTap: () => _toggle(person.id),
        );
      },
    );
  }
}

/// بيانات الدخول الجديدة لكل من أُعيدت كلمة سره: تظهر هنا مرة واحدة فقط، ووُضعت لكل واحد رسالة
/// في طابور الرسائل. زر نسخ الكل ينسخها نصاً لحفظها أو طباعتها.
class _CredentialsListDialog extends StatelessWidget {
  const _CredentialsListDialog({
    required this.kind,
    required this.results,
    required this.failed,
  });

  final PersonKind kind;
  final List<(BulkPerson, ProvisionedAccount)> results;
  final int failed;

  String _owner(BulkPerson person) =>
      kind == PersonKind.student ? 'وليّ ${person.name}' : person.name;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final queued = results.where((r) => r.$2.smsQueued).length;
    final all = [
      for (final (person, account) in results)
        '${_owner(person)}: ${LoginCredentials.displayLogin(account.email)}'
            ' / ${account.password}',
    ].join('\n');
    return ClayDialog(
      title: 'بيانات الدخول الجديدة (${results.length})',
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'وُضعت $queued رسالة في طابور الإرسال'
              '${failed > 0 ? '، وتعذّر $failed حساب (أعد المحاولة لاحقاً)' : ''}. '
              'احفظ كلمات السر الآن فلن تظهر ثانية.',
              style: text.bodySmall!.copyWith(color: p.textMuted),
            ),
            const SizedBox(height: ClaySpacing.sm),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (person, account) in results)
                      Padding(
                        padding: const EdgeInsets.only(bottom: ClaySpacing.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_owner(person), style: text.titleSmall),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: SelectableText(
                                '${LoginCredentials.displayLogin(account.email)}'
                                '   ${account.password}',
                                style: text.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        ClayButton(
          label: 'نسخ الكل',
          icon: Icons.copy_rounded,
          kind: ClayButtonKind.secondary,
          onPressed: () => Clipboard.setData(ClipboardData(text: all)),
        ),
        Builder(
          builder: (context) => ClayButton(
            label: 'تم',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}
