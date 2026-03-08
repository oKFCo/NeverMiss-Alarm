package com.verint.verint_alarm_flutter

import com.verint.verint_alarm_flutter.platform.AndroidAlarmChannelRegistrar
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AndroidAlarmChannelRegistrar.register(
            context = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            activityProvider = { this },
        )
    }
}
