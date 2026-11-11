import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// يعرض بيانات دخول حساب أُنشئ أو أُعيد توليده. كلمة السر تظهر هنا مرة
/// واحدة فقط، وتُرسل لصاحبها برسالة قصيرة.
Future<void> showCredentialsDialog(
  BuildContext context, {
  required ProvisionedAccount account,
  required String ownerName,
  required String phone,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CredentialsDialog(
      account: account,
      ownerName: ownerName,
      phone: phone,
    ),
  );
}

class _CredentialsDialog extends StatelessWidget {
  const _CredentialsDialog({
    required this.account,
    required this.ownerName,
    required this.phone,
  });

  final ProvisionedAccount account;
  final String ownerName;
  final String phone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: ClaySpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.bodySmall),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(value, style: text.titleMedium),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'نسخ $label',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
          ),
        ],
      ),
    );

    return ClayDialog(
      title: 'بيانات دخول $ownerName',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row('البريد', account.email),
          if (account.password.isNotEmpty) row('كلمة السر', account.password),
          Text(
            account.smsQueued
                ? 'وُضعت رسالة بهذه البيانات في طابور الإرسال إلى $phone. '
                      'احفظ كلمة السر الآن فلن تظهر ثانية.'
                : 'الحساب موجود من قبل ولم تُنشأ كلمة سر جديدة.',
            style: text.bodySmall!.copyWith(color: p.textMuted),
          ),
        ],
      ),
      actions: [
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

/// قائمة الأساتذة.
class TeachersScreen extends ConsumerWidget {
  const TeachersScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<TeacherCreated>(
      context: context,
      builder: (_) => const TeacherFormDialog(),
    );
    if (created == null || !context.mounted) return;
    await showCredentialsDialog(
      context,
      account: created.account,
      ownerName: created.teacher.name,
      phone: created.teacher.phone,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canAdd = ref.can(PermissionModule.teachers, PermissionAction.add);
    return ClayListPage<TeacherItem>(
      title: 'الأساتذة',
      data: ref.watch(teachersProvider),
      emptyTitle: 'لا يوجد أساتذة بعد',
      emptyMessage: 'أضف الأساتذة لتُنشأ حساباتهم ورموزهم وتصلهم بياناتهم',
      searchHint: 'ابحث بالاسم أو الهاتف أو المادة',
      matches: (item, query) =>
          item.name.contains(query) ||
          item.teacher.phone.contains(query) ||
          item.subjectNames.any((s) => s.contains(query)),
      onRetry: () => ref.invalidate(teachersProvider),
      addLabel: 'إضافة أستاذ',
      onAdd: canAdd ? () => _add(context, ref) : null,
      itemExtent: 76,
      itemBuilder: (context, item) => ClayListTile(
        leading: ClayAvatar(name: item.name),
        title: item.name,
        subtitle: item.subjectNames.isEmpty
            ? item.teacher.phone
            : '${item.subjectNames.join('، ')} · ${item.teacher.phone}',
        onTap: () => context.push('/teachers/${item.id}'),
        trailing: const [Icon(Icons.chevron_left_rounded)],
      ),
    );
  }
}

/// نموذج إضافة أستاذ أو تعديله. عند الحفظ يُغلق ويعيد [TeacherCreated] في
/// الإضافة (ليُعرض حسابه)، ولا شيء في التعديل.
class TeacherFormDialog extends ConsumerStatefulWidget {
  const TeacherFormDialog({this.initial, this.initialSubjectIds, super.key});

  final TeacherRow? initial;
  final Set<String>? initialSubjectIds;

  @override
  ConsumerState<TeacherFormDialog> createState() => _TeacherFormDialogState();
}

class _TeacherFormDialogState extends ConsumerState<TeacherFormDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _phone = TextEditingController(text: widget.initial?.phone ?? '');
  late final _rate = TextEditingController(
    text: '${widget.initial?.ratePerStudent ?? 0}',
  );
  late final Set<String> _subjects = {...?widget.initialSubjectIds};
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final rate = int.tryParse(_rate.text.trim());
    if (rate == null) {
      setState(() => _errors = {TeacherService.fieldRate: 'أدخل المبلغ'});
      return;
    }
    setState(() {
      _saving = true;
      _errors = const {};
    });
    final service = ref.read(teacherServiceProvider);
    try {
      final initial = widget.initial;
      if (initial == null) {
        final created = await service.add(
          name: _name.text,
          phone: _phone.text,
          subjectIds: _subjects,
          ratePerStudent: rate,
        );
        if (mounted) Navigator.of(context).pop(created);
      } else {
        await service.update(
          initial.id,
          name: _name.text,
          phone: _phone.text,
          subjectIds: _subjects,
          ratePerStudent: rate,
        );
        if (mounted) Navigator.of(context).pop();
      }
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } on AuthFailureException catch (e) {
      if (mounted) setState(() => _errors = {'form': e.message});
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = ref.watch(subjectsProvider).value ?? const <SubjectItem>[];
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return ClayDialog(
      title: widget.initial == null ? 'إضافة أستاذ' : 'تعديل الأستاذ',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClayTextField(
            controller: _name,
            label: 'الاسم الكامل',
            autofocus: true,
            error: _errors[TeacherService.fieldName],
          ),
          const SizedBox(height: ClaySpacing.md),
          ClayTextField(
            controller: _phone,
            label: 'الهاتف',
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            helper: widget.initial == null
                ? 'يُبنى منه بريد الدخول وتصله عليه كلمة السر'
                : 'بريد الدخول لا يتغير بتغيير الهاتف',
            error: _errors[TeacherService.fieldPhone],
          ),
          const SizedBox(height: ClaySpacing.md),
          ClayTextField(
            controller: _rate,
            label: 'نصيبه لكل تلميذ في الدورة (${Money.currency})',
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            helper: 'قيمة افتراضية تُغيَّر لكل مجموعة',
            error: _errors[TeacherService.fieldRate],
          ),
          const SizedBox(height: ClaySpacing.md),
          Text('المواد التي يدرّسها', style: text.labelMedium),
          const SizedBox(height: ClaySpacing.xs),
          if (subjects.isEmpty)
            Text(
              'لا توجد مواد بعد؛ أضفها من «المزيد ← المواد».',
              style: text.bodySmall!.copyWith(color: p.textMuted),
            )
          else
            Wrap(
              spacing: ClaySpacing.sm,
              children: [
                for (final subject in subjects)
                  ClayChip(
                    label: subject.levelName == null
                        ? subject.name
                        : '${subject.name} (${subject.levelName})',
                    selected: _subjects.contains(subject.id),
                    onTap: () => setState(() {
                      if (!_subjects.add(subject.id)) {
                        _subjects.remove(subject.id);
                      }
                    }),
                  ),
              ],
            ),
          if (_errors['form'] != null)
            Padding(
              padding: const EdgeInsets.only(top: ClaySpacing.md),
              child: Text(
                _errors['form']!,
                style: text.bodySmall!.copyWith(color: p.status.danger),
              ),
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

/// ملف الأستاذ: بياناته، مواده، رمز QR، وإجراءات التعديل وإعادة كلمة السر
/// والحذف.
class TeacherProfileScreen extends ConsumerWidget {
  const TeacherProfileScreen({required this.teacherId, super.key});

  final String teacherId;

  Future<void> _edit(BuildContext context, WidgetRef ref, TeacherRow t) async {
    final ids = await ref.read(teacherServiceProvider).subjectIdsOf(t.id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => TeacherFormDialog(initial: t, initialSubjectIds: ids),
    );
  }

  Future<void> _reset(BuildContext context, WidgetRef ref, TeacherRow t) async {
    final ok = await showClayConfirm(
      context,
      title: 'إعادة كلمة السر',
      message:
          'ستُولَّد كلمة سر جديدة وتُرسل لـ ${t.name}، ولن تعمل كلمة السر '
          'القديمة.',
      confirmLabel: 'إعادة التوليد',
    );
    if (!ok || !context.mounted) return;
    try {
      final account = await ref
          .read(teacherServiceProvider)
          .resetPassword(t.id);
      if (!context.mounted) return;
      await showCredentialsDialog(
        context,
        account: account,
        ownerName: t.name,
        phone: t.phone,
      );
    } on Object catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    TeacherRow t,
  ) async {
    final ok = await showClayConfirm(
      context,
      title: 'حذف الأستاذ',
      message:
          'سيُعطَّل حساب ${t.name} ويختفي من القوائم، وتبقى سجلاته المالية '
          'وحضوره.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(teacherServiceProvider).remove(t.id);
      if (context.mounted) context.pop();
    } on ValidationException catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  void _showError(BuildContext context, Object error) {
    showClayDialog<void>(
      context,
      title: 'تعذّرت العملية',
      message: error.toString(),
      actions: [
        Builder(
          builder: (context) => ClayButton(
            label: 'حسناً',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final canEdit = ref.can(PermissionModule.teachers, PermissionAction.edit);
    final canDelete = ref.can(
      PermissionModule.teachers,
      PermissionAction.delete,
    );
    final items = ref.watch(teachersProvider);
    return Scaffold(
      appBar: const ClayAppBar(title: 'ملف الأستاذ', showBack: true),
      body: items.when(
        loading: () => const ClayLoadingView(),
        error: (_, _) => ClayErrorView(
          message: 'تعذّرت قراءة بيانات الأستاذ',
          onRetry: () => ref.invalidate(teachersProvider),
        ),
        data: (list) {
          final matches = list.where((i) => i.id == teacherId);
          if (matches.isEmpty) {
            return const ClayEmptyView(title: 'هذا الأستاذ غير موجود');
          }
          final item = matches.first;
          final t = item.teacher;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                children: [
                  ClayCard(
                    child: Column(
                      children: [
                        ClayAvatar(name: t.name, size: 72),
                        const SizedBox(height: ClaySpacing.md),
                        Text(t.name, style: text.headlineSmall),
                        const SizedBox(height: ClaySpacing.xs),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(t.phone, style: text.bodyMedium),
                        ),
                        const SizedBox(height: ClaySpacing.md),
                        Wrap(
                          spacing: ClaySpacing.sm,
                          runSpacing: ClaySpacing.xs,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final subject in item.subjectNames)
                              ClayChip(label: subject),
                            if (item.subjectNames.isEmpty)
                              Text(
                                'لم تُحدَّد مواد',
                                style: text.bodySmall!.copyWith(
                                  color: p.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: ClaySpacing.lg),
                  ClayCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _InfoRow(
                          label: 'بريد الدخول',
                          value: t.email,
                          ltr: true,
                        ),
                        _InfoRow(
                          label: 'نصيبه لكل تلميذ',
                          value: Money.format(t.ratePerStudent),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: ClaySpacing.lg),
                  ClayCard(
                    child: Column(
                      children: [
                        Text('رمز حضور الأستاذ', style: text.titleMedium),
                        const SizedBox(height: ClaySpacing.md),
                        ClayQrCode(
                          data: t.qrCode,
                          semanticLabel: 'رمز QR للأستاذ ${t.name}',
                        ),
                        const SizedBox(height: ClaySpacing.sm),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: SelectableText(
                            t.qrCode,
                            style: text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: ClaySpacing.xl),
                  if (canEdit) ...[
                    ClayButton(
                      label: 'تعديل البيانات',
                      icon: ClayIcons.edit,
                      expand: true,
                      onPressed: () => _edit(context, ref, t),
                    ),
                    const SizedBox(height: ClaySpacing.md),
                    ClayButton(
                      label: 'إعادة توليد كلمة السر',
                      icon: ClayIcons.sms,
                      kind: ClayButtonKind.secondary,
                      expand: true,
                      onPressed: () => _reset(context, ref, t),
                    ),
                  ],
                  if (canDelete) ...[
                    const SizedBox(height: ClaySpacing.md),
                    ClayButton(
                      label: 'حذف الأستاذ',
                      icon: ClayIcons.delete,
                      kind: ClayButtonKind.danger,
                      expand: true,
                      onPressed: () => _delete(context, ref, t),
                    ),
                  ],
                  const SizedBox(height: ClaySpacing.xl),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.ltr = false});

  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
      child: Row(
        children: [
          Text(label, style: text.bodyMedium!.copyWith(color: p.textMuted)),
          const SizedBox(width: ClaySpacing.md),
          Expanded(
            child: Directionality(
              textDirection: ltr
                  ? TextDirection.ltr
                  : Directionality.of(context),
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: text.titleSmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
