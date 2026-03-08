package com.verint.verint_alarm_flutter.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.verint.verint_alarm_flutter.failsafe.FailSafeKeepAliveService

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> {
                AlarmScheduler.rescheduleAllFromStore(context)
                FailSafeKeepAliveService.syncFromPrefs(context)
            }
        }
    }
}
