import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/enums.dart';
import 'auth_gateway.dart';
import 'local_auth_gateway.dart';

/// ينشئ حساب دخول (بريد وكلمة سر) ويعيد معرّفه.
///
/// كل الحسابات تُنشأ من تطبيق الإدارة (إجابة ب1). في وضع الخادم لا يستطيع
/// تطبيق أن ينشئ مستخدماً في Supabase Auth بمفتاحه العام، فيُستدعى دالة
/// خادم؛ وفي الوضع المحلي تُحفظ بصمة كلمة السر على الجهاز.
abstract interface class AccountProvisioner {
  /// ينشئ الحساب ويعيد معرّفه (وهو نفسه معرّف المستخدم على الخادم).
  Future<String> provision({
    required String email,
    required String password,
    required UserRole role,
  });

  /// يغيّر كلمة سر حساب موجود (إعادة توليد بيانات الدخول).
  Future<void> resetPassword({
    required String accountId,
    required String password,
  });
}

/// الوضع المحلي: المعرّف يُولَّد على الجهاز وكلمة السر تُشتق محلياً.
class LocalAccountProvisioner implements AccountProvisioner {
  LocalAccountProvisioner(this.gateway);

  final LocalAuthGateway gateway;

  @override
  Future<String> provision({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final id = const Uuid().v4();
    await gateway.setPassword(id, password);
    return id;
  }

  @override
  Future<void> resetPassword({
    required String accountId,
    required String password,
  }) => gateway.setPassword(accountId, password);
}

/// وضع الخادم: دالتا Supabase Edge `provision-account` و`reset-account-password`
/// (تُكتبان وتُنشران في المهمة 8.1 لأنهما تحتاجان مفتاح الخدمة السرّي الذي
/// لا يجوز أن يخرج من الخادم). الغلاف رقيق ويُتحقق منه في 8.2.
class SupabaseAccountProvisioner implements AccountProvisioner {
  SupabaseAccountProvisioner(this.client);

  final SupabaseClient client;

  @override
  Future<String> provision({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final response = await _invoke('provision-account', {
      'email': email,
      'password': password,
      'role': role.code,
    });
    final id = response is Map ? response['id'] : null;
    if (id is! String || id.isEmpty) {
      throw const AuthFailureException(
        AuthFailure.unknown,
        message: 'رد غير مفهوم من الخادم عند إنشاء الحساب',
      );
    }
    return id;
  }

  @override
  Future<void> resetPassword({
    required String accountId,
    required String password,
  }) async {
    await _invoke('reset-account-password', {
      'id': accountId,
      'password': password,
    });
  }

  Future<Object?> _invoke(String function, Map<String, Object> body) async {
    try {
      final response = await client.functions.invoke(function, body: body);
      return response.data;
    } on FunctionException catch (e) {
      throw AuthFailureException(
        e.status >= 500 ? AuthFailure.network : AuthFailure.unknown,
        message: e.status == 409
            ? 'يوجد حساب بهذا البريد مسبقاً'
            : 'تعذّر إنشاء الحساب على الخادم (${e.status})',
      );
    }
  }
}
