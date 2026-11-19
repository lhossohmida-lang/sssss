import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_ui/school_ui.dart';

/// الحرف الذي يترجمه النظام لمفتاح القارئ على لوحة فرنسية (AZERTY) دون Shift.
String azerty(String ch) => switch (ch) {
  '1' => '&',
  '2' => 'é',
  '3' => '"',
  '4' => "'",
  '5' => '(',
  '6' => '-',
  '7' => 'è',
  '8' => '_',
  '9' => 'ç',
  '0' => 'à',
  '-' => ')',
  'A' => 'Q',
  'Q' => 'A',
  'Z' => 'W',
  'W' => 'Z',
  'M' => ',',
  _ => ch,
};

/// ما يترجمه النظام على لوحة عربية: أحرف عربية للحروف وأرقام هندية للأرقام.
String arabic(String ch) {
  const digits = '٠١٢٣٤٥٦٧٨٩';
  if (RegExp('[0-9]').hasMatch(ch)) return digits[int.parse(ch)];
  if (RegExp('[A-Za-z]').hasMatch(ch)) return 'ش';
  return ch;
}

void main() {
  late DateTime now;
  late KeyboardWedgeSource source;
  late List<String> codes;

  setUp(() {
    now = DateTime(2026, 11, 14, 10);
    source = KeyboardWedgeSource(clock: () => now);
    codes = [];
    source.codes.listen(codes.add);
  });

  /// المفتاح الفعلي لحرف لاتيني أو رقم أو شرطة (معرّف المفتاح المنطقي = رمز الحرف الصغير).
  LogicalKeyboardKey keyOf(String ch) =>
      LogicalKeyboardKey.findKeyByKeyId(ch.toLowerCase().codeUnitAt(0))!;

  /// يكتب [text] كما يفعل قارئ يرسل أرقام مفاتيح لوحة إنجليزية: مفتاح كل [gap] (والأحرف الكبيرة مع Shift)، ثم
  /// Enter. [layout] ما يترجمه النظام فعلاً لكل مفتاح (لغة الإدخال المضبوطة).
  Future<void> type(
    WidgetTester tester,
    String text, {
    Duration gap = const Duration(milliseconds: 10),
    bool enter = true,
    String Function(String) layout = _identity,
  }) async {
    for (final ch in text.split('')) {
      now = now.add(gap);
      final upper = RegExp('[A-Z]').hasMatch(ch);
      if (upper) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(keyOf(ch), character: layout(ch));
      if (upper) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    if (enter) {
      now = now.add(gap);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    }
  }

  testWidgets('قارئ سريع: الرمز كاملاً عند Enter', (tester) async {
    await source.start();
    await type(tester, 'S-AAAAAAAAAA');
    expect(codes, ['S-AAAAAAAAAA']);
    await source.dispose();
  });

  testWidgets('لوحة فرنسية: الأرقام التي يترجمها النظام رموزاً تُقرأ أرقاماً', (
    tester,
  ) async {
    await source.start();
    // دون الإصلاح كان الرمز يظهر «S-&é"'(-è_çà» وتتبدّل A وQ وZ وW.
    await type(tester, 'S-1234567890', layout: azerty);
    await type(tester, 'T-AZQWM12345', layout: azerty);
    expect(codes, ['S-1234567890', 'T-AZQWM12345']);
    await source.dispose();
  });

  testWidgets('لوحة عربية: الحروف العربية والأرقام الهندية تُقرأ لاتينية', (
    tester,
  ) async {
    await source.start();
    await type(tester, 'S-AB12CD34EF', layout: arabic);
    expect(codes, ['S-AB12CD34EF']);
    await source.dispose();
  });

  testWidgets('الرمز نفسه في ثلاث لغات إدخال يعطي النتيجة نفسها', (
    tester,
  ) async {
    await source.start();
    for (final layout in [_identity, azerty, arabic]) {
      now = now.add(const Duration(seconds: 2));
      await type(tester, 'W-QZ09AW81MK', layout: layout);
    }
    expect(codes, List.filled(3, 'W-QZ09AW81MK'));
    await source.dispose();
  });

  testWidgets('رمزان متتاليان منفصلان', (tester) async {
    await source.start();
    await type(tester, 'S-AAAAAAAAAA');
    now = now.add(const Duration(seconds: 2));
    await type(tester, 'T-BBBBBBBBBB');
    expect(codes, ['S-AAAAAAAAAA', 'T-BBBBBBBBBB']);
    await source.dispose();
  });

  testWidgets('كتابة بطيئة (إنسان) لا تُعدّ رمزاً', (tester) async {
    await source.start();
    await type(tester, 'S-AAAAAAAAAA', gap: const Duration(milliseconds: 400));
    expect(codes, isEmpty);
    await source.dispose();
  });

  testWidgets('نص أقصر من الحد الأدنى يُهمل', (tester) async {
    await source.start();
    await type(tester, 'ab');
    expect(codes, isEmpty);
    await source.dispose();
  });

  testWidgets('ما كُتب قبل فاصل طويل يُمسح ولا يختلط بالرمز', (tester) async {
    await source.start();
    await type(tester, 'xyz', enter: false);
    now = now.add(const Duration(seconds: 3));
    await type(tester, 'S-AAAAAAAAAA');
    expect(codes, ['S-AAAAAAAAAA']);
    await source.dispose();
  });

  testWidgets('بعد dispose لا يُستقبل شيء', (tester) async {
    await source.start();
    await source.dispose();
    await type(tester, 'S-AAAAAAAAAA');
    expect(codes, isEmpty);
  });

  testWidgets('بدء مزدوج لا يكرر المعالج', (tester) async {
    await source.start();
    await source.start();
    await type(tester, 'S-AAAAAAAAAA');
    expect(codes, hasLength(1));
    await source.dispose();
  });

  group('usKeyboardCharacter: المفتاح الفعلي كلوحة إنجليزية', () {
    test('الحروف: صغيرة دون Shift، وكبيرة معه، وCaps Lock يقلبها', () {
      expect(usKeyboardCharacter(PhysicalKeyboardKey.keyQ), 'q');
      expect(usKeyboardCharacter(PhysicalKeyboardKey.keyQ, shift: true), 'Q');
      expect(
        usKeyboardCharacter(PhysicalKeyboardKey.keyQ, capsLock: true),
        'Q',
      );
      expect(
        usKeyboardCharacter(
          PhysicalKeyboardKey.keyQ,
          shift: true,
          capsLock: true,
        ),
        'q',
      );
    });

    test('الأرقام والشرطة دون Shift، ورموزها معه، وCaps Lock لا يمسّها', () {
      expect(usKeyboardCharacter(PhysicalKeyboardKey.digit1), '1');
      expect(usKeyboardCharacter(PhysicalKeyboardKey.digit1, shift: true), '!');
      expect(usKeyboardCharacter(PhysicalKeyboardKey.digit0), '0');
      expect(usKeyboardCharacter(PhysicalKeyboardKey.minus), '-');
      expect(usKeyboardCharacter(PhysicalKeyboardKey.minus, shift: true), '_');
      expect(
        usKeyboardCharacter(PhysicalKeyboardKey.digit5, capsLock: true),
        '5',
      );
      expect(usKeyboardCharacter(PhysicalKeyboardKey.numpad7), '7');
    });

    test('مفتاح بلا حرف يعيد null', () {
      expect(usKeyboardCharacter(PhysicalKeyboardKey.shiftLeft), isNull);
      expect(usKeyboardCharacter(PhysicalKeyboardKey.enter), isNull);
      expect(usKeyboardCharacter(PhysicalKeyboardKey.arrowUp), isNull);
    });
  });
}

String _identity(String ch) => ch;
