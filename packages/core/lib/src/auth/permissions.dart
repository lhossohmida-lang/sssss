import 'dart:convert';

import '../app_identity.dart';
import '../domain/enums.dart';

/// وحدة من وحدات النظام تُمنح صلاحياتها للعامل.
///
/// الرموز هي نفسها التي تفحصها دالة `app.can` على الخادم في
/// `supabase/migrations/0002_rls.sql`، فما يمنعه التطبيق يمنعه الخادم.
enum PermissionModule {
  students('students', 'التلاميذ'),
  teachers('teachers', 'الأساتذة'),
  subjects('subjects', 'المواد'),
  rooms('rooms', 'القاعات'),
  groups('groups', 'المجموعات'),
  attendance('attendance', 'الحضور'),
  waiting('waiting', 'قوائم الانتظار'),
  payments('payments', 'المدفوعات'),
  payouts('payouts', 'خلاص الأساتذة'),
  expenses('expenses', 'المصاريف'),
  workers('workers', 'العمال'),
  requests('requests', 'طلبات الأساتذة'),
  sms('sms', 'الرسائل'),
  chat('chat', 'المحادثات'),
  transport('transport', 'النقل'),
  audit('audit', 'سجل العمليات'),
  settings('settings', 'الإعدادات'),
  scanner('scanner', 'الماسح'),
  receiveMoney('receive_money', 'استلام المال');

  const PermissionModule(this.code, this.label);

  /// القيمة المخزَّنة في `workers.permissions` وعلى الخادم.
  final String code;

  /// النص العربي الظاهر في شاشة صلاحيات العامل.
  final String label;

  /// الأفعال التي تُعرض كمربعات اختيار لهذه الوحدة.
  ///
  /// سجل العمليات يُقرأ فقط، والإعدادات لا تُضاف ولا تُحذف، والماسح
  /// واستلام المال فعلهما واحد: الاستعمال.
  List<PermissionAction> get actions => switch (this) {
    audit => const [PermissionAction.view],
    settings => const [PermissionAction.view, PermissionAction.edit],
    scanner || receiveMoney => const [PermissionAction.use],
    sms => const [
      PermissionAction.view,
      PermissionAction.add,
      PermissionAction.edit,
      PermissionAction.delete,
      PermissionAction.use,
    ],
    _ => const [
      PermissionAction.view,
      PermissionAction.add,
      PermissionAction.edit,
      PermissionAction.delete,
    ],
  };

  /// يحوّل القيمة المخزَّنة إلى النوع، ويعيد `null` إن كانت مجهولة.
  static PermissionModule? tryFromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return null;
  }

  /// يحوّل القيمة المخزَّنة إلى النوع، ويرمي [ArgumentError] إن كانت مجهولة.
  static PermissionModule fromCode(String code) {
    final value = tryFromCode(code);
    if (value == null) {
      throw ArgumentError.value(code, 'code', 'وحدة صلاحيات غير معروفة');
    }
    return value;
  }
}

/// فعل مسموح على وحدة.
enum PermissionAction {
  view('view', 'عرض'),
  add('add', 'إضافة'),
  edit('edit', 'تعديل'),
  delete('delete', 'حذف'),
  use('use', 'استعمال');

  const PermissionAction(this.code, this.label);

  /// القيمة المخزَّنة في `workers.permissions` وعلى الخادم.
  final String code;

  /// النص العربي الظاهر في شاشة صلاحيات العامل.
  final String label;

  /// يحوّل القيمة المخزَّنة إلى النوع، ويعيد `null` إن كانت مجهولة.
  static PermissionAction? tryFromCode(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return null;
  }

  /// يحوّل القيمة المخزَّنة إلى النوع، ويرمي [ArgumentError] إن كانت مجهولة.
  static PermissionAction fromCode(String code) {
    final value = tryFromCode(code);
    if (value == null) {
      throw ArgumentError.value(code, 'code', 'فعل صلاحيات غير معروف');
    }
    return value;
  }
}

/// صلاحيات عامل: لكل وحدة قائمة الأفعال التي فعّلها المدير.
///
/// تُخزَّن في `workers.permissions` بصيغة JSON مثل
/// `{"students":["view","add"],"scanner":["use"]}`، وهي نفس الصيغة التي
/// تفحصها دالة `app.can` على الخادم.
class WorkerPermissions {
  const WorkerPermissions(this._granted);

  /// عامل جديد بلا أي صلاحية.
  static const WorkerPermissions none = WorkerPermissions({});

  final Map<PermissionModule, Set<PermissionAction>> _granted;

  /// هل الصلاحيات فارغة تماماً؟
  bool get isEmpty => _granted.values.every((actions) => actions.isEmpty);

  /// الوحدات التي فيها فعل مسموح واحد على الأقل.
  Iterable<PermissionModule> get modules => [
    for (final module in PermissionModule.values)
      if (actionsOf(module).isNotEmpty) module,
  ];

  /// هل يملك العامل [action] على [module]؟
  bool can(PermissionModule module, PermissionAction action) =>
      _granted[module]?.contains(action) ?? false;

  /// الأفعال المسموحة على [module] بترتيب العرض.
  List<PermissionAction> actionsOf(PermissionModule module) => [
    for (final action in module.actions)
      if (can(module, action)) action,
  ];

