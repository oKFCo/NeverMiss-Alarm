import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/alarm.dart';
import '../domain/alarm_scheduler.dart';

class AndroidNotificationAlarmScheduler implements AlarmScheduler {
  static const MethodChannel _channel = MethodChannel('verint_alarm/android_alarm');
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized || !Platform.isAndroid) {
      return;
    }
    _initialized = true;
  }

  @override
  Future<void> requestPermissions() async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('requestPermissions');
  }

  @override
  Future<void> schedule(Alarm alarm) async {
    if (!Platform.isAndroid) {
      return;
    }
    await initialize();
    await cancel(alarm.id);

    if (!alarm.isEnabled) {
      return;
    }

    await _channel.invokeMethod<void>('schedule', <String, dynamic>{
      'alarm': <String, dynamic>{
        'id': alarm.id,
        'label': alarm.label,
        'hour': alarm.hour,
        'minute': alarm.minute,
        'daysOfWeek': alarm.daysOfWeek.toList()..sort(),
        'snoozeMinutes': alarm.snoozeMinutes ?? 5,
        'isEnabled': alarm.isEnabled,
        'scheduledAtEpochMs': alarm.scheduledAt?.millisecondsSinceEpoch,
      },
    });
  }

  @override
  Future<void> cancel(String alarmId) async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('cancel', <String, dynamic>{
      'alarmId': alarmId,
    });
  }

  @override
  Future<void> cancelAll() async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('cancelAll');
  }
}
