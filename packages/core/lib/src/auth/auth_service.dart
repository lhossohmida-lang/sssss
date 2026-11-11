import 'dart:async';

import 'package:drift/drift.dart';

import '../app_identity.dart';
import '../data/local/app_database.dart';
import '../data/local/sync_writer.dart';
import 'account_directory.dart';
import 'auth_gateway.dart';
import 'auth_session.dart';
import 'credentials.dart';
import 'session_store.dart';

/// المصادقة كما تستعملها التطبيقات الثلاثة: دخول بالبريد وكلمة السر، حفظ
/// الجلسة، تحديد الدور والصلاحيات، وتغيير كلمة السر عند أول دخول.
///
/// الدور يُقرأ من `user_accounts`: من القاعدة المحلية إن كانت مزامَنة، وإلا
/// من الخادم عند أول دخول على جهاز جديد.
class AuthService {
  AuthService({
    required this.gateway,
    required this.store,
    required this.directories,
    required this.writer,
    this.app,
  });

  final AuthGateway gateway;
  final SessionStore store;

  /// مصادر الحساب بالترتيب: المحلي أولاً ثم الخادم.
  final List<AccountDirectory> directories;

  /// نقطة الكتابة الموحّدة؛ تُؤخذ عند الحاجة لأن صاحب العملية هو هذه الجلسة.
  final SyncWriter Function() writer;

  /// التطبيق الذي يعمل فيه هذا الحساب؛ إن حُدّد مُنع دخول دور لا يخصه.
  final AppIdentity? app;

  final StreamController<AuthSession?> _sessions =
      StreamController<AuthSession?>.broadcast();

  AuthSession? _current;

  /// الجلسة الحالية، أو `null` إن لم يسجّل أحد الدخول.
  AuthSession? get current => _current;

  /// هل سُجّل الدخول وانتهى تغيير كلمة السر الأول؟
  bool get isReady => _current != null && !_current!.mustChangePassword;

  /// تغيّرات الجلسة: دخول، تغيير صلاحيات، خروج (`null`).
  Stream<AuthSession?> get changes => _sessions.stream;

  /// يستعيد الجلسة المحفوظة عند تشغيل التطبيق.
  ///
  /// يُبقي الجلسة المحفوظة حتى دون إنترنت، ويمحوها إن كانت جلسة الخادم
  /// قد انتهت أو حُذف الحساب.
  Future<AuthSession?> restore() async {
    final saved = await store.read();
    if (saved == null) {
      _emit(null);
      return null;
    }
    if (gateway.currentIdentity == null) {
      await store.clear();
      _emit(null);
      return null;
    }
    final fresh = await _lookupLocal(saved.accountId);
    final session = AuthSession(fresh ?? saved.account);
    if (fresh != null) await store.write(session);
    _emit(session);
    return session;
  }

  /// يسجّل الدخول بالبريد وكلمة السر.
  ///
  /// يرمي [AuthFailureException] إن رُفضت البيانات، أو لم يوجد حساب
  /// للمستخدم، أو كان دوره لا يدخل من هذا التطبيق.
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    final address = LoginCredentials.normalizeEmail(email);
    if (LoginCredentials.emailProblem(address) != null) {
      throw const AuthFailureException(AuthFailure.invalidEmail);
    }
    if (password.isEmpty) {
      throw const AuthFailureException(AuthFailure.invalidCredentials);
    }
    final identity = await gateway.signIn(email: address, password: password);
    final AccountRecord? record;
    try {
      record = await _lookup(identity.id);
    } on AuthFailureException {
      await gateway.signOut();
      rethrow;
    }
    if (record == null) {
      await gateway.signOut();
      throw const AuthFailureException(AuthFailure.noAccount);
    }
    final session = AuthSession(record);
    final target = app;
    if (target != null && !session.allowsApp(target)) {
      await gateway.signOut();
      throw AuthFailureException(
        AuthFailure.wrongApp,
        message:
            'حساب ${record.role.label} لا يدخل من تطبيق ${target.displayName}',
      );
    }
    await store.write(session);
    _emit(session);
    return session;
  }

  /// يخرج ويمحو الجلسة المحفوظة على الجهاز.
  Future<void> signOut() async {
    await gateway.signOut();
    await store.clear();
    _emit(null);
  }

  /// يغيّر كلمة السر، ويرفع علامة «يجب تغيير كلمة السر» عند أول دخول.
  ///
  /// يرمي [AuthFailureException] إن لم يُسجَّل الدخول أو كانت كلمة السر
  /// الجديدة غير مقبولة.
  Future<AuthSession> changePassword({required String newPassword}) async {
    final session = _current;
    if (session == null) {
      throw const AuthFailureException(AuthFailure.notSignedIn);
    }
    final problem = LoginCredentials.passwordProblem(newPassword);
    if (problem != null) {
      throw AuthFailureException(AuthFailure.weakPassword, message: problem);
    }
    await gateway.changePassword(newPassword: newPassword);
    if (!session.mustChangePassword) return session;
    final updated = AuthSession(
      session.account.copyWith(mustChangePassword: false),
    );
    await _saveAccountRow(updated);
    await store.write(updated);
    _emit(updated);
    return updated;
  }

  /// يعيد قراءة الحساب محلياً بعد المزامنة (تغيّر صلاحيات أو اسم أو حذف).
  ///
  /// يخرج إن حُذف الحساب من النظام.
  Future<AuthSession?> refresh() async {
    final session = _current;
    if (session == null) return null;
    final record = await _lookupLocal(session.accountId);
    if (record == null) return session;
    if (record == session.account) return session;
    final updated = AuthSession(record);
    await store.write(updated);
    _emit(updated);
    return updated;
  }

  /// يُغلق بث التغيّرات.
  Future<void> dispose() => _sessions.close();

  /// يكتب صف الحساب محلياً بعد تغيير كلمة السر، فيُدفع إلى الخادم.
  Future<void> _saveAccountRow(AuthSession session) async {
    final account = session.account;
    final sync = writer();
    await sync.save(
      sync.db.userAccounts,
      UserAccountsCompanion.insert(
        id: account.id,
        createdAt: sync.now(),
        updatedAt: sync.now(),
        email: account.email,
        role: account.role.code,
        entityId: Value(account.entityId),
        displayName: Value(account.displayName),
        mustChangePassword: const Value(false),
      ),
      key: {'id': account.id},
    );
  }

  Future<AccountRecord?> _lookup(String accountId) async {
    for (final directory in directories) {
      final record = await directory.find(accountId);
      if (record != null) return record;
    }
    return null;
  }

  /// يقرأ الحساب من المصادر المحلية فقط (لا شبكة).
  Future<AccountRecord?> _lookupLocal(String accountId) async {
    for (final directory in directories) {
      if (directory is! LocalAccountDirectory) continue;
      final record = await directory.find(accountId);
      if (record != null) return record;
    }
    return null;
  }

  void _emit(AuthSession? session) {
    _current = session;
    if (!_sessions.isClosed) _sessions.add(session);
  }
}
