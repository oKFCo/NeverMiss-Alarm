package com.verint.verint_alarm_flutter.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ACTION_TRIGGER) {
            return
        }
        val alarmId = intent.getStringExtra(EXTRA_ALARM_ID) ?: return
        val label = intent.getStringExtra(EXTRA_LABEL) ?: "Alarm"
        val snoozeMinutes = intent.getIntExtra(EXTRA_SNOOZE_MINUTES, 5).coerceIn(1, 60)
        val fromStoredDefinition = intent.getBooleanExtra(EXTRA_FROM_STORED_DEFINITION, false)

        val serviceIntent = AlarmService.startIntent(
            context = context,
            alarmId = alarmId,
            label = label,
            snoozeMinutes = snoozeMinutes,
        )
        ContextCompat.startForegroundService(context, serviceIntent)

        if (!fromStoredDefinition) {
            return
        }

        val store = AlarmStore(context)
        val current = store.get(alarmId) ?: return
        if (!current.isEnabled) {
            return
        }
        if (current.daysOfWeek.isEmpty()) {
            store.remove(alarmId)
            AlarmScheduler.cancel(context, alarmId)
        } else {
            AlarmScheduler.schedule(context, current)
        }
    }

    companion object {
        const val ACTION_TRIGGER = "com.verint.verint_alarm_flutter.alarm.TRIGGER"
        const val EXTRA_ALARM_ID = "extra_alarm_id"
        const val EXTRA_LABEL = "extra_label"
        const val EXTRA_SNOOZE_MINUTES = "extra_snooze_minutes"
        const val EXTRA_FROM_STORED_DEFINITION = "extra_from_stored_definition"

        fun buildTriggerIntent(
            context: Context,
            alarmId: String,
            label: String,
            snoozeMinutes: Int,
            fromStoredDefinition: Boolean,
        ): Intent {
            return Intent(context, AlarmReceiver::class.java)
                .setAction(ACTION_TRIGGER)
                .putExtra(EXTRA_ALARM_ID, alarmId)
                .putExtra(EXTRA_LABEL, label)
                .putExtra(EXTRA_SNOOZE_MINUTES, snoozeMinutes.coerceIn(1, 60))
                .putExtra(EXTRA_FROM_STORED_DEFINITION, fromStoredDefinition)
        }
    }
}
