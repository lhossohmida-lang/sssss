import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import 'account_directory.dart';
import 'auth_session.dart';
import 'permissions.dart';

/// حفظ الجلسة على الجهاز بين التشغيلات.
abstract interface class SessionStore {
  /// يعيد الجلسة المحفوظة، أو `null` إن لم يسجّل أحد الدخول.
  Future<AuthSession?> read();

  Future<void> write(AuthSession session);

  Future<void> clear();
}

/// يحفظ الجلسة في جدول `device_session` المحلي (صف واحد لا يُزامَن).
class DatabaseSessionStore implements SessionStore {
  DatabaseSessionStore(this.db, {int Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  /// رقم الصف الوحيد.
  static const int rowId = 1;

  final AppDatabase db;
  final int Function() _clock;

  @override
  Future<AuthSession?> read() async {
    final row = await (db.select(
      db.deviceSession,
    )..where((t) => t.id.equals(rowId))).getSingleOrNull();
    if (row == null) return null;
    final account = AccountRecord.fromRow({
      'id': row.accountId,
      'email': row.email,
      'role': row.role,
      'entity_id': row.entityId,
      'display_name': row.displayName,
      'must_change_password': row.mustChangePassword,
    }, permissions: WorkerPermissions.decode(row.permissions));
    if (account == null) {
      await clear();
      return null;
    }
    return AuthSession(account);
  }

  @override
  Future<void> write(AuthSession session) async {
    final account = session.account;
    await db
        .into(db.deviceSession)
        .insertOnConflictUpdate(
          DeviceSessionCompanion.insert(
            id: const Value(rowId),
            accountId: account.id,
            email: account.email,
            role: account.role.code,
            entityId: Value(account.entityId),
            displayName: Value(account.displayName),
            mustChangePassword: Value(account.mustChangePassword),
            permissions: Value(account.permissions.encode()),
            savedAt: _clock(),
          ),
        );
  }

  @override
  Future<void> clear() =>
      (db.delete(db.deviceSession)..where((t) => t.id.equals(rowId))).go();
}
