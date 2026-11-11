import 'package:school_core/school_core.dart';

/// خدمة مصادقة وهمية: حسابات في الذاكرة، وجلسة تُحفظ كما يفعل Supabase.
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway(this.accounts);

  /// بريد → (معرّف، كلمة سر).
  final Map<String, ({String id, String password})> accounts;

  AuthIdentity? _identity;
  bool offline = false;
  int signOuts = 0;
  String? lastPasswordSet;

  /// يحاكي جلسة محفوظة من تشغيل سابق.
  void restoreIdentity(AuthIdentity? identity) => _identity = identity;

  @override
  AuthIdentity? get currentIdentity => _identity;

  @override
  Future<AuthIdentity> signIn({
    required String email,
    required String password,
  }) async {
    if (offline) throw const AuthFailureException(AuthFailure.network);
    final account = accounts[email];
    if (account == null || account.password != password) {
      throw const AuthFailureException(AuthFailure.invalidCredentials);
    }
    return _identity = AuthIdentity(id: account.id, email: email);
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    _identity = null;
  }

  @override
  Future<void> changePassword({required String newPassword}) async {
    if (offline) throw const AuthFailureException(AuthFailure.network);
    final identity = _identity;
    if (identity == null) {
      throw const AuthFailureException(AuthFailure.notSignedIn);
    }
    accounts[identity.email] = (id: identity.id, password: newPassword);
    lastPasswordSet = newPassword;
  }
}
