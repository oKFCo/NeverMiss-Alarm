import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../application/alarm_attention_controller.dart';
import '../domain/alarm_tone.dart';
import 'alarm_settings_store.dart';
import '../domain/alarm.dart';

class AndroidAlarmAttentionController implements AlarmAttentionController {
  AndroidAlarmAttentionController({
    required AlarmSettingsStore settingsStore,
  }) : _settingsStore = settingsStore;

  static const MethodChannel _channel =
      MethodChannel('verint_alarm/android_alarm');
  final AlarmSettingsStore _settingsStore;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (!Platform.isAndroid || _initialized) {
      return;
    }
    await _pushToneToNative();
    _settingsStore.addListener(_onSettingsChanged);
    _initialized = true;
  }

  @override
  Future<void> startRingingAttention(Alarm alarm) async {
    if (!Platform.isAndroid) {
      return;
    }
    await initialize();
    await _channel.invokeMethod<void>('startNow', <String, dynamic>{
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
  Future<void> stopRingingAttention() async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('stopActive');
  }

  @override
  Future<List<AlarmOutputDevice>> listOutputDevices() async {
    return const <AlarmOutputDevice>[];
  }

  @override
  Future<void> setPreferredOutputDevice(String? deviceId) async {}

  @override
  Future<AlarmAttentionState> readAttentionState() async {
    if (!Platform.isAndroid) {
      return const AlarmAttentionState(isActive: false);
    }
    final map =
        await _channel.invokeMapMethod<String, dynamic>('getAlarmState');
    if (map == null) {
      return const AlarmAttentionState(isActive: false);
    }
    final actionRaw = (map['lastAction'] as String? ?? '').toLowerCase();
    final action = switch (actionRaw) {
      'dismiss' => AlarmAttentionAction.dismiss,
      'snooze' => AlarmAttentionAction.snooze,
      _ => AlarmAttentionAction.none,
    };
    return AlarmAttentionState(
      isActive: map['isActive'] as bool? ?? false,
      alarmId: map['alarmId'] as String?,
      action: action,
      actionSeq: map['actionSeq'] as int? ?? 0,
    );
  }

  @override
  void dispose() {
    if (Platform.isAndroid && _initialized) {
      _settingsStore.removeListener(_onSettingsChanged);
    }
  }

  void _onSettingsChanged() {
    _pushToneToNative();
  }

  Future<void> _pushToneToNative() async {
    try {
      final toneId = normalizeAlarmToneId(_settingsStore.settings.alarmToneId);
      await _channel.invokeMethod<void>('setAlarmTone', <String, dynamic>{
        'toneId': toneId,
      });
    } catch (error) {
      debugPrint('Failed to sync Android alarm tone: $error');
    }
  }
}
