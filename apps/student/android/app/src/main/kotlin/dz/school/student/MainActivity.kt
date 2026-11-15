package dz.school.student

import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private var textToSpeech: TextToSpeech? = null
    private var textToSpeechReady = false
    private var textToSpeechInitializationFinished = false
    private val pendingSpeech = mutableListOf<Pair<String, MethodChannel.Result>>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TTS_CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "speak" -> speak(call, result)
                    "stop" -> {
                        textToSpeech?.stop()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        textToSpeech = TextToSpeech(this) { status ->
            textToSpeechInitializationFinished = true
            if (status != TextToSpeech.SUCCESS) {
                completePendingSpeech("تعذّر تشغيل محرك النطق")
                return@TextToSpeech
            }
            val engine = textToSpeech ?: return@TextToSpeech
            val languageStatus = engine.setLanguage(Locale("ar", "DZ"))
            textToSpeechReady = languageStatus != TextToSpeech.LANG_MISSING_DATA &&
                languageStatus != TextToSpeech.LANG_NOT_SUPPORTED
            if (!textToSpeechReady) {
                val fallbackStatus = engine.setLanguage(Locale("ar"))
                textToSpeechReady = fallbackStatus != TextToSpeech.LANG_MISSING_DATA &&
                    fallbackStatus != TextToSpeech.LANG_NOT_SUPPORTED
            }
            if (textToSpeechReady) {
                val queued = pendingSpeech.toList()
                pendingSpeech.clear()
                queued.forEachIndexed { index, (text, result) ->
                    playSpeech(text, result, if (index == 0) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD)
                }
            } else {
                completePendingSpeech("لا تتوفر لغة عربية في محرك النطق")
            }
        }
    }

    private fun speak(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")?.trim().orEmpty()
        if (text.isEmpty() || text.length > 6000) {
            result.error("invalid_text", "نص القراءة الصوتية فارغ أو طويل جداً", null)
            return
        }
        if (!textToSpeechReady) {
            if (textToSpeechInitializationFinished) {
                result.error("speech_unavailable", "لا تتوفر لغة عربية في محرك النطق", null)
            } else {
                pendingSpeech.add(text to result)
            }
            return
        }
        playSpeech(text, result, TextToSpeech.QUEUE_FLUSH)
    }

    private fun playSpeech(text: String, result: MethodChannel.Result, queueMode: Int) {
        val status = textToSpeech?.speak(
            text,
            queueMode,
            null,
            "school-assistant-${System.nanoTime()}",
        ) ?: TextToSpeech.ERROR
        if (status == TextToSpeech.SUCCESS) {
            result.success(true)
        } else {
            result.error("speech_failed", "تعذّرت قراءة الإجابة صوتياً", null)
        }
    }

    private fun completePendingSpeech(message: String) {
        textToSpeechInitializationFinished = true
        val queued = pendingSpeech.toList()
        pendingSpeech.clear()
        queued.forEach { (_, result) ->
            result.error("speech_unavailable", message, null)
        }
    }

    override fun onDestroy() {
        completePendingSpeech("أُغلقت الشاشة قبل بدء القراءة")
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        super.onDestroy()
    }

    companion object {
        private const val TTS_CHANNEL_NAME = "dz.school.assistant/tts"
    }
}
