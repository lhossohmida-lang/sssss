import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'student_picker.dart';

/// تلاميذ الفوج ووضع تسديد دورته الحالية (ويُعاد جلبه بعد كل إضافة أو دفعة).
final groupSetupRowsProvider = FutureProvider.autoDispose
    .family<List<GroupSetupRow>, String>(
      (ref, groupId) => ref.watch(groupSetupServiceProvider).students(groupId),
    );

/// عدد حصص الدورة الحالية التي سُجِّلت (المنعقدة).
final groupSetupHeldProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, groupId) => ref.watch(groupSetupServiceProvider).heldSessions(groupId),
);

/// سعر دورة الفوج للتلميذ (سعر مادته).
final groupSetupPriceProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, groupId) => ref.watch(groupSetupServiceProvider).priceOfGroup(groupId),
);

/// إعداد الفوج من صفحة واحدة: تلاميذه (يُنشأ كل تلميذ بحساب وليّه ورسالة بياناته
/// ويُحدَّد ما سُدِّد من دورته الحالية)، وحضورهم السابق، وتسديد الباقي. تُفتح بعد
/// إنشاء فوج، ومن تفاصيل أي فوج.
class GroupSetupScreen extends ConsumerStatefulWidget {
  const GroupSetupScreen({required this.groupId, this.firstDate, super.key});

  final String groupId;

  /// تاريخ أول حصة (`YYYY-MM-DD`) الذي أُدخل عند إنشاء الفوج، يُنقل إلى شاشة الحضور
  /// السابق فتبني الحصص المقررة منه.
  final String? firstDate;

  @override
  ConsumerState<GroupSetupScreen> createState() => _GroupSetupScreenState();
}

class _GroupSetupScreenState extends ConsumerState<GroupSetupScreen> {
  void _refresh() {
    ref
      ..invalidate(groupSetupRowsProvider(widget.groupId))
      ..invalidate(groupSetupHeldProvider(widget.groupId));
  }

