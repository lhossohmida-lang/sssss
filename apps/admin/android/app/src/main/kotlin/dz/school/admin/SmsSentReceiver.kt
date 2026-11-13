package dz.school.admin

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class SmsSentReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(EXTRA_MESSAGE_ID) ?: return
        val part = intent.getIntExtra(EXTRA_PART_INDEX, -1)
        if (part < 0) return
        SmsSendRegistry.completePart(id, part, resultCode)
    }

    companion object {
        const val EXTRA_MESSAGE_ID = "sms_message_id"
        const val EXTRA_PART_INDEX = "sms_part_index"
    }
}
