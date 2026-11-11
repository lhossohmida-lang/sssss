import 'dart:math';

/// صاحب رمز QR، ويُعرف من بادئة الرمز.
enum QrOwnerKind {
  student('S-'),
  teacher('T-'),
  worker('W-');

  const QrOwnerKind(this.prefix);

  /// بادئة الرمز: `S-` تلميذ، `T-` أستاذ، `W-` عامل.
  final String prefix;
}

/// رمز QR صالح بعد تحليله.
class ParsedQrCode {
  const ParsedQrCode({required this.kind, required this.code});

  final QrOwnerKind kind;

  /// الرمز الكامل مع البادئة، كما يُخزَّن في القاعدة.
  final String code;

  @override
  bool operator ==(Object other) =>
      other is ParsedQrCode && other.kind == kind && other.code == code;

  @override
  int get hashCode => Object.hash(kind, code);

  @override
  String toString() => 'ParsedQrCode(${kind.name}, $code)';
}

/// توليد رموز QR وتمييز نوعها.
abstract final class QrCodes {
  /// حروف وأرقام دون الملتبسة (0 و O، 1 و I و L).
  static const String _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  /// طول الجزء العشوائي بعد البادئة.
  static const int bodyLength = 10;

  static final RegExp _body = RegExp('^[$_alphabet]{$bodyLength}\$');

  /// يحلّل النص الممسوح. يعيد `null` إن لم يكن رمزاً من رموز النظام.
  static ParsedQrCode? parse(String raw) {
    final text = raw.trim().toUpperCase();
    for (final kind in QrOwnerKind.values) {
      if (text.startsWith(kind.prefix) &&
          _body.hasMatch(text.substring(kind.prefix.length))) {
        return ParsedQrCode(kind: kind, code: text);
      }
    }
    return null;
  }

  /// يولّد رمزاً جديداً لصاحب من النوع [kind].
  static String generate(QrOwnerKind kind, {Random? random}) {
    final source = random ?? Random.secure();
    final buffer = StringBuffer(kind.prefix);
    for (var i = 0; i < bodyLength; i++) {
      buffer.write(_alphabet[source.nextInt(_alphabet.length)]);
    }
    return buffer.toString();
  }
}
