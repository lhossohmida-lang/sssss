package dz.school.admin

import android.app.Activity
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

internal object SmsSendRegistry {
    private class PendingSend(
        val expectedParts: Int,
        val result: MethodChannel.Result,
    ) {
        val results = mutableMapOf<Int, Int>()
    }

    private val pending = ConcurrentHashMap<String, PendingSend>()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(id: String, expectedParts: Int, result: MethodChannel.Result) {
        pending[id] = PendingSend(expectedParts, result)
    }

    fun completePart(id: String, partIndex: Int, resultCode: Int) {
        val send = pending[id] ?: return
        var completed: Map<Int, Int>? = null
        synchronized(send) {
            if (send.results.containsKey(partIndex)) return
            send.results[partIndex] = resultCode
            if (send.results.size == send.expectedParts) {
                pending.remove(id, send)
                completed = send.results.toMap()
            }
        }
        val results = completed ?: return
        mainHandler.post {
            val failure = results.entries.firstOrNull { it.value != Activity.RESULT_OK }
            if (failure == null) {
                send.result.success(mapOf("parts" to send.expectedParts))
            } else {
                send.result.error(
                    "sms_send_failed",
                    "فشل إرسال جزء ${failure.key + 1} (رمز ${failure.value})",
                    failure.value,
                )
            }
        }
    }

    fun fail(id: String, code: String, message: String) {
        val send = pending.remove(id) ?: return
        mainHandler.post { send.result.error(code, message, null) }
    }
}
