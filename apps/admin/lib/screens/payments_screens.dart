import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

import 'receipt_action.dart';

/// «2026-11-14 10:30» من وقت بالمللي ثانية (بالتوقيت المحلي).
String paymentDateText(int millis) {
  final t = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '${DateKey.of(t)} $hh:$mm';
}

/// تبويب المدفوعات: ما استُلم اليوم، وقائمة الدفعات مع بحث بالتلميذ أو رقم
/// الوصل وتصفية بالنوع، وزر تسجيل دفعة.
class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  final _scroll = ScrollController();
  Timer? _debounce;
  String _query = '';
  PaymentType? _type;
  int _limit = PaymentService.pageSize;
  PaymentPage? _last;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    final page = _last;
    if (page == null || !page.hasMore) return;
    if (_scroll.position.extentAfter < 600 && page.items.length >= _limit) {
      setState(() => _limit += PaymentService.pageSize);
    }
  }

  void _search(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = value.trim();
        _limit = PaymentService.pageSize;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _setType(PaymentType? type) => setState(() {
    _type = type;
    _limit = PaymentService.pageSize;
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final state = ref.watch(
      paymentPageProvider((query: _query, type: _type, limit: _limit)),
    );
    state.whenData((page) => _last = page);
    final page = state.value ?? _last;
    final today = ref.watch(receivedTodayProvider).value ?? 0;
    final canReceive = ref.can(
      PermissionModule.receiveMoney,
      PermissionAction.use,
    );

    Widget body;
    if (page == null) {
      body = state.hasError
          ? ClayErrorView(
              message: 'تعذّرت قراءة المدفوعات',
              onRetry: () => ref.invalidate(paymentPageProvider),
            )
          : const ClaySkeletonList();
    } else if (page.items.isEmpty) {
      final filtered = _query.isNotEmpty || _type != null;
      body = ClayEmptyView(
        title: filtered ? 'لا نتائج مطابقة' : 'لا مدفوعات بعد',
        message: filtered
            ? 'جرّب اسماً آخر أو رقم وصل مختلفاً'
            : 'تظهر هنا الدفعات التي تُسجَّل بوصولاتها',
        icon: ClayIcons.payments,
      );
    } else {
      body = ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(
          horizontal: ClaySpacing.screenPadding,
        ),
        itemCount: page.items.length,
        itemExtent: 96,
        itemBuilder: (context, i) => _PaymentTile(item: page.items[i]),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ClaySpacing.screenPadding,
            ClaySpacing.sm,
            ClaySpacing.screenPadding,
            ClaySpacing.xs,
          ),
          child: ClayCard(
            flat: true,
            child: Row(
              children: [
                Expanded(child: Text('استُلم اليوم', style: text.titleSmall)),
                Text(Money.format(today), style: text.titleMedium),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ClaySpacing.screenPadding,
          ),
          child: ClayTextField(
            hint: 'ابحث باسم التلميذ أو رقم الوصل',
            prefixIcon: ClayIcons.search,
            onChanged: _search,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ClaySpacing.screenPadding,
            vertical: ClaySpacing.xs,
          ),
          child: Wrap(
            spacing: ClaySpacing.sm,
            children: [
              ClayChip(
                label: 'الكل',
                selected: _type == null,
                onTap: () => _setType(null),
              ),
              for (final type in PaymentType.values)
                ClayChip(
                  label: type.label,
                  selected: _type == type,
                  onTap: () => _setType(type),
                ),
            ],
          ),
        ),
        if (page != null && page.items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaySpacing.screenPadding,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                '${page.total} دفعة',
                style: text.bodySmall!.copyWith(color: p.textMuted),
              ),
            ),
          ),
        Expanded(child: body),
        if (canReceive)
          Padding(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            child: ClayButton(
              label: 'تسجيل دفعة',
              icon: ClayIcons.add,
              expand: true,
              onPressed: () => context.push('/payments/new'),
            ),
          ),
      ],
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.item});

  final PaymentListItem item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ClayListTile(
      title: item.studentName,
      subtitle:
          '${item.description}\n'
          '${item.payment.receiptNumber} · '
          '${paymentDateText(item.payment.createdAt)}',
      subtitleLines: 2,
      onTap: () => context.push('/payments/${item.id}'),
      trailing: [
        Text(Money.format(item.payment.amount), style: text.titleSmall),
      ],
    );
  }
}

/// تسجيل دفعة: اختيار التلميذ، ثم ما يدفعه (شهر / نقل / حقوق تسجيل)
/// والمبلغ (كاملاً أو جزءاً)، ثم الحفظ بوصل مرقَّم.
class PaymentFormScreen extends ConsumerStatefulWidget {
  const PaymentFormScreen({this.studentId, super.key});

  /// تلميذ مختار مسبقاً (من ملفه)؛ وإلا يُبحث عنه.
  final String? studentId;

