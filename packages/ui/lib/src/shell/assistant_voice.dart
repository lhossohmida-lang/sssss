import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// واجهة صوتية قابلة للاستبدال في اختبارات الشاشة.
abstract class AssistantVoiceEngine extends ChangeNotifier {
  bool get isListening;

  String? get error;

  Future<void> listen({required ValueChanged<String> onResult});

  Future<void> stopListening();

  Future<void> speak(String text);

  Future<void> stopSpeaking();
}

/// تعرف قصير على كلام المستخدم وقراءة الرد بمحرك الهاتف (Android وiPhone).
class PluginAssistantVoiceEngine extends AssistantVoiceEngine {
  PluginAssistantVoiceEngine({stt.SpeechToText? recognizer})
    : _recognizer = recognizer ?? stt.SpeechToText();

  final stt.SpeechToText _recognizer;
  static const MethodChannel _textToSpeechChannel = MethodChannel(
    'dz.school.assistant/tts',
  );
  bool _initialized = false;
  bool _isListening = false;
  String? _error;

  @override
  bool get isListening => _isListening;

  @override
  String? get error => _error;

  @override
  Future<void> listen({required ValueChanged<String> onResult}) async {
    _error = null;
    if (!_initialized) {
      _initialized = await _recognizer.initialize(
        onStatus: (status) {
          _isListening = status == stt.SpeechToText.listeningStatus;
          notifyListeners();
        },
        onError: (error) {
          _error = error.errorMsg;
          _isListening = false;
          notifyListeners();
        },
        options: [stt.SpeechToText.androidNoBluetooth],
      );
    }
    if (!_initialized) {
      throw const AssistantVoiceException();
    }

    final locales = await _recognizer.locales();
    String? localeId;
    for (final locale in locales) {
      if (locale.localeId.toLowerCase() == 'ar-dz') {
        localeId = locale.localeId;
        break;
      }
    }
    if (localeId == null) {
      for (final locale in locales) {
        if (locale.localeId.toLowerCase().startsWith('ar')) {
          localeId = locale.localeId;
          break;
        }
      }
    }

    await _recognizer.listen(
      onResult: (SpeechRecognitionResult result) =>
          onResult(result.recognizedWords),
      listenOptions: stt.SpeechListenOptions(
        localeId: localeId,
        listenFor: const Duration(seconds: 35),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
    _isListening = _recognizer.isListening;
    notifyListeners();
  }

  @override
  Future<void> stopListening() async {
    await _recognizer.stop();
    _isListening = false;
    notifyListeners();
  }

  @override
  Future<void> speak(String text) async {
    _error = null;
    try {
      await _textToSpeechChannel.invokeMethod<void>('speak', {'text': text});
    } on Object {
      _error = 'تعذّرت قراءة الإجابة صوتياً.';
      notifyListeners();
      throw const AssistantVoiceException('تعذّرت قراءة الإجابة صوتياً.');
    }
  }

  @override
  Future<void> stopSpeaking() async {
    await _textToSpeechChannel.invokeMethod<void>('stop');
  }

  @override
  void dispose() {
    unawaited(_recognizer.cancel());
    unawaited(
      _textToSpeechChannel.invokeMethod<void>('stop').catchError((_) {}),
    );
    super.dispose();
  }
}

/// فشل بدء التعرف أو القراءة الصوتية.
class AssistantVoiceException implements Exception {
  const AssistantVoiceException([
    this.message = 'تحقق من إذن الميكروفون وتوفر خدمة الصوت في الهاتف.',
  ]);

  final String message;

  @override
  String toString() => message;
}
