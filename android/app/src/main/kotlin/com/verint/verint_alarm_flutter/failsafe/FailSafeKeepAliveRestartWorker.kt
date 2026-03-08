package com.verint.verint_alarm_flutter.failsafe

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

class FailSafeKeepAliveRestartWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {
    override fun doWork(): Result {
        FailSafeKeepAliveService.logRestartStage(
            stage = "workerFallbackTriggered",
            details = "attempt=$runAttemptCount",
        )
        val started = FailSafeKeepAliveService.restartFromWorker(applicationContext)
        return if (started) {
            Result.success()
        } else {
            Result.retry()
        }
    }
}
