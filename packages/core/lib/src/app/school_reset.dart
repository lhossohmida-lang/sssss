import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

/// العبارة التي يرسلها التطبيق بعد أن يكتب المالك تأكيده، وتشترطها دالة `reset-school` على الخادم
/// فلا تُنفَّذ إعادة التعيين بطلب ناقص أو عابر.
const String schoolResetConfirmation = 'RESET-SCHOOL';

/// سبب تعذّر إعادة تعيين المدرسة.
enum SchoolResetFailure {
  /// كلمة سر المالك غير صحيحة.
  wrongPassword,

  /// ليس صاحب المدرسة.
  forbidden,

  /// دالة الإعادة غير منشورة على هذا الخادم أو الخادم غير مهيّأ لها.
  notAvailable,

  /// لا اتصال بالإنترنت أو عطل مؤقت: لم يُمسح شيء، وتُعاد المحاولة.
  network,
}

/// إعادة التعيين لم تُنفَّذ؛ [message] بالعربية لعرضه.
class SchoolResetException implements Exception {
  const SchoolResetException(this.failure, this.message);

  final SchoolResetFailure failure;
  final String message;

  @override
  String toString() => message;
}

/// ما تمّ في إعادة تعيين المدرسة على الخادم.
class SchoolResetResult {
  const SchoolResetResult({
    required this.epoch,
    required this.removedAccounts,
    this.authFailures = 0,
    this.directoryFailures = 0,
    this.storageFailures = 0,
  });

  /// دورة المدرسة الجديدة: تعرف بها الأجهزة أن مدرستها أُعيدت فتمسح بياناتها.
  final String epoch;

  /// عدد حسابات غير المالك التي حُذفت.
  final int removedAccounts;

  /// ما تعذّر حذفه بعد مسح البيانات: حسابات دخول، وأرقام في دليل المدارس، وملفات. إعادة
  /// التشغيل تُكمله.
  final int authFailures;
  final int directoryFailures;
  final int storageFailures;

  int get leftovers => authFailures + directoryFailures + storageFailures;

  /// هل مُسح كل شيء دون بقايا؟
  bool get complete => leftovers == 0;
}

/// إعادة تعيين المدرسة بالكامل على الخادم (لصاحبها).
abstract interface class SchoolResetGateway {
  /// يمسح كل بيانات المدرسة وحسابات من عدا المالك وملفاتها، بعد التحقق من [password]. يرمي
  /// [SchoolResetException].
  Future<SchoolResetResult> reset({required String password});
}

/// تنفيذ [SchoolResetGateway] بدالة `reset-school` على Supabase.
class SupabaseSchoolResetGateway implements SchoolResetGateway {
  SupabaseSchoolResetGateway(this.client);

  final SupabaseClient client;

  @override
  Future<SchoolResetResult> reset({required String password}) async {
    try {
      final response = await client.functions.invoke(
        'reset-school',
        body: {
          'current_password': password,
          'confirm': schoolResetConfirmation,
        },
      );
      return parse(response.data);
    } on FunctionException catch (e) {
      throw mapFailure(e.status, e.details);
    } on SocketException {
      throw _network;
    } on TimeoutException {
      throw _network;
    }
  }

  static const SchoolResetException _network = SchoolResetException(
    SchoolResetFailure.network,
    'لا اتصال بالإنترنت أو عطل مؤقت: لم يُمسح شيء. أعد المحاولة',
  );

  /// يحوّل رد الدالة الناجح إلى نتيجة، ويرمي إن لم يكن بالشكل المتوقع.
  @visibleForTesting
  static SchoolResetResult parse(Object? data) {
    if (data is! Map || data['ok'] != true || data['epoch'] is! String) {
      throw const SchoolResetException(
        SchoolResetFailure.notAvailable,
        'رد غير مفهوم من الخادم: لا يُعرف إن اكتملت الإعادة',
      );
    }
    final failures = data['failures'];
    int count(String key) {
      final value = failures is Map ? failures[key] : null;
      return value is num ? value.toInt() : 0;
    }

    final removed = data['removed_accounts'];
    return SchoolResetResult(
      epoch: data['epoch'] as String,
      removedAccounts: removed is num ? removed.toInt() : 0,
      authFailures: count('auth'),
      directoryFailures: count('directory'),
      storageFailures: count('storage'),
    );
  }

  /// رفض الدالة (قبل أي مسح) بحسب حالته ورمز خطئها.
  @visibleForTesting
  static SchoolResetException mapFailure(int status, [Object? details]) {
    final code = details is Map ? details['error'] : null;
    if (status == 403 && code == 'wrong_password') {
      return const SchoolResetException(
        SchoolResetFailure.wrongPassword,
        'كلمة السر غير صحيحة',
      );
    }
    if (status == 403) {
      return const SchoolResetException(
        SchoolResetFailure.forbidden,
        'إعادة تعيين المدرسة لصاحبها وحده',
      );
    }
    if (status == 401) {
      return const SchoolResetException(
        SchoolResetFailure.forbidden,
        'انتهت جلستك: سجّل الدخول من جديد وأعد المحاولة',
      );
    }
    if (status == 400) {
      return const SchoolResetException(
        SchoolResetFailure.notAvailable,
        'طلب غير صالح: حدّث التطبيق وأعد المحاولة',
      );
    }
    if (status == 404 || status == 503) {
      return const SchoolResetException(
        SchoolResetFailure.notAvailable,
        'الإعادة غير متاحة على خادم هذه المدرسة بعد (يلزم نشر دالة reset-school)',
      );
    }
    if (status >= 500) return _network;
    return const SchoolResetException(
      SchoolResetFailure.notAvailable,
      'تعذّرت الإعادة',
    );
  }
}