  @override
  ConsumerState<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends ConsumerState<PaymentFormScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _studentId;
  String? _studentName;
  PayableItem? _selected;
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _studentId = widget.studentId;
    if (_studentId != null) unawaited(_loadName());
  }

  Future<void> _loadName() async {
    final db = ref.read(runtimeProvider).db;
    final student = await (db.select(
      db.students,
    )..where((s) => s.id.equals(_studentId!))).getSingleOrNull();
    if (!mounted || student == null) return;
    setState(() => _studentName = '${student.firstName} ${student.lastName}');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _pickStudent(StudentListItem item) => setState(() {
    _studentId = item.id;
    _studentName = item.fullName;
    _selected = null;
    _amount.clear();
    _errors = const {};
  });

  void _select(PayableItem item) => setState(() {
    _selected = item;
    _amount.text = '${item.remaining}';
    _errors = const {};
  });

  Future<void> _save() async {
    final item = _selected;
    final studentId = _studentId;
    if (item == null || studentId == null) {
      setState(() => _errors = {PaymentService.fieldItem: 'اختر ما يدفعه'});
      return;
    }
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      final paid = await ref
          .read(paymentServiceProvider)
          .record(
            studentId: studentId,
            type: item.type,
            groupId: item.groupId,
            cycleNumber: item.cycleNumber,
            periodKey: item.periodKey,
            amount: int.tryParse(_amount.text.trim()) ?? 0,
            note: _note.text,
          );
      ref.invalidate(payablesProvider(studentId));
      if (mounted) context.pushReplacement('/payments/${paid.id}');
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return Scaffold(
      appBar: const ClayAppBar(title: 'تسجيل دفعة', showBack: true),
      body: _studentId == null
          ? _StudentPicker(
              query: _query,
              onSearch: _search,
              onPick: _pickStudent,
            )
          : ListView(
              padding: const EdgeInsets.all(ClaySpacing.screenPadding),
              children: [
                ClayCard(
                  child: Row(
                    children: [
                      ClayAvatar(name: _studentName ?? '', size: 44),
                      const SizedBox(width: ClaySpacing.md),
                      Expanded(
                        child: Text(
                          _studentName ?? '',
                          style: text.titleMedium,
                        ),
                      ),
                      if (widget.studentId == null)
                        TextButton(
                          onPressed: () => setState(() {
                            _studentId = null;
                            _studentName = null;
                            _selected = null;
                            _query = '';
                          }),
                          child: const Text('تغيير'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: ClaySpacing.lg),
                Text('ما يدفعه', style: text.titleSmall),
                const SizedBox(height: ClaySpacing.sm),
                ref
                    .watch(payablesProvider(_studentId!))
                    .when(
                      loading: () => const ClayLoadingView(),
                      error: (_, _) => ClayErrorView(
                        message: 'تعذّر حساب المستحقات',
                        onRetry: () => ref.invalidate(payablesProvider),
                      ),
                      data: (items) {
                        if (items.isEmpty) {
                          return const ClayEmptyView(
                            title: 'لا شيء مستحق',
                            message: 'سدّد هذا التلميذ كل ما عليه',
                            icon: ClayIcons.check,
                          );
                        }
                        return Column(
                          children: [
                            for (final item in items)
                              _PayableTile(
                                item: item,
                                selected: _selected?.key == item.key,
                                onTap: () => _select(item),
                              ),
                          ],
                        );
                      },
                    ),
                if (_errors[PaymentService.fieldItem] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: ClaySpacing.xs),
                    child: Text(
                      _errors[PaymentService.fieldItem]!,
                      style: text.bodySmall!.copyWith(color: p.status.danger),
                    ),
                  ),
                if (_selected != null) ...[
                  const SizedBox(height: ClaySpacing.lg),
                  ClayTextField(
                    controller: _amount,
                    label: 'المبلغ المدفوع (${Money.currency})',
                    helper:
                        'الباقي ${Money.format(_selected!.remaining)} — '
                        'يجوز دفع جزء منه',
                    error: _errors[PaymentService.fieldAmount],
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  if (_selected!.type == PaymentType.month) ...[
                    const SizedBox(height: ClaySpacing.md),
                    ClayTextField(controller: _note, label: 'ملاحظة (اختياري)'),
                  ],
                  const SizedBox(height: ClaySpacing.xl),
                  ClayButton(
                    label: 'تسجيل الدفعة',
                    icon: ClayIcons.check,
                    expand: true,
                    loading: _saving,
                    onPressed: _save,
                  ),
                ],
              ],
            ),
    );
  }
}

/// بحث عن التلميذ لاختياره عند تسجيل الدفعة.
class _StudentPicker extends ConsumerWidget {
  const _StudentPicker({
    required this.query,
    required this.onSearch,
    required this.onPick,
  });

  final String query;
  final ValueChanged<String> onSearch;
  final ValueChanged<StudentListItem> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(studentPageProvider((query: query, limit: 30)));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(ClaySpacing.screenPadding),
          child: ClayTextField(
            hint: 'ابحث عن التلميذ بالاسم أو هاتف الوليّ',
            prefixIcon: ClayIcons.search,
            autofocus: true,
            onChanged: onSearch,
          ),
        ),
        Expanded(
          child: page.when(
            loading: () => const ClayLoadingView(),
            error: (_, _) => ClayErrorView(
              message: 'تعذّرت قراءة التلاميذ',
              onRetry: () => ref.invalidate(studentPageProvider),
            ),
            data: (data) {
              if (data.items.isEmpty) {
                return ClayEmptyView(
                  title: query.isEmpty
                      ? 'لا يوجد تلاميذ بعد'
                      : 'لا نتائج مطابقة للبحث',
                  icon: ClayIcons.students,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: ClaySpacing.screenPadding,
                ),
                itemCount: data.items.length,
                itemExtent: 72,
                itemBuilder: (context, i) {
                  final item = data.items[i];
                  return ClayListTile(
                    leading: ClayAvatar(name: item.fullName),
                    title: item.fullName,
                    subtitle: item.student.parentPhone,
                    onTap: () => onPick(item),
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

class _PayableTile extends StatelessWidget {
  const _PayableTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final PayableItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final parts = [
      'المطلوب ${Money.format(item.total)}',
      if (item.paid > 0) 'دُفع ${Money.format(item.paid)}',
      if (item.credits > 0) 'بعد خصم رصيد ${Money.format(item.credits)}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: ClaySpacing.sm),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${item.label}، الباقي ${Money.format(item.remaining)}',
        excludeSemantics: true,
        child: ClayCard(
          flat: !selected,
          onTap: onTap,
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? p.accent : p.textMuted,
              ),
              const SizedBox(width: ClaySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label, style: text.titleSmall),
                    Text(
                      parts.join(' · '),
                      style: text.bodySmall!.copyWith(color: p.textMuted),
                    ),
                  ],
                ),
              ),
              Text(
                'الباقي ${Money.format(item.remaining)}',
                style: text.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// تفاصيل دفعة (الوصل): رقمه وتاريخه والتلميذ وما دُفع عنه والمبلغ
/// والباقي والمستلِم، مع عرض الوصل PDF للطباعة أو المشاركة.
class PaymentDetailsScreen extends ConsumerWidget {
  const PaymentDetailsScreen({required this.paymentId, super.key});

  final String paymentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final detail = ref.watch(paymentDetailProvider(paymentId));
    return Scaffold(
      appBar: const ClayAppBar(title: 'الوصل', showBack: true),
      body: detail.when(
        loading: () => const ClayLoadingView(),
        error: (_, _) => ClayErrorView(
          message: 'تعذّرت قراءة الدفعة',
          onRetry: () => ref.invalidate(paymentDetailProvider),
        ),
        data: (d) {
          if (d == null) {
            return const ClayEmptyView(title: 'هذه الدفعة غير موجودة');
          }
          final payment = d.payment;
          Widget row(String label, String value) => Padding(
            padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    label,
                    style: text.bodyMedium!.copyWith(color: p.textMuted),
                  ),
                ),
                Expanded(child: Text(value, style: text.bodyLarge)),
              ],
            ),
          );
          return ListView(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            children: [
              ClayCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        payment.receiptNumber,
                        style: text.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: ClaySpacing.sm),
                    Text(
                      Money.format(payment.amount),
                      style: text.headlineMedium!.copyWith(color: p.accent),
                    ),
                    const SizedBox(height: ClaySpacing.md),
                    row('التلميذ', d.item.studentName),
                    row('عن', d.item.description),
                    row('التاريخ', paymentDateText(payment.createdAt)),
                    if (d.remaining != null)
                      row(
                        'الباقي',
                        d.remaining == 0
                            ? 'مسدَّد بالكامل'
                            : Money.format(d.remaining!),
                      ),
                    row('المستلِم', d.receivedByName),
                    if (payment.note.isNotEmpty) row('ملاحظة', payment.note),
                  ],
                ),
              ),
              const SizedBox(height: ClaySpacing.md),
              ClayButton(
                label: 'عرض الوصل وطباعته',
                icon: ClayIcons.print,
                expand: true,
                onPressed: () => showReceipt(context, ref, d),
              ),
              const SizedBox(height: ClaySpacing.sm),
              ClayButton(
                label: 'ملف التلميذ',
                icon: ClayIcons.students,
                kind: ClayButtonKind.secondary,
                expand: true,
                onPressed: () => context.push('/students/${d.studentId}'),
              ),
            ],
          );
        },
      ),
    );
  }
}