  void _note(String message) {
    // الرسالة الأحدث تحلّ محل السابقة بدل أن تنتظر دورها في الطابور.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
      );
  }

  Future<void> _addStudent() async {
    final added = await showClayDialog<bool>(
      context,
      title: 'إضافة تلميذ إلى الفوج',
      content: _AddStudentForm(
        groupId: widget.groupId,
        // من لا يملك «استلام المال» يُضيف التلميذ دون تسجيل دفعة.
        canPay: ref.can(PermissionModule.receiveMoney, PermissionAction.use),
        onAdded: (result) {
          _refresh();
          _note(_addedMessage(result));
        },
      ),
    );
    if (added == true) _refresh();
  }

  static String _addedMessage(GroupSetupResult result) {
    final name = '${result.student.firstName} ${result.student.lastName}';
    final account = result.parentAccount.created
        ? 'وأُرسلت بيانات دخول وليّه برسالة'
        : 'ورُبط بحساب وليّه القائم';
    final payment = result.paidNow > 0
        ? '، وسُدِّد ${Money.format(result.paidNow)}'
        : '';
    final failure = result.paymentError == null
        ? ''
        : '. تعذّر تسجيل الدفعة: ${result.paymentError}';
    return 'أُضيف $name $account$payment$failure';
  }

  /// ينسب تلاميذ مسجَّلين من قبل إلى الفوج: يُختارون من قائمة المدرسة ببحث، فيُضافون بسعر
  /// مادة الفوج (والملتحق في منتصف الدورة يأخذ رصيد ما فاته). التسديد من زر «تسديد» بعدها.
  Future<void> _addExisting() async {
    final inGroup = {
      for (final row
          in ref.read(groupSetupRowsProvider(widget.groupId)).value ??
              const <GroupSetupRow>[])
        row.studentId,
    };
    final picked = await pickExistingStudents(context, exclude: inGroup);
    if (picked == null || picked.isEmpty || !mounted) return;
    try {
      final result = await ref.read(groupSetupServiceProvider).addExisting(
        widget.groupId,
        [for (final student in picked) student.id],
      );
      if (!mounted) return;
      _refresh();
      _note(_existingMessage(result, picked));
    } on ValidationException catch (e) {
      if (mounted) _note(e.toString());
    }
  }

  static String _existingMessage(
    ExistingStudentsResult result,
    List<StudentListItem> picked,
  ) {
    final names = {for (final s in picked) s.id: s.fullName};
    final count = result.added.length;
    final added = switch (count) {
      0 => 'لم يُضَف أحد',
      1 => 'أُضيف ${names[result.added.single]} إلى الفوج',
      2 => 'أُضيف تلميذان إلى الفوج',
      <= 10 => 'أُضيف $count تلاميذ إلى الفوج',
      _ => 'أُضيف $count تلميذاً إلى الفوج',
    };
    if (result.skipped.isEmpty) return added;
    final skipped = [
      for (final e in result.skipped.entries)
        '${names[e.key] ?? ''} (${e.value})',
    ].join('، ');
    return '$added. تعذّرت إضافة: $skipped';
  }

  Future<void> _pay(GroupSetupRow row) async {
    final paid = await showClayDialog<bool>(
      context,
      title: 'تسديد ${row.name}',
      content: _PayForm(groupId: widget.groupId, row: row),
    );
    if (paid == true) {
      _refresh();
      if (mounted) _note('سُجّلت الدفعة وأُرسل وصلها إلى الوليّ');
    }
  }

  /// تاريخ أول حصة المنقول من نموذج الإنشاء إن كان تاريخاً صالحاً.
  String? get _firstDate {
    final value = widget.firstDate;
    if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    return DateKey.of(DateKey.parse(value)) == value ? value : null;
  }

  Future<void> _openPast() async {
    final from = _firstDate;
    await context.push(
      '/groups/${widget.groupId}/past${from == null ? '' : '?from=$from'}',
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final item = ref.watch(groupItemProvider(widget.groupId));
    final rows = ref.watch(groupSetupRowsProvider(widget.groupId));
    final held = ref.watch(groupSetupHeldProvider(widget.groupId)).value ?? 0;
    final canAdd = ref.can(PermissionModule.students, PermissionAction.add);
    final canReceive = ref.can(
      PermissionModule.receiveMoney,
      PermissionAction.use,
    );
    final canPast = ref.can(PermissionModule.attendance, PermissionAction.edit);
    final students = rows.value ?? const <GroupSetupRow>[];

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
      appBar: const ClayAppBar(title: 'إعداد الفوج', showBack: true),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            children: [
              if (item != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: ClaySpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.subjectName} · الفوج ${item.number}',
                        style: text.titleLarge,
                      ),
                      Text(
                        '${item.teacherName} · ${item.scheduleText}',
                        style: text.bodyMedium!.copyWith(color: p.textMuted),
                      ),
                    ],
                  ),
                ),
              Text(
                'أضف تلاميذ الفوج (جدداً، أو ممن سُجّلوا من قبل باختيارهم ببحث)، '
                'وسجّل حضورهم السابق إن كانت الدورة بدأت قبل استعمال النظام، '
                'وحدّد ما سدّدوه، كل ذلك من هذه الصفحة.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: ClaySpacing.lg),
              card('1. التلاميذ', [
                if (rows.hasError)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rows.error is StateError
                            ? (rows.error! as StateError).message
                            : 'تعذّر عرض تلاميذ الفوج',
                        style: text.bodyMedium!.copyWith(
                          color: p.status.danger,
                        ),
                      ),
                      TextButton(
                        onPressed: _refresh,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  )
                else if (rows.isLoading)
                  const Padding(
                    padding: EdgeInsets.all(ClaySpacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (students.isEmpty)
                  Text(
                    'لا تلاميذ في الفوج بعد.',
                    style: text.bodyMedium!.copyWith(color: p.textMuted),
                  )
                else
                  for (final row in students)
                    ClayListTile(
                      title: row.name,
                      subtitle: 'الوليّ ${row.parentPhone}',
                      trailing: [
                        if (row.isSettled)
                          const ClayBadge(
                            label: 'مسدّدة',
                            tone: ClayTone.success,
                          )
                        else ...[
                          ClayBadge(
                            label: 'الباقي ${Money.format(row.remaining)}',
                            tone: ClayTone.warning,
                          ),
                          if (canReceive)
                            TextButton(
                              onPressed: () => _pay(row),
                              child: const Text('تسديد'),
                            ),
                        ],
                      ],
                    ),
                if (canAdd) ...[
                  const SizedBox(height: ClaySpacing.md),
                  ClayButton(
                    label: 'إضافة تلميذ',
                    icon: ClayIcons.add,
                    expand: true,
                    onPressed: _addStudent,
                  ),
                  const SizedBox(height: ClaySpacing.sm),
                  ClayButton(
                    label: 'إضافة تلاميذ موجودين',
                    icon: ClayIcons.students,
                    kind: ClayButtonKind.secondary,
                    expand: true,
                    onPressed: _addExisting,
                  ),
                ],
              ]),
              if (canPast)
                card('2. الحضور السابق', [
                  Text(
                    held == 0
                        ? 'لم يُسجَّل حضور سابق في الدورة الحالية.'
                        : 'سُجّل حضور $held حصة في الدورة الحالية.',
                    style: text.bodyMedium,
                  ),
                  if (_firstDate != null) ...[
                    const SizedBox(height: ClaySpacing.xs),
                    Text(
                      'تاريخ أول حصة الذي أدخلته: $_firstDate. تُبنى منه «الحصص '
                      'المقررة» عند تسجيل الحضور السابق.',
                      style: text.bodySmall!.copyWith(color: p.textMuted),
                    ),
                  ],
                  const SizedBox(height: ClaySpacing.md),
                  ClayButton(
                    label: 'تسجيل الحضور السابق',
                    icon: ClayIcons.attendance,
                    kind: ClayButtonKind.secondary,
                    expand: true,
                    onPressed: students.isEmpty ? null : _openPast,
                  ),
                  if (students.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: ClaySpacing.sm),
                      child: Text(
                        'أضف تلميذاً واحداً على الأقل أولاً.',
                        style: text.bodySmall!.copyWith(color: p.textMuted),
                      ),
                    ),
                ]),
              ClayButton(
                label: 'تم',
                icon: ClayIcons.check,
                expand: true,
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/groups'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// نموذج إضافة تلميذ: بياناته وبيانات وليّه، وما سُدِّد من الدورة الحالية.
class _AddStudentForm extends ConsumerStatefulWidget {
  const _AddStudentForm({
    required this.groupId,
    required this.canPay,
    required this.onAdded,
  });

  final String groupId;

  /// هل يُعرض اختيار ما سُدِّد من الدورة الحالية.
  final bool canPay;
  final ValueChanged<GroupSetupResult> onAdded;

  @override
  ConsumerState<_AddStudentForm> createState() => _AddStudentFormState();
}

class _AddStudentFormState extends ConsumerState<_AddStudentForm> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _parent = TextEditingController();
  final _phone = TextEditingController();
  final _partial = TextEditingController();
  CyclePaymentChoice _payment = CyclePaymentChoice.unpaid;
  bool _busy = false;
  Map<String, String> _errors = const {};
  String? _formError;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _parent.dispose();
    _phone.dispose();
    _partial.dispose();
    super.dispose();
  }

  /// يمسح بيانات التلميذ ويُبقي الوليّ لأخ يليه، لتسهيل إضافة الإخوة.
  void _afterAdd() {
    _first.clear();
    _last.clear();
    _partial.clear();
    _payment = CyclePaymentChoice.unpaid;
    _errors = const {};
  }

  Future<void> _submit({required bool another}) async {
    if (_busy) return;
    final amount = int.tryParse(_partial.text.trim()) ?? 0;
    if (_payment == CyclePaymentChoice.partial && amount <= 0) {
      setState(
        () => _errors = {GroupSetupService.fieldAmount: 'أدخل المبلغ المسدَّد'},
      );
      return;
    }
    setState(() {
      _busy = true;
      _errors = const {};
      _formError = null;
    });
    try {
      final settings = await ref.read(settingsServiceProvider).load();
      final result = await ref
          .read(groupSetupServiceProvider)
          .addStudent(
            widget.groupId,
            GroupSetupStudent(
              firstName: _first.text,
              lastName: _last.text,
              parentName: _parent.text,
              parentPhone: _phone.text,
              payment: _payment,
              partialAmount: amount,
            ),
            settings: settings,
          );
      widget.onAdded(result);
      if (!mounted) return;
      if (another) {
        setState(_afterAdd);
      } else {
        Navigator.of(context).pop(true);
      }
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } on AuthFailureException catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final price = ref.watch(groupSetupPriceProvider(widget.groupId)).value;
    String full() => price == null
        ? 'مسدّدة كاملة'
        : 'مسدّدة كاملة (${Money.format(price)})';
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClayTextField(
            controller: _first,
            label: 'الاسم',
            error: _errors[RegistrationService.fieldFirstName],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: ClaySpacing.md),
          ClayTextField(
            controller: _last,
            label: 'اللقب',
            error: _errors[RegistrationService.fieldLastName],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: ClaySpacing.md),
          ClayTextField(
            controller: _parent,
            label: 'اسم الوليّ',
            error: _errors[RegistrationService.fieldParentName],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: ClaySpacing.md),
          ClayTextField(
            controller: _phone,
            label: 'هاتف الوليّ',
            hint: '0550123456',
            error: _errors[RegistrationService.fieldPhone],
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            textInputAction: TextInputAction.next,
            helper: 'تصله رسالة ببيانات دخول حسابه تلقائياً',
          ),
          if (widget.canPay) ...[
            const SizedBox(height: ClaySpacing.lg),
            Text('الدورة الحالية', style: text.titleSmall),
            const SizedBox(height: ClaySpacing.sm),
            Wrap(
              spacing: ClaySpacing.sm,
              runSpacing: ClaySpacing.sm,
              children: [
                ClayChip(
                  label: 'غير مسدّدة',
                  selected: _payment == CyclePaymentChoice.unpaid,
                  onTap: () =>
                      setState(() => _payment = CyclePaymentChoice.unpaid),
                ),
                ClayChip(
                  label: full(),
                  selected: _payment == CyclePaymentChoice.full,
                  onTap: () =>
                      setState(() => _payment = CyclePaymentChoice.full),
                ),
                ClayChip(
                  label: 'سُدِّد جزء منها',
                  selected: _payment == CyclePaymentChoice.partial,
                  onTap: () =>
                      setState(() => _payment = CyclePaymentChoice.partial),
                ),
              ],
            ),
            if (_payment == CyclePaymentChoice.partial) ...[
              const SizedBox(height: ClaySpacing.md),
              ClayTextField(
                controller: _partial,
                label: 'المبلغ المسدَّد (دج)',
                error: _errors[GroupSetupService.fieldAmount],
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
              ),
            ] else if (_errors[GroupSetupService.fieldAmount] != null)
              Padding(
                padding: const EdgeInsets.only(top: ClaySpacing.sm),
                child: Text(
                  _errors[GroupSetupService.fieldAmount]!,
                  style: text.bodySmall!.copyWith(color: p.status.danger),
                ),
              ),
          ],
          if (_formError != null)
            Padding(
              padding: const EdgeInsets.only(top: ClaySpacing.sm),
              child: Text(
                _formError!,
                style: text.bodySmall!.copyWith(color: p.status.danger),
              ),
            ),
          const SizedBox(height: ClaySpacing.lg),
          ClayButton(
            label: 'حفظ',
            expand: true,
            loading: _busy,
            onPressed: () => _submit(another: false),
          ),
          const SizedBox(height: ClaySpacing.sm),
          ClayButton(
            label: 'حفظ وإضافة تلميذ آخر',
            kind: ClayButtonKind.secondary,
            expand: true,
            onPressed: _busy ? null : () => _submit(another: true),
          ),
          const SizedBox(height: ClaySpacing.sm),
          ClayButton(
            label: 'إغلاق',
            kind: ClayButtonKind.secondary,
            expand: true,
            onPressed: _busy ? null : () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }
}

/// تسديد جزء أو كل ما بقي من الدورة الحالية لتلميذ.
class _PayForm extends ConsumerStatefulWidget {
  const _PayForm({required this.groupId, required this.row});

  final String groupId;
  final GroupSetupRow row;

  @override
  ConsumerState<_PayForm> createState() => _PayFormState();
}

class _PayFormState extends ConsumerState<_PayForm> {
  late final TextEditingController _amount = TextEditingController(
    text: '${widget.row.remaining}',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(groupSetupServiceProvider)
          .payCurrentCycle(
            groupId: widget.groupId,
            studentId: widget.row.studentId,
            amount: amount,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ValidationException catch (e) {
      if (mounted) {
        setState(() => _error = e.errors.values.firstOrNull ?? 'تعذّر التسديد');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'الباقي من الدورة الحالية: ${Money.format(widget.row.remaining)}',
          style: text.bodyMedium,
        ),
        const SizedBox(height: ClaySpacing.md),
        ClayTextField(
          controller: _amount,
          label: 'المبلغ (دج)',
          error: _error,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: ClaySpacing.lg),
        ClayButton(
          label: 'تسديد',
          expand: true,
          loading: _busy,
          onPressed: _submit,
        ),
        const SizedBox(height: ClaySpacing.sm),
        ClayButton(
          label: 'إلغاء',
          kind: ClayButtonKind.secondary,
          expand: true,
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
