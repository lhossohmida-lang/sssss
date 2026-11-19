import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'qr_scanning.dart';

/// الحرف الذي يكتبه المفتاح الفعلي [key] في لوحة مفاتيح إنجليزية (US)، أياً كانت لغة الإدخال المضبوطة
/// في النظام. قارئ USB يرسل **أرقام مفاتيح** على أنه لوحة إنجليزية؛ فإن كانت لغة النظام عربية أو
/// فرنسية ترجمها النظام إلى حروف أخرى (على الفرنسية يصير `1234567890` هكذا `&é"'(-è_çà`، وتبدّل A وQ
/// وZ وW)، فنقرأ المفتاح نفسه لا الحرف المترجَم. [shift] إن كان Shift مضغوطاً، و[capsLock] إن كان
/// Caps Lock مفعَّلاً (يقلب حالة الأحرف وحدها). يعيد `null` لمفتاح لا حرف له.
String? usKeyboardCharacter(
  PhysicalKeyboardKey key, {
  bool shift = false,
  bool capsLock = false,
}) {
  final letter = _usLetters[key];
  if (letter != null) return shift != capsLock ? letter.toUpperCase() : letter;
  final pair = _usSymbols[key];
  if (pair == null) return null;
  return shift ? pair.$2 : pair.$1;
}

final Map<PhysicalKeyboardKey, String> _usLetters = {
  PhysicalKeyboardKey.keyA: 'a',
  PhysicalKeyboardKey.keyB: 'b',
  PhysicalKeyboardKey.keyC: 'c',
  PhysicalKeyboardKey.keyD: 'd',
  PhysicalKeyboardKey.keyE: 'e',
  PhysicalKeyboardKey.keyF: 'f',
  PhysicalKeyboardKey.keyG: 'g',
  PhysicalKeyboardKey.keyH: 'h',
  PhysicalKeyboardKey.keyI: 'i',
  PhysicalKeyboardKey.keyJ: 'j',
  PhysicalKeyboardKey.keyK: 'k',
  PhysicalKeyboardKey.keyL: 'l',
  PhysicalKeyboardKey.keyM: 'm',
  PhysicalKeyboardKey.keyN: 'n',
  PhysicalKeyboardKey.keyO: 'o',
  PhysicalKeyboardKey.keyP: 'p',
  PhysicalKeyboardKey.keyQ: 'q',
  PhysicalKeyboardKey.keyR: 'r',
  PhysicalKeyboardKey.keyS: 's',
  PhysicalKeyboardKey.keyT: 't',
  PhysicalKeyboardKey.keyU: 'u',
  PhysicalKeyboardKey.keyV: 'v',
  PhysicalKeyboardKey.keyW: 'w',
  PhysicalKeyboardKey.keyX: 'x',
  PhysicalKeyboardKey.keyY: 'y',
  PhysicalKeyboardKey.keyZ: 'z',
};

/// المفتاح ← (حرفه دون Shift، حرفه مع Shift) في اللوحة الإنجليزية.
final Map<PhysicalKeyboardKey, (String, String)> _usSymbols = {
  PhysicalKeyboardKey.digit1: ('1', '!'),
  PhysicalKeyboardKey.digit2: ('2', '@'),
  PhysicalKeyboardKey.digit3: ('3', '#'),
  PhysicalKeyboardKey.digit4: ('4', r'$'),
  PhysicalKeyboardKey.digit5: ('5', '%'),
  PhysicalKeyboardKey.digit6: ('6', '^'),
  PhysicalKeyboardKey.digit7: ('7', '&'),
  PhysicalKeyboardKey.digit8: ('8', '*'),
  PhysicalKeyboardKey.digit9: ('9', '('),
  PhysicalKeyboardKey.digit0: ('0', ')'),
  PhysicalKeyboardKey.minus: ('-', '_'),
  PhysicalKeyboardKey.equal: ('=', '+'),
  PhysicalKeyboardKey.bracketLeft: ('[', '{'),
  PhysicalKeyboardKey.bracketRight: (']', '}'),
  PhysicalKeyboardKey.backslash: (r'', '|'),
  PhysicalKeyboardKey.semicolon: (';', ':'),
  PhysicalKeyboardKey.quote: ("'", '"'),
  PhysicalKeyboardKey.backquote: ('`', '~'),
  PhysicalKeyboardKey.comma: (',', '<'),
  PhysicalKeyboardKey.period: ('.', '>'),
  PhysicalKeyboardKey.slash: ('/', '?'),
  PhysicalKeyboardKey.numpad0: ('0', '0'),
  PhysicalKeyboardKey.numpad1: ('1', '1'),
  PhysicalKeyboardKey.numpad2: ('2', '2'),
  PhysicalKeyboardKey.numpad3: ('3', '3'),
  PhysicalKeyboardKey.numpad4: ('4', '4'),
  PhysicalKeyboardKey.numpad5: ('5', '5'),
  PhysicalKeyboardKey.numpad6: ('6', '6'),
  PhysicalKeyboardKey.numpad7: ('7', '7'),
  PhysicalKeyboardKey.numpad8: ('8', '8'),
  PhysicalKeyboardKey.numpad9: ('9', '9'),
  PhysicalKeyboardKey.numpadSubtract: ('-', '-'),
  PhysicalKeyboardKey.numpadDecimal: ('.', '.'),
};

