import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'registration_screen.dart' show ChoiceDraft, SubjectChoiceCard;
import 'student_card_action.dart';
import 'teachers_screens.dart' show showCredentialsDialog;

/// ملف التلميذ: بياناته ووليّه، مجموعاته بحضوره ومستحقاته، قوائم انتظاره،
/// رمز QR، وإجراءات التعديل وإضافة مادة والمغادرة والحذف.
class StudentProfileScreen extends ConsumerWidget {
  const StudentProfileScreen({required this.studentId, super.key});

  final String studentId;

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

  Future<void> _leaveGroup(
    BuildContext context,
    WidgetRef ref,
    EnrolmentInfo info,
  ) async {
    final ok = await showClayConfirm(
      context,
      title: 'مغادرة المجموعة',
      message:
          'سيغادر التلميذ مجموعة ${info.subjectName} رقم ${info.groupNumber}. '
          'تبقى دوراته السابقة ومستحقاتها، ولا تُحسب عليه الدورات القادمة.',
      confirmLabel: 'مغادرة',
      danger: true,
    );
    if (ok) {
      await ref
          .read(studentServiceProvider)
          .leaveGroup(studentId, info.groupId);
    }
  }

  Future<void> _resetParentPassword(
    BuildContext context,
    WidgetRef ref,
    StudentProfile profile,
  ) async {
    final parent = profile.parent;
    if (parent == null) return;
    final ok = await showClayConfirm(
      context,
      title: 'إعادة كلمة سر الوليّ',
      message:
          'ستُولَّد كلمة سر جديدة وتُرسل إلى ${parent.phone}، ولن تعمل كلمة '
          'السر القديمة.',
      confirmLabel: 'إعادة التوليد',
    );
    if (!ok || !context.mounted) return;
    try {
      final accounts = ref.read(accountServiceProvider);
      final account = await accounts.findByEmail(parent.email);
      if (account == null) {
        throw ValidationException.field('account', 'لا حساب لهذا الوليّ');
      }
      final result = await accounts.resetPassword(account.id);
      if (!context.mounted) return;
      await showCredentialsDialog(
        context,
        account: result,
        ownerName: parent.name.isEmpty ? 'الوليّ' : parent.name,
        phone: parent.phone,
      );
    } on Object catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    StudentProfile profile,
  ) async {
    final ok = await showClayConfirm(
      context,
      title: 'حذف التلميذ',
      message:
          'سيختفي ${profile.fullName} من القوائم ويغادر مجموعاته، وتبقى '
          'مدفوعاته وحضوره في السجلات.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    await ref.read(studentServiceProvider).remove(studentId);
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final canEdit = ref.can(PermissionModule.students, PermissionAction.edit);
    final canDelete = ref.can(
      PermissionModule.students,
      PermissionAction.delete,
    );
    final state = ref.watch(studentProfileProvider(studentId));

    Widget card(String title, List<Widget> children) => Padding(
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

    return Scaffold(
      appBar: const ClayAppBar(title: 'ملف التلميذ', showBack: true),
      body: state.when(
        loading: () => const ClayLoadingView(),
        error: (_, _) => ClayErrorView(
          message: 'تعذّرت قراءة ملف التلميذ',
          onRetry: () => ref.invalidate(studentProfileProvider(studentId)),
        ),
        data: (profile) {
          if (profile == null) {
            return const ClayEmptyView(title: 'هذا التلميذ غير موجود');
          }
          final s = profile.student;
          final parent = profile.parent;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: ClaySpacing.lg),
                    child: ClayCard(
                      child: Column(
                        children: [
                          ClayAvatar(
                            name: profile.fullName,
                            image: localPhoto(s.photoLocalPath),
                            size: 72,
                          ),
                          const SizedBox(height: ClaySpacing.md),
                          Text(profile.fullName, style: text.headlineSmall),
                          if (profile.levelName != null)
                            Text(profile.levelName!, style: text.bodyMedium),
                          const SizedBox(height: ClaySpacing.md),
                          ClayBadge(
                            label: profile.totalRemaining == 0
                                ? 'لا مستحقات'
                                : 'عليه ${Money.format(profile.totalRemaining)}',
                            tone: profile.totalRemaining == 0
                                ? ClayTone.success
                                : ClayTone.warning,
                          ),
                        ],
                      ),
                    ),
                  ),
                  card('الوليّ', [
                    _InfoRow(
                      label: 'الاسم',
                      value: parent == null || parent.name.isEmpty
                          ? 'غير مسجَّل'
                          : parent.name,
                    ),
                    _InfoRow(label: 'الهاتف', value: s.parentPhone, ltr: true),
                    if (parent != null)
                      _InfoRow(
                        label: 'بريد الدخول',
                        value: parent.email,
                        ltr: true,
                      ),
                  ]),
                  card('المجموعات', [
                    if (profile.enrolments.isEmpty)
                      Text(
                        'غير منتسب إلى أي مجموعة',
                        style: text.bodyMedium!.copyWith(color: p.textMuted),
                      ),
                    for (final info in profile.enrolments)
                      _EnrolmentTile(
                        info: info,
                        onLeave: canEdit
                            ? () => _leaveGroup(context, ref, info)
                            : null,
                      ),
                  ]),
                  if (profile.waiting.isNotEmpty)
                    card('قوائم الانتظار', [
                      for (final w in profile.waiting)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                w.levelName == null
                                    ? w.subjectName
                                    : '${w.subjectName} (${w.levelName})',
                                style: text.bodyLarge,
                              ),
                            ),
                            if (canEdit)
                              IconButton(
                                tooltip: 'إزالة من انتظار ${w.subjectName}',
                                icon: const Icon(ClayIcons.close),
                                onPressed: () => ref
                                    .read(studentServiceProvider)
                                    .leaveWaiting(w.entryId),
                              ),
                          ],
                        ),
                    ]),
                  card('المستحقات', [
                    _InfoRow(
                      label: 'الدورات',
                      value: Money.format(profile.cyclesRemaining),
                    ),
                    _InfoRow(
                      label: 'حقوق التسجيل',
                      value: Money.format(profile.registrationFeeRemaining),
                    ),
                    if (s.usesTransport)
                      _InfoRow(
                        label: 'نقل هذا الشهر',
                        value: Money.format(profile.transportRemaining),
                      ),
                    const Divider(),
                    _InfoRow(
                      label: 'المجموع',
                      value: Money.format(profile.totalRemaining),
                    ),
                  ]),
                  card('رمز الدخول', [
                    Center(
                      child: ClayQrCode(
                        data: s.qrCode,
                        semanticLabel: 'رمز QR للتلميذ ${profile.fullName}',
                      ),
                    ),
                    const SizedBox(height: ClaySpacing.sm),
                    Center(
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: SelectableText(s.qrCode, style: text.bodySmall),
                      ),
                    ),
                    const SizedBox(height: ClaySpacing.md),
                    ClayButton(
                      label: 'بطاقة التلميذ PDF',
                      icon: ClayIcons.print,
                      kind: ClayButtonKind.secondary,
                      expand: true,
                      onPressed: () => showStudentCard(context, ref, profile),
                    ),
                  ]),
                  if (canEdit) ...[
                    ClayButton(
                      label: 'تعديل البيانات',
                      icon: ClayIcons.edit,
                      expand: true,
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => StudentEditDialog(student: s),
                      ),
                    ),
                    const SizedBox(height: ClaySpacing.md),
                    ClayButton(
                      label: 'إضافة مادة',
                      icon: ClayIcons.add,
                      kind: ClayButtonKind.secondary,
                      expand: true,
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => AddSubjectDialog(student: s),
                      ),
                    ),
                    if (parent != null) ...[
                      const SizedBox(height: ClaySpacing.md),
                      ClayButton(
                        label: 'إعادة كلمة سر الوليّ',
                        icon: ClayIcons.sms,
                        kind: ClayButtonKind.secondary,
                        expand: true,
                        onPressed: () =>
                            _resetParentPassword(context, ref, profile),
                      ),
                    ],
                  ],
                  if (canDelete) ...[
                    const SizedBox(height: ClaySpacing.md),
                    ClayButton(
                      label: 'حذف التلميذ',
                      icon: ClayIcons.delete,
                      kind: ClayButtonKind.danger,
                      expand: true,
                      onPressed: () => _delete(context, ref, profile),
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

class _EnrolmentTile extends StatelessWidget {
  const _EnrolmentTile({required this.info, required this.onLeave});

  final EnrolmentInfo info;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
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
                  child: Text(
                    '${info.subjectName} · المجموعة ${info.groupNumber}',
                    style: text.titleSmall,
                  ),
                ),
                if (onLeave != null)
                  IconButton(
                    tooltip: 'مغادرة مجموعة ${info.subjectName}',
                    icon: const Icon(ClayIcons.logout),
                    onPressed: onLeave,
                  ),
              ],
            ),
            Text(
              '${info.teacherName} · ${Money.format(info.netPrice)} للدورة',
              style: text.bodySmall!.copyWith(color: p.textMuted),
            ),
            const SizedBox(height: ClaySpacing.sm),
            Wrap(
              spacing: ClaySpacing.sm,
              runSpacing: ClaySpacing.xs,
              children: [
                ClayBadge(
                  label: 'حاضر ${info.present}',
                  tone: ClayTone.success,
                ),
                ClayBadge(label: 'غائب ${info.absent}', tone: ClayTone.danger),
                ClayBadge(
                  label: 'برخصة ${info.excused}',
                  tone: ClayTone.excused,
                ),
                if (info.remaining > 0)
                  ClayBadge(
                    label: 'الباقي ${Money.format(info.remaining)}',
                    tone: ClayTone.warning,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// تعديل بيانات التلميذ وصورته ونقله.
class StudentEditDialog extends ConsumerStatefulWidget {
  const StudentEditDialog({required this.student, super.key});

  final StudentRow student;

  @override
  ConsumerState<StudentEditDialog> createState() => _StudentEditDialogState();
}

class _StudentEditDialogState extends ConsumerState<StudentEditDialog> {
  late final _first = TextEditingController(text: widget.student.firstName);
  late final _last = TextEditingController(text: widget.student.lastName);
  late final _transportPrice = TextEditingController(
    text: widget.student.usesTransport
        ? '${widget.student.transportPrice}'
        : '',
  );
  late String? _levelId = widget.student.levelId;
  late bool _transport = widget.student.usesTransport;
  late String? _lineId = widget.student.transportLineId;
  Uint8List? _photo;
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _transportPrice.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _errors = const {};
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(studentServiceProvider)
          .update(
            widget.student.id,
            firstName: _first.text,
            lastName: _last.text,
            levelId: _levelId,
            usesTransport: _transport,
            transportPrice: int.tryParse(_transportPrice.text.trim()) ?? 0,
            transportLineId: _lineId,
          );
      final photo = _photo;
      if (photo != null) {
        try {
          await ref
              .read(photoServiceProvider)
              .attach(PhotoOwner.student, widget.student.id, photo);
        } on FormatException catch (e) {
          messenger?.showSnackBar(
            SnackBar(content: Text('تعذّر حفظ الصورة: ${e.message}')),
          );
        }
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
    final levels = ref.watch(levelsProvider).value ?? const <LevelRow>[];
    final lines =
        ref.watch(transportLinesProvider).value ?? const <TransportLineRow>[];
    final text = Theme.of(context).textTheme;
    const gap = SizedBox(height: ClaySpacing.md);
    return ClayDialog(
      title: 'تعديل بيانات التلميذ',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClayPhotoField(
            name: '${_first.text} ${_last.text}',
            current: localPhoto(widget.student.photoLocalPath),
            pending: _photo,
            enabled: !_saving,
            onChanged: (bytes) => setState(() => _photo = bytes),
          ),
          gap,
          ClayTextField(
            controller: _first,
            label: 'الاسم',
            error: _errors[StudentService.fieldFirstName],
          ),
          gap,
          ClayTextField(
            controller: _last,
            label: 'اللقب',
            error: _errors[StudentService.fieldLastName],
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
          gap,
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
              error: _errors[StudentService.fieldTransport],
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

/// إضافة مادة لتلميذ مسجَّل: مجموعة بسعر وتخفيض، أو قائمة الانتظار.
class AddSubjectDialog extends ConsumerStatefulWidget {
  const AddSubjectDialog({required this.student, super.key});

  final StudentRow student;

  @override
  ConsumerState<AddSubjectDialog> createState() => _AddSubjectDialogState();
}

class _AddSubjectDialogState extends ConsumerState<AddSubjectDialog> {
  final _draft = ChoiceDraft();
  Map<String, String> _errors = const {};
  String? _formError;
  bool _saving = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final subjectId = _draft.subjectId;
    if (subjectId == null) {
      setState(() => _formError = 'اختر المادة');
      return;
    }
    setState(() {
      _saving = true;
      _errors = const {};
      _formError = null;
    });
    final service = ref.read(enrolmentServiceProvider);
    try {
      final groupId = _draft.groupId;
      if (groupId == null) {
        await service.addToWaiting(
          studentId: widget.student.id,
          subjectId: subjectId,
          levelId: widget.student.levelId,
          preferredTeacherId: _draft.preferredTeacherId,
        );
      } else {
        await service.enrol(
          studentId: widget.student.id,
          groupId: groupId,
          monthlyPrice: int.tryParse(_draft.price.text.trim()) ?? 0,
          discountType: _draft.discountType,
          discountValue: int.tryParse(_draft.discount.text.trim()) ?? 0,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on ValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        // أخطاء السعر والتخفيض عند حقليهما، وغيرها (المجموعة) أسفل النموذج.
        _errors = {
          for (final entry in e.errors.entries)
            RegistrationService.choiceField(0, entry.key): entry.value,
        };
        _formError = e.errors[EnrolmentService.fieldGroup];
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = ref.watch(subjectsProvider).value ?? const <SubjectItem>[];
    final levelId = widget.student.levelId;
    final offered = [
      for (final s in subjects)
        if (levelId == null ||
            s.subject.levelId == null ||
            s.subject.levelId == levelId)
          s,
    ];
    final p = context.palette;
    return ClayDialog(
      title: 'إضافة مادة',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SubjectChoiceCard(
            index: 0,
            draft: _draft,
            subjects: offered,
            errors: _errors,
            onChanged: () => setState(() {}),
            onRemove: null,
          ),
          if (_formError != null)
            Text(
              _formError!,
              style: Theme.of(context).textTheme.bodySmall!
                  .copyWith(color: p.status.danger),
            ),
        ],
      ),
      actions: [
        ClayButton(label: 'إضافة', loading: _saving, onPressed: _submit),
        ClayButton(
          label: 'إلغاء',
          kind: ClayButtonKind.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
