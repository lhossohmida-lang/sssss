import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:school_core/school_core.dart';
import 'package:school_core/testing.dart';

Uint8List cairo() => File('../ui/assets/fonts/Cairo.ttf').readAsBytesSync();

void main() {
  ReceiptData data({
    Uint8List? logo,
    int? remaining = 1500,
    String note = '',
    String description = 'شهر — رياضيات · المجموعة 2 · الدورة 3',
    String school = 'مدرسة النجاح',
  }) => ReceiptData(
    schoolName: school,
    schoolAddress: 'حي السلام، الجزائر',
    schoolPhone: '0550123456',
    receiptNumber: 'ABC-000123',
    dateText: '2026-11-14 10:30',
    studentName: 'أحمد بن علي',
    description: description,
    amount: 500,
    remaining: remaining,
    receivedByName: 'المدير',
    note: note,
    logo: logo,
  );

  test('ملف PDF صالح من صفحة واحدة بمقاس A5 عمودياً', () async {
    final bytes = await ReceiptPdf.build(data(), fontData: cairo());
    final text = latin1.decode(bytes, allowInvalid: true);
    expect(text.startsWith('%PDF-'), isTrue);
    expect(text.trimRight().endsWith('%%EOF'), isTrue);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text), hasLength(1));
    final box = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]')
        .firstMatch(text)!;
    // A5: 148×210 مم (1 مم = 72/25.4 نقطة).
    expect(double.parse(box.group(1)!), closeTo(148 * 72 / 25.4, 0.1));
    expect(double.parse(box.group(2)!), closeTo(210 * 72 / 25.4, 0.1));
  });

  test('بالشعار أكبر حجماً من دونه', () async {
    final logo = samplePngBytes(width: 120, height: 120);
    final withLogo = await ReceiptPdf.build(
      data(logo: logo),
      fontData: cairo(),
    );
    final plain = await ReceiptPdf.build(data(), fontData: cairo());
    expect(withLogo.length, greaterThan(plain.length));
  });

  test('الباقي صفر أو غائب أو ملاحظة طويلة لا ترمي', () async {
    for (final d in [
      data(remaining: 0),
      data(remaining: null),
      data(note: 'ملاحظة ' * 40),
      data(description: 'وصف ' * 60, school: 'مدرسة ' * 30),
    ]) {
      final bytes = await ReceiptPdf.build(d, fontData: cairo());
      expect(latin1.decode(bytes, allowInvalid: true), startsWith('%PDF-'));
    }
  });

  test('الحقول الاختيارية الفارغة تُحذف دون خطأ', () async {
    final bytes = await ReceiptPdf.build(
      const ReceiptData(
        schoolName: 'م',
        receiptNumber: 'A-000001',
        dateText: '2026-11-14 10:30',
        studentName: 'س',
        description: 'ش',
        amount: 1,
        receivedByName: 'ر',
      ),
      fontData: cairo(),
    );
    expect(latin1.decode(bytes, allowInvalid: true), startsWith('%PDF-'));
  });
}
