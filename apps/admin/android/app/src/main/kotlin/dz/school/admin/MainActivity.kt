package dz.school.admin

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermissions" -> requestSmsPermissions(result)
                    "availableSimCards" -> listActiveSimCards(result)
                    "startForegroundService" -> startSmsService(result)
                    "stopForegroundService" -> stopSmsService(result)
                    "send" -> send(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestSmsPermissions(result: MethodChannel.Result) {
        if (permissionResult != null) {
            result.error("permission_request_in_progress", "طلب الصلاحيات جارٍ", null)
            return
        }
        val permissions = mutableListOf(
            Manifest.permission.SEND_SMS,
            Manifest.permission.READ_PHONE_STATE,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        val missing = permissions.filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        permissionResult = result
        requestPermissions(missing.toTypedArray(), SMS_PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != SMS_PERMISSION_REQUEST) return
        val result = permissionResult
        permissionResult = null
        val requiredGranted = checkSelfPermission(Manifest.permission.SEND_SMS) ==
            PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.READ_PHONE_STATE) ==
            PackageManager.PERMISSION_GRANTED
        result?.success(requiredGranted)
    }

    private fun listActiveSimCards(result: MethodChannel.Result) {
        if (!hasPermission(Manifest.permission.READ_PHONE_STATE)) {
            result.error("permission_denied", "يلزم السماح بقراءة شرائح SIM", null)
            return
        }
        try {
            val manager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
                as SubscriptionManager
            val cards = manager.activeSubscriptionInfoList.orEmpty().map { info ->
                mapOf(
                    "slotIndex" to info.simSlotIndex,
                    "subscriptionId" to info.subscriptionId,
                    "displayName" to info.displayName.toString(),
                    "carrierName" to info.carrierName.toString(),
                )
            }
            result.success(cards)
        } catch (error: SecurityException) {
            result.error("permission_denied", "لا يمكن قراءة شرائح SIM", error.message)
        } catch (error: UnsupportedOperationException) {
            result.error("no_telephony", "هذا الجهاز لا يدعم شرائح الهاتف", error.message)
        }
    }

    private fun startSmsService(result: MethodChannel.Result) {
        try {
            val intent = Intent(this, SmsForegroundService::class.java)
                .setAction(SmsForegroundService.ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            result.success(true)
        } catch (error: RuntimeException) {
            result.error("foreground_service_failed", "تعذّر بدء خدمة إرسال الرسائل", error.message)
        }
    }

    private fun stopSmsService(result: MethodChannel.Result) {
        stopService(Intent(this, SmsForegroundService::class.java))
        result.success(true)
    }

    private fun send(call: MethodCall, result: MethodChannel.Result) {
        if (!hasPermission(Manifest.permission.SEND_SMS) ||
            !hasPermission(Manifest.permission.READ_PHONE_STATE)
        ) {
            result.error("permission_denied", "يلزم السماح بإرسال الرسائل وقراءة الشرائح", null)
            return
        }
        val id = call.argument<String>("id")?.trim().orEmpty()
        val phone = call.argument<String>("phone")?.trim().orEmpty()
        val body = call.argument<String>("body")?.trim().orEmpty()
        val slotIndex = call.argument<Int>("simSlotIndex")
        if (id.isEmpty() || slotIndex == null) {
            result.error("invalid_request", "بيانات إرسال SMS غير مكتملة", null)
            return
        }
        if (!PHONE_PATTERN.matches(phone)) {
            result.error("invalid_phone", "رقم الهاتف الجزائري غير صالح", null)
            return
        }
        if (body.isEmpty()) {
            result.error("empty_message", "نص الرسالة فارغ", null)
            return
        }
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY_MESSAGING)) {
            result.error("no_telephony", "هذا الجهاز لا يدعم إرسال SMS", null)
            return
        }

        var registered = false
        try {
            val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
                as SubscriptionManager
            val subscription = subscriptionManager.activeSubscriptionInfoList
                .orEmpty()
                .firstOrNull { it.simSlotIndex == slotIndex }
            if (subscription == null) {
                result.error("sim_not_found", "الشريحة المختارة غير نشطة", null)
                return
            }
            val manager = smsManager(subscription.subscriptionId)
            val parts = manager.divideMessage(body)
            if (parts.isEmpty()) {
                result.error("empty_message", "تعذّر تقسيم نص الرسالة", null)
                return
            }
            SmsSendRegistry.register(id, parts.size, result)
            registered = true
            val callbacks = ArrayList<PendingIntent>(parts.size)
            for (index in parts.indices) {
                val callback = Intent(this, SmsSentReceiver::class.java)
                    .setAction(SENT_ACTION)
                    .setData(Uri.parse("school-sms://$id/$index"))
                    .putExtra(SmsSentReceiver.EXTRA_MESSAGE_ID, id)
                    .putExtra(SmsSentReceiver.EXTRA_PART_INDEX, index)
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                callbacks.add(PendingIntent.getBroadcast(this, id.hashCode() + index, callback, flags))
            }
            if (parts.size == 1) {
                manager.sendTextMessage(phone, null, parts.first(), callbacks.first(), null)
            } else {
                manager.sendMultipartTextMessage(phone, null, parts, callbacks, null)
            }
        } catch (error: SecurityException) {
            failSend(result, id, registered, "permission_denied", "لا توجد صلاحية إرسال SMS")
        } catch (error: IllegalArgumentException) {
            failSend(result, id, registered, "invalid_request", error.message ?: "بيانات SMS غير صالحة")
        } catch (error: UnsupportedOperationException) {
            failSend(result, id, registered, "no_telephony", "هذا الجهاز لا يدعم إرسال SMS")
        } catch (error: RuntimeException) {
            failSend(result, id, registered, "sms_service_failed", error.message ?: "تعذّر إرسال SMS")
        }
    }

    private fun failSend(
        result: MethodChannel.Result,
        id: String,
        registered: Boolean,
        code: String,
        message: String,
    ) {
        if (registered) {
            SmsSendRegistry.fail(id, code, message)
        } else {
            result.error(code, message, null)
        }
    }

    private fun smsManager(subscriptionId: Int): SmsManager {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(SmsManager::class.java).createForSubscriptionId(subscriptionId)
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
        }
    }

    private fun hasPermission(permission: String): Boolean =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    companion object {
        private const val CHANNEL_NAME = "dz.school.admin/sms"
        private const val SMS_PERMISSION_REQUEST = 7201
        private const val SENT_ACTION = "dz.school.admin.SMS_SENT"
        private val PHONE_PATTERN = Regex("^\\+213[567][0-9]{8}$")
    }
}
