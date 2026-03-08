package com.verint.verint_alarm_flutter.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

object AlarmScheduler {
    fun schedule(context: Context, alarm: AlarmDefinition) {
        cancel(context, alarm.id)
        if (!alarm.isEnabled) {
            return
        }

        val nowMs = System.currentTimeMillis()
        val triggerAtMs = if (alarm.scheduledAtEpochMs != null) {
            if (alarm.scheduledAtEpochMs <= nowMs) {
                return
            }
            alarm.scheduledAtEpochMs
        } else {
            computeNextTriggerAt(
                hour = alarm.hour,
                minute = alarm.minute,
                daysOfWeek = alarm.daysOfWeek,
                nowMs = nowMs,
            ) ?: return
        }

        val intent = AlarmReceiver.buildTriggerIntent(
            context = context,
            alarmId = alarm.id,
            label = alarm.label,
            snoozeMinutes = alarm.snoozeMinutes,
            fromStoredDefinition = true,
        )
        scheduleExact(context, intent, alarmRequestCode(alarm.id), triggerAtMs)
    }

    fun scheduleSnooze(
        context: Context,
        alarmId: String,
        label: String,
        snoozeMinutes: Int,
    ) {
        val triggerAtMs = System.currentTimeMillis() + snoozeMinutes.coerceIn(1, 60) * 60_000L
        val intent = AlarmReceiver.buildTriggerIntent(
            context = context,
            alarmId = alarmId,
            label = label,
            snoozeMinutes = snoozeMinutes,
            fromStoredDefinition = false,
        )
        scheduleExact(context, intent, snoozeRequestCode(alarmId), triggerAtMs)
    }

    fun cancel(context: Context, alarmId: String) {
        cancelRequestCode(context, alarmRequestCode(alarmId))
        cancelRequestCode(context, snoozeRequestCode(alarmId))
    }

    fun cancelAll(context: Context) {
        val store = AlarmStore(context)
        store.all().forEach { alarm ->
            cancel(context, alarm.id)
        }
    }

    fun rescheduleAllFromStore(context: Context) {
        val store = AlarmStore(context)
        store.all().forEach { alarm ->
            schedule(context, alarm)
        }
    }

    private fun cancelRequestCode(context: Context, requestCode: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val cancelIntent = Intent(context, AlarmReceiver::class.java).setAction(AlarmReceiver.ACTION_TRIGGER)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            cancelIntent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        if (pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }
    }

    private fun scheduleExact(
        context: Context,
        intent: Intent,
        requestCode: Int,
        triggerAtMs: Long,
    ) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMs,
                pendingIntent,
            )
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent)
        }
    }

    private fun alarmRequestCode(alarmId: String): Int = stableId("alarm:$alarmId")

    private fun snoozeRequestCode(alarmId: String): Int = stableId("snooze:$alarmId")

    private fun stableId(value: String): Int = value.hashCode() and 0x7fffffff

    private fun computeNextTriggerAt(
        hour: Int,
        minute: Int,
        daysOfWeek: Set<Int>,
        nowMs: Long,
    ): Long? {
        val now = Calendar.getInstance().apply { timeInMillis = nowMs }
        val candidate = Calendar.getInstance().apply {
            timeInMillis = nowMs
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
        }

        if (daysOfWeek.isEmpty()) {
            if (candidate.timeInMillis <= now.timeInMillis) {
                return null
            }
            return candidate.timeInMillis
        }

        repeat(8) {
            val day = calendarToDartWeekday(candidate)
            if (daysOfWeek.contains(day) && candidate.timeInMillis > now.timeInMillis) {
                return candidate.timeInMillis
            }
            candidate.add(Calendar.DAY_OF_YEAR, 1)
            candidate.set(Calendar.HOUR_OF_DAY, hour)
            candidate.set(Calendar.MINUTE, minute)
        }
        return null
    }

    private fun calendarToDartWeekday(calendar: Calendar): Int {
        return when (calendar.get(Calendar.DAY_OF_WEEK)) {
            Calendar.MONDAY -> 1
            Calendar.TUESDAY -> 2
            Calendar.WEDNESDAY -> 3
            Calendar.THURSDAY -> 4
            Calendar.FRIDAY -> 5
            Calendar.SATURDAY -> 6
            Calendar.SUNDAY -> 7
            else -> 1
        }
    }
}
