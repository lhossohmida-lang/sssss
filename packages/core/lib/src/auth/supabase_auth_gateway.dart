import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gateway.dart';

/// [AuthGateway] على Supabase Auth (بريد + كلمة سر).
///
/// مكتبة Supabase تحفظ الجلسة وتجدّد رمز الدخول بنفسها، فتبقى الجلسة بين
/// التشغيلات. هذا الغلاف رقيق ويُتحقق منه على المشروع الحقيقي في المهمة 8.2؛
/// منطق المصادقة نفسه يُختبر عبر الواجهة المجرّدة.
class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this.client);

  final SupabaseClient client;

  @override
  AuthIdentity? get currentIdentity {
    final user = client.auth.currentUser;
    if (user == null || client.auth.currentSession == null) return null;
    return AuthIdentity(id: user.id, email: user.email ?? '');
  }

  @override
  Future<AuthIdentity> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user == null) {
        throw const AuthFailureException(AuthFailure.invalidCredentials);
      }
      return AuthIdentity(id: user.id, email: user.email ?? email);
    } on AuthException catch (e) {
      throw mapException(e);
    } on SocketException {
      throw const AuthFailureException(AuthFailure.network);
    } on TimeoutException {
      throw const AuthFailureException(AuthFailure.network);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } on AuthException {
      // الخروج المحلي يتم حتى لو تعذّر إبلاغ الخادم.
    } on SocketException {
      // دون إنترنت: تُمحى الجلسة المحلية فقط.
    }
  }

  @override
  Future<void> changePassword({required String newPassword}) async {
    if (client.auth.currentSession == null) {
      throw const AuthFailureException(AuthFailure.notSignedIn);
    }
    try {
      await client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw mapException(e);
    } on SocketException {
      throw const AuthFailureException(AuthFailure.network);
    } on TimeoutException {
      throw const AuthFailureException(AuthFailure.network);
    }
  }

  @override
  Future<AuthIdentity> changeEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    final user = client.auth.currentUser;
    if (user == null || client.auth.currentSession == null) {
      throw const AuthFailureException(AuthFailure.notSignedIn);
    }
    try {
      await client.functions.invoke(
        'change-login',
        body: {'new_email': newEmail, 'current_password': currentPassword},
      );
      // الجلسة القديمة تحمل البريد القديم: تُجدَّد ليصير بريدها الجديد.
      await client.auth.refreshSession();
    } on FunctionException catch (e) {
      throw _mapChange(e);
    } on AuthException catch (e) {
      throw mapException(e);
    } on SocketException {
      throw const AuthFailureException(AuthFailure.network);
    } on TimeoutException {
      throw const AuthFailureException(AuthFailure.network);
    }
    return AuthIdentity(id: user.id, email: newEmail);
  }

  static AuthFailureException _mapChange(FunctionException e) {
    return switch (e.status) {
      403 => const AuthFailureException(
        AuthFailure.invalidCredentials,
        message: 'كلمة السر الحالية غير صحيحة',
      ),
      409 => const AuthFailureException(
        AuthFailure.unknown,
        message: 'رقم الهاتف مستعمل في حساب آخر',
      ),
      >= 500 => const AuthFailureException(
        AuthFailure.network,
        message: 'تعذّر تغيير رقم الدخول الآن، أعد المحاولة بعد قليل',
      ),
      _ => const AuthFailureException(
        AuthFailure.unknown,
        message: 'تعذّر تغيير رقم الدخول',
      ),
    };
  }

  /// يحوّل رفض Supabase إلى سبب يفهمه المستخدم. يفرّق بين كلمة سر أو رقم خاطئ (400 برمز
  /// `invalid_credentials`) ومفتاح ربط مرفوض (401) فلا تُنسب كل الأعطال إلى كلمة السر.
  @visibleForTesting
  static AuthFailureException mapException(AuthException e) {
    final status = int.tryParse(e.statusCode ?? '');
    final code = e.code ?? '';
    if (code == 'weak_password') {
      return const AuthFailureException(AuthFailure.weakPassword);
    }
    if (code == 'invalid_credentials') {
      return const AuthFailureException(AuthFailure.invalidCredentials);
    }
    // 401: رفض الخادم المفتاح العام المحفوظ على الجهاز (قديم أو مُلغى) لا كلمة السر.
    if (status == 401 ||
        code == 'invalid_api_key' ||
        code == 'no_authorization' ||
        code == 'bad_jwt') {
      return const AuthFailureException(AuthFailure.serverRejected);
    }
    if (status == 429 || code == 'over_request_rate_limit') {
      return const AuthFailureException(
        AuthFailure.unknown,
        message: 'محاولات دخول كثيرة، انتظر دقيقة ثم أعد المحاولة',
      );
    }
    if (status != null && status >= 500) {
      return const AuthFailureException(AuthFailure.network);
    }
    if (status == 400) {
      // 400 آخر (بريد غير مؤكد، بيانات غير صالحة...): يُذكر رمزه ليُعرف سببه بدل «كلمة سر خاطئة».
      return AuthFailureException(
        AuthFailure.unknown,
        message: 'تعذّر الدخول (${code.isEmpty ? '400' : code})، أعد المحاولة',
      );
    }
    return const AuthFailureException(AuthFailure.unknown);
  }
}
