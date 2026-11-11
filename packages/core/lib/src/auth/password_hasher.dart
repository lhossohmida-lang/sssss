import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// كلمة سر مشتقة جاهزة للتخزين: الملح والتكرارات والبصمة.
class PasswordDigest {
  const PasswordDigest({
    required this.salt,
    required this.hash,
    required this.iterations,
  });

  /// الملح (base64).
  final String salt;

  /// ناتج PBKDF2 (base64).
  final String hash;
  final int iterations;
}

/// اشتقاق كلمات السر بـ PBKDF2-HMAC-SHA256 للوضع المحلي (دون خادم).
///
/// في وضع الخادم لا تُخزَّن كلمات السر على الجهاز أبداً؛ هذا للمعاينة
/// المحلية فقط. الاشتقاق ثقيل عمداً، فيُنفَّذ في isolate خلفي.
abstract final class PasswordHasher {
  /// عدد التكرارات الافتراضي.
  static const int defaultIterations = 60000;

  static const int _saltLength = 16;
  static const int _keyLength = 32;

  /// يشتق بصمة جديدة بملح عشوائي، خارج خيط الواجهة.
  static Future<PasswordDigest> create(
    String password, {
    int iterations = defaultIterations,
    Random? random,
  }) {
    final source = random ?? Random.secure();
    final salt = Uint8List.fromList([
      for (var i = 0; i < _saltLength; i++) source.nextInt(256),
    ]);
    return Isolate.run(
      () => PasswordDigest(
        salt: base64Encode(salt),
        hash: base64Encode(derive(password, salt, iterations)),
        iterations: iterations,
      ),
    );
  }

  /// هل [password] تطابق [digest]؟ المقارنة بزمن ثابت.
  static Future<bool> verify(String password, PasswordDigest digest) {
    final Uint8List salt;
    final Uint8List expected;
    try {
      salt = base64Decode(digest.salt);
      expected = base64Decode(digest.hash);
    } on FormatException {
      return Future.value(false);
    }
    final iterations = digest.iterations;
    if (iterations < 1) return Future.value(false);
    return Isolate.run(() {
      final actual = derive(password, salt, iterations);
      if (actual.length != expected.length) return false;
      var diff = 0;
      for (var i = 0; i < actual.length; i++) {
        diff |= actual[i] ^ expected[i];
      }
      return diff == 0;
    });
  }

  /// PBKDF2-HMAC-SHA256 بمفتاح من 32 بايتاً (كتلة واحدة). عام ليُتحقق من
  /// متجهات الاختبار المعروفة.
  static Uint8List derive(String password, Uint8List salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final block = Uint8List(salt.length + 4)
      ..setRange(0, salt.length, salt)
      ..[salt.length + 3] = 1;
    var u = Uint8List.fromList(hmac.convert(block).bytes);
    final result = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < _keyLength; j++) {
        result[j] ^= u[j];
      }
    }
    return result;
  }
}
