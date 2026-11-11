import '../app_identity.dart';
import '../data/local/sync_writer.dart';
import '../domain/enums.dart';
import 'account_directory.dart';
import 'permissions.dart';

/// المستخدم المسجَّل حالياً على الجهاز: حسابه ودوره وصلاحياته.
class AuthSession {
  AuthSession(this.account)
    : policy = AccessPolicy(
        role: account.role,
        permissions: account.permissions,
      );

  final AccountRecord account;

  /// ما يحق لصاحب الجلسة فعله.
  final AccessPolicy policy;

  /// معرّف الحساب، وهو نفسه معرّف المستخدم على الخادم.
  String get accountId => account.id;

  String get email => account.email;

  UserRole get role => account.role;

  /// معرّف السجل في جدول الدور (عامل، أستاذ، وليّ)؛ فارغ لصاحب المدرسة.
  String? get entityId => account.entityId;

  /// هل يجب أن يغيّر كلمة السر المولَّدة قبل استعمال التطبيق؟
  bool get mustChangePassword => account.mustChangePassword;

  /// الاسم الظاهر، وإلا البريد.
  String get displayName =>
      account.displayName.isEmpty ? account.email : account.displayName;

  /// صاحب العملية الذي يُسجَّل في سجل العمليات لكل كتابة من هذا الجهاز.
  Actor get actor => Actor(userId: accountId, userName: displayName);

  /// هل يملك المستخدم [action] على [module]؟
  bool can(PermissionModule module, PermissionAction action) =>
      policy.can(module, action);

  /// هل يحق لهذا الحساب الدخول من تطبيق [app]؟
  bool allowsApp(AppIdentity app) => policy.allowsApp(app);

  @override
  bool operator ==(Object other) =>
      other is AuthSession && other.account == account;

  @override
  int get hashCode => account.hashCode;

  @override
  String toString() => 'AuthSession($accountId, ${role.code})';
}
