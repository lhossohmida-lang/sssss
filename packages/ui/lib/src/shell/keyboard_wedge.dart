import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'qr_scanning.dart';

/// قارئ رموز USB: يعمل كلوحة مفاتيح تكتب الرمز بسرعة ثم Enter.
///
/// يستمع لأحداث لوحة المفاتيح العامة، فيعمل أياً كان العنصر المركَّز. تُفرَّق
/// كتابة القارئ (أحرف متلاحقة في أجزاء من الثانية) عن كتابة الإنسان: فاصل أكبر
/// من [maxGap] بين حرفين يمسح ما تجمّع. ولا يُعدّ رمزاً ما قلّ عن [minLength].
/// الـ Enter الذي يُتمّ رمزاً صالحاً يُستهلك فلا ينشّط زراً مركَّزاً.
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
    final character = event.character;
    if (character != null &&
        character.length == 1 &&
        character.codeUnitAt(0) > 32) {
      _buffer.write(character);
    }
    return false;
  }
}

/// مصنع قارئ USB؛ الافتراضي لوحة المفاتيح الفعلية، وتبدّله الاختبارات.
final Provider<QrCodeSource Function()> usbReaderFactoryProvider =
    Provider<QrCodeSource Function()>((ref) => KeyboardWedgeSource.new);
