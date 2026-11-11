import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// تاريخ `YYYY-MM-DD` بصيغة العرض `DD/MM/YYYY` بأرقام لاتينية.
String displayDate(String key) {
  final parts = key.split('-');
  return parts.length == 3 ? '${parts[2]}/${parts[1]}/${parts[0]}' : key;
}

/// شاشة الإعدادات: بيانات المدرسة، حقوق التسجيل، الفصول، المستويات، وهوامش
/// الحضور. تُحفظ عبر زر واحد، أما المستويات فتُحفظ فور تعديلها.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _fee = TextEditingController();
  final _margin = TextEditingController();
  final _grace = TextEditingController();
  final _threshold = TextEditingController();

  SchoolSettings? _loaded;
  FeePeriod _period = FeePeriod.year;
  List<Semester> _semesters = const [];
  Map<String, String> _errors = const {};
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    ref.read(settingsServiceProvider).load().then((settings) {
      if (!mounted) return;
      setState(() {
        _loaded = settings;
        _name.text = settings.schoolName;
        _address.text = settings.schoolAddress;
        _phone.text = settings.schoolPhone;
        _fee.text = '${settings.registrationFee}';
        _margin.text = '${settings.scanMarginMinutes}';
        _grace.text = '${settings.graceMinutes}';
        _threshold.text = '${settings.duesSessionThreshold}';
        _period = settings.registrationFeePeriod;
        _semesters = settings.semesters;
      });
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _address,
      _phone,
      _fee,
      _margin,
      _grace,
      _threshold,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canEdit =>
      ref
          .read(sessionProvider)
          .value
          ?.can(PermissionModule.settings, PermissionAction.edit) ??
      false;

  /// يقرأ الحقول إلى إعدادات، ويعيد `null` مع أخطاء إن كان رقم غير صالح.
  SchoolSettings? _collect() {
    final errors = <String, String>{};
    int? number(
      TextEditingController c,
      String key, {
      bool allowEmpty = false,
    }) {
      final text = c.text.trim();
      if (text.isEmpty && allowEmpty) return 0;
      final value = int.tryParse(text);
      if (value == null) errors[key] = 'أدخل رقماً صحيحاً';
      return value;
    }

    final fee = number(_fee, SettingKeys.registrationFee, allowEmpty: true);
    final margin = number(_margin, SettingKeys.scanMarginMinutes);
    final grace = number(_grace, SettingKeys.graceMinutes);
    final threshold = number(_threshold, SettingKeys.duesSessionThreshold);
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return null;
    }
    return SchoolSettings(
      schoolName: _name.text,
      schoolAddress: _address.text,
      schoolPhone: _phone.text,
      registrationFee: fee!,
      registrationFeePeriod: _period,
      semesters: _semesters,
      scanMarginMinutes: margin!,
      graceMinutes: grace!,
      duesSessionThreshold: threshold!,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _message = null;
      _errors = const {};
    });
    final settings = _collect();
    if (settings == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(settingsServiceProvider).save(settings);
      if (mounted) setState(() => _message = 'تم حفظ الإعدادات');
    } on SettingsValidationException catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editSemester(int? index) async {
    final result = await showDialog<Semester>(
      context: context,
      builder: (_) =>
          _SemesterDialog(initial: index == null ? null : _semesters[index]),
    );
    if (result == null) return;
    setState(() {
      final list = [..._semesters];
      if (index == null) {
        list.add(result);
      } else {
        list[index] = result;
      }
      _semesters = list;
    });
  }

  Future<void> _editLevel(LevelRow? level) async {
    final result = await showDialog<_LevelInput>(
      context: context,
      builder: (_) => _LevelDialog(initial: level),
    );
    if (result == null) return;
    final service = ref.read(levelServiceProvider);
    try {
      if (level == null) {
        await service.add(name: result.name, stage: result.stage);
      } else {
        await service.rename(level.id, result.name);
      }
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _message = '${e.message}');
    }
  }

  Future<void> _removeLevel(LevelRow level) async {
    final ok = await showClayConfirm(
      context,
      title: 'حذف المستوى',
      message:
          'سيختفي «${level.name}» من القوائم، ويبقى اسمه في سجلات التلاميذ '
          'المرتبطين به.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (ok) await ref.read(levelServiceProvider).remove(level.id);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final canEdit = _canEdit;
    final levels = ref.watch(levelsProvider).value ?? const <LevelRow>[];

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: ClaySpacing.lg),
      child: ClayCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: text.titleMedium),
            ),
            const SizedBox(height: ClaySpacing.md),
            ...children,
          ],
        ),
      ),
    );

    Widget gap() => const SizedBox(height: ClaySpacing.md);

    return Scaffold(
      appBar: const ClayAppBar(title: 'الإعدادات', showBack: true),
      body: _loaded == null
          ? const ClayLoadingView()
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                  children: [
                    if (!canEdit)
                      const Padding(
                        padding: EdgeInsets.only(bottom: ClaySpacing.lg),
                        child: ClayBadge(
                          label: 'عرض فقط: ليست لديك صلاحية تعديل الإعدادات',
                          tone: ClayTone.info,
                        ),
                      ),
                    section('بيانات المدرسة', [
                      ClayTextField(
                        controller: _name,
                        label: 'اسم المدرسة',
                        enabled: canEdit,
                        error: _errors[SettingKeys.schoolName],
                      ),
                      gap(),
                      ClayTextField(
                        controller: _address,
                        label: 'العنوان',
                        enabled: canEdit,
                        maxLines: 2,
                      ),
                      gap(),
                      ClayTextField(
                        controller: _phone,
                        label: 'الهاتف',
                        enabled: canEdit,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        error: _errors[SettingKeys.schoolPhone],
                      ),
                    ]),
                    section('حقوق التسجيل', [
                      ClayTextField(
                        controller: _fee,
                        label: 'المبلغ (${Money.currency})',
                        enabled: canEdit,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        helper: '0 يعني بلا حقوق تسجيل',
                        error: _errors[SettingKeys.registrationFee],
                      ),
                      gap(),
                      ClayDropdown<FeePeriod>(
                        label: 'مدتها',
                        value: _period,
                        options: [
                          for (final period in FeePeriod.values)
                            ClayOption(value: period, label: period.label),
                        ],
                        onChanged: canEdit
                            ? (value) =>
                                  setState(() => _period = value ?? _period)
                            : null,
                      ),
                    ]),
                    section('الفصول الدراسية', [
                      if (_semesters.isEmpty)
                        Text(
                          'لم تُضف فصول بعد',
                          style: text.bodyMedium!.copyWith(color: p.textMuted),
                        ),
                      for (var i = 0; i < _semesters.length; i++)
                        _SemesterRow(
                          semester: _semesters[i],
                          onEdit: canEdit ? () => _editSemester(i) : null,
                          onRemove: canEdit
                              ? () => setState(
                                  () => _semesters = [
                                    for (var j = 0; j < _semesters.length; j++)
                                      if (j != i) _semesters[j],
                                  ],
                                )
                              : null,
                        ),
                      if (_errors[SettingKeys.semesters] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: ClaySpacing.sm),
                          child: Text(
                            _errors[SettingKeys.semesters]!,
                            style: text.bodySmall!.copyWith(
                              color: p.status.danger,
                            ),
                          ),
                        ),
                      gap(),
                      ClayButton(
                        label: 'إضافة فصل',
                        icon: ClayIcons.add,
                        kind: ClayButtonKind.secondary,
                        onPressed: canEdit ? () => _editSemester(null) : null,
                      ),
                    ]),
                    section('المستويات الدراسية', [
                      for (final stage in EducationStage.values) ...[
                        Text(
                          stage.label,
                          style: text.labelLarge!.copyWith(color: p.textMuted),
                        ),
                        Wrap(
                          spacing: ClaySpacing.sm,
                          children: [
                            for (final level in levels.where(
                              (l) => l.stage == stage.code,
                            ))
                              _LevelChip(
                                level: level,
                                onEdit: canEdit
                                    ? () => _editLevel(level)
                                    : null,
                                onRemove: canEdit
                                    ? () => _removeLevel(level)
                                    : null,
                              ),
                          ],
                        ),
                        gap(),
                      ],
                      ClayButton(
                        label: 'إضافة مستوى',
                        icon: ClayIcons.add,
                        kind: ClayButtonKind.secondary,
                        onPressed: canEdit ? () => _editLevel(null) : null,
                      ),
                    ]),
                    section('الحضور والمسح', [
                      ClayTextField(
                        controller: _margin,
                        label: 'هامش المسح قبل الحصة (دقيقة)',
                        enabled: canEdit,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        helper: 'يُقبل مسح التلميذ قبل بداية حصته بهذه المدة',
                        error: _errors[SettingKeys.scanMarginMinutes],
                      ),
                      gap(),
                      ClayTextField(
                        controller: _grace,
                        label: 'مهلة السماح للتأخر (دقيقة)',
                        enabled: canEdit,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        helper: 'للعرض فقط عند العمال، بلا أثر مالي',
                        error: _errors[SettingKeys.graceMinutes],
                      ),
                      gap(),
                      ClayTextField(
                        controller: _threshold,
                        label: 'مستحقات الدورة الحالية بعد حصة رقم',
                        enabled: canEdit,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        helper:
                            'يُنبَّه إلى «عليه مستحقات» إن لم يدفع التلميذ دورته '
                            'الحالية بعد هذا العدد من الحصص',
                        error: _errors[SettingKeys.duesSessionThreshold],
                      ),
                    ]),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: ClaySpacing.md),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _message!,
                            textAlign: TextAlign.center,
                            style: text.bodyMedium!.copyWith(
                              color: _message!.startsWith('تم')
                                  ? p.status.success
                                  : p.status.danger,
                            ),
                          ),
                        ),
                      ),
                    ClayButton(
                      label: 'حفظ الإعدادات',
                      expand: true,
                      loading: _saving,
                      onPressed: canEdit ? _save : null,
                    ),
                    const SizedBox(height: ClaySpacing.xl),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SemesterRow extends StatelessWidget {
  const _SemesterRow({required this.semester, this.onEdit, this.onRemove});

  final Semester semester;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(semester.name, style: text.titleSmall),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '${displayDate(semester.start)}  →  ${displayDate(semester.end)}',
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'تعديل ${semester.name}',
            icon: const Icon(ClayIcons.edit),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'حذف ${semester.name}',
            icon: const Icon(ClayIcons.delete),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level, this.onEdit, this.onRemove});

  final LevelRow level;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
      child: ClayContainer.flat(
        radius: ClayRadius.pill,
        padding: const EdgeInsetsDirectional.only(
          start: ClaySpacing.md,
          end: ClaySpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(level.name, style: text.labelMedium),
            IconButton(
              tooltip: 'تعديل ${level.name}',
              visualDensity: VisualDensity.compact,
              icon: Icon(ClayIcons.edit, size: 18, color: p.textMuted),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: 'حذف ${level.name}',
              visualDensity: VisualDensity.compact,
              icon: Icon(ClayIcons.close, size: 18, color: p.textMuted),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelInput {
  const _LevelInput(this.name, this.stage);

  final String name;
  final EducationStage stage;
}

class _LevelDialog extends StatefulWidget {
  const _LevelDialog({this.initial});

  final LevelRow? initial;

  @override
  State<_LevelDialog> createState() => _LevelDialogState();
}

class _LevelDialogState extends State<_LevelDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late EducationStage _stage = widget.initial == null
      ? EducationStage.primary
      : EducationStage.fromCode(widget.initial!.stage);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'أدخل اسم المستوى');
      return;
    }
    Navigator.of(context).pop(_LevelInput(_name.text.trim(), _stage));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return ClayDialog(
      title: editing ? 'تعديل المستوى' : 'إضافة مستوى',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClayTextField(
            controller: _name,
            label: 'الاسم',
            hint: 'مثال: 5 متوسط',
            error: _error,
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: ClaySpacing.md),
          ClayDropdown<EducationStage>(
            label: 'الطور',
            value: _stage,
            options: [
              for (final stage in EducationStage.values)
                ClayOption(value: stage, label: stage.label),
            ],
            // الطور لا يتغير بعد الإنشاء لأن الترتيب مبني عليه.
            onChanged: editing
                ? null
                : (value) => setState(() => _stage = value ?? _stage),
          ),
        ],
      ),
      actions: [
        ClayButton(label: 'حفظ', onPressed: _submit),
        ClayButton(
          label: 'إلغاء',
          kind: ClayButtonKind.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _SemesterDialog extends StatefulWidget {
  const _SemesterDialog({this.initial});

  final Semester? initial;

  @override
  State<_SemesterDialog> createState() => _SemesterDialogState();
}

class _SemesterDialogState extends State<_SemesterDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late String? _start = widget.initial?.start;
  late String? _end = widget.initial?.end;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool start}) async {
    final current = start ? _start : _end;
    final picked = await showClayDatePicker(
      context,
      title: start ? 'بداية الفصل' : 'نهاية الفصل',
      initial: current == null ? null : DateKey.parse(current),
    );
    if (picked == null) return;
    setState(() {
      final key = DateKey.of(picked);
      if (start) {
        _start = key;
      } else {
        _end = key;
      }
    });
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'أدخل اسم الفصل');
    } else if (_start == null || _end == null) {
      setState(() => _error = 'اختر تاريخي البداية والنهاية');
    } else if (_start!.compareTo(_end!) > 0) {
      setState(() => _error = 'بداية الفصل بعد نهايته');
    } else {
      Navigator.of(context)
          .pop(Semester(name: _name.text.trim(), start: _start!, end: _end!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClayDialog(
      title: widget.initial == null ? 'إضافة فصل' : 'تعديل الفصل',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClayTextField(
            controller: _name,
            label: 'الاسم',
            hint: 'مثال: الفصل الأول',
            autofocus: true,
          ),
          const SizedBox(height: ClaySpacing.md),
          ClayButton(
            label: _start == null
                ? 'تاريخ البداية'
                : 'البداية: ${displayDate(_start!)}',
            icon: ClayIcons.schedule,
            kind: ClayButtonKind.secondary,
            onPressed: () => _pick(start: true),
          ),
          const SizedBox(height: ClaySpacing.sm),
          ClayButton(
            label: _end == null
                ? 'تاريخ النهاية'
                : 'النهاية: ${displayDate(_end!)}',
            icon: ClayIcons.schedule,
            kind: ClayButtonKind.secondary,
            onPressed: () => _pick(start: false),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: ClaySpacing.md),
              child: Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall!
                    .copyWith(color: p.status.danger),
              ),
            ),
        ],
      ),
      actions: [
        ClayButton(label: 'حفظ', onPressed: _submit),
        ClayButton(
          label: 'إلغاء',
          kind: ClayButtonKind.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
