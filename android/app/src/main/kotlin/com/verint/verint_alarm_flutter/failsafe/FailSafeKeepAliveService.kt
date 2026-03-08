package com.verint.verint_alarm_flutter.failsafe

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.work.BackoffPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import com.verint.verint_alarm_flutter.MainActivity
import com.verint.verint_alarm_flutter.R
import com.verint.verint_alarm_flutter.platform.AndroidAlarmChannelRegistrar
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.util.concurrent.TimeUnit

class FailSafeKeepAliveService : Service() {
    private var allowAutoRestart = true

    override fun onCreate() {
        super.onCreate()
        Log.i(LOG_TAG, "Service onCreate")
        ensureNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(
            LOG_TAG,
            "onStartCommand action=${intent?.action ?: "null"} flags=$flags startId=$startId",
        )
        when (intent?.action) {
            ACTION_STOP -> {
                logRestartStage("serviceStopAction", "action=STOP")
                allowAutoRestart = false
                cancelScheduledRestart(this)
                stopBackgroundRuntime()
                stopForeground(STOP_FOREGROUND_REMOVE)
                setForegroundRunning(false)
                stopSelf()
                Log.i(LOG_TAG, "Service stop requested.")
                return START_NOT_STICKY
            }
            ACTION_DISABLE -> {
                logRestartStage("serviceStopAction", "action=DISABLE")
                allowAutoRestart = false
                persistEnabled(this, false)
                cancelScheduledRestart(this)
                stopBackgroundRuntime()
                stopForeground(STOP_FOREGROUND_REMOVE)
                setForegroundRunning(false)
                stopSelf()
                Log.i(LOG_TAG, "Service disable requested.")
                return START_NOT_STICKY
            }
        }
        allowAutoRestart = true
        cancelScheduledRestart(this)
        Log.i(LOG_TAG, "startForeground begin notificationId=$NOTIFICATION_ID")
        startForeground(NOTIFICATION_ID, buildNotification())
        Log.i(LOG_TAG, "startForeground complete")
        setForegroundRunning(true)
        ensureBackgroundRuntime(this)
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        logRestartStage(
            "taskRemoved",
            "allowAutoRestart=$allowAutoRestart enabled=${isEnabled(this)}",
        )
        if (allowAutoRestart && isEnabled(this)) {
            scheduleRestart(this, delayMs = 2_500L)
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        Log.i(LOG_TAG, "Service onDestroy allowAutoRestart=$allowAutoRestart enabled=${isEnabled(this)}")
        if (allowAutoRestart && isEnabled(this)) {
            scheduleRestart(this, delayMs = 3_500L)
        } else {
            stopBackgroundRuntime()
        }
        setForegroundRunning(false)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        val activityIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val openIntent = PendingIntent.getActivity(
            this,
            3101,
            activityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val disableIntent = PendingIntent.getService(
            this,
            3102,
            Intent(this, FailSafeKeepAliveService::class.java).setAction(ACTION_DISABLE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Fail-safe protection is active")
            .setContentText("Background listener is running")
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "NeverMiss Alarm is keeping fail-safe listening active so remote alerts and timeout routing stay reliable.",
                ),
            )
            .setSubText("NeverMiss Alarm")
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setColor(ContextCompat.getColor(this, R.color.failsafe_accent))
            .setColorized(false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(openIntent)
            .addAction(0, "Disable", disableIntent)
            .build()
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
            "Fail-safe keep-alive",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Background process keep-alive for fail-safe listener"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "verint_alarm_failsafe_keepalive"
        private const val NOTIFICATION_ID = 90422
        private const val ACTION_START = "com.verint.verint_alarm_flutter.failsafe.START_KEEPALIVE"
        private const val ACTION_STOP = "com.verint.verint_alarm_flutter.failsafe.STOP_KEEPALIVE"
        private const val ACTION_DISABLE = "com.verint.verint_alarm_flutter.failsafe.DISABLE_KEEPALIVE"
        private const val ACTION_RESTART = "com.verint.verint_alarm_flutter.failsafe.RESTART_KEEPALIVE"
        private const val PREFS_NAME = "verint_alarm_runtime"
        private const val KEY_FAILSAFE_KEEPALIVE_ENABLED = "failsafe_keepalive_enabled"
        private const val RESTART_REQUEST_CODE = 3103
        private const val BACKGROUND_ENTRYPOINT = "backgroundMain"
        private const val BACKGROUND_CHANNEL = "verint_alarm/failsafe_background"
        private const val HEARTBEAT_TIMEOUT_MS = 35_000L
        private const val HEALTH_CHECK_INTERVAL_MS = 10_000L
        private const val HEARTBEAT_LOG_INTERVAL_MS = 60_000L
        private const val WORK_RESTART_UNIQUE = "failsafe_keepalive_worker_restart"
        private const val LOG_TAG = "FailSafeKeepAlive"
        @Volatile
        private var backgroundEngine: FlutterEngine? = null
        @Volatile
        private var lastHeartbeatElapsedMs: Long = 0L
        @Volatile
        private var lastHeartbeatLogElapsedMs: Long = 0L
        @Volatile
        private var foregroundRunning: Boolean = false
        @Volatile
        private var uiSocketsBound: Boolean = false
        @Volatile
        private var backgroundSocketsBound: Boolean = false
        private var healthCheckHandler: Handler? = null
        private var healthCheckRunnable: Runnable? = null

        fun setEnabled(context: Context, enabled: Boolean) {
            logRestartStage("setEnabledCalled", "enabled=$enabled")
            persistEnabled(context, enabled)
            if (enabled) {
                start(context, source = "setEnabled")
            } else {
                stop(context)
            }
        }

        fun start(context: Context) {
            persistEnabled(context, true)
            start(context, source = "directStart")
        }

        fun isEnabled(context: Context): Boolean {
            return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_FAILSAFE_KEEPALIVE_ENABLED, false)
        }

        fun syncFromPrefs(context: Context) {
            if (isEnabled(context)) {
                start(context, source = "bootSync")
            } else {
                stop(context)
            }
        }

        fun restartFromWatchdog(context: Context) {
            if (!isEnabled(context)) {
                cancelScheduledRestart(context)
                return
            }
            start(context, source = "receiver")
        }

        fun restartFromWorker(context: Context): Boolean {
            if (!isEnabled(context)) {
                return true
            }
            return start(
                context = context,
                source = "worker",
                allowWorkerFallback = false,
            )
        }

        fun setUiSocketState(ownsSockets: Boolean) {
            uiSocketsBound = ownsSockets
            Log.i(LOG_TAG, "Socket ownership update: uiSocketsBound=$ownsSockets")
        }

        fun setBackgroundSocketState(ownsSockets: Boolean) {
            backgroundSocketsBound = ownsSockets
            Log.i(LOG_TAG, "Socket ownership update: backgroundSocketsBound=$ownsSockets")
        }

        fun onConfigChanged(context: Context) {
            if (!isEnabled(context)) {
                return
            }
            Log.i(LOG_TAG, "Fail-safe config changed; reloading background runtime.")
            restartBackgroundRuntime(context.applicationContext)
        }

        fun getDebugState(context: Context): Map<String, Any?> {
            val now = SystemClock.elapsedRealtime()
            val heartbeatAgeMs =
                if (lastHeartbeatElapsedMs <= 0L) null else (now - lastHeartbeatElapsedMs)
            val heartbeatAlive = heartbeatAgeMs != null && heartbeatAgeMs <= HEARTBEAT_TIMEOUT_MS
            val runtimeOwner = when {
                backgroundSocketsBound -> "background"
                uiSocketsBound -> "ui"
                else -> "none"
            }
            return mapOf(
                "serviceEnabled" to isEnabled(context),
                "foregroundRunning" to foregroundRunning,
                "backgroundEngineRunning" to (backgroundEngine?.dartExecutor?.isExecutingDart == true),
                "heartbeatAlive" to heartbeatAlive,
                "heartbeatAgeMs" to heartbeatAgeMs,
                "runtimeOwner" to runtimeOwner,
                "backgroundSocketsBound" to backgroundSocketsBound,
                "uiSocketsBound" to uiSocketsBound,
            )
        }

        fun logRestartStage(stage: String, details: String? = null) {
            if (details.isNullOrBlank()) {
                Log.i(LOG_TAG, "restart_stage=$stage")
                return
            }
            Log.i(LOG_TAG, "restart_stage=$stage details=$details")
        }

        private fun setForegroundRunning(value: Boolean) {
            foregroundRunning = value
        }

        private fun start(
            context: Context,
            source: String,
            allowWorkerFallback: Boolean = true,
        ): Boolean {
            Log.i(LOG_TAG, "start(context) invoked source=$source")
            cancelScheduledRestart(context)
            val intent = Intent(context, FailSafeKeepAliveService::class.java).setAction(ACTION_START)
            logRestartStage("serviceStartAttempt", "source=$source")
            try {
                ContextCompat.startForegroundService(context, intent)
                return true
            } catch (error: Throwable) {
                if (isForegroundServiceStartNotAllowed(error)) {
                    logRestartStage("serviceStartBlocked", "source=$source")
                    if (allowWorkerFallback) {
                        scheduleWorkerFallback(context)
                    }
                } else {
                    Log.w(LOG_TAG, "Foreground start failed unexpectedly.", error)
                }
                scheduleRestart(context, delayMs = 10_000L)
                return false
            }
        }

        private fun stop(context: Context) {
            cancelScheduledRestart(context)
            stopBackgroundRuntime()
            val intent = Intent(context, FailSafeKeepAliveService::class.java).setAction(ACTION_STOP)
            context.startService(intent)
        }

        private fun ensureBackgroundRuntime(context: Context) {
            synchronized(this) {
                val existing = backgroundEngine
                if (existing != null && existing.dartExecutor.isExecutingDart) {
                    Log.i(LOG_TAG, "Background engine already running; reusing.")
                    startHealthWatchdog(context.applicationContext)
                    return
                }

                val appContext = context.applicationContext
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(appContext)
                loader.ensureInitializationComplete(appContext, arrayOf())

                Log.i(LOG_TAG, "Creating background FlutterEngine.")
                val engine = FlutterEngine(appContext)
                GeneratedPluginRegistrant.registerWith(engine)
                AndroidAlarmChannelRegistrar.register(
                    context = appContext,
                    messenger = engine.dartExecutor.binaryMessenger,
                )
                lastHeartbeatElapsedMs = SystemClock.elapsedRealtime()
                MethodChannel(
                    engine.dartExecutor.binaryMessenger,
                    BACKGROUND_CHANNEL,
                ).setMethodCallHandler { call, result ->
                    when (call.method) {
                        "heartbeat" -> {
                            val now = SystemClock.elapsedRealtime()
                            lastHeartbeatElapsedMs = now
                            if (now - lastHeartbeatLogElapsedMs >= HEARTBEAT_LOG_INTERVAL_MS) {
                                lastHeartbeatLogElapsedMs = now
                                Log.d(LOG_TAG, "Heartbeat received from Dart runtime.")
                            }
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                }
                val entrypoint = DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(),
                    BACKGROUND_ENTRYPOINT,
                )
                Log.i(LOG_TAG, "Executing Dart entrypoint: $BACKGROUND_ENTRYPOINT")
                engine.dartExecutor.executeDartEntrypoint(entrypoint)
                backgroundEngine = engine
                startHealthWatchdog(appContext)
            }
        }

        private fun startHealthWatchdog(context: Context) {
            val appContext = context.applicationContext
            val handler = healthCheckHandler ?: Handler(Looper.getMainLooper()).also {
                healthCheckHandler = it
            }
            healthCheckRunnable?.let(handler::removeCallbacks)
            val runnable = Runnable {
                val now = SystemClock.elapsedRealtime()
                val heartbeatAgeMs = now - lastHeartbeatElapsedMs
                if (isEnabled(appContext) &&
                    backgroundEngine != null &&
                    heartbeatAgeMs > HEARTBEAT_TIMEOUT_MS
                ) {
                    Log.w(LOG_TAG, "Heartbeat stale (${heartbeatAgeMs}ms); restarting background engine.")
                    restartBackgroundRuntime(appContext)
                }
                handler.postDelayed(healthCheckRunnable ?: return@Runnable, HEALTH_CHECK_INTERVAL_MS)
            }
            healthCheckRunnable = runnable
            handler.postDelayed(runnable, HEALTH_CHECK_INTERVAL_MS)
        }

        private fun restartBackgroundRuntime(context: Context) {
            Log.i(LOG_TAG, "Restarting background FlutterEngine.")
            stopBackgroundRuntime(clearHealthCheck = false)
            ensureBackgroundRuntime(context)
        }

        private fun stopBackgroundRuntime(clearHealthCheck: Boolean = true) {
            synchronized(this) {
                backgroundEngine?.destroy()
                backgroundEngine = null
                lastHeartbeatElapsedMs = 0L
                lastHeartbeatLogElapsedMs = 0L
                backgroundSocketsBound = false
                if (clearHealthCheck) {
                    healthCheckRunnable?.let { runnable ->
                        healthCheckHandler?.removeCallbacks(runnable)
                    }
                    healthCheckRunnable = null
                }
            }
        }

        private fun scheduleRestart(context: Context, delayMs: Long) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val triggerAt = SystemClock.elapsedRealtime() + delayMs.coerceAtLeast(1_000L)
            logRestartStage("alarmScheduled", "delayMs=$delayMs triggerAt=$triggerAt")
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                RESTART_REQUEST_CODE,
                Intent(context, FailSafeKeepAliveRestartReceiver::class.java).setAction(ACTION_RESTART),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAt,
                        pendingIntent,
                    )
                } else {
                    alarmManager.setExact(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAt,
                        pendingIntent,
                    )
                }
            } catch (_: SecurityException) {
                Log.w(LOG_TAG, "Exact alarm denied; falling back to inexact while-idle restart.")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAt,
                        pendingIntent,
                    )
                } else {
                    alarmManager.set(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAt,
                        pendingIntent,
                    )
                }
            }
        }

        private fun scheduleWorkerFallback(context: Context) {
            val request = OneTimeWorkRequestBuilder<FailSafeKeepAliveRestartWorker>()
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .setBackoffCriteria(BackoffPolicy.LINEAR, 15, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
                WORK_RESTART_UNIQUE,
                ExistingWorkPolicy.REPLACE,
                request,
            )
            logRestartStage("workerFallbackTriggered", "enqueued=true")
        }

        private fun isForegroundServiceStartNotAllowed(error: Throwable): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                return false
            }
            var cursor: Throwable? = error
            while (cursor != null) {
                if (cursor.javaClass.name == "android.app.ForegroundServiceStartNotAllowedException") {
                    return true
                }
                cursor = cursor.cause
            }
            return false
        }

        private fun cancelScheduledRestart(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                RESTART_REQUEST_CODE,
                Intent(context, FailSafeKeepAliveRestartReceiver::class.java).setAction(ACTION_RESTART),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            ) ?: return
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }

        private fun persistEnabled(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_FAILSAFE_KEEPALIVE_ENABLED, enabled)
                .apply()
        }
    }
}
