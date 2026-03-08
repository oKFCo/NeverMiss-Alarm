package com.verint.verint_alarm_flutter.failsafe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class FailSafeKeepAliveRestartReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        FailSafeKeepAliveService.logRestartStage("receiverTriggered")
        FailSafeKeepAliveService.restartFromWatchdog(context)
    }
}
