import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_core/school_core.dart';
import 'package:school_ui/school_ui.dart';

const Map<String, String> _auditActionLabels = {
  'create': 'إضافة',
  'update': 'تعديل',
  'delete': 'حذف',
  'receive_money': 'استلام المال',
  'pay_teacher': 'خلاص أستاذ',
  'cycle_complete': 'إكمال الدورة',
  'set_permissions': 'تعديل الصلاحيات',
  'reset_school': 'إعادة تعيين المدرسة',
};

const Map<String, String> _auditEntityLabels = {
  'school': 'المدرسة',
  'settings': 'الإعدادات',
  'levels': 'المستويات',
  'students': 'التلاميذ',
  'parents': 'الأولياء',
  'teachers': 'الأساتذة',
  'workers': 'العمال',
  'subjects': 'المواد',
  'rooms': 'القاعات',
  'transport_lines': 'خطوط النقل',
  'groups': 'الأفواج',
  'group_students': 'انتساب التلاميذ للأفواج',
  'waiting_lists': 'قوائم الانتظار',
  'waiting_entries': 'منتظرو الأفواج',
  'sessions': 'الحصص',
  'attendance': 'حضور التلاميذ',
  'teacher_attendance': 'حضور الأساتذة',
  'worker_attendance': 'حضور العمال',
  'session_requests': 'طلبات الحصص',
  'payments': 'المدفوعات',
  'student_credits': 'أرصدة التلاميذ',
  'registration_fees': 'حقوق التسجيل',
  'teacher_payouts': 'خلاص الأساتذة',
  'staff_debts': 'ديون الأساتذة والعمال',
  'expense_categories': 'أنواع المصاريف',
  'expenses': 'المصاريف',
  'sms_templates': 'قوالب الرسائل',
  'chat_rooms': 'غرف المحادثة',
  'chat_members': 'أعضاء المحادثة',
  'chat_messages': 'رسائل المحادثة',
  'grades': 'النتائج',
  'group_files': 'ملفات الأفواج',
  'notifications': 'الإشعارات',
  'user_accounts': 'حسابات المستخدمين',
};

const Map<String, String> _auditFieldLabels = {
  'name': 'الاسم',
  'first_name': 'الاسم الأول',
  'last_name': 'اللقب',
  'phone': 'الهاتف',
  'parent_phone': 'هاتف الوليّ',
  'email': 'البريد الإلكتروني',
  'amount': 'المبلغ',
  'date': 'التاريخ',
  'status': 'الحالة',
  'note': 'ملاحظة',
  'title': 'العنوان',
  'description': 'الوصف',
  'monthly_price': 'السعر الشهري',
  'discount_value': 'قيمة التخفيض',
  'discount_type': 'نوع التخفيض',
  'receipt_number': 'رقم الوصل',
  'room_id': 'معرّف القاعة',
  'teacher_id': 'معرّف الأستاذ',
  'student_id': 'معرّف التلميذ',
  'group_id': 'معرّف الفوج',
  'must_change_password': 'تغيير كلمة السر عند الدخول',
};

