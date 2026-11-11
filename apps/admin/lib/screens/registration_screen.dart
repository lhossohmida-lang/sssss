import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'teachers_screens.dart' show showCredentialsDialog;

/// مسودة مادة في الاستمارة قبل الحفظ.
class _ChoiceDraft {
  _ChoiceDraft();

  String? subjectId;

  /// `null` يعني قائمة الانتظار.
  String? groupId;
  String? preferredTeacherId;
  final price = TextEditingController();
  DiscountType discountType = DiscountType.none;
  final discount = TextEditingController();

  void dispose() {
    price.dispose();
    discount.dispose();
  }
}

/// استمارة تسجيل تلميذ جديد: بياناته وصورته، وليّه، مواده (مجموعة أو قائمة
/// انتظار بسعر وتخفيض)، النقل، وحقوق التسجيل. عند الحفظ يُنشأ رمز QR وحساب
/// الوليّ أو يُربط بحسابه القائم بنفس الهاتف.
class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _parentName = TextEditingController();
  final _phone = TextEditingController();
  final _transportPrice = TextEditingController();
  final List<_ChoiceDraft> _choices = [_ChoiceDraft()];

  String? _levelId;
  bool _transport = false;
  String? _lineId;
  Uint8List? _photo;
  Map<String, String> _errors = const {};
  String? _formError;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_first, _last, _parentName, _phone, _transportPrice]) {
      c.dispose();
    }
    for (final choice in _choices) {
      choice.dispose();
    }
    super.dispose();
  }

  RegistrationRequest _request() => RegistrationRequest(
    firstName: _first.text,
    lastName: _last.text,
    parentName: _parentName.text,
    parentPhone: _phone.text,
    levelId: _levelId,
    date: DateKey.of(DateTime.now()),
    usesTransport: _transport,
    transportPrice: int.tryParse(_transportPrice.text.trim()) ?? 0,
    transportLineId: _lineId,
    choices: [
      for (final c in _choices)
        if (c.subjectId != null)
          SubjectChoice(
            subjectId: c.subjectId!,
            groupId: c.groupId,
            preferredTeacherId: c.preferredTeacherId,
            monthlyPrice: int.tryParse(c.price.text.trim()) ?? 0,
            discountType: c.discountType,
            discountValue: int.tryParse(c.discount.text.trim()) ?? 0,
          ),
    ],
  );

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _errors = const {};
      _formError = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final settings = await ref.read(settingsServiceProvider).load();
      final result = await ref
          .read(registrationServiceProvider)
          .register(_request(), settings: settings);
      final photo = _photo;
      if (photo != null) {
        try {
          await ref
              .read(photoServiceProvider)
              .attach(PhotoOwner.student, result.student.id, photo);
        } on FormatException catch (e) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('سُجّل التلميذ لكن تعذّر حفظ صورته: ${e.message}'),
            ),
          );
        }
      }
      if (!mounted) return;
      // انتهى الحفظ: يتوقف مؤشر التحميل قبل عرض بيانات الدخول.
      setState(() => _saving = false);
      if (result.parentAccount.created) {
        await showCredentialsDialog(
          context,
          account: result.parentAccount,
          ownerName: _parentName.text.trim(),
          phone: result.student.parentPhone,
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('سُجّل التلميذ ورُبط بحساب وليّه القائم'),
          ),
        );
      }
      if (mounted) context.pop();
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } on AuthFailureException catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addChoice() => setState(() => _choices.add(_ChoiceDraft()));

  void _removeChoice(int index) => setState(() {
    _choices.removeAt(index).dispose();
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final levels = ref.watch(levelsProvider).value ?? const <LevelRow>[];
    final subjects = ref.watch(subjectsProvider).value ?? const <SubjectItem>[];
    final lines =
        ref.watch(transportLinesProvider).value ?? const <TransportLineRow>[];
    final settings = ref.watch(schoolSettingsProvider).value;
    // مواد مستوى التلميذ والمواد العامة؛ دون مستوى تُعرض كلها.
    final offered = [
      for (final s in subjects)
        if (_levelId == null ||
            s.subject.levelId == null ||
            s.subject.levelId == _levelId)
          s,
    ];

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
    const gap = SizedBox(height: ClaySpacing.md);

    return Scaffold(
      appBar: const ClayAppBar(title: 'تسجيل تلميذ', showBack: true),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            children: [
              section('التلميذ', [
                ClayPhotoField(
                  name: '${_first.text} ${_last.text}',
                  pending: _photo,
                  enabled: !_saving,
                  onChanged: (bytes) => setState(() => _photo = bytes),
                ),
                gap,
                ClayTextField(
                  controller: _first,
                  label: 'الاسم',
                  error: _errors[RegistrationService.fieldFirstName],
                  textInputAction: TextInputAction.next,
                ),
                gap,
                ClayTextField(
                  controller: _last,
                  label: 'اللقب',
                  error: _errors[RegistrationService.fieldLastName],
                  textInputAction: TextInputAction.next,
                ),
                gap,
                ClayDropdown<String?>(
                  label: 'المستوى',
                  value: _levelId,
                  options: [
                    const ClayOption(value: null, label: 'غير محدد'),
                    for (final level in levels)
                      ClayOption(value: level.id, label: level.name),
                  ],
                  onChanged: (value) => setState(() => _levelId = value),
                ),
              ]),
              section('الوليّ', [
                ClayTextField(
                  controller: _parentName,
                  label: 'اسم الوليّ',
                  error: _errors[RegistrationService.fieldParentName],
                  textInputAction: TextInputAction.next,
                ),
                gap,
                ClayTextField(
                  controller: _phone,
                  label: 'هاتف الوليّ',
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  helper:
                      'يُنشأ له حساب وتصله بياناته برسالة؛ وإن كان له ابن مسجَّل '
                      'بنفس الرقم رُبط بحسابه',
                  error: _errors[RegistrationService.fieldPhone],
                ),
              ]),
              section('المواد', [
                for (var i = 0; i < _choices.length; i++)
                  _ChoiceCard(
                    key: ObjectKey(_choices[i]),
                    index: i,
                    draft: _choices[i],
                    subjects: offered,
                    errors: _errors,
                    onChanged: () => setState(() {}),
                    onRemove: _choices.length > 1
                        ? () => _removeChoice(i)
                        : null,
                  ),
                if (_errors[RegistrationService.fieldSubjects] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: ClaySpacing.sm),
                    child: Text(
                      _errors[RegistrationService.fieldSubjects]!,
                      style: text.bodySmall!.copyWith(color: p.status.danger),
                    ),
                  ),
                ClayButton(
                  label: 'إضافة مادة أخرى',
                  icon: ClayIcons.add,
                  kind: ClayButtonKind.secondary,
                  onPressed: _addChoice,
                ),
              ]),
              section('النقل', [
                Row(
                  children: [
                    Expanded(
                      child: Text('يستعمل نقل المدرسة', style: text.bodyLarge),
                    ),
                    ClayToggle(
                      value: _transport,
                      semanticLabel: 'يستعمل نقل المدرسة',
                      onChanged: (value) => setState(() => _transport = value),
                    ),
                  ],
                ),
                if (_transport) ...[
                  gap,
                  ClayTextField(
                    controller: _transportPrice,
                    label: 'سعر النقل الشهري (${Money.currency})',
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    error: _errors[RegistrationService.fieldTransport],
                  ),
                  if (lines.isNotEmpty) ...[
                    gap,
                    ClayDropdown<String?>(
                      label: 'خط النقل',
                      value: _lineId,
                      options: [
                        const ClayOption(value: null, label: 'غير محدد'),
                        for (final line in lines)
                          ClayOption(value: line.id, label: line.name),
                      ],
                      onChanged: (value) => setState(() => _lineId = value),
                    ),
                  ],
                ],
              ]),
              section('حقوق التسجيل', [
                Text(
                  settings == null || settings.registrationFee == 0
                      ? 'لا حقوق تسجيل محددة في الإعدادات'
                      : '${Money.format(settings.registrationFee)} عن كل '
                            '${settings.registrationFeePeriod.label}، تُسجَّل '
                            'مستحقة على التلميذ مرة واحدة مهما كان عدد مواده',
                  style: text.bodyMedium,
                ),
              ]),
              if (_formError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: ClaySpacing.md),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _formError!,
                      textAlign: TextAlign.center,
                      style: text.bodyMedium!.copyWith(color: p.status.danger),
                    ),
                  ),
                ),
              ClayButton(
                label: 'تسجيل التلميذ',
                expand: true,
                loading: _saving,
                onPressed: _submit,
              ),
              const SizedBox(height: ClaySpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

/// بطاقة مادة واحدة في الاستمارة.
class _ChoiceCard extends ConsumerWidget {
  const _ChoiceCard({
    required this.index,
    required this.draft,
    required this.subjects,
    required this.errors,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final int index;
  final _ChoiceDraft draft;
  final List<SubjectItem> subjects;
  final Map<String, String> errors;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  void _pickSubject(String? id) {
    draft
      ..subjectId = id
      ..groupId = null
      ..preferredTeacherId = null;
    final price = subjects.where((s) => s.id == id).firstOrNull?.monthlyPrice;
    draft.price.text = price == null ? '' : '$price';
    onChanged();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final subjectId = draft.subjectId;
    final groups = subjectId == null
        ? const <GroupOption>[]
        : ref.watch(groupOptionsProvider(subjectId)).value ??
              const <GroupOption>[];
    final teachers = subjectId == null
        ? const <TeacherRow>[]
        : ref.watch(subjectTeachersProvider(subjectId)).value ??
              const <TeacherRow>[];
    const gap = SizedBox(height: ClaySpacing.md);
    final price = int.tryParse(draft.price.text.trim()) ?? 0;
    final discountValue = int.tryParse(draft.discount.text.trim()) ?? 0;
    final net = price < 0
        ? 0
        : Pricing.netPrice(
            price: price,
            discountType: draft.discountType,
            discountValue: discountValue,
          );
    final needsValue =
        draft.discountType == DiscountType.percent ||
        draft.discountType == DiscountType.fixed;

    return Padding(
      padding: const EdgeInsets.only(bottom: ClaySpacing.md),
      child: ClayContainer.flat(
        padding: const EdgeInsets.all(ClaySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('المادة ${index + 1}', style: text.titleSmall),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'إزالة المادة ${index + 1}',
                    icon: const Icon(ClayIcons.close),
                    onPressed: onRemove,
                  ),
              ],
            ),
            ClayDropdown<String>(
              hint: subjects.isEmpty
                  ? 'لا توجد مواد لهذا المستوى'
                  : 'اختر المادة',
              value: subjectId,
              options: [
                for (final s in subjects)
                  ClayOption(
                    value: s.id,
                    label: s.levelName == null
                        ? s.name
                        : '${s.name} (${s.levelName})',
                  ),
              ],
              onChanged: _pickSubject,
            ),
            if (subjectId != null) ...[
              gap,
              ClayDropdown<String?>(
                label: 'المجموعة',
                value: draft.groupId,
                options: [
                  const ClayOption(value: null, label: 'قائمة الانتظار'),
                  for (final g in groups)
                    ClayOption(
                      value: g.id,
                      label: '${g.label} (${g.studentCount} تلميذ)',
                    ),
                ],
                helper: groups.isEmpty
                    ? 'لا مجموعات لهذه المادة بعد؛ يُضاف إلى قائمة الانتظار'
                    : null,
                onChanged: (value) {
                  draft.groupId = value;
                  onChanged();
                },
              ),
              gap,
              if (draft.groupId == null)
                ClayDropdown<String?>(
                  label: 'الأستاذ المفضّل (اختياري)',
                  value: draft.preferredTeacherId,
                  options: [
                    const ClayOption(value: null, label: 'دون تفضيل'),
                    for (final t in teachers)
                      ClayOption(value: t.id, label: t.name),
                  ],
                  onChanged: (value) {
                    draft.preferredTeacherId = value;
                    onChanged();
                  },
                )
              else ...[
                ClayTextField(
                  controller: draft.price,
                  label: 'سعر الشهر (${Money.currency})',
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  error:
                      errors[RegistrationService.choiceField(
                        index,
                        EnrolmentService.fieldPrice,
                      )],
                  onChanged: (_) => onChanged(),
                ),
                gap,
                ClayDropdown<DiscountType>(
                  label: 'التخفيض',
                  value: draft.discountType,
                  options: [
                    for (final type in DiscountType.values)
                      ClayOption(value: type, label: type.label),
                  ],
                  onChanged: (value) {
                    draft.discountType = value ?? DiscountType.none;
                    onChanged();
                  },
                ),
                if (needsValue) ...[
                  gap,
                  ClayTextField(
                    controller: draft.discount,
                    label: draft.discountType == DiscountType.percent
                        ? 'النسبة (%)'
                        : 'مبلغ التخفيض (${Money.currency})',
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    error:
                        errors[RegistrationService.choiceField(
                          index,
                          EnrolmentService.fieldDiscount,
                        )],
                    onChanged: (_) => onChanged(),
                  ),
                ],
                gap,
                Text(
                  'يدفع عن كل دورة: ${Money.format(net)}',
                  style: text.bodyMedium!.copyWith(color: p.accent),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
