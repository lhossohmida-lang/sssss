import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthApiException;

AuthFailureException map(String status, {String? code, String? message}) =>
    SupabaseAuthGateway.mapException(
      AuthApiException(message ?? 'x', statusCode: status, code: code),
    );

void main() {
  group('تحويل رفض Supabase إلى سبب مفهوم', () {
    test('كلمة سر أو رقم خاطئ: 400 برمز invalid_credentials', () {
      final e = map('400', code: 'invalid_credentials');
      expect(e.failure, AuthFailure.invalidCredentials);
      expect(e.message, 'رقم الهاتف أو كلمة السر غير صحيحة');
    });

    test(
      'مفتاح الربط مرفوض (401 بلا رمز كما يردّ البوابة) لا يُنسب إلى كلمة السر',
      () {
        final e = map('401', message: 'Invalid API key');
        expect(e.failure, AuthFailure.serverRejected);
        expect(e.message, contains('مفتاح ربط'));
        expect(e.message, contains('ربط الجهاز بمدرسة أخرى'));
        expect(e.message, isNot(contains('كلمة السر غير صحيحة')));
      },
    );

    test('رموز الرفض الأخرى للمفتاح أو الرمز المميّز', () {
      for (final code in ['invalid_api_key', 'no_authorization', 'bad_jwt']) {
        expect(
          map('400', code: code).failure,
          AuthFailure.serverRejected,
          reason: code,
        );
      }
    });

    test('كثرة المحاولات: رسالة انتظار', () {
      expect(map('429').message, contains('انتظر'));
      expect(
        map('400', code: 'over_request_rate_limit').message,
        contains('محاولات دخول كثيرة'),
      );
    });

    test('أعطال الخادم تُعامل كعطل اتصال يُعاد', () {
      for (final status in ['500', '502', '503']) {
        final e = map(status);
        expect(e.failure, AuthFailure.network, reason: status);
        expect(e.transient, isTrue);
      }
    });

    test('400 برمز آخر يُذكر رمزه بدل «كلمة سر خاطئة»', () {
      final e = map('400', code: 'email_not_confirmed');
      expect(e.failure, AuthFailure.unknown);
      expect(e.message, contains('email_not_confirmed'));
      expect(e.message, isNot(contains('كلمة السر')));
      expect(map('400').message, contains('400'));
    });

    test('كلمة سر ضعيفة عند التغيير', () {
      expect(
        map('422', code: 'weak_password').failure,
        AuthFailure.weakPassword,
      );
    });

    test('استثناء بلا حالة ولا رمز: عطل عام', () {
      final e = SupabaseAuthGateway.mapException(const AuthApiException('x'));
      expect(e.failure, AuthFailure.unknown);
      expect(e.message, AuthFailure.unknown.message);
    });
  });
}
