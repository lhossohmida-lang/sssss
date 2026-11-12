import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_ui/school_ui.dart';

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

  /// يكتب [text] كما يفعل قارئ: حرف كل [gap]، ثم Enter.
  Future<void> type(
    WidgetTester tester,
    String text, {
    Duration gap = const Duration(milliseconds: 10),
    bool enter = true,
  }) async {
    for (final ch in text.split('')) {
      now = now.add(gap);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: ch);
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
}
