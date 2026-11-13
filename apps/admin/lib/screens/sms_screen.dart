import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_sms/school_sms.dart';
import 'package:school_ui/school_ui.dart';

final Provider<SmsQueueService> smsQueueServiceProvider =
    Provider<SmsQueueService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return SmsQueueService(runtime.db, runtime.writer);
    });

final Provider<SmsTemplateService> smsTemplateServiceProvider =
    Provider<SmsTemplateService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return SmsTemplateService(runtime.db, runtime.writer);
    });

final Provider<SmsBroadcastService> smsBroadcastServiceProvider =
    Provider<SmsBroadcastService>((ref) {
      final runtime = ref.watch(runtimeProvider);
      return SmsBroadcastService(
        runtime.db,
        ref.watch(smsQueueServiceProvider),
        ref.watch(smsTemplateServiceProvider),
      );
    });

final smsQueueRowsProvider = StreamProvider.autoDispose
    .family<List<SmsQueueRow>, int>(
      (ref, limit) =>
          ref.watch(smsQueueServiceProvider).watchQueue(limit: limit),
    );

final smsQueueCountsProvider = StreamProvider.autoDispose<Map<String, int>>(
  (ref) => ref.watch(smsQueueServiceProvider).watchStatusCounts(),
);

final smsTemplateViewsProvider =
    FutureProvider.autoDispose<List<SmsTemplateView>>(
      (ref) => ref.watch(smsTemplateServiceProvider).load(),
    );

