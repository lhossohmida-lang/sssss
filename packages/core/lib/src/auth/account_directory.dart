import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import '../domain/enums.dart';
import 'permissions.dart';

/// حساب دخول بدوره وصلاحياته، كما هو مخزَّن محلياً أو على الخادم.
class AccountRecord {
  const AccountRecord({
    required this.id,
    required this.email,
    required this.role,
    this.entityId,
    this.displayName = '',
    this.mustChangePassword = true,
    this.permissions = WorkerPermissions.none,
  });

  /// معرّف الحساب، وهو نفسه معرّف المستخدم على الخادم.
  final String id;

  final String email;

  final UserRole role;

  /// معرّف السجل في جدول الدور (عامل، أستاذ، وليّ)؛ فارغ لصاحب المدرسة.
  final String? entityId;

  final String displayName;

  /// `true` حتى يغيّر صاحب الحساب كلمة السر المولَّدة له.
  final bool mustChangePassword;

  /// صلاحيات العامل؛ فارغة في بقية الأدوار.
  final WorkerPermissions permissions;

  /// نسخة بعد تغيير بعض الحقول.
  AccountRecord copyWith({
    String? displayName,
    bool? mustChangePassword,
    WorkerPermissions? permissions,
  }) => AccountRecord(
    id: id,
    email: email,
    role: role,
    entityId: entityId,
    displayName: displayName ?? this.displayName,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    permissions: permissions ?? this.permissions,
  );

  /// يبني الحساب من صف `user_accounts`. يعيد `null` إن كان الصف ناقصاً أو
  /// دوره مجهولاً، فلا يُسمح بدخول حساب لا يُفهم دوره.
  static AccountRecord? fromRow(
    Map<String, Object?> row, {
    WorkerPermissions permissions = WorkerPermissions.none,
  }) {
    final id = row['id'];
    final email = row['email'];
    final roleCode = row['role'];
    if (id is! String || id.isEmpty) return null;
    if (email is! String) return null;
    if (roleCode is! String) return null;
    final UserRole role;
    try {
      role = UserRole.fromCode(roleCode);
    } on ArgumentError {
      return null;
    }
    final entityId = row['entity_id'];
    final displayName = row['display_name'];
    return AccountRecord(
      id: id,
      email: email,
      role: role,
      entityId: entityId is String && entityId.isNotEmpty ? entityId : null,
      displayName: displayName is String ? displayName : '',
      mustChangePassword: _asBool(row['must_change_password']),
      permissions: permissions,
    );
  }

  /// `must_change_password` يأتي عدداً من SQLite ومنطقياً من الخادم.
  static bool _asBool(Object? value) => switch (value) {
    bool() => value,
    int() => value != 0,
    String() => value == 'true' || value == 't' || value == '1',
    _ => true,
  };

  @override
  bool operator ==(Object other) =>
      other is AccountRecord &&
      other.id == id &&
      other.email == email &&
      other.role == role &&
      other.entityId == entityId &&
      other.displayName == displayName &&
      other.mustChangePassword == mustChangePassword &&
      other.permissions == permissions;

  @override
  int get hashCode => Object.hash(
    id,
    email,
    role,
    entityId,
    displayName,
    mustChangePassword,
    permissions,
  );

  @override
  String toString() => 'AccountRecord($id, ${role.code})';
}

/// مصدر يُقرأ منه حساب الدخول بعد نجاح المصادقة.
abstract interface class AccountDirectory {
  /// يعيد الحساب، أو `null` إن لم يوجد في هذا المصدر.
  Future<AccountRecord?> find(String accountId);
}

/// يقرأ الحساب من القاعدة المحلية، فيعمل الدخول دون إنترنت بعد أول مزامنة.
class LocalAccountDirectory implements AccountDirectory {
  const LocalAccountDirectory(this.db);

  final AppDatabase db;

  @override
  Future<AccountRecord?> find(String accountId) async {
    final row = await db
        .customSelect(
          'SELECT a.id, a.email, a.role, a.entity_id, a.display_name, '
          'a.must_change_password, w.permissions AS worker_permissions '
          'FROM user_accounts a '
          "LEFT JOIN workers w ON a.role = 'worker' AND w.id = a.entity_id "
          'AND w.deleted_at IS NULL '
          'WHERE a.id = ? AND a.deleted_at IS NULL',
          variables: [Variable<String>(accountId)],
          readsFrom: {db.userAccounts, db.workers},
        )
        .getSingleOrNull();
    if (row == null) return null;
    final permissions = row.data['worker_permissions'];
    return AccountRecord.fromRow(
      row.data,
      permissions: WorkerPermissions.decode(
        permissions is String ? permissions : null,
      ),
    );
  }
}

/// يقرأ صفوفاً من جدول على الخادم بشرط تساوي عمود بقيمة.
typedef RemoteRowQuery = Future<List<Map<String, Object?>>> Function(
  String table,
  String column,
  String value,
);

/// يقرأ الحساب من الخادم عند أول دخول على جهاز لم يُزامَن بعد.
class RemoteAccountDirectory implements AccountDirectory {
  const RemoteAccountDirectory(this.query);

  final RemoteRowQuery query;

  @override
  Future<AccountRecord?> find(String accountId) async {
    final rows = await query('user_accounts', 'id', accountId);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final entityId = row['entity_id'];
    var permissions = WorkerPermissions.none;
    if (row['role'] == UserRole.worker.code &&
        entityId is String &&
        entityId.isNotEmpty) {
      final workers = await query('workers', 'id', entityId);
      if (workers.isNotEmpty) {
        final field = workers.first['permissions'];
        permissions = WorkerPermissions.decode(field is String ? field : null);
      }
    }
    return AccountRecord.fromRow(row, permissions: permissions);
  }
}
