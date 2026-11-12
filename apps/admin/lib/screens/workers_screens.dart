import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'teachers_screens.dart' show showCredentialsDialog;

/// قائمة العمال: اسم وأيام عمل وأجر اليوم، وإضافة عامل.
class WorkersScreen extends ConsumerWidget {
  const WorkersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canAdd = ref.can(PermissionModule.workers, PermissionAction.add);
    return ClayListPage<WorkerItem>(
      title: 'العمال',
      data: ref.watch(workersProvider),
      emptyTitle: 'لا يوجد عمال بعد',
      emptyMessage: 'أضف العامل بأجريه وبرنامج عمله لتُنشأ حسابه وصلاحياته',
      searchHint: 'ابحث بالاسم أو الهاتف',
      matches: (item, query) =>
          item.name.contains(query) || item.worker.phone.contains(query),
      onRetry: () => ref.invalidate(workersProvider),
      addLabel: 'إضافة عامل',
      onAdd: canAdd ? () => context.push('/workers/new') : null,
      itemExtent: 80,
      itemBuilder: (context, item) => ClayListTile(
        leading: ClayAvatar(name: item.name),
        title: item.name,
        subtitle:
            '${item.workDays} أيام عمل · يوم ${Money.format(item.worker.fullDayWage)}'
            ' · ${item.worker.phone}',
        onTap: () => context.push('/workers/${item.id}'),
        trailing: const [Icon(Icons.chevron_left_rounded)],
      ),
    );
  }
}

/// مسودة نوع اليوم في النموذج.
const List<WorkDayKind> _kinds = [
  WorkDayKind.off,
  WorkDayKind.half,
  WorkDayKind.full,
];

/// إضافة عامل أو تعديله: الاسم والهاتف وأجر اليوم الكامل ونصفه والساعات
/// وبرنامج الأسبوع (لكل يوم: لا يعمل / نصف يوم / يوم كامل).
class WorkerFormScreen extends ConsumerStatefulWidget {
  const WorkerFormScreen({this.workerId, super.key});

  /// معرّف العامل عند التعديل؛ `null` للإضافة.
  final String? workerId;

  @override
  ConsumerState<WorkerFormScreen> createState() => _WorkerFormScreenState();
}