/// مركز رسائل الإدارة: الطابور، الإرسال الجماعي، والقوالب.
class SmsCenterScreen extends ConsumerWidget {
  const SmsCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = <({String title, Widget page})>[];
    if (ref.can(PermissionModule.sms, PermissionAction.view)) {
      tabs.add((title: 'الطابور', page: const _SmsQueueTab()));
    }
    if (ref.can(PermissionModule.sms, PermissionAction.add)) {
      tabs.add((title: 'رسالة جماعية', page: const _SmsBroadcastTab()));
    }
    if (ref.can(PermissionModule.sms, PermissionAction.edit)) {
      tabs.add((title: 'القوالب', page: const _SmsTemplatesTab()));
    }
    if (tabs.isEmpty) {
      return const ClayEmptyView(
        title: 'لا توجد صلاحية للرسائل',
        message: 'اطلب من الإدارة تفعيل صلاحية مناسبة لحسابك',
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: const ClayAppBar(title: 'مركز الرسائل القصيرة', showBack: true),
        body: Column(
          children: [
            TabBar(tabs: [for (final tab in tabs) Tab(text: tab.title)]),
            Expanded(
              child: TabBarView(children: [for (final tab in tabs) tab.page]),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmsQueueTab extends ConsumerStatefulWidget {
  const _SmsQueueTab();

  @override
  ConsumerState<_SmsQueueTab> createState() => _SmsQueueTabState();
}

class _SmsQueueTabState extends ConsumerState<_SmsQueueTab> {
  int _limit = 100;
  bool _sending = false;
  SmsDispatchWorker? _worker;

  Future<void> _retry(SmsQueueRow row) async {
    final changed = await ref.read(smsQueueServiceProvider).retry(row.id);
    if (mounted) {
      _notify(
        context,
        changed ? 'أُعيدت الرسالة إلى الطابور' : 'تعذّرت إعادة المحاولة',
      );
    }
  }

  Future<void> _startSending() async {
    if (!Platform.isAndroid) {
      _notify(context, 'إرسال الرسائل يحتاج هاتف Android مع شريحة SIM');
      return;
    }
    final runtime = ref.read(runtimeProvider);
    final worker = SmsDispatchWorker(
      queue: ref.read(smsQueueServiceProvider),
      settings: SmsSettingsService(runtime.db, runtime.writer),
      platform: AndroidSmsPlatform(),
    );
    setState(() {
      _worker = worker;
      _sending = true;
    });
    try {
      final result = await worker.start();
      if (!mounted) return;
      final parts = <String>[
        'أُرسلت ${result.sent}',
        'فشلت ${result.failed}',
        'مؤجلة ${result.retried}',
      ];
      if (result.deferredUntil != null) {
        parts.add('يُستأنف الإرسال ${_displayTime(result.deferredUntil!)}');
      }
      _notify(context, parts.join(' · '));
    } on Object catch (error) {
      if (mounted) _notify(context, 'تعذّر تشغيل الإرسال: $error');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _worker = null;
        });
      }
    }
  }

  Future<void> _stopSending() async {
    await _worker?.stop();
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(smsQueueRowsProvider(_limit));
    final counts = ref.watch(smsQueueCountsProvider).value ?? const {};
    final canSend = ref.can(PermissionModule.sms, PermissionAction.use);
    final canRetry = ref.can(PermissionModule.sms, PermissionAction.edit);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(ClaySpacing.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: ClaySpacing.sm,
                runSpacing: ClaySpacing.sm,
                children: [
                  for (final status in SmsStatus.values)
                    ClayBadge(
                      label: '${status.label}: ${counts[status.code] ?? 0}',
                      tone: _tone(status),
                    ),
                ],
              ),
              const SizedBox(height: ClaySpacing.md),
              if (canSend)
                ClayButton(
                  label: _sending
                      ? 'إيقاف الإرسال بعد الرسالة الحالية'
                      : 'بدء إرسال الطابور',
                  icon: _sending ? Icons.stop_rounded : ClayIcons.sms,
                  kind: _sending
                      ? ClayButtonKind.secondary
                      : ClayButtonKind.primary,
                  loading: false,
                  onPressed: _sending ? _stopSending : _startSending,
                  expand: true,
                )
              else if (!Platform.isAndroid)
                Text(
                  'إرسال الرسائل متاح على هاتف Android مع شريحة SIM.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        Expanded(
          child: rows.when(
            loading: () => const ClaySkeletonList(),
            error: (_, _) => ClayErrorView(
              message: 'تعذّر تحميل طابور الرسائل',
              onRetry: () => ref.invalidate(smsQueueRowsProvider),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const ClayEmptyView(
                  title: 'الطابور فارغ',
                  message: 'ستظهر هنا الرسائل الآلية والجماعية عند تجهيزها',
                );
              }
              final canLoadMore = items.length == _limit;
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  ClaySpacing.screenPadding,
                  0,
                  ClaySpacing.screenPadding,
                  ClaySpacing.screenPadding,
                ),
                itemCount: items.length + (canLoadMore ? 1 : 0),
                itemExtentBuilder: (index, _) =>
                    index == items.length ? 60 : 174,
                itemBuilder: (context, index) {
                  if (index == items.length) {
                    return Center(
                      child: TextButton(
                        onPressed: () => setState(() => _limit += 100),
                        child: const Text('تحميل رسائل أقدم'),
                      ),
                    );
                  }
                  return _SmsQueueTile(
                    row: items[index],
                    canRetry: canRetry,
                    onRetry: () => _retry(items[index]),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SmsQueueTile extends StatelessWidget {
  const _SmsQueueTile({
    required this.row,
    required this.canRetry,
    required this.onRetry,
  });

  final SmsQueueRow row;
  final bool canRetry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final status = SmsStatus.values.firstWhere(
      (value) => value.code == row.status,
      orElse: () => SmsStatus.failed,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: ClaySpacing.sm),
      child: ClayCard(
        flat: true,
        child: Padding(
          padding: const EdgeInsets.all(ClaySpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.phone,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  ClayBadge(label: status.label, tone: _tone(status)),
                ],
              ),
              const SizedBox(height: ClaySpacing.xs),
              Text(
                row.message.isEmpty
                    ? 'محتوى حساس أُخفي بعد نجاح الإرسال'
                    : row.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (row.lastError != null)
                Text(
                  row.lastError!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall!
                      .copyWith(color: context.palette.status.danger),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'أُضيفت ${_displayTime(DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true).toLocal())}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  if (status == SmsStatus.failed && canRetry)
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة المحاولة'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmsBroadcastTab extends ConsumerStatefulWidget {
  const _SmsBroadcastTab();

  @override
  ConsumerState<_SmsBroadcastTab> createState() => _SmsBroadcastTabState();
}

class _SmsBroadcastTabState extends ConsumerState<_SmsBroadcastTab> {
  SmsBroadcastAudience _audience = SmsBroadcastAudience.parents;
  late Future<SmsBroadcastPreview> _preview;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _preview = ref.read(smsBroadcastServiceProvider).preview(_audience);
  }

  void _changeAudience(SmsBroadcastAudience? value) {
    if (value == null) return;
    setState(() {
      _audience = value;
      _preview = ref.read(smsBroadcastServiceProvider).preview(value);
    });
  }

  Future<void> _enqueue(SmsBroadcastPreview preview) async {
    if (preview.recipients.isEmpty) {
      _notify(context, 'لا توجد أرقام صالحة لهذا الجمهور');
      return;
    }
    final sample = ref
        .read(smsTemplateServiceProvider)
        .get(SmsTemplateKeys.broadcast);
    final view = await sample;
    if (!mounted) return;
    final school = ref.read(schoolNameProvider).value ?? '';
    final message = SmsTemplateRenderer.fill(view.body, {
      'school': school.isEmpty ? 'المدرسة' : school,
      'name': preview.recipients.first.name,
    });
    final confirmed = await showClayConfirm(
      context,
      title: 'تجهيز رسالة جماعية',
      message:
          'ستُضاف رسالة إلى طابور الإرسال لكل واحد من ${preview.recipients.length} '
          '${preview.audience.label}.\n\nمعاينة:\n$message',
      confirmLabel: 'إضافة إلى الطابور',
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(smsBroadcastServiceProvider)
          .enqueue(audience: _audience, schoolName: school);
      if (mounted) {
        _notify(
          context,
          'أُضيفت ${result.queued} رسالة، تعذّر ${result.failed}، '
          'وتُجاهل ${result.invalidContacts} رقم غير صالح',
        );
      }
    } on Object catch (error) {
      if (mounted) _notify(context, 'تعذّر تجهيز الرسائل: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(smsTemplateViewsProvider);
    final school = ref.watch(schoolNameProvider).value ?? 'المدرسة';
    final canAdd = ref.can(PermissionModule.sms, PermissionAction.add);

    return FutureBuilder<SmsBroadcastPreview>(
      future: _preview,
      builder: (context, snapshot) {
        final preview = snapshot.data;
        final broadcast = templates.value
            ?.where(
              (template) =>
                  template.definition.key == SmsTemplateKeys.broadcast,
            )
            .firstOrNull;
        final sample = broadcast == null
            ? ''
            : SmsTemplateRenderer.fill(broadcast.body, {
                'school': school.isEmpty ? 'المدرسة' : school,
                'name': 'أسماء التلاميذ',
              });
        return ListView(
          padding: const EdgeInsets.all(ClaySpacing.screenPadding),
          children: [
            ClayCard(
              child: Padding(
                padding: const EdgeInsets.all(ClaySpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'اختر المستهدفين',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: ClaySpacing.md),
                    ClayDropdown<SmsBroadcastAudience>(
                      label: 'الجمهور',
                      value: _audience,
                      options: [
                        for (final audience in SmsBroadcastAudience.values)
                          ClayOption(value: audience, label: audience.label),
                      ],
                      onChanged: _changeAudience,
                    ),
                    const SizedBox(height: ClaySpacing.md),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const LinearProgressIndicator(),
                    if (preview != null) ...[
                      Text(
                        '${preview.recipients.length} مستلم برقم صالح · '
                        '${preview.invalidContacts} رقم غير صالح سيُتجاهل',
                      ),
                      if (_audience == SmsBroadcastAudience.parents)
                        const Text(
                          'تُرسل رسالة واحدة لكل هاتف وليّ، مع جمع أسماء أبنائه.',
                        ),
                    ],
                    const SizedBox(height: ClaySpacing.lg),
                    Text(
                      'معاينة قالب الرسالة',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: ClaySpacing.sm),
                    if (templates.isLoading)
                      const LinearProgressIndicator()
                    else if (templates.hasError)
                      const Text('تعذّر تحميل قالب الرسالة الجماعية')
                    else
                      Text(sample),
                    const SizedBox(height: ClaySpacing.lg),
                    ClayButton(
                      label: 'إضافة الرسائل إلى الطابور',
                      icon: ClayIcons.sms,
                      loading: _saving,
                      expand: true,
                      onPressed: canAdd && preview != null && !_saving
                          ? () => _enqueue(preview)
                          : null,
                    ),
                    const SizedBox(height: ClaySpacing.sm),
                    Text(
                      'تُجهّز الرسائل هنا فقط؛ يبدأ الإرسال من تبويب الطابور على هاتف Android.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SmsTemplatesTab extends ConsumerStatefulWidget {
  const _SmsTemplatesTab();

  @override
  ConsumerState<_SmsTemplatesTab> createState() => _SmsTemplatesTabState();
}

class _SmsTemplatesTabState extends ConsumerState<_SmsTemplatesTab> {
  final _body = TextEditingController();
  String _selected = SmsTemplateKeys.broadcast;
  String? _loadedKey;
  String _draft = '';
  bool _saving = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  void _select(String key, List<SmsTemplateView> templates) {
    final view = templates.firstWhere((item) => item.definition.key == key);
    setState(() {
      _selected = key;
      _loadedKey = key;
      _draft = view.body;
      _body.text = view.body;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(smsTemplateServiceProvider).save(_selected, _draft);
      ref.invalidate(smsTemplateViewsProvider);
      if (mounted) _notify(context, 'تم حفظ القالب ومزامنته');
    } on Object catch (error) {
      if (mounted) _notify(context, 'تعذّر حفظ القالب: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset(List<SmsTemplateView> templates) async {
    final view = templates.firstWhere(
      (item) => item.definition.key == _selected,
    );
    final confirmed = await showClayConfirm(
      context,
      title: 'استعادة القالب الافتراضي',
      message:
          'سيُستبدل النص الحالي بالنص الافتراضي لـ «${view.definition.title}».',
      confirmLabel: 'استعادة',
    );
    if (!confirmed) return;
    setState(() => _saving = true);
    try {
      await ref.read(smsTemplateServiceProvider).reset(_selected);
      final updated = await ref.read(smsTemplateServiceProvider).get(_selected);
      if (!mounted) return;
      setState(() {
        _loadedKey = _selected;
        _draft = updated.body;
        _body.text = updated.body;
      });
      ref.invalidate(smsTemplateViewsProvider);
      _notify(context, 'استُعيد القالب الافتراضي');
    } on Object catch (error) {
      if (mounted) _notify(context, 'تعذّرت استعادة القالب: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _insertVariable(String variable) {
    final value = _body.value;
    final start = value.selection.isValid
        ? value.selection.start
        : value.text.length;
    final end = value.selection.isValid
        ? value.selection.end
        : value.text.length;
    final token = '{$variable}';
    final text = value.text.replaceRange(start, end, token);
    _body.value = value.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    setState(() => _draft = text);
  }

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(smsTemplateViewsProvider);
    final canEdit = ref.can(PermissionModule.sms, PermissionAction.edit);
    return templates.when(
      loading: () => const ClaySkeletonList(),
      error: (_, _) => ClayErrorView(
        message: 'تعذّر تحميل قوالب الرسائل',
        onRetry: () => ref.invalidate(smsTemplateViewsProvider),
      ),
      data: (items) {
        final selected = items.firstWhere(
          (item) => item.definition.key == _selected,
          orElse: () => items.first,
        );
        if (_loadedKey != selected.definition.key) {
          _loadedKey = selected.definition.key;
          _draft = selected.body;
          _body.text = selected.body;
        }
        final values = {
          for (final variable in selected.definition.variables)
            variable: _sampleVariable(variable),
        };
        final rendered = SmsTemplateRenderer.fill(_draft, values);
        return ListView(
          padding: const EdgeInsets.all(ClaySpacing.screenPadding),
          children: [
            ClayCard(
              child: Padding(
                padding: const EdgeInsets.all(ClaySpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClayDropdown<String>(
                      label: 'القالب',
                      value: selected.definition.key,
                      options: [
                        for (final template in items)
                          ClayOption(
                            value: template.definition.key,
                            label: template.definition.title,
                          ),
                      ],
                      onChanged: canEdit
                          ? (key) {
                              if (key != null) _select(key, items);
                            }
                          : null,
                    ),
                    const SizedBox(height: ClaySpacing.md),
                    TextField(
                      controller: _body,
                      onChanged: (value) => setState(() => _draft = value),
                      readOnly: !canEdit,
                      minLines: 3,
                      maxLines: 7,
                      maxLength: 900,
                      decoration: const InputDecoration(
                        labelText: 'نص الرسالة',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    Text(
                      'المتغيرات المتاحة',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: ClaySpacing.xs),
                    Wrap(
                      spacing: ClaySpacing.xs,
                      runSpacing: ClaySpacing.xs,
                      children: [
                        for (final variable in selected.definition.variables)
                          ActionChip(
                            label: Text('{$variable}'),
                            onPressed: canEdit
                                ? () => _insertVariable(variable)
                                : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: ClaySpacing.lg),
                    Text(
                      'المعاينة',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: ClaySpacing.xs),
                    Text(rendered),
                    const SizedBox(height: ClaySpacing.lg),
                    Wrap(
                      spacing: ClaySpacing.sm,
                      runSpacing: ClaySpacing.sm,
                      children: [
                        ClayButton(
                          label: 'حفظ القالب',
                          icon: Icons.save_rounded,
                          loading: _saving,
                          onPressed: canEdit && !_saving ? _save : null,
                        ),
                        ClayButton(
                          label: 'استعادة الافتراضي',
                          kind: ClayButtonKind.secondary,
                          icon: Icons.restart_alt_rounded,
                          onPressed: canEdit && !_saving
                              ? () => _reset(items)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

String _sampleVariable(String key) => switch (key) {
  'school' => 'مدرسة النجاح',
  'name' => 'سمير بن علي',
  'email' => 'student@school.local',
  'password' => '••••••••',
  'subject' => 'الرياضيات',
  'group' => 'المجموعة 1',
  'schedule' || 'summary' => 'الأحد 09:00',
  'date' => '15/11/2026',
  'time' => '09:00',
  'room' => '1',
  'receipt' => 'AAA-000001',
  'amount' => '2000',
  'item' => 'الدورة 1',
  'cycle' => '1',
  'count' => '5',
  'request' => 'تغيير موعد الحصة',
  'note' => 'يرجى التواصل مع الإدارة',
  _ => key,
};

ClayTone _tone(SmsStatus status) => switch (status) {
  SmsStatus.pending => ClayTone.info,
  SmsStatus.sending => ClayTone.warning,
  SmsStatus.sent => ClayTone.success,
  SmsStatus.failed => ClayTone.danger,
  SmsStatus.cancelled => ClayTone.neutral,
};

String _displayTime(DateTime time) =>
    '${time.day}/${time.month} ${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

void _notify(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
  );
}
