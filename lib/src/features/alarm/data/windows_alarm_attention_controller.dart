import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:win32/win32.dart';

import '../application/alarm_attention_controller.dart';
import '../domain/alarm_tone.dart';
import 'alarm_settings_store.dart';
import '../domain/alarm.dart';

class WindowsAlarmAttentionController implements AlarmAttentionController {
  WindowsAlarmAttentionController({
    required AlarmSettingsStore settingsStore,
  }) : _settingsStore = settingsStore;

  final AlarmSettingsStore _settingsStore;
  Player? _player;
  Timer? _beepFallbackTimer;
  Timer? _focusPulseTimer;
  bool _initialized = false;
  bool _audioPlaying = false;
  String? _currentOutputDeviceId;

  @override
  Future<void> initialize() async {
    if (!Platform.isWindows || _initialized) {
      return;
    }
    MediaKit.ensureInitialized();
    _player ??= Player();
    await windowManager.ensureInitialized();
    await _player!.setPlaylistMode(PlaylistMode.single);
    await _player!.setVolume(100.0);
    await _applyConfiguredOutputDevice();
    _initialized = true;
  }

  @override
  Future<void> startRingingAttention(Alarm alarm) async {
    if (!Platform.isWindows) {
      return;
    }
    await initialize();
    await stopRingingAttention();

    await windowManager.show();
    await windowManager.restore();
    await windowManager.setAlwaysOnTop(true);
    await windowManager.focus();

    await _startAudioLoopOrFallback();

    _focusPulseTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
    });
  }

  @override
  Future<void> stopRingingAttention() async {
    _beepFallbackTimer?.cancel();
    _beepFallbackTimer = null;
    if (_audioPlaying) {
      await _player!.stop();
      _audioPlaying = false;
    }
    _focusPulseTimer?.cancel();
    _focusPulseTimer = null;

    if (!Platform.isWindows || !_initialized) {
      return;
    }
    await windowManager.setAlwaysOnTop(false);
  }

  @override
  Future<AlarmAttentionState> readAttentionState() async {
    return const AlarmAttentionState(isActive: false);
  }

  @override
  Future<List<AlarmOutputDevice>> listOutputDevices() async {
    if (!Platform.isWindows) {
      return const <AlarmOutputDevice>[];
    }
    await initialize();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final devices = _player!.state.audioDevices;
    return devices
        .map(
          (d) => AlarmOutputDevice(
            id: d.name,
            label: _friendlyDeviceLabel(d.name, d.description),
            description: _friendlyDeviceDescription(d.name),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> setPreferredOutputDevice(String? deviceId) async {
    if (!Platform.isWindows) {
      return;
    }
    await initialize();
    _currentOutputDeviceId = deviceId;
    await _applyOutputDevice(deviceId);
  }

  @override
  void dispose() {
    _beepFallbackTimer?.cancel();
    _focusPulseTimer?.cancel();
    _player?.dispose();
  }

  Future<void> _startAudioLoopOrFallback() async {
    try {
      await _player!.stop();
      await _applyConfiguredOutputDevice();
      final tone = alarmToneById(_settingsStore.settings.alarmToneId);
      await _player!.open(
        Media('asset:///${tone.assetPath}'),
        play: true,
      );
      _audioPlaying = true;
    } catch (error) {
      debugPrint('Audio alarm failed, using beep fallback: $error');
      _audioPlaying = false;
      _beepFallbackTimer =
          Timer.periodic(const Duration(milliseconds: 900), (_) {
        Beep(1100, 180);
      });
    }
  }

  Future<void> _applyConfiguredOutputDevice() async {
    final configured = _settingsStore.settings.alarmOutputDeviceId;
    if (configured == _currentOutputDeviceId && configured != null) {
      return;
    }
    _currentOutputDeviceId = configured;
    await _applyOutputDevice(configured);
  }

  Future<void> _applyOutputDevice(String? deviceId) async {
    final selected =
        (deviceId == null || deviceId.isEmpty || deviceId == 'auto')
            ? AudioDevice.auto()
            : AudioDevice(deviceId, '');
    await _player!.setAudioDevice(selected);
  }

  String _friendlyDeviceLabel(String name, String description) {
    if (name == 'auto') {
      return 'System default';
    }
    final text = description.trim();
    if (text.isNotEmpty) {
      return text;
    }
    return name;
  }

  String? _friendlyDeviceDescription(String name) {
    if (name == 'auto') {
      return 'Autoselect device';
    }
    final slashIndex = name.indexOf('/');
    if (slashIndex <= 0) {
      return null;
    }
    final backend = name.substring(0, slashIndex).trim();
    if (backend.isEmpty) {
      return null;
    }
    return backend.toUpperCase();
  }
}
