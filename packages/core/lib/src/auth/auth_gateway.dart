/// سبب فشل عملية مصادقة، مع نصه العربي الظاهر للمستخدم.
enum AuthFailure {
  invalidCredentials('البريد أو كلمة السر غير صحيحة'),
  weakPassword('كلمة السر غير مقبولة'),
  invalidEmail('البريد غير مكتوب بصيغة صحيحة'),
  network('لا يوجد اتصال بالإنترنت'),
  notSignedIn('لم يُسجَّل الدخول'),
  noAccount('لا يوجد حساب لهذا المستخدم في النظام'),
  wrongApp('هذا الحساب لا يدخل من هذا التطبيق'),
  unknown('تعذّر إتمام العملية، أعد المحاولة');

  const AuthFailure(this.message);

  /// النص العربي الافتراضي.
  final String message;

  /// هل يُعاد المحاولة تلقائياً؟ (عطل شبكة فقط)
  bool get transient => this == network;
}

/// فشل في المصادقة. [failure] يحدد السبب و[message] نصه للمستخدم.
class AuthFailureException implements Exception {
  const AuthFailureException(this.failure, {this._message});

  final AuthFailure failure;
  final String? _message;

  /// النص العربي الظاهر للمستخدم.
  String get message => _message ?? failure.message;

  /// هل العطل مؤقت فيُعاد المحاولة؟
  bool get transient => failure.transient;

  @override
  String toString() => message;
}

/// مستخدم مصادَق عليه كما يعرفه الخادم، قبل معرفة دوره.
class AuthIdentity {
  const AuthIdentity({required this.id, required this.email});

  /// معرّف المستخدم على الخادم، وهو نفسه `user_accounts.id`.
  final String id;

  final String email;

  @override
  bool operator ==(Object other) =>
      other is AuthIdentity && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);

  @override
  String toString() => 'AuthIdentity($id, $email)';
}

/// خدمة المصادقة (بريد + كلمة سر) كما يراها التطبيق.
///
/// واجهة مجرّدة: يُنفّذها [AuthGateway] على Supabase في الإنتاج، وخادم وهمي
/// في الاختبارات. الجلسة تُحفظ في التنفيذ نفسه فلا يُطلب الدخول كل مرة.
abstract interface class AuthGateway {
  /// المستخدم المصادَق عليه حالياً، أو `null` إن لم تُحفظ جلسة.
  AuthIdentity? get currentIdentity;

  /// يسجّل الدخول ويحفظ الجلسة.
  ///
  /// يرمي [AuthFailureException] عند الرفض أو عند عطل الشبكة.
  Future<AuthIdentity> signIn({
    required String email,
    required String password,
  });

  /// يخرج ويمحو الجلسة المحفوظة.
  Future<void> signOut();

  /// يغيّر كلمة سر المستخدم الحالي.
  Future<void> changePassword({required String newPassword});
}