/// سجل عمليات للقراءة فقط، محمي بصلاحية `audit.view`.
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String _action = '';
  int _page = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.can(PermissionModule.audit, PermissionAction.view)) {
      return const Scaffold(
        appBar: ClayAppBar(title: 'سجل العمليات', showBack: true),
        body: ClayEmptyView(
          title: 'الصلاحية غير متاحة',
          message: 'يتطلب سجل العمليات صلاحية العرض',
          icon: Icons.lock_outline,
        ),
      );
    }

    final key = (action: _action, query: _query, page: _page);
    final logs = ref.watch(auditLogProvider(key));
    return Scaffold(
      appBar: const ClayAppBar(title: 'سجل العمليات', showBack: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              ClaySpacing.screenPadding,
              ClaySpacing.sm,
              ClaySpacing.screenPadding,
              0,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _applySearch(),
                        decoration: const InputDecoration(
                          labelText: 'ابحث باسم المنفّذ أو معرّف السجل',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: ClaySpacing.xs),
                    IconButton.filledTonal(
                      tooltip: 'بحث',
                      onPressed: _applySearch,
                      icon: const Icon(Icons.search_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: ClaySpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: _action,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'نوع العملية'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('كل العمليات'),
                    ),
                    for (final entry in _auditActionLabels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _action = value ?? '';
                    _page = 0;
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: logs.when(
              loading: () => const ClaySkeletonList(count: 5, itemExtent: 84),
              error: (_, _) => ClayErrorView(
                message: 'تعذّرت قراءة سجل العمليات',
                onRetry: () => ref.invalidate(auditLogProvider),
              ),
              data: (data) => _AuditLogPageView(
                page: data,
                onPrevious: data.hasPrevious
                    ? () => setState(() => _page--)
                    : null,
                onNext: data.hasNext ? () => setState(() => _page++) : null,
                onSelect: (entry) => _showDetails(context, entry),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _applySearch() {
    final query = _search.text.trim();
    if (_query == query && _page == 0) return;
    setState(() {
      _query = query;
      _page = 0;
    });
  }

  Future<void> _showDetails(BuildContext context, AuditLogRow entry) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => _AuditDetailsSheet(entry: entry),
      );
}

class _AuditLogPageView extends StatelessWidget {
  const _AuditLogPageView({
    required this.page,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  final AuditLogPage page;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<AuditLogRow> onSelect;

  @override
  Widget build(BuildContext context) {
    if (page.entries.isEmpty) {
      return const ClayEmptyView(
        title: 'لا توجد عمليات مطابقة',
        message: 'ستظهر هنا التغييرات التي تُسجَّل في قاعدة المدرسة',
        icon: Icons.history_rounded,
      );
    }
    final start = page.page * page.pageSize + 1;
    final end = start + page.entries.length - 1;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(ClaySpacing.screenPadding),
            itemCount: page.entries.length,
            itemExtent: 84,
            itemBuilder: (context, index) {
              final entry = page.entries[index];
              return ClayListTile(
                title:
                    '${_actionLabel(entry.action)} · ${_entityLabel(entry.entity)}',
                subtitle:
                    '${entry.userName.isEmpty ? entry.userId : entry.userName} · #${entry.entityId}',
                leading: Icon(
                  _actionIcon(entry.action),
                  color: context.palette.accent,
                ),
                trailing: [
                  Text(
                    _dateTimeLabel(entry.createdAt),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
                onTap: () => onSelect(entry),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            ClaySpacing.md,
            0,
            ClaySpacing.md,
            ClaySpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$start–$end من ${page.totalCount} عملية',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: 'الأحدث',
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text('${page.page + 1} / ${page.pageCount}'),
              IconButton(
                tooltip: 'الأقدم',
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AuditDetailsSheet extends StatelessWidget {
  const _AuditDetailsSheet({required this.entry});

  final AuditLogRow entry;

  @override
  Widget build(BuildContext context) {
    final changes = _changedFields(entry);
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            ClaySpacing.lg,
            0,
            ClaySpacing.lg,
            ClaySpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_actionLabel(entry.action)} · ${_entityLabel(entry.entity)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: ClaySpacing.xs),
              Text(
                '${entry.userName.isEmpty ? entry.userId : entry.userName} · ${_dateTimeLabel(entry.createdAt)}',
              ),
              Text('معرّف السجل: ${entry.entityId}'),
              const SizedBox(height: ClaySpacing.md),
              Text(
                'تفاصيل التغيير',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Divider(),
              Expanded(
                child: changes.isEmpty
                    ? const Center(child: Text('لا توجد تفاصيل إضافية مسجّلة'))
                    : ListView.builder(
                        itemCount: changes.length,
                        itemExtent: 84,
                        itemBuilder: (context, index) => changes[index],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuditFieldChange extends StatelessWidget {
  const _AuditFieldChange({
    required this.label,
    required this.keyName,
    required this.before,
    required this.after,
    required this.action,
  });

  final String label;
  final String keyName;
  final Object? before;
  final Object? after;
  final String action;

  @override
  Widget build(BuildContext context) {
    final oldValue = _safeValue(before, key: keyName);
    final newValue = _safeValue(after, key: keyName);
    final value = switch (action) {
      'create' => 'القيمة: $newValue',
      'delete' => 'قبل الحذف: $oldValue',
      _ => 'قبل: $oldValue  ←  بعد: $newValue',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ClaySpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
          const Divider(height: ClaySpacing.md),
        ],
      ),
    );
  }
}

List<Widget> _changedFields(AuditLogRow entry) {
  final before = _decodeSnapshot(entry.before);
  final after = _decodeSnapshot(entry.after);
  const ignored = {'id', 'created_at', 'updated_at', 'synced_at'};
  final fields = {...?before?.keys, ...?after?.keys}.toList()..sort();
  return [
    for (final key in fields)
      if (!ignored.contains(key) &&
          (entry.action == 'create' ||
              entry.action == 'delete' ||
              jsonEncode(before?[key]) != jsonEncode(after?[key])))
        _AuditFieldChange(
          label: _fieldLabel(key),
          keyName: key,
          before: before?[key],
          after: after?[key],
          action: entry.action,
        ),
  ];
}

Map<String, Object?>? _decodeSnapshot(String? value) {
  if (value == null) return null;
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
  } on Object catch (_) {
    return null;
  }
  return null;
}

String _safeValue(Object? value, {required String key}) {
  final safe = _redactSensitive(value, key: key);
  return switch (safe) {
    null => '—',
    bool() => safe ? 'نعم' : 'لا',
    Map() || List() => jsonEncode(safe),
    _ => '$safe',
  };
}

Object? _redactSensitive(Object? value, {String? key}) {
  if (key != null && _isSensitiveKey(key)) return '••••••';
  if (value is Map) {
    return {
      for (final entry in value.entries)
        '${entry.key}': _redactSensitive(entry.value, key: '${entry.key}'),
    };
  }
  if (value is List) {
    return [for (final item in value) _redactSensitive(item)];
  }
  return value;
}

bool _isSensitiveKey(String value) {
  final key = value.toLowerCase();
  return key.contains('password') ||
      key.contains('token') ||
      key.contains('secret') ||
      key == 'qr' ||
      key == 'qr_code';
}

String _fieldLabel(String key) {
  if (_isSensitiveKey(key)) return 'بيانات سرية';
  return _auditFieldLabels[key] ?? 'حقل ${key.replaceAll('_', ' ')}';
}

String _actionLabel(String action) =>
    _auditActionLabels[action] ?? action.replaceAll('_', ' ');

String _entityLabel(String entity) =>
    _auditEntityLabels[entity] ?? entity.replaceAll('_', ' ');

IconData _actionIcon(String action) => switch (action) {
  'create' => Icons.add_circle_outline_rounded,
  'update' || 'set_permissions' => Icons.edit_outlined,
  'delete' => Icons.delete_outline_rounded,
  'receive_money' || 'pay_teacher' => Icons.payments_outlined,
  _ => Icons.history_rounded,
};

String _dateTimeLabel(int milliseconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day/$month/${date.year} $hour:$minute';
}