  /// نسخة بعد تفعيل [action] أو تعطيله على [module] (لشاشة الصلاحيات).
  ///
  /// يرمي [ArgumentError] إن لم يكن [action] من أفعال [module].
  WorkerPermissions withAction(
    PermissionModule module,
    PermissionAction action, {
    required bool allowed,
  }) {
    if (!module.actions.contains(action)) {
      throw ArgumentError.value(
        action,
        'action',
        'الفعل ${action.code} لا يخص وحدة ${module.code}',
      );
    }
    final updated = {
      for (final entry in _granted.entries) entry.key: {...entry.value},
    };
    final actions = updated.putIfAbsent(module, () => <PermissionAction>{});
    if (allowed) {
      actions.add(action);
    } else {
      actions.remove(action);
    }
    updated.removeWhere((_, value) => value.isEmpty);
    return WorkerPermissions(updated);
  }

  /// نسخة فيها كل أفعال [module] أو بلا أي فعل منها.
  WorkerPermissions withModule(
    PermissionModule module, {
    required bool allowed,
  }) {
    var result = this;
    for (final action in module.actions) {
      result = result.withAction(module, action, allowed: allowed);
    }
    return result;
  }

  /// يقرأ الصلاحيات من حقل JSON. ما لا يُفهم يُتجاهل حتى لا يمنع الدخول:
  /// حقل فارغ أو تالف يعني «بلا صلاحيات».
  static WorkerPermissions decode(String? source) {
    if (source == null || source.trim().isEmpty) return none;
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return none;
    }
    if (decoded is! Map) return none;
    final granted = <PermissionModule, Set<PermissionAction>>{};
    for (final entry in decoded.entries) {
      final key = entry.key;
      if (key is! String) continue;
      final module = PermissionModule.tryFromCode(key);
      if (module == null) continue;
      final value = entry.value;
      if (value is! List) continue;
      final actions = <PermissionAction>{};
      for (final item in value) {
        if (item is! String) continue;
        final action = PermissionAction.tryFromCode(item);
        if (action != null && module.actions.contains(action)) {
          actions.add(action);
        }
      }
      if (actions.isNotEmpty) granted[module] = actions;
    }
    return WorkerPermissions(granted);
  }

  /// يكتب الصلاحيات حقل JSON بترتيب ثابت، فلا يتغير الحقل دون سبب.
  String encode() => jsonEncode({
    for (final module in PermissionModule.values)
      if (actionsOf(module).isNotEmpty)
        module.code: [for (final action in actionsOf(module)) action.code],
  });

  @override
  bool operator ==(Object other) {
    if (other is! WorkerPermissions) return false;
    final mine = modules.toList();
    final theirs = other.modules.toList();
    if (mine.length != theirs.length) return false;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) return false;
      final a = actionsOf(mine[i]);
      final b = other.actionsOf(theirs[i]);
      if (a.length != b.length) return false;
      for (var j = 0; j < a.length; j++) {
        if (a[j] != b[j]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([
    for (final module in modules) ...[module, ...actionsOf(module)],
  ]);

  @override
  String toString() => 'WorkerPermissions(${encode()})';
}

/// ما يحق للمستخدم الحالي فعله: الدور، ومعه صلاحيات العامل إن كان عاملاً.
///
/// نفس منطق `app.can` على الخادم: صاحب المدرسة يملك كل شيء، والعامل حسب ما
/// فعّله له المدير، والأستاذ والوليّ لا يملكان صلاحيات إدارية.
class AccessPolicy {
  const AccessPolicy({
    required this.role,
    this.permissions = WorkerPermissions.none,
  });

  final UserRole role;

  /// صلاحيات العامل؛ تُتجاهل في بقية الأدوار.
  final WorkerPermissions permissions;

  /// هل المستخدم صاحب المدرسة؟
  bool get isOwner => role == UserRole.owner;

  /// هل يستعمل المستخدم تطبيق الإدارة (صاحب المدرسة أو عامل)؟
  bool get isStaff => role.usesAdminApp;

  /// هل يملك المستخدم [action] على [module]؟
  bool can(PermissionModule module, PermissionAction action) => switch (role) {
    UserRole.owner => true,
    UserRole.worker => permissions.can(module, action),
    UserRole.teacher || UserRole.parent => false,
  };

  /// هل يملك المستخدم فعلاً واحداً على الأقل في [module]؟ (لعرض الشاشة)
  bool canAnyOf(PermissionModule module) =>
      module.actions.any((action) => can(module, action));

  /// هل يحق لهذا الدور الدخول من تطبيق [app]؟
  bool allowsApp(AppIdentity app) => switch (app) {
    AppIdentity.admin => role.usesAdminApp,
    AppIdentity.teacher => role == UserRole.teacher,
    AppIdentity.student => role == UserRole.parent,
  };

  @override
  bool operator ==(Object other) =>
      other is AccessPolicy &&
      other.role == role &&
      other.permissions == permissions;

  @override
  int get hashCode => Object.hash(role, permissions);

  @override
  String toString() => 'AccessPolicy(${role.code}, ${permissions.encode()})';
}
