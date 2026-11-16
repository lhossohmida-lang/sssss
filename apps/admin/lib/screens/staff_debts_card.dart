import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// بطاقة «الديون على المدرسة» في ملف أستاذ أو عامل (السائق عامل): تُضاف لها
/// مبالغ مستحقة لم تُسلَّم بعد (كأجور ما قبل استعمال النظام)، وتُسدَّد كلها أو بعضها
/// فيخرج التسديد من الصندوق في تقرير الشهر. لصاحب المدرسة وحده.
class StaffDebtsCard extends ConsumerWidget {
  const StaffDebtsCard({
    required this.kind,
    required this.staffId,
    required this.staffName,
    super.key,
  });

  final StaffKind kind;
  final String staffId;
  final String staffName;

  Future<void> _open(
    BuildContext context, {
    required bool payment,
    required int balance,
  }) => showDialog<void>(
    context: context,
    builder: (_) => StaffDebtDialog(
      kind: kind,
      staffId: staffId,
      staffName: staffName,
      payment: payment,
      balance: balance,
    ),
  );

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    StaffDebtRow entry,
  ) async {
    final isPayment = entry.kind == StaffDebtKind.payment.code;
    final ok = await showClayConfirm(
      context,
      title: isPayment ? 'حذف التسديد' : 'حذف الدين',
      message: isPayment
          ? 'سيُحذف تسديد ${Money.format(entry.amount)} ومصروفه من تقرير '
                'الشهر، ويعود المبلغ ديناً قائماً.'
          : 'سيُحذف هذا الدين (${Money.format(entry.amount)}) من الدفتر.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(staffDebtServiceProvider).remove(entry.id);
    } on ValidationException catch (e) {
      if (!context.mounted) return;
      await showClayDialog<void>(
        context,
        title: 'تعذّر الحذف',
        message: e.toString(),
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
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(
      sessionProvider.select((s) => s.value?.role == UserRole.owner),
    );
    if (!isOwner) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final summary = ref.watch(
      staffDebtProvider((kind: kind, staffId: staffId)),
    );
    return ClayCard(
      child: summary.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(ClaySpacing.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => const Text('تعذّرت قراءة دفتر الديون'),
        data: (data) {
          final balance = data.balance;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('الديون على المدرسة', style: text.titleMedium),
                  ),
                  ClayBadge(
                    label: balance > 0 ? 'دين قائم' : 'لا دين',
                    tone: balance > 0 ? ClayTone.warning : ClayTone.success,
                  ),
                ],
              ),
              const SizedBox(height: ClaySpacing.xs),
              Text(
                'مبالغ مستحقة لـ$staffName على المدرسة لم تُسلَّم بعد، كأجر '
                'سابق. تدخل تسديداتها في مصاريف شهر التسديد.',
                style: text.bodySmall!.copyWith(color: p.textMuted),
              ),
              const SizedBox(height: ClaySpacing.md),
              Row(
                children: [
                  Text(
                    'المتبقي',
                    style: text.bodyMedium!.copyWith(color: p.textMuted),
                  ),
                  const SizedBox(width: ClaySpacing.md),
                  Expanded(
                    child: Text(
                      Money.format(balance),
                      textAlign: TextAlign.end,
                      style: text.headlineSmall!.copyWith(
                        color: balance > 0 ? p.status.danger : p.text,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ClaySpacing.md),
              Wrap(
                spacing: ClaySpacing.md,
                runSpacing: ClaySpacing.sm,
                children: [
                  ClayButton(
                    label: 'إضافة دين',
                    icon: ClayIcons.add,
                    kind: ClayButtonKind.secondary,
                    onPressed: () =>
                        _open(context, payment: false, balance: balance),
                  ),
                  ClayButton(
                    label: 'تسديد',
                    icon: ClayIcons.payments,
                    onPressed: balance > 0
                        ? () => _open(context, payment: true, balance: balance)
                        : null,
                  ),
                ],
              ),
              if (data.entries.isNotEmpty) ...[
                const SizedBox(height: ClaySpacing.lg),
                Text('السجل', style: text.titleSmall),
                for (final entry in data.entries)
                  _EntryRow(
                    entry: entry,
                    onDelete: () => _remove(context, ref, entry),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.onDelete});

  final StaffDebtRow entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final isPayment = entry.kind == StaffDebtKind.payment.code;
    final label = StaffDebtKind.fromCode(entry.kind).label;
    return Padding(
      padding: const EdgeInsets.only(top: ClaySpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.note.isEmpty ? label : '$label · ${entry.note}',
                  style: text.bodyMedium,
                ),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    entry.date,
                    style: text.bodySmall!.copyWith(color: p.textMuted),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${isPayment ? '−' : '+'} ${Money.format(entry.amount)}',
            style: text.titleSmall!.copyWith(
              color: isPayment ? p.status.success : p.status.danger,
            ),
          ),
          IconButton(
            tooltip: isPayment ? 'حذف التسديد' : 'حذف الدين',
            icon: const Icon(ClayIcons.delete),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// نافذة إضافة دين أو تسديد: المبلغ والتاريخ وملاحظة اختيارية.
class StaffDebtDialog extends ConsumerStatefulWidget {
  const StaffDebtDialog({
    required this.kind,
    required this.staffId,
    required this.staffName,
    required this.payment,
    required this.balance,
    super.key,
  });

  final StaffKind kind;
  final String staffId;
  final String staffName;

  /// تسديد (وإلا دين جديد).
  final bool payment;

  /// المتبقي الحالي؛ يملأ مبلغ التسديد افتراضياً.
  final int balance;

  @override
  ConsumerState<StaffDebtDialog> createState() => _StaffDebtDialogState();
}

class _StaffDebtDialogState extends ConsumerState<StaffDebtDialog> {
  late final _amount = TextEditingController(
    text: widget.payment ? '${widget.balance}' : '',
  );
  late final _note = TextEditingController();
  late final _date = TextEditingController(text: DateKey.of(DateTime.now()));
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final current = DateTime.tryParse(_date.text) ?? DateTime.now();
    final picked = await showClayDatePicker(
      context,
      title: widget.payment ? 'تاريخ التسديد' : 'تاريخ استحقاق الدين',
      initial: current,
    );
    if (picked != null) setState(() => _date.text = DateKey.of(picked));
  }

  Future<void> _submit() async {
    if (_saving) return;
    final amount = int.tryParse(_amount.text.trim());
    if (amount == null) {
      setState(() => _errors = {'amount': 'اكتب المبلغ بالأرقام'});
      return;
    }
    setState(() {
      _saving = true;
      _errors = const {};
    });
    final service = ref.read(staffDebtServiceProvider);
    try {
      if (widget.payment) {
        await service.pay(
          kind: widget.kind,
          staffId: widget.staffId,
          amount: amount,
          date: _date.text,
          note: _note.text,
        );
      } else {
        await service.addDebt(
          kind: widget.kind,
          staffId: widget.staffId,
          amount: amount,
          date: _date.text,
          note: _note.text,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } on Object {
      if (mounted) {
        setState(() => _errors = {'form': 'تعذّر الحفظ، حاول مرة أخرى'});
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return ClayDialog(
      title: widget.payment
          ? 'تسديد دين لـ${widget.staffName}'
          : 'إضافة دين لـ${widget.staffName}',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClayTextField(
            controller: _amount,
            label: 'المبلغ (${Money.currency})',
            helper: widget.payment
                ? 'المتبقي ${Money.format(widget.balance)}'
                : 'مبلغ مستحق له على المدرسة',
            error: _errors['amount'],
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            enabled: !_saving,
            autofocus: true,
          ),
          const SizedBox(height: ClaySpacing.md),
          ClayTextField(
            controller: _date,
            label: widget.payment ? 'تاريخ التسديد' : 'تاريخ الاستحقاق',
            error: _errors['date'],
            textDirection: TextDirection.ltr,
            readOnly: true,
            enabled: !_saving,
            prefixIcon: ClayIcons.schedule,
            onTap: _pickDate,
          ),
          const SizedBox(height: ClaySpacing.md),
          ClayTextField(
            controller: _note,
            label: 'ملاحظة (اختياري)',
            hint: widget.payment ? 'مثل: دفعة أولى' : 'مثل: أجر شهر أكتوبر',
            error: _errors['note'],
            maxLength: 200,
            enabled: !_saving,
          ),
          if (_errors['form'] != null || _errors['staff'] != null) ...[
            const SizedBox(height: ClaySpacing.sm),
            Text(
              _errors['form'] ?? _errors['staff']!,
              style: text.bodySmall!.copyWith(color: p.status.danger),
            ),
          ],
        ],
      ),
      actions: [
        ClayButton(
          label: widget.payment ? 'تسجيل التسديد' : 'إضافة الدين',
          loading: _saving,
          onPressed: _submit,
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

/// ديون الأساتذة والعمال: من له دين متبقٍّ ومجموع المتبقي (لصاحب المدرسة).
class StaffDebtsScreen extends ConsumerWidget {
  const StaffDebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final list = ref.watch(staffOutstandingProvider);
    return Scaffold(
      appBar: const ClayAppBar(title: 'ديون الأساتذة والعمال', showBack: true),
      body: list.when(
        loading: () => const ClayLoadingView(),
        error: (_, _) => ClayErrorView(
          message: 'تعذّرت قراءة الديون',
          onRetry: () => ref.invalidate(staffOutstandingProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const ClayEmptyView(
              title: 'لا ديون على المدرسة',
              message:
                  'تُضاف الديون من ملف الأستاذ أو العامل (السائق عامل) كأجر '
                  'سابق لم يُسلَّم.',
              icon: ClayIcons.dues,
            );
          }
          final total = items.fold(0, (sum, item) => sum + item.balance);
          return ListView(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            children: [
              ClayCard(
                child: Row(
                  children: [
                    Text(
                      'مجموع المتبقي',
                      style: text.bodyMedium!.copyWith(color: p.textMuted),
                    ),
                    const SizedBox(width: ClaySpacing.md),
                    Expanded(
                      child: Text(
                        Money.format(total),
                        textAlign: TextAlign.end,
                        style: text.headlineSmall!.copyWith(
                          color: p.status.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ClaySpacing.md),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: ClaySpacing.sm),
                  child: ClayListTile(
                    title: item.name,
                    subtitle: item.kind.label,
                    onTap: () => context.push(
                      item.kind == StaffKind.teacher
                          ? '/teachers/${item.staffId}'
                          : '/workers/${item.staffId}',
                    ),
                    trailing: [
                      ClayBadge(
                        label: Money.format(item.balance),
                        tone: ClayTone.warning,
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
