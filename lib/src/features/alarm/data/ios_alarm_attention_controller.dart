import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../application/alarm_attention_controller.dart';
import '../domain/alarm_tone.dart';
import 'alarm_settings_store.dart';
import '../domain/alarm.dart';

class IosAlarmAttentionController implements AlarmAttentionController {
  IosAlarmAttentionController({
    required AlarmSettingsStore settingsStore,
  }) : _settingsStore = settingsStore;

  static const MethodChannel _channel = MethodChannel('verint_alarm/ios_alarm');
  final AlarmSettingsStore _settingsStore;
  final AudioPlayer _player = AudioPlayer(playerId: 'ios_alarm_attention');
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (!Platform.isIOS || _initialized) {
      return;
    }
    await _prepareAudioSession();
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(1.0);
    _initialized = true;
  }

  @override
  Future<void> startRingingAttention(Alarm alarm) async {
    if (!Platform.isIOS) {
      return;
    }
    await initialize();
    await _prepareAudioSession();
    try {
      await _player.stop();
      final tone = alarmToneById(_settingsStore.settings.alarmToneId);
      final relative = tone.assetPath.replaceFirst('assets/', '');
      await _player.play(AssetSource(relative));
    } catch (error) {
      debugPrint('iOS alarm playback failed: $error');
    }
  }

  @override
  Future<void> stopRingingAttention() async {
    if (!Platform.isIOS) {
      return;
    }
    await _player.stop();
  }

  @override
  Future<List<AlarmOutputDevice>> listOutputDevices() async {
    return const <AlarmOutputDevice>[];
  }

  @override
  Future<void> setPreferredOutputDevice(String? deviceId) async {}

  @override
  Future<AlarmAttentionState> readAttentionState() async {
    return const AlarmAttentionState(isActive: false);
  }

  @override
  void dispose() {
    _player.dispose();
  }

  Future<void> _prepareAudioSession() async {
    try {
      await _channel.invokeMethod<void>('prepareAlarmAudioSession');
    } catch (error) {
      debugPrint('iOS audio session prep failed: $error');
    }
  }
}