/// قارئ رموز USB: يعمل كلوحة مفاتيح تكتب الرمز بسرعة ثم Enter.
///
/// يستمع لأحداث لوحة المفاتيح العامة، فيعمل أياً كان العنصر المركَّز. تُفرَّق
/// كتابة القارئ (أحرف متلاحقة في أجزاء من الثانية) عن كتابة الإنسان: فاصل أكبر
/// من [maxGap] بين حرفين يمسح ما تجمّع. ولا يُعدّ رمزاً ما قلّ عن [minLength].
/// الـ Enter الذي يُتمّ رمزاً صالحاً يُستهلك فلا ينشّط زراً مركَّزاً.
///
/// تُقرأ **المفاتيح الفعلية كأنها لوحة إنجليزية** ([usKeyboardCharacter]) لا الحروف التي يترجمها
/// النظام، فيُقرأ الرمز كما هو ولو كانت لغة الإدخال عربية أو فرنسية.
class KeyboardWedgeSource implements QrCodeSource {
  KeyboardWedgeSource({
    this.maxGap = const Duration(milliseconds: 120),
    this.minLength = 6,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration maxGap;
  final int minLength;
  final DateTime Function() _clock;

  final StreamController<String> _controller =
      StreamController<String>.broadcast();
  final StringBuffer _buffer = StringBuffer();
  DateTime? _lastKey;
  bool _listening = false;

  @override
  Stream<String> get codes => _controller.stream;

  /// لا معاينة للقارئ.
  @override
  Widget buildPreview(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> start() async {
    if (_listening) return;
    _listening = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  Future<void> dispose() async {
    if (_listening) HardwareKeyboard.instance.removeHandler(_onKey);
    _listening = false;
    await _controller.close();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final now = _clock();
    final last = _lastKey;
    if (last != null && now.difference(last) > maxGap) _buffer.clear();
    _lastKey = now;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final code = _buffer.toString().trim();
      _buffer.clear();
      if (code.length >= minLength) {
        _controller.add(code);
        return true;
      }
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    var character = usKeyboardCharacter(
      event.physicalKey,
      shift: keyboard.isShiftPressed,
      capsLock: keyboard.lockModesEnabled.contains(KeyboardLockMode.capsLock),
    );
    // مفتاح خارج الجدول: يُؤخذ حرفه إن كان ASCII (لا عربياً ولا مترجَماً إلى لغة أخرى).
    final typed = event.character;
    if (character == null &&
        typed != null &&
        typed.length == 1 &&
        typed.codeUnitAt(0) < 127) {
      character = typed;
    }
    if (character != null && character.codeUnitAt(0) > 32) {
      _buffer.write(character);
    }
    return false;
  }
}

/// مصنع قارئ USB؛ الافتراضي لوحة المفاتيح الفعلية، وتبدّله الاختبارات.
final Provider<QrCodeSource Function()> usbReaderFactoryProvider =
    Provider<QrCodeSource Function()>((ref) => KeyboardWedgeSource.new);
