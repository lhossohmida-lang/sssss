import '../auth/account_provisioner.dart';
import '../auth/auth_gateway.dart';
import '../domain/enums.dart';

/// منشئ حسابات وهمي للاختبارات: يسجّل ما أُنشئ دون أي اتصال.
class FakeAccountProvisioner implements AccountProvisioner {
  /// ما أُنشئ: معرّف ← (بريد، كلمة سر، دور).
  final Map<String, ({String email, String password, UserRole role})> created =
      {};

  /// سجل كلمات السر المعاد تعيينها: معرّف ← كلمة السر الأخيرة.
  final Map<String, String> resets = {};

  /// `true`: كل استدعاء يفشل بانقطاع الشبكة (محاكاة انقطاع الخادم).
  bool failing = false;

  /// `true`: الخادم يرفض الإنشاء رفضاً نهائياً (البريد مستعمل).
  bool rejecting = false;

  int _next = 0;

  @override
  Future<String> provision({
    required String email,
    required String password,
    required UserRole role,
    String? id,
  }) async {
    if (rejecting) {
      throw const AuthFailureException(
        AuthFailure.unknown,
        message: 'يوجد حساب بهذا البريد مسبقاً',
      );
    }
    if (failing) throw const AuthFailureException(AuthFailure.network);
    final id = 'acct-${++_next}';
    created[id] = (email: email, password: password, role: role);
    return id;
  }

  @override
  Future<void> resetPassword({
    required String accountId,
    required String password,
  }) async {
    if (failing) throw const AuthFailureException(AuthFailure.network);
    resets[accountId] = password;
  }
}
