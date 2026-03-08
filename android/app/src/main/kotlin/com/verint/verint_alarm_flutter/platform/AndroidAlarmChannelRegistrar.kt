package com.verint.verint_alarm_flutter.platform

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.verint.verint_alarm_flutter.alarm.AlarmDefinition
import com.verint.verint_alarm_flutter.alarm.AlarmScheduler
import com.verint.verint_alarm_flutter.alarm.AlarmService
import com.verint.verint_alarm_flutter.alarm.AlarmStore
import com.verint.verint_alarm_flutter.failsafe.FailSafeKeepAliveService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object AndroidAlarmChannelRegistrar {
    private const val CHANNEL = "verint_alarm/android_alarm"
    private const val REQUEST_NOTIFICATIONS_PERMISSION = 701
    private const val PREFS_NAME = "verint_alarm_native_store"
    private const val KEY_ALARM_TONE_ID = "alarm_tone_id"

    fun register(
        context: Context,
        messenger: BinaryMessenger,
        activityProvider: (() -> Activity?)? = null,
    ) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "schedule" -> {
                        val alarm = call.argument<Map<String, Any?>>("alarm")
                        if (alarm == null) {
                            result.error("invalid_args", "Missing alarm payload", null)
                            return@setMethodCallHandler
                        }
                        val definition = toDefinition(alarm)
                        if (definition == null) {
                            result.error("invalid_args", "Invalid alarm payload", null)
                            return@setMethodCallHandler
                        }
                        val store = AlarmStore(context)
                        store.upsert(definition)
                        AlarmScheduler.schedule(context, definition)
                        result.success(true)
                    }
                    "cancel" -> {
                        val alarmId = call.argument<String>("alarmId")
                        if (alarmId.isNullOrBlank()) {
                            result.error("invalid_args", "Missing alarmId", null)
                            return@setMethodCallHandler
                        }
                        AlarmStore(context).remove(alarmId)
                        AlarmScheduler.cancel(context, alarmId)
                        result.success(true)
                    }
                    "cancelAll" -> {
                        AlarmStore(context).clear()
                        AlarmScheduler.cancelAll(context)
                        result.success(true)
                    }
                    "requestPermissions" -> {
                        requestPermissionsIfNeeded(context, activityProvider?.invoke())
                        result.success(true)
                    }
                    "startNow" -> {
                        val alarm = call.argument<Map<String, Any?>>("alarm")
                        if (alarm == null) {
                            result.error("invalid_args", "Missing alarm payload", null)
                            return@setMethodCallHandler
                        }
                        val definition = toDefinition(alarm)
                        if (definition == null) {
                            result.error("invalid_args", "Invalid alarm payload", null)
                            return@setMethodCallHandler
                        }
                        AlarmService.startNow(
                            context = context,
                            alarmId = definition.id,
                            label = definition.label,
                            snoozeMinutes = definition.snoozeMinutes,
                        )
                        result.success(true)
                    }
                    "stopActive" -> {
                        AlarmService.stopActive(context)
                        result.success(true)
                    }
                    "setAlarmStreamToMax" -> {
                        setAlarmStreamToMax(context)
                        result.success(true)
                    }
                    "getAlarmState" -> {
                        result.success(AlarmService.stateMap())
                    }
                    "setAlarmTone" -> {
                        val toneId = call.argument<String>("toneId")
                        if (toneId.isNullOrBlank()) {
                            result.error("invalid_args", "Missing toneId", null)
                            return@setMethodCallHandler
                        }
                        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        prefs.edit().putString(KEY_ALARM_TONE_ID, toneId).apply()
                        result.success(true)
                    }
                    "setFailSafeKeepAliveEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        FailSafeKeepAliveService.setEnabled(context, enabled)
                        result.success(true)
                    }
                    "startFailSafeKeepAliveNow" -> {
                        FailSafeKeepAliveService.start(context)
                        result.success(true)
                    }
                    "getFailSafeKeepAliveState" -> {
                        result.success(
                            mapOf(
                                "enabled" to FailSafeKeepAliveService.isEnabled(context),
                                "ignoringBatteryOptimizations" to isIgnoringBatteryOptimizations(context),
                            ),
                        )
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations(context)
                        result.success(true)
                    }
                    "getFailSafeDebugState" -> {
                        result.success(FailSafeKeepAliveService.getDebugState(context))
                    }
                    "setFailSafeUiSocketState" -> {
                        val ownsSockets = call.argument<Boolean>("ownsSockets") ?: false
                        FailSafeKeepAliveService.setUiSocketState(ownsSockets)
                        result.success(true)
                    }
                    "setFailSafeBackgroundSocketState" -> {
                        val ownsSockets = call.argument<Boolean>("ownsSockets") ?: false
                        FailSafeKeepAliveService.setBackgroundSocketState(ownsSockets)
                        result.success(true)
                    }
                    "notifyFailSafeConfigChanged" -> {
                        FailSafeKeepAliveService.onConfigChanged(context)
                        result.success(true)
                    }
                    "getDeviceIdentifier" -> {
                        val androidId = Settings.Secure.getString(
                            context.contentResolver,
                            Settings.Secure.ANDROID_ID,
                        )
                        if (androidId.isNullOrBlank()) {
                            result.error("device_id_unavailable", "ANDROID_ID unavailable", null)
                        } else {
                            result.success("android:$androidId")
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                result.error("native_alarm_error", error.message, null)
            }
        }
    }

    private fun requestPermissionsIfNeeded(context: Context, activity: Activity?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && activity != null) {
            val granted = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                ActivityCompat.requestPermissions(
                    activity,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    REQUEST_NOTIFICATIONS_PERMISSION,
                )
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (!alarmManager.canScheduleExactAlarms()) {
                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = Uri.parse("package:${context.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
            }
        }
    }

    private fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun requestIgnoreBatteryOptimizations(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || isIgnoringBatteryOptimizations(context)) {
            return
        }
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    private fun setAlarmStreamToMax(context: Context) {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        if (max > 0) {
            audioManager.setStreamVolume(AudioManager.STREAM_ALARM, max, 0)
        }
    }

    private fun toDefinition(values: Map<String, Any?>): AlarmDefinition? {
        val id = values["id"] as? String ?: return null
        if (id.isBlank()) return null
        val label = (values["label"] as? String)?.ifBlank { "Alarm" } ?: "Alarm"
        val hour = (values["hour"] as? Number)?.toInt()?.coerceIn(0, 23) ?: return null
        val minute = (values["minute"] as? Number)?.toInt()?.coerceIn(0, 59) ?: return null
        val daysRaw = values["daysOfWeek"] as? List<*>
        val days = daysRaw
            ?.mapNotNull { (it as? Number)?.toInt() }
            ?.filter { it in 1..7 }
            ?.toSet()
            ?: emptySet()
        val scheduledAtEpochMs = (values["scheduledAtEpochMs"] as? Number)?.toLong()
        val snoozeMinutes = (values["snoozeMinutes"] as? Number)?.toInt()?.coerceIn(1, 60) ?: 5
        val isEnabled = values["isEnabled"] as? Boolean ?: true
        return AlarmDefinition(
            id = id,
            label = label,
            hour = hour,
            minute = minute,
            scheduledAtEpochMs = scheduledAtEpochMs,
            daysOfWeek = days,
            snoozeMinutes = snoozeMinutes,
            isEnabled = isEnabled,
        )
    }
}
