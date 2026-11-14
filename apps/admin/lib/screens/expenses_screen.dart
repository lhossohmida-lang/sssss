import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  bool _busy = false;

  static const List<String> _months = [
    'جانفي',
    'فيفري',
    'مارس',
    'أفريل',
    'ماي',
    'جوان',
    'جويلية',
    'أوت',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  Future<String?> _askCategoryName({String initial = ''}) async =>
      showDialog<String>(
        context: context,
        builder: (context) => _CategoryNameDialog(initial: initial),
      );

  Future<void> _manageCategories(List<ExpenseCategory> categories) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _CategoryManagerDialog(
        categories: categories,
        canAdd: ref.can(PermissionModule.expenses, PermissionAction.add),
        canEdit: ref.can(PermissionModule.expenses, PermissionAction.edit),
        canDelete: ref.can(PermissionModule.expenses, PermissionAction.delete),
        askName: _askCategoryName,
        addCategory: (name) =>
            ref.read(expenseServiceProvider).addCategory(name),
        saveName: (id, name) =>
            ref.read(expenseServiceProvider).renameCategory(id, name),
        delete: (id) => ref.read(expenseServiceProvider).deleteCategory(id),
      ),
    );
  }

  Future<void> _openExpense({ExpenseItem? existing}) async {
    final categories = ref.read(expenseCategoriesProvider).value ?? const [];
    final canAddCategory = ref.can(
      PermissionModule.expenses,
      PermissionAction.add,
    );
    final value = await showDialog<_ExpenseFormValue>(
      context: context,
      builder: (context) => _ExpenseFormDialog(
        categories: categories,
        initial: existing,
        canAddCategory: canAddCategory,
        askCategoryName: canAddCategory ? _askCategoryName : null,
        addCategory: (name) =>
            ref.read(expenseServiceProvider).addCategory(name),
      ),
    );
    if (value == null || !mounted) return;
    setState(() => _busy = true);
    var savedId = existing?.id;
    try {
      final service = ref.read(expenseServiceProvider);
      if (existing == null) {
        savedId = await service.addExpense(
          categoryId: value.categoryId,
          amount: value.amount,
          date: value.date,
          note: value.note,
        );
      } else {
        await service.updateExpense(
          id: existing.id,
          categoryId: value.categoryId,
          amount: value.amount,
          date: value.date,
          note: value.note,
        );
      }
      if (value.invoiceBytes != null && savedId != null) {
        try {
          await ref
              .read(photoServiceProvider)
              .attach(PhotoOwner.expenseInvoice, savedId, value.invoiceBytes!);
        } on Object catch (error) {
          _message(
            'سُجّل المصروف لكن تعذّر حفظ صورة الفاتورة: ${_errorText(error)}',
            error: true,
          );
          return;
        }
      }
      _message(existing == null ? 'سُجّل المصروف' : 'حُدّث المصروف');
    } on Object catch (error) {
      _message(_errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteExpense(ExpenseItem expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المصروف؟'),
        content: Text(
          '${expense.categoryName} · ${Money.format(expense.amount)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(expenseServiceProvider).deleteExpense(expense.id);
      _message('حُذف المصروف');
    } on Object catch (error) {
      _message(_errorText(error), error: true);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  String _errorText(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is FormatException) return error.message;
    return 'تعذّرت العملية: $error';
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(expenseCategoriesProvider);
    final canView = ref.can(PermissionModule.expenses, PermissionAction.view);
    final canAdd = ref.can(PermissionModule.expenses, PermissionAction.add);
    final canEdit = ref.can(PermissionModule.expenses, PermissionAction.edit);
    final canDelete = ref.can(
      PermissionModule.expenses,
      PermissionAction.delete,
    );
    final key = (year: _year, month: _month);
    final totals = canView ? ref.watch(expenseTotalsProvider(key)) : null;
    final expenses = canView ? ref.watch(expenseMonthProvider(key)) : null;
    final years = [
      for (
        var year = DateTime.now().year - 10;
        year <= DateTime.now().year + 1;
        year++
      )
        year,
    ];

    return Scaffold(
      appBar: const ClayAppBar(title: 'المصاريف', showBack: true),
      body: Column(
        children: [
          if (totals != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ClaySpacing.screenPadding,
                0,
                ClaySpacing.screenPadding,
                ClaySpacing.sm,
              ),
              child: ClayCard(
                flat: true,
                child: totals.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const Text('تعذّر حساب المجاميع'),
                  data: (value) => Wrap(
                    spacing: 20,
                    runSpacing: 6,
                    children: [
                      Text(
                        'مجموع ${_months[_month - 1]} $_year: '
                        '${Money.format(value.monthTotal)}',
                      ),
                      Text(
                        'مجموع سنة $_year: ${Money.format(value.yearTotal)}',
                      ),
                      Text('${value.monthCount} مصروف'),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ClaySpacing.screenPadding,
            ),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _month,
                    decoration: const InputDecoration(labelText: 'الشهر'),
                    items: [
                      for (var month = 1; month <= 12; month++)
                        DropdownMenuItem(
                          value: month,
                          child: Text(_months[month - 1]),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _month = value);
                    },
                  ),
                ),
                const SizedBox(width: ClaySpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _year,
                    decoration: const InputDecoration(labelText: 'السنة'),
                    items: [
                      for (final year in years.reversed)
                        DropdownMenuItem(value: year, child: Text('$year')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _year = value);
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            child: Wrap(
              spacing: ClaySpacing.sm,
              runSpacing: ClaySpacing.sm,
              children: [
                if (canAdd)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _openExpense(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('إضافة مصروف'),
                  ),
                OutlinedButton.icon(
                  onPressed: categories.value == null
                      ? null
                      : () => _manageCategories(categories.value!),
                  icon: const Icon(Icons.category_outlined),
                  label: const Text('أنواع المصاريف'),
                ),
              ],
            ),
          ),
          Expanded(
            child: !canView
                ? const ClayEmptyView(
                    title: 'سجل المصاريف مخفي',
                    message: 'لديك صلاحية الإضافة دون عرض السجل.',
                    icon: Icons.lock_outline_rounded,
                  )
                : expenses!.when(
                    loading: () => const ClaySkeletonList(),
                    error: (_, _) => ClayErrorView(
                      message: 'تعذّرت قراءة المصاريف',
                      onRetry: () => ref.invalidate(expenseMonthProvider),
                    ),
                    data: (items) => items.isEmpty
                        ? ClayEmptyView(
                            title: 'لا مصاريف في هذا الشهر',
                            message: canAdd
                                ? 'أضف نوعاً ثم سجّل أول مصروف.'
                                : 'تظهر المصاريف المسجلة هنا.',
                            icon: ClayIcons.expenses,
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: ClaySpacing.screenPadding,
                            ),
                            itemCount: items.length,
                            itemExtent: 92,
                            itemBuilder: (context, index) => _ExpenseTile(
                              expense: items[index],
                              canEdit: canEdit && items[index].workerId == null,
                              canDelete:
                                  canDelete && items[index].workerId == null,
                              onEdit: () =>
                                  _openExpense(existing: items[index]),
                              onDelete: () => _deleteExpense(items[index]),
                              onInvoice: () => _showInvoice(items[index]),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showInvoice(ExpenseItem expense) async {
    final file = await ref
        .read(photoServiceProvider)
        .resolve(PhotoOwner.expenseInvoice, expense.id);
    if (!mounted) return;
    if (file == null) {
      _message('تعذّر تحميل صورة الفاتورة', error: true);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(child: Image.file(file, fit: BoxFit.contain)),
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({
    required this.expense,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
    required this.onInvoice,
  });

  final ExpenseItem expense;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onInvoice;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (expense.invoicePhotoLocalPath != null ||
          expense.invoicePhotoUrl != null)
        IconButton(
          tooltip: 'عرض صورة الفاتورة',
          onPressed: onInvoice,
          icon: const Icon(Icons.receipt_long_outlined),
        ),
      if (canDelete)
        PopupMenuButton<String>(
          tooltip: 'إجراءات المصروف',
          onSelected: (value) {
            if (value == 'edit') onEdit();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => [
            if (canEdit)
              const PopupMenuItem(value: 'edit', child: Text('تعديل')),
            const PopupMenuItem(value: 'delete', child: Text('حذف')),
          ],
        )
      else if (canEdit)
        IconButton(
          tooltip: 'تعديل المصروف',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
    ];
    return ClayListTile(
      title: expense.categoryName,
      subtitle: '${expense.date}  ${expense.note}'.trim(),
      subtitleLines: 2,
      onTap: canEdit ? onEdit : null,
      trailing: [Text(Money.format(expense.amount)), ...actions],
    );
  }
}

class _ExpenseFormValue {
  const _ExpenseFormValue({
    required this.categoryId,
    required this.amount,
    required this.date,
    required this.note,
    this.invoiceBytes,
  });

  final String categoryId;
  final int amount;
  final String date;
  final String note;
  final Uint8List? invoiceBytes;
}

class _ExpenseFormDialog extends StatefulWidget {
  const _ExpenseFormDialog({
    required this.categories,
    required this.canAddCategory,
    required this.addCategory,
    this.initial,
    this.askCategoryName,
  });

  final List<ExpenseCategory> categories;
  final ExpenseItem? initial;
  final bool canAddCategory;
  final Future<String?> Function()? askCategoryName;
  final Future<String> Function(String name) addCategory;

  @override
  State<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<_ExpenseFormDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String? _categoryId;
  late List<ExpenseCategory> _categories;
  late String _date;
  Uint8List? _invoiceBytes;
  String? _invoiceName;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _amount = TextEditingController(text: initial?.amount.toString() ?? '');
    _note = TextEditingController(text: initial?.note ?? '');
    _categories = [...widget.categories];
    _categoryId = initial?.categoryId ?? _categories.firstOrNull?.id;
    _date = initial?.date ?? DateKey.of(DateTime.now());
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _createCategory() async {
    final ask = widget.askCategoryName;
    if (ask == null) return;
    final name = await ask();
    if (name == null || !mounted) return;
    try {
      final id = await widget.addCategory(name);
      if (mounted) {
        setState(() {
          _categories = [
            ..._categories,
            ExpenseCategory(id: id, name: name.trim(), isWages: false),
          ];
          _categoryId = id;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _errorText(error));
      }
    }
  }

  Future<void> _pickInvoice() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty || !mounted) return;
    final file = files.first;
    if (await file.length() > PhotoProcessor.maxInputBytes) {
      setState(() => _error = 'حجم الصورة أكبر من 10 ميغابايت');
      return;
    }
    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _invoiceBytes = bytes;
        _invoiceName = file.name;
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'تعذّر فتح الصورة: $error');
    }
  }

  Future<void> _pickDate() async {
    final current = DateKey.parse(_date);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = DateKey.of(picked));
  }

  void _submit() {
    final amount = int.tryParse(_amount.text.trim());
    if (_categoryId == null) {
      setState(() => _error = 'أضف نوع مصروف أولاً');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'اكتب مبلغاً صحيحاً أكبر من صفر');
      return;
    }
    Navigator.pop(
      context,
      _ExpenseFormValue(
        categoryId: _categoryId!,
        amount: amount,
        date: _date,
        note: _note.text,
        invoiceBytes: _invoiceBytes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'إضافة مصروف' : 'تعديل المصروف'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'نوع المصروف'),
              items: [
                for (final category in _categories)
                  if (!category.isWages)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    ),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
            if (widget.canAddCategory)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _createCategory,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة نوع جديد'),
                ),
              ),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'المبلغ بالدينار',
                suffixText: 'دج',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(_date),
            ),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickInvoice,
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(_invoiceName ?? 'إرفاق صورة الفاتورة (اختياري)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(onPressed: _submit, child: const Text('حفظ')),
    ],
  );
}

class _CategoryManagerDialog extends StatefulWidget {
  const _CategoryManagerDialog({
    required this.categories,
    required this.canAdd,
    required this.canEdit,
    required this.canDelete,
    required this.askName,
    required this.addCategory,
    required this.saveName,
    required this.delete,
  });

  final List<ExpenseCategory> categories;
  final bool canAdd;
  final bool canEdit;
  final bool canDelete;
  final Future<String?> Function({String initial}) askName;
  final Future<String> Function(String name) addCategory;
  final Future<void> Function(String id, String name) saveName;
  final Future<void> Function(String id) delete;

  @override
  State<_CategoryManagerDialog> createState() => _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends State<_CategoryManagerDialog> {
  String? _error;

  Future<void> _rename(ExpenseCategory category) async {
    final name = await widget.askName(initial: category.name);
    if (name == null || !mounted) return;
    try {
      await widget.saveName(category.id, name);
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    }
  }

  Future<void> _delete(ExpenseCategory category) async {
    try {
      await widget.delete(category.id);
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('أنواع المصاريف'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.categories.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('لا توجد أنواع بعد. أضف نوعاً لتسجيل مصروف.'),
            )
          else
            SizedBox(
              height: (widget.categories.length * 56.0)
                  .clamp(56, 350)
                  .toDouble(),
              child: ListView.builder(
                itemCount: widget.categories.length,
                itemExtent: 56,
                itemBuilder: (context, index) {
                  final category = widget.categories[index];
                  return ListTile(
                    dense: true,
                    title: Text(category.name),
                    trailing: Wrap(
                      children: [
                        if (widget.canEdit)
                          IconButton(
                            tooltip: 'إعادة تسمية',
                            onPressed: () => _rename(category),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        if (widget.canDelete)
                          IconButton(
                            tooltip: 'حذف النوع',
                            onPressed: () => _delete(category),
                            icon: const Icon(Icons.delete_outline),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      if (widget.canAdd)
        TextButton.icon(
          onPressed: () async {
            final name = await widget.askName();
            if (name == null || !context.mounted) return;
            try {
              // The dialog gets rebuilt when its provider emits the new row.
              await widget.addCategory(name);
              if (context.mounted) Navigator.pop(context);
            } on Object catch (error) {
              if (mounted) setState(() => _error = _errorText(error));
            }
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('إضافة نوع'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إغلاق'),
      ),
    ],
  );
}

class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({required this.initial});

  final String initial;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial.isEmpty ? 'نوع مصروف جديد' : 'تعديل النوع'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 60,
      decoration: const InputDecoration(labelText: 'اسم النوع'),
      onSubmitted: (_) => Navigator.pop(context, _controller.text),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('حفظ'),
      ),
    ],
  );
}

String _errorText(Object error) {
  if (error is StateError) return error.message.toString();
  if (error is FormatException) return error.message;
  return 'تعذّرت العملية: $error';
}
