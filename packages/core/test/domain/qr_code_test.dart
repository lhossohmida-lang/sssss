import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';

void main() {
  test('الرمز المولَّد يُحلَّل إلى نوعه الصحيح', () {
    final random = Random(7);
    for (final kind in QrOwnerKind.values) {
      final code = QrCodes.generate(kind, random: random);
      expect(code, startsWith(kind.prefix));
      expect(code.length, kind.prefix.length + QrCodes.bodyLength);
      expect(QrCodes.parse(code), ParsedQrCode(kind: kind, code: code));
    }
  });

  test('تمييز النوع من البادئة', () {
    expect(QrCodes.parse('S-ABCDEFGHJK')?.kind, QrOwnerKind.student);
    expect(QrCodes.parse('T-ABCDEFGHJK')?.kind, QrOwnerKind.teacher);
    expect(QrCodes.parse('W-ABCDEFGHJK')?.kind, QrOwnerKind.worker);
  });

  test('يتسامح مع المسافات والحروف الصغيرة', () {
    expect(QrCodes.parse('  s-abcdefghjk\n')?.code, 'S-ABCDEFGHJK');
  });

  test('يرفض ما ليس من رموز النظام', () {
    expect(QrCodes.parse(''), isNull);
    expect(QrCodes.parse('X-ABCDEFGHJK'), isNull);
    expect(QrCodes.parse('S-ABC'), isNull);
    expect(QrCodes.parse('S-ABCDEFGHJKL'), isNull);
    expect(QrCodes.parse('S-ABCDEFGHJ0'), isNull);
    expect(QrCodes.parse('https://example.com'), isNull);
  });

  test('الرموز المولَّدة لا تتكرر عملياً', () {
    final random = Random(1);
    final codes = {
      for (var i = 0; i < 5000; i++)
        QrCodes.generate(QrOwnerKind.student, random: random),
    };
    expect(codes, hasLength(5000));
  });
}
