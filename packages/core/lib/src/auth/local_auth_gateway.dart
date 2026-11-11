import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import '../domain/enums.dart';
import 'auth_gateway.dart';
import 'credentials.dart';
import 'password_hasher.dart';

/// دخول بلا خادم، للمعاينة المحلية قبل ضبط Supabase.
///
/// الحسابات في `user_accounts` المحلي وكلمات سرها مشتقة بـ PBKDF2 في
/// `local_credentials`. لا يُستعمل إلا عند غياب إعدادات الخادم، وما يُنشأ فيه
/// لا ينتقل إلى الخادم لاحقاً (معرّفات الحسابات هناك يصدرها Supabase Auth).
class LocalAuthGateway implements AuthGateway {
  LocalAuthGateway._(this.db, this._identity, this._iterations, this._clock);

  /// يفتح البوابة ويستعيد المستخدم الذي سجّل دخوله من قبل على هذا الجهاز.
  static Future<LocalAuthGateway> open(
    AppDatabase db, {
    int iterations = PasswordHasher.defaultIterations,
    int Function()? clock,
  }) async {
    final saved = await (db.select(
      db.deviceSession,
    )..where((t) => t.id.equals(1))).getSingleOrNull();
    return LocalAuthGateway._(
      db,
      saved == null
          ? null
          : AuthIdentity(id: saved.accountId, email: saved.email),
      iterations,
      clock ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch),
    );
  }

  final AppDatabase db;
  final int _iterations;
  final int Function() _clock;
  AuthIdentity? _identity;

  @override
  AuthIdentity? get currentIdentity => _identity;

  /// هل لا يوجد أي حساب بعد؟ (فيُعرض إنشاء حساب صاحب المدرسة)
  Future<bool> hasNoAccounts() async {
    final count = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM user_accounts WHERE deleted_at IS NULL',
          readsFrom: {db.userAccounts},
        )
        .getSingle();
    return count.read<int>('n') == 0;
  }

  /// يخزّن كلمة سر لحساب موجود (إنشاء أو تغيير).
  Future<void> setPassword(String accountId, String password) async {
    final problem = LoginCredentials.passwordProblem(password);
    if (problem != null) {
      throw AuthFailureException(AuthFailure.weakPassword, message: problem);
    }
    final digest = await PasswordHasher.create(
      password,
      iterations: _iterations,
    );
    await db
        .into(db.localCredentials)
        .insertOnConflictUpdate(
          LocalCredentialsCompanion.insert(
            accountId: accountId,
            salt: digest.salt,
            hash: digest.hash,
            iterations: digest.iterations,
            updatedAt: _clock(),
          ),
        );
  }

  @override
  Future<AuthIdentity> signIn({
    required String email,
    required String password,
  }) async {
    final account = await db
        .customSelect(
          'SELECT a.id, a.email, c.salt, c.hash, c.iterations '
          'FROM user_accounts a '
          'JOIN local_credentials c ON c.account_id = a.id '
          'WHERE a.email = ? AND a.deleted_at IS NULL',
          variables: [Variable<String>(email)],
          readsFrom: {db.userAccounts, db.localCredentials},
        )
        .getSingleOrNull();
    if (account == null) {
      // نفس الزمن تقريباً سواء وُجد الحساب أم لا، فلا يُعرف وجوده بالتوقيت.
      await PasswordHasher.verify(
        password,
        PasswordDigest(
          salt: 'AAAAAAAAAAAAAAAAAAAAAA==',
          hash: 'AA==',
          iterations: _iterations,
        ),
      );
      throw const AuthFailureException(AuthFailure.invalidCredentials);
    }
    final matches = await PasswordHasher.verify(
      password,
      PasswordDigest(
        salt: account.read<String>('salt'),
        hash: account.read<String>('hash'),
        iterations: account.read<int>('iterations'),
      ),
    );
    if (!matches) {
      throw const AuthFailureException(AuthFailure.invalidCredentials);
    }
    return _identity = AuthIdentity(
      id: account.read<String>('id'),
      email: account.read<String>('email'),
    );
  }

  @override
  Future<void> signOut() async {
    _identity = null;
  }

  @override
  Future<void> changePassword({required String newPassword}) async {
    final identity = _identity;
    if (identity == null) {
      throw const AuthFailureException(AuthFailure.notSignedIn);
    }
    await setPassword(identity.id, newPassword);
  }

  /// ينشئ حساب صاحب المدرسة عند الإعداد الأول على الجهاز (مرة واحدة).
  ///
  /// يرمي [AuthFailureException] إن وُجد حساب مسبقاً أو كانت البيانات غير
  /// صالحة. صاحب المدرسة اختار كلمة سره بنفسه فلا يُجبر على تغييرها.
  Future<AuthIdentity> createFirstOwner({
    required String email,
    required String displayName,
    required String password,
  }) async {
    final address = LoginCredentials.normalizeEmail(email);
    final emailProblem = LoginCredentials.emailProblem(address);
    if (emailProblem != null) {
      throw AuthFailureException(
        AuthFailure.invalidEmail,
        message: emailProblem,
      );
    }
    final name = displayName.trim();
    if (name.isEmpty) {
      throw const AuthFailureException(
        AuthFailure.unknown,
        message: 'أدخل اسم صاحب المدرسة',
      );
    }
    if (!await hasNoAccounts()) {
      throw const AuthFailureException(
        AuthFailure.unknown,
        message: 'تم إنشاء حساب على هذا الجهاز من قبل',
      );
    }
    final id = const Uuid().v4();
    final writer = SyncWriter(
      db,
      actor: () => Actor(userId: id, userName: name),
      clock: _clock,
    );
    await setPassword(id, password);
    await writer.save(
      db.userAccounts,
      UserAccountsCompanion.insert(
        id: id,
        createdAt: writer.now(),
        updatedAt: writer.now(),
        email: address,
        role: UserRole.owner.code,
        displayName: Value(name),
        mustChangePassword: const Value(false),
      ),
      key: {'id': id},
    );
    return AuthIdentity(id: id, email: address);
  }
}

/// بوابة تُستعمل حين لا يكون الخادم مهيّأً وليس الوضع المحلي مسموحاً
/// (تطبيقا الأستاذ والوليّ): كل محاولة دخول تُرفض برسالة واضحة.
class UnconfiguredAuthGateway implements AuthGateway {
  const UnconfiguredAuthGateway();

  /// الرسالة الظاهرة للمستخدم.
  static const String message =
      'الخادم غير مهيّأ في هذه النسخة. اطلب من الإدارة نسخة مفعّلة.';

  @override
  AuthIdentity? get currentIdentity => null;

  @override
  Future<AuthIdentity> signIn({
    required String email,
    required String password,
  }) async =>
      throw const AuthFailureException(AuthFailure.network, message: message);

  @override
  Future<void> signOut() async {}

  @override
  Future<void> changePassword({required String newPassword}) async =>
      throw const AuthFailureException(AuthFailure.notSignedIn);
}