class _WorkerFormScreenState extends ConsumerState<WorkerFormScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _full = TextEditingController(text: '0');
  final _half = TextEditingController(text: '0');
  final Map<int, WorkDayKind> _days = {
    for (final d in GroupService.displayWeekdays) d: WorkDayKind.off,
  };
  int _start = 480;
  int _end = 1020;
  bool _loaded = false;
  bool _saving = false;
  Map<String, String> _errors = const {};

  bool get _editing => widget.workerId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      _load();
    } else {
      _loaded = true;
    }
  }

  Future<void> _load() async {
    final db = ref.read(runtimeProvider).db;
    final worker = await (db.select(
      db.workers,
    )..where((w) => w.id.equals(widget.workerId!))).getSingleOrNull();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      if (worker == null) return;
      _name.text = worker.name;
      _phone.text = worker.phone;
      _full.text = '${worker.fullDayWage}';
      _half.text = '${worker.halfDayWage}';
      _start = worker.expectedStartMinutes;
      _end = worker.expectedEndMinutes;
      final schedule = WorkerSchedule.fromJson(worker.weeklySchedule);
      for (final d in GroupService.displayWeekdays) {
        _days[d] = schedule.kindOn(d);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _full.dispose();
    _half.dispose();
    super.dispose();
  }

  WorkerSchedule get _schedule => WorkerSchedule(Map.of(_days));

  Future<void> _pickTime({required bool start}) async {
    final picked = await showClayTimePicker(
      context,
      title: start ? 'بداية العمل' : 'نهاية العمل',
      initial: start ? _start : _end,
    );
    if (picked == null) return;
    setState(() => start ? _start = picked : _end = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _errors = const {};
    });
    final service = ref.read(workerServiceProvider);
    final full = int.tryParse(_full.text.trim()) ?? 0;
    final half = int.tryParse(_half.text.trim()) ?? 0;
    try {
      if (_editing) {
        await service.update(
          widget.workerId!,
          name: _name.text,
          phone: _phone.text,
          fullDayWage: full,
          halfDayWage: half,
          schedule: _schedule,
          startMinutes: _start,
          endMinutes: _end,
        );
        if (mounted) context.pop();
      } else {
        final created = await service.add(
          name: _name.text,
          phone: _phone.text,
          fullDayWage: full,
          halfDayWage: half,
          schedule: _schedule,
          startMinutes: _start,
          endMinutes: _end,
        );
        if (!mounted) return;
        // لا يبقى زر الحفظ في حالة «جارٍ» خلف نافذة بيانات الدخول.
        setState(() => _saving = false);
        await showCredentialsDialog(
          context,
          account: created.account,
          ownerName: created.worker.name,
          phone: created.worker.phone,
        );
        // العامل الجديد بلا صلاحيات: تُضبط من ملفه.
        if (mounted) context.pushReplacement('/workers/${created.worker.id}');
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
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    const gap = SizedBox(height: ClaySpacing.md);
    return Scaffold(
      appBar: ClayAppBar(
        title: _editing ? 'تعديل العامل' : 'إضافة عامل',
        showBack: true,
      ),
      body: !_loaded
          ? const ClayLoadingView()
          : ListView(
              padding: const EdgeInsets.all(ClaySpacing.screenPadding),
              children: [
                ClayTextField(
                  controller: _name,
                  label: 'الاسم الكامل',
                  autofocus: !_editing,
                  error: _errors[WorkerService.fieldName],
                ),
                gap,
                ClayTextField(
                  controller: _phone,
                  label: 'الهاتف',
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  helper: _editing
                      ? 'بريد الدخول لا يتغير بتغيير الهاتف'
                      : 'يُبنى منه بريد الدخول وتصله عليه كلمة السر',
                  error: _errors[WorkerService.fieldPhone],
                ),
                gap,
                ClayTextField(
                  controller: _full,
                  label: 'أجر اليوم الكامل (${Money.currency})',
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  error: _errors[WorkerService.fieldFullWage],
                ),
                gap,
                ClayTextField(
                  controller: _half,
                  label: 'أجر نصف اليوم (${Money.currency})',
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  helper: 'مبلغ مستقل يحدده المدير، لا خصم عند التأخر',
                  error: _errors[WorkerService.fieldHalfWage],
                ),
                gap,
                Text('ساعات العمل المتوقعة', style: text.titleSmall),
                const SizedBox(height: ClaySpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: ClayButton(
                        label: 'من ${DateKey.formatMinutes(_start)}',
                        kind: ClayButtonKind.secondary,
                        onPressed: () => _pickTime(start: true),
                      ),
                    ),
                    const SizedBox(width: ClaySpacing.sm),
                    Expanded(
                      child: ClayButton(
                        label: 'إلى ${DateKey.formatMinutes(_end)}',
                        kind: ClayButtonKind.secondary,
                        onPressed: () => _pickTime(start: false),
                      ),
                    ),
                  ],
                ),
                if (_errors[WorkerService.fieldHours] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: ClaySpacing.xs),
                    child: Text(
                      _errors[WorkerService.fieldHours]!,
                      style: text.bodySmall!.copyWith(color: p.status.danger),
                    ),
                  ),
                gap,
                Text('برنامج العمل الأسبوعي', style: text.titleSmall),
                for (final day in GroupService.displayWeekdays)
                  Padding(
                    padding: const EdgeInsets.only(top: ClaySpacing.sm),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 76,
                          child: Text(
                            GroupService.weekdayName(day),
                            style: text.bodyMedium,
                          ),
                        ),
                        Expanded(
                          child: Wrap(
                            spacing: ClaySpacing.xs,
                            children: [
                              for (final kind in _kinds)
                                ClayChip(
                                  label: kind.label,
                                  selected: _days[day] == kind,
                                  onTap: () =>
                                      setState(() => _days[day] = kind),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_errors[WorkerService.fieldSchedule] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: ClaySpacing.xs),
                    child: Text(
                      _errors[WorkerService.fieldSchedule]!,
                      style: text.bodySmall!.copyWith(color: p.status.danger),
                    ),
                  ),
                if (_errors['form'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: ClaySpacing.md),
                    child: Text(
                      _errors['form']!,
                      style: text.bodySmall!.copyWith(color: p.status.danger),
                    ),
                  ),
                const SizedBox(height: ClaySpacing.xl),
                ClayButton(
                  label: _editing ? 'حفظ التعديلات' : 'إضافة العامل',
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

/// ملف العامل: بياناته وأجراه وبرنامجه ورمزه وصلاحياته، وإجراءات التعديل
/// والصلاحيات وإعادة كلمة السر والحذف.
class WorkerProfileScreen extends ConsumerWidget {
  const WorkerProfileScreen({required this.workerId, super.key});

  final String workerId;

  Future<void> _reset(BuildContext context, WidgetRef ref, WorkerRow w) async {
    final ok = await showClayConfirm(
      context,
      title: 'إعادة كلمة السر',
      message:
          'ستُولَّد كلمة سر جديدة وتُرسل لـ ${w.name}، ولن تعمل كلمة السر '
          'القديمة.',
      confirmLabel: 'إعادة التوليد',
    );
    if (!ok || !context.mounted) return;
    try {
      final account = await ref.read(workerServiceProvider).resetPassword(w.id);
      if (!context.mounted) return;
      await showCredentialsDialog(
        context,
        account: account,
        ownerName: w.name,
        phone: w.phone,
      );
    } on Object catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, WorkerRow w) async {
    final ok = await showClayConfirm(
      context,
      title: 'حذف العامل',
      message:
          'سيُعطَّل حساب ${w.name} ويختفي من القوائم، وتبقى سجلات حضوره '
          'وأجره.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    await ref.read(workerServiceProvider).remove(w.id);
    if (context.mounted) context.pop();
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
    final workers = ref.watch(workersProvider);
    final canEdit = ref.can(PermissionModule.workers, PermissionAction.edit);
    final canDelete = ref.can(
      PermissionModule.workers,
      PermissionAction.delete,
    );
    return Scaffold(
      appBar: const ClayAppBar(title: 'ملف العامل', showBack: true),
      body: workers.when(
        loading: () => const ClayLoadingView(),
        error: (_, _) => ClayErrorView(
          message: 'تعذّرت قراءة العامل',
          onRetry: () => ref.invalidate(workersProvider),
        ),
        data: (all) {
          final item = all.where((w) => w.id == workerId).firstOrNull;
          if (item == null) {
            return const ClayEmptyView(title: 'هذا العامل غير موجود');
          }
          final w = item.worker;
          final permissions = item.permissions;
          Widget row(String label, String value, {bool ltr = false}) => Padding(
            padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
            child: Row(
              children: [
                Text(
                  label,
                  style: text.bodyMedium!.copyWith(color: p.textMuted),
                ),
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
          return ListView(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            children: [
              ClayCard(
                child: Column(
                  children: [
                    ClayAvatar(name: w.name, size: 72),
                    const SizedBox(height: ClaySpacing.sm),
                    Text(w.name, style: text.titleLarge),
                    const SizedBox(height: ClaySpacing.md),
                    row('الهاتف', w.phone, ltr: true),
                    row('البريد', w.email, ltr: true),
                    row('أجر اليوم الكامل', Money.format(w.fullDayWage)),
                    row('أجر نصف اليوم', Money.format(w.halfDayWage)),
                    row(
                      'ساعات العمل',
                      '${DateKey.formatMinutes(w.expectedStartMinutes)}'
                          ' – ${DateKey.formatMinutes(w.expectedEndMinutes)}',
                      ltr: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ClaySpacing.md),
              ClayCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('برنامج العمل', style: text.titleSmall),
                    for (final d in GroupService.displayWeekdays)
                      row(
                        GroupService.weekdayName(d),
                        item.schedule.kindOn(d).label,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: ClaySpacing.md),
              ClayCard(
                child: Column(
                  children: [
                    Text('رمز الحضور', style: text.titleSmall),
                    const SizedBox(height: ClaySpacing.sm),
                    ClayQrCode(data: w.qrCode, size: 160),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: SelectableText(w.qrCode, style: text.bodySmall),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ClaySpacing.md),
              ClayCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الصلاحيات', style: text.titleSmall),
                    const SizedBox(height: ClaySpacing.xs),
                    if (permissions.isEmpty)
                      Text(
                        'بلا صلاحيات؛ لا يرى شيئاً في التطبيق حتى تُفعَّل له',
                        style: text.bodySmall!.copyWith(color: p.textMuted),
                      )
                    else
                      Wrap(
                        spacing: ClaySpacing.xs,
                        children: [
                          for (final module in permissions.modules)
                            ClayChip(label: module.label),
                        ],
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
                  onPressed: () => context.push('/workers/${w.id}/edit'),
                ),
                const SizedBox(height: ClaySpacing.md),
                ClayButton(
                  label: 'ضبط الصلاحيات',
                  icon: ClayIcons.settings,
                  kind: ClayButtonKind.secondary,
                  expand: true,
                  onPressed: () => context.push('/workers/${w.id}/permissions'),
                ),
                const SizedBox(height: ClaySpacing.md),
                ClayButton(
                  label: 'إعادة توليد كلمة السر',
                  icon: ClayIcons.sms,
                  kind: ClayButtonKind.secondary,
                  expand: true,
                  onPressed: () => _reset(context, ref, w),
                ),
              ],
              if (canDelete) ...[
                const SizedBox(height: ClaySpacing.md),
                ClayButton(
                  label: 'حذف العامل',
                  icon: ClayIcons.delete,
                  kind: ClayButtonKind.danger,
                  expand: true,
                  onPressed: () => _delete(context, ref, w),
                ),
              ],
              const SizedBox(height: ClaySpacing.xl),
            ],
          );
        },
      ),
    );
  }
}

/// ضبط صلاحيات العامل: لكل وحدة أفعالها (عرض، إضافة، تعديل، حذف، استعمال)
/// تُفعَّل بالنقر، مع «الكل» لتفعيل الوحدة كلها. الحفظ يكتبها بصيغة الخادم.
class WorkerPermissionsScreen extends ConsumerStatefulWidget {
  const WorkerPermissionsScreen({required this.workerId, super.key});

  final String workerId;

  @override
  ConsumerState<WorkerPermissionsScreen> createState() =>
      _WorkerPermissionsScreenState();
}

class _WorkerPermissionsScreenState
    extends ConsumerState<WorkerPermissionsScreen> {
  WorkerPermissions? _permissions;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final workers = ref.watch(workersProvider);
    final item = workers.value
        ?.where((w) => w.id == widget.workerId)
        .firstOrNull;
    if (item != null) _permissions ??= item.permissions;
    final perms = _permissions;

    return Scaffold(
      appBar: const ClayAppBar(title: 'صلاحيات العامل', showBack: true),
      body: item == null || perms == null
          ? (workers.isLoading
                ? const ClayLoadingView()
                : const ClayEmptyView(title: 'هذا العامل غير موجود'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(item.name, style: text.titleMedium),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ClaySpacing.screenPadding,
                    ),
                    itemCount: PermissionModule.values.length,
                    itemBuilder: (context, i) {
                      final module = PermissionModule.values[i];
                      final all = module.actions.every(
                        (a) => perms.can(module, a),
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: ClaySpacing.sm),
                        child: ClayCard(
                          flat: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(module.label, style: text.titleSmall),
                              Wrap(
                                spacing: ClaySpacing.xs,
                                children: [
                                  ClayChip(
                                    label: 'الكل',
                                    selected: all,
                                    onTap: () => setState(
                                      () => _permissions = perms.withModule(
                                        module,
                                        allowed: !all,
                                      ),
                                    ),
                                  ),
                                  for (final action in module.actions)
                                    ClayChip(
                                      label: action.label,
                                      selected: perms.can(module, action),
                                      onTap: () => setState(
                                        () => _permissions = perms.withAction(
                                          module,
                                          action,
                                          allowed: !perms.can(module, action),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                  child: Column(
                    children: [
                      Text(
                        'تسري الصلاحيات الجديدة على العامل عند تجديد جلسته '
                        '(دخوله من جديد)',
                        style: text.bodySmall!.copyWith(color: p.textMuted),
                      ),
                      const SizedBox(height: ClaySpacing.sm),
                      ClayButton(
                        label: 'حفظ الصلاحيات',
                        icon: ClayIcons.check,
                        expand: true,
                        loading: _saving,
                        onPressed: () async {
                          setState(() => _saving = true);
                          try {
                            await ref
                                .read(workerServiceProvider)
                                .setPermissions(item.id, perms);
                            if (context.mounted) context.pop();
                          } finally {
                            if (mounted) setState(() => _saving = false);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
