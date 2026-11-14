import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

/// خطوط المدرسة وسائقوها وحافلاتها والتلاميذ المسجّلون في كل خط.
class TransportScreen extends ConsumerWidget {
  const TransportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView = ref.can(PermissionModule.transport, PermissionAction.view);
    final canViewStudents = ref.can(
      PermissionModule.students,
      PermissionAction.view,
    );
    final canAdd = ref.can(PermissionModule.transport, PermissionAction.add);
    final canEdit = ref.can(PermissionModule.transport, PermissionAction.edit);
    final canDelete = ref.can(
      PermissionModule.transport,
      PermissionAction.delete,
    );
    if (!canView) {
      return Scaffold(
        appBar: const ClayAppBar(title: 'النقل', showBack: true),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ClayEmptyView(
                  title: 'العرض غير متاح',
                  message: 'تحتاج إلى صلاحية عرض خطوط النقل',
                  icon: ClayIcons.transport,
                ),
                if (canAdd)
                  ClayButton(
                    label: 'إضافة خط نقل',
                    icon: ClayIcons.add,
                    onPressed: () => context.push('/transport/new'),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final data = ref.watch(transportLineSummariesProvider);
    return ClayListPage<TransportLineItem>(
      title: 'النقل',
      data: data,
      emptyTitle: 'لا توجد خطوط نقل بعد',
      emptyMessage: 'أضف الخط مع اسم السائق ورقمه والحافلة',
      searchHint: 'ابحث بالخط أو السائق أو رقم الحافلة',
      matches: (item, query) =>
          item.name.contains(query) ||
          item.driverName.contains(query) ||
          item.driverPhone.contains(query) ||
          item.busNumber.contains(query),
      onRetry: () => ref.invalidate(transportLineSummariesProvider),
      addLabel: 'إضافة خط نقل',
      onAdd: canAdd ? () => context.push('/transport/new') : null,
      itemExtent: 92,
      itemBuilder: (context, item) => ClayListTile(
        leading: const Icon(ClayIcons.transport),
        title: item.name,
        subtitle:
            '${item.driverName.isEmpty ? 'بلا سائق مسجّل' : item.driverName}'
            ' · ${item.busNumber.isEmpty ? 'بلا حافلة مسجّلة' : item.busNumber}'
            '${canViewStudents ? ' · ${item.studentCount} تلميذ' : ''}',
        onTap: () => context.push('/transport/${item.id}'),
        trailing: [
          if (canEdit)
            IconButton(
              tooltip: 'تعديل ${item.name}',
              icon: const Icon(ClayIcons.edit),
              onPressed: () => context.push('/transport/${item.id}/edit'),
            ),
          if (canDelete)
            IconButton(
              tooltip: 'حذف ${item.name}',
              icon: const Icon(ClayIcons.delete),
              onPressed: () => _deleteLine(context, ref, item),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteLine(
    BuildContext context,
    WidgetRef ref,
    TransportLineItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف خط النقل'),
        content: Text('هل تريد حذف «${item.name}»؟'),
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
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(transportServiceProvider).deleteLine(item.id);
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_errorText(error))));
    }
  }
}

/// إضافة أو تعديل بيانات الخط والسائق والحافلة.
class TransportLineFormScreen extends ConsumerStatefulWidget {
  const TransportLineFormScreen({this.lineId, super.key});

  final String? lineId;

  @override
  ConsumerState<TransportLineFormScreen> createState() =>
      _TransportLineFormScreenState();
}

class _TransportLineFormScreenState
    extends ConsumerState<TransportLineFormScreen> {
  final _name = TextEditingController();
  final _driver = TextEditingController();
  final _phone = TextEditingController();
  final _bus = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.lineId != null;

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
    try {
      final line = await ref
          .read(transportServiceProvider)
          .line(widget.lineId!);
      if (!mounted) return;
      setState(() {
        _loaded = true;
        if (line == null) {
          _error = 'خط النقل غير موجود';
          return;
        }
        _name.text = line.name;
        _driver.text = line.driverName;
        _phone.text = line.driverPhone;
        _bus.text = line.busNumber;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _error = _errorText(error);
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _driver.dispose();
    _phone.dispose();
    _bus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final service = ref.read(transportServiceProvider);
    try {
      if (_editing) {
        await service.updateLine(
          id: widget.lineId!,
          name: _name.text,
          driverName: _driver.text,
          driverPhone: _phone.text,
          busNumber: _bus.text,
        );
      } else {
        await service.addLine(
          name: _name.text,
          driverName: _driver.text,
          driverPhone: _phone.text,
          busNumber: _bus.text,
        );
      }
      if (mounted) context.pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _errorText(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ClayAppBar(
      title: _editing ? 'تعديل خط النقل' : 'إضافة خط نقل',
      showBack: true,
    ),
    body: !_loaded
        ? const ClayLoadingView()
        : ListView(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            children: [
              ClayTextField(
                controller: _name,
                label: 'اسم الخط',
                autofocus: !_editing,
                error: _error?.contains('اسم') == true ? _error : null,
              ),
              const SizedBox(height: ClaySpacing.md),
              ClayTextField(controller: _driver, label: 'اسم السائق'),
              const SizedBox(height: ClaySpacing.md),
              ClayTextField(
                controller: _phone,
                label: 'هاتف السائق (اختياري)',
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                error: _error?.contains('السائق') == true ? _error : null,
              ),
              const SizedBox(height: ClaySpacing.md),
              ClayTextField(
                controller: _bus,
                label: 'رقم الحافلة أو لوحتها',
                textDirection: TextDirection.ltr,
                error: _error?.contains('الحافلة') == true ? _error : null,
              ),
              if (_error != null &&
                  !_error!.contains('الخط') &&
                  !_error!.contains('اسم') &&
                  !_error!.contains('السائق') &&
                  !_error!.contains('الحافلة'))
                Padding(
                  padding: const EdgeInsets.only(top: ClaySpacing.sm),
                  child: Text(
                    _error!,
                    style: TextStyle(color: context.palette.status.danger),
                  ),
                ),
              const SizedBox(height: ClaySpacing.lg),
              ClayButton(
                label: _saving ? 'جارٍ الحفظ…' : 'حفظ',
                icon: _saving ? null : ClayIcons.check,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
  );
}

/// تفاصيل السائق والحافلة وقائمة التلاميذ المسندين إلى الخط.
class TransportLineDetailsScreen extends ConsumerWidget {
  const TransportLineDetailsScreen({required this.lineId, super.key});

  final String lineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.can(PermissionModule.transport, PermissionAction.edit);
    final canViewStudents = ref.can(
      PermissionModule.students,
      PermissionAction.view,
    );
    final canManageStudents =
        canViewStudents &&
        canEdit &&
        ref.can(PermissionModule.students, PermissionAction.edit);
    final line = ref.watch(transportLineProvider(lineId));
    final students = canViewStudents
        ? ref.watch(transportStudentsProvider(lineId))
        : null;
    return Scaffold(
      appBar: ClayAppBar(
        title: 'تفاصيل خط النقل',
        showBack: true,
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'تعديل خط النقل',
              icon: const Icon(ClayIcons.edit),
              onPressed: () => context.push('/transport/$lineId/edit'),
            ),
        ],
      ),
      body: line.when(
        loading: () => const ClayLoadingView(),
        error: (_, _) => ClayErrorView(
          message: 'تعذّر قراءة خط النقل',
          onRetry: () => ref.invalidate(transportLineProvider(lineId)),
        ),
        data: (item) {
          if (item == null) {
            return const ClayEmptyView(
              title: 'خط النقل غير موجود',
              message: 'قد يكون حُذف من جهاز آخر',
              icon: ClayIcons.transport,
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(ClaySpacing.screenPadding),
                child: ClayCard(
                  flat: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        item.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: ClaySpacing.xs),
                      Text(
                        'السائق: ${item.driverName.isEmpty ? 'غير محدّد' : item.driverName}',
                      ),
                      if (item.driverPhone.isNotEmpty)
                        Text('الهاتف: ${item.driverPhone}'),
                      Text(
                        'الحافلة: ${item.busNumber.isEmpty ? 'غير محدّدة' : item.busNumber}',
                      ),
                      if (canViewStudents)
                        Text('التلاميذ: ${item.studentCount}'),
                    ],
                  ),
                ),
              ),
              if (canManageStudents)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    ClaySpacing.screenPadding,
                    0,
                    ClaySpacing.screenPadding,
                    ClaySpacing.sm,
                  ),
                  child: ClayButton(
                    label: 'إضافة أو نقل تلاميذ إلى الخط',
                    icon: ClayIcons.add,
                    kind: ClayButtonKind.secondary,
                    onPressed: () => _assignStudents(context, ref),
                  ),
                ),
              Expanded(
                child: !canViewStudents
                    ? const ClayEmptyView(
                        title: 'قائمة التلاميذ مخفية',
                        message: 'تحتاج إلى صلاحية عرض التلاميذ',
                        icon: ClayIcons.students,
                      )
                    : students!.when(
                        loading: () => const ClaySkeletonList(),
                        error: (_, _) => ClayErrorView(
                          message: 'تعذّر قراءة تلاميذ الخط',
                          onRetry: () =>
                              ref.invalidate(transportStudentsProvider(lineId)),
                        ),
                        data: (items) => items.isEmpty
                            ? const ClayEmptyView(
                                title: 'لا تلاميذ في هذا الخط',
                                message: 'أضف المستعملين للنقل أو أسندهم إليه',
                                icon: ClayIcons.students,
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: ClaySpacing.screenPadding,
                                ),
                                itemCount: items.length,
                                itemExtent: 78,
                                itemBuilder: (context, index) {
                                  final student = items[index];
                                  return ClayListTile(
                                    leading: ClayAvatar(name: student.name),
                                    title: student.name,
                                    subtitle:
                                        '${Money.format(student.price)} شهرياً',
                                    trailing: [
                                      if (canManageStudents)
                                        IconButton(
                                          tooltip:
                                              'إزالة ${student.name} من الخط',
                                          icon: const Icon(ClayIcons.close),
                                          onPressed: () =>
                                              _unassign(context, ref, student),
                                        ),
                                    ],
                                  );
                                },
                              ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _assignStudents(BuildContext context, WidgetRef ref) =>
      showDialog<void>(
        context: context,
        builder: (_) => _AssignStudentsDialog(lineId: lineId),
      );

  Future<void> _unassign(
    BuildContext context,
    WidgetRef ref,
    TransportStudentItem student,
  ) async {
    try {
      await ref
          .read(transportServiceProvider)
          .unassignStudent(lineId: lineId, studentId: student.id);
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_errorText(error))));
    }
  }
}

class _AssignStudentsDialog extends ConsumerStatefulWidget {
  const _AssignStudentsDialog({required this.lineId});

  final String lineId;

  @override
  ConsumerState<_AssignStudentsDialog> createState() =>
      _AssignStudentsDialogState();
}

class _AssignStudentsDialogState extends ConsumerState<_AssignStudentsDialog> {
  String _query = '';
  String? _busyStudentId;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(
      transportOtherStudentsProvider((lineId: widget.lineId, query: _query)),
    );
    return AlertDialog(
      title: const Text('اختيار تلميذ للنقل'),
      content: SizedBox(
        width: 500,
        height: 520,
        child: Column(
          children: [
            ClayTextField(
              hint: 'ابحث باسم التلميذ أو هاتف الوليّ',
              prefixIcon: ClayIcons.search,
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: ClaySpacing.xs),
                child: Text(
                  _error!,
                  style: TextStyle(color: context.palette.status.danger),
                ),
              ),
            const SizedBox(height: ClaySpacing.sm),
            Expanded(
              child: students.when(
                loading: () => const ClayLoadingView(),
                error: (_, _) => const ClayErrorView(
                  message: 'تعذّر قراءة التلاميذ المستعملين للنقل',
                ),
                data: (items) => items.isEmpty
                    ? const ClayEmptyView(
                        title: 'لا تلاميذ آخرون للنقل',
                        message: 'تأكد من تفعيل النقل في ملف التلميذ',
                        icon: ClayIcons.students,
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemExtent: 84,
                        itemBuilder: (context, index) {
                          final student = items[index];
                          final moving = student.lineId != null;
                          return ClayListTile(
                            title: student.name,
                            subtitle: moving
                                ? 'خطه الحالي: ${student.lineName ?? 'غير متاح'}'
                                : 'مستعمل للنقل · ${Money.format(student.price)} شهرياً',
                            trailing: [
                              IconButton(
                                tooltip: moving
                                    ? 'نقل إلى هذا الخط'
                                    : 'إسناد إلى الخط',
                                onPressed: _busyStudentId == student.id
                                    ? null
                                    : () => _assign(student),
                                icon: _busyStudentId == student.id
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        moving
                                            ? Icons.swap_horiz_rounded
                                            : ClayIcons.add,
                                      ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }

  Future<void> _assign(TransportStudentItem student) async {
    setState(() {
      _busyStudentId = student.id;
      _error = null;
    });
    try {
      await ref
          .read(transportServiceProvider)
          .assignStudent(lineId: widget.lineId, studentId: student.id);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _busyStudentId = null);
    }
  }
}

String _errorText(Object error) {
  if (error is FormatException) return error.message.toString();
  if (error is StateError) return error.message;
  return 'تعذّر حفظ بيانات النقل';
}
