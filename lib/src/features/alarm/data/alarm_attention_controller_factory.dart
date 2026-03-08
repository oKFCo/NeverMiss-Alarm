import 'dart:io';

import '../application/alarm_attention_controller.dart';
import 'alarm_settings_store.dart';
import 'android_alarm_attention_controller.dart';
import 'ios_alarm_attention_controller.dart';
import 'windows_alarm_attention_controller.dart';

Future<AlarmAttentionController> createAlarmAttentionController(
  AlarmSettingsStore settingsStore,
) async {
  final controller = Platform.isWindows
      ? WindowsAlarmAttentionController(settingsStore: settingsStore)
      : Platform.isAndroid
          ? AndroidAlarmAttentionController(settingsStore: settingsStore)
          : Platform.isIOS
              ? IosAlarmAttentionController(settingsStore: settingsStore)
              : NoopAlarmAttentionController();
  await controller.initialize();
  return controller;
}
