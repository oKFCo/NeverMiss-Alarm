import 'dart:io';

import 'package:flutter/services.dart';

class FailSafeVolumeBooster {
  static const MethodChannel _androidChannel =
      MethodChannel('verint_alarm/android_alarm');
  static const MethodChannel _iosChannel =
      MethodChannel('verint_alarm/ios_alarm');

  static Future<void> boostToMaximumForFailSafe() async {
    try {
      if (Platform.isAndroid) {
        await _androidChannel.invokeMethod<void>('setAlarmStreamToMax');
      } else if (Platform.isIOS) {
        await _iosChannel.invokeMethod<void>('prepareAlarmAudioSession');
      }
    } catch (_) {
      // Best-effort only: ringing flow must continue even if volume boost fails.
    }
  }
}
