package com.verint.verint_alarm_flutter.alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.verint.verint_alarm_flutter.MainActivity
import com.verint.verint_alarm_flutter.R

class AlarmService : Service() {
    private var mediaPlayer: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var vibrator: Vibrator? = null
    private var currentAlarmId: String? = null
    private var currentLabel: String = "Alarm"
    private var currentSnoozeMinutes: Int = 5

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_DISMISS -> {
                publishAction("dismiss")
                stopAlarm()
                return START_NOT_STICKY
            }
            ACTION_SNOOZE -> {
                publishAction("snooze")
                val id = currentAlarmId
                if (id != null) {
                    AlarmScheduler.scheduleSnooze(
                        context = this,
                        alarmId = id,
                        label = currentLabel,
                        snoozeMinutes = currentSnoozeMinutes,
                    )
                }
                stopAlarm()
                return START_NOT_STICKY
            }
            ACTION_START, null -> {
                val alarmId = intent?.getStringExtra(EXTRA_ALARM_ID) ?: return START_NOT_STICKY
                val label = intent.getStringExtra(EXTRA_LABEL) ?: "Alarm"
                val snoozeMinutes = intent.getIntExtra(EXTRA_SNOOZE_MINUTES, 5).coerceIn(1, 60)
                startAlarm(alarmId, label, snoozeMinutes)
                return START_STICKY
            }
            else -> return START_NOT_STICKY
        }
    }

    private fun startAlarm(alarmId: String, label: String, snoozeMinutes: Int) {
        currentAlarmId = alarmId
        currentLabel = label
        currentSnoozeMinutes = snoozeMinutes
        isAlarmActive = true
        activeAlarmId = alarmId
        publishAction("start")
        startForeground(NOTIFICATION_ID, buildNotification(label, snoozeMinutes))
        acquireWakeLock()
        startPlayback()
    }

    private fun buildNotification(label: String, snoozeMinutes: Int): Notification {
        val activityIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("alarm_active", true)
        }
        val openIntent = PendingIntent.getActivity(
            this,
            2001,
            activityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val dismissIntent = PendingIntent.getService(
            this,
            2002,
            dismissIntent(this),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val snoozeIntent = PendingIntent.getService(
            this,
            2003,
            snoozeIntent(this),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Alarm ringing")
            .setContentText(label)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(false)
            .setAutoCancel(false)
            .setContentIntent(openIntent)
            .setFullScreenIntent(openIntent, true)
            .setDeleteIntent(dismissIntent)
            .addAction(0, "Dismiss", dismissIntent)
            .addAction(0, "Snooze ${snoozeMinutes}m", snoozeIntent)
            .build()
    }

    private fun startPlayback() {
        val uri = resolveAlarmToneUri()
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        mediaPlayer?.release()
        mediaPlayer = MediaPlayer().apply {
            setDataSource(this@AlarmService, uri)
            setAudioAttributes(attributes)
            isLooping = true
            setOnPreparedListener { it.start() }
            prepareAsync()
        }

        val pattern = longArrayOf(0, 650, 450)
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager
            manager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun stopAlarm() {
        isAlarmActive = false
        activeAlarmId = null
        mediaPlayer?.run {
            runCatching { stop() }
            release()
        }
        mediaPlayer = null
        vibrator?.cancel()
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) {
            return
        }
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Alarm playback",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Active alarm playback and controls"
            setSound(null, null)
            enableVibration(true)
            lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun resolveAlarmToneUri(): Uri {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val toneId = prefs.getString(KEY_ALARM_TONE_ID, DEFAULT_TONE_ID) ?: DEFAULT_TONE_ID
        val rawResId = when (toneId) {
            "system_default" -> return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: Uri.parse("android.resource://$packageName/${R.raw.marimba}")
            "marimba" -> R.raw.marimba
            "fresh_morning" -> R.raw.fresh_morning
            "pixel_alarm" -> R.raw.pixel_alarm
            "never_miss" -> R.raw.never_miss
            else -> R.raw.marimba
        }
        return Uri.parse("android.resource://$packageName/$rawResId")
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) {
            return
        }
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "verint_alarm:flutter_alarm")
        wakeLock?.acquire(WAKELOCK_TIMEOUT_MS)
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        wakeLock = null
    }

    override fun onDestroy() {
        mediaPlayer?.run {
            runCatching { stop() }
            release()
        }
        mediaPlayer = null
        vibrator?.cancel()
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val CHANNEL_ID = "verint_alarm_native_channel_v2"
        private const val NOTIFICATION_ID = 90421
        private const val WAKELOCK_TIMEOUT_MS = 15 * 60 * 1000L
        private const val PREFS_NAME = "verint_alarm_native_store"
        private const val KEY_ALARM_TONE_ID = "alarm_tone_id"
        private const val DEFAULT_TONE_ID = "marimba"
        @Volatile
        private var isAlarmActive: Boolean = false
        @Volatile
        private var activeAlarmId: String? = null
        @Volatile
        private var lastAction: String = "none"
        @Volatile
        private var actionSeq: Int = 0

        const val ACTION_START = "com.verint.verint_alarm_flutter.alarm.START"
        const val ACTION_DISMISS = "com.verint.verint_alarm_flutter.alarm.DISMISS"
        const val ACTION_SNOOZE = "com.verint.verint_alarm_flutter.alarm.SNOOZE"
        const val EXTRA_ALARM_ID = "extra_alarm_id"
        const val EXTRA_LABEL = "extra_label"
        const val EXTRA_SNOOZE_MINUTES = "extra_snooze_minutes"

        fun startIntent(
            context: Context,
            alarmId: String,
            label: String,
            snoozeMinutes: Int,
        ): Intent {
            return Intent(context, AlarmService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_ALARM_ID, alarmId)
                .putExtra(EXTRA_LABEL, label)
                .putExtra(EXTRA_SNOOZE_MINUTES, snoozeMinutes.coerceIn(1, 60))
        }

        fun dismissIntent(context: Context): Intent {
            return Intent(context, AlarmService::class.java).setAction(ACTION_DISMISS)
        }

        fun snoozeIntent(context: Context): Intent {
            return Intent(context, AlarmService::class.java).setAction(ACTION_SNOOZE)
        }

        fun startNow(context: Context, alarmId: String, label: String, snoozeMinutes: Int) {
            ContextCompat.startForegroundService(
                context,
                startIntent(context, alarmId, label, snoozeMinutes),
            )
        }

        fun stopActive(context: Context) {
            context.startService(dismissIntent(context))
        }

        fun stateMap(): Map<String, Any?> {
            return mapOf(
                "isActive" to isAlarmActive,
                "alarmId" to activeAlarmId,
                "lastAction" to lastAction,
                "actionSeq" to actionSeq,
            )
        }

        private fun publishAction(action: String) {
            lastAction = action
            actionSeq += 1
        }
    }
}
