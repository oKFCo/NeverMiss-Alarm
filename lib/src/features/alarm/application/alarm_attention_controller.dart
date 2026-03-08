import '../domain/alarm.dart';

enum AlarmAttentionAction {
  none,
  dismiss,
  snooze,
}

class AlarmAttentionState {
  const AlarmAttentionState({
    required this.isActive,
    this.alarmId,
    this.action = AlarmAttentionAction.none,
    this.actionSeq = 0,
  });

  final bool isActive;
  final String? alarmId;
  final AlarmAttentionAction action;
  final int actionSeq;
}

class AlarmOutputDevice {
  const AlarmOutputDevice({
    required this.id,
    required this.label,
    this.description,
  });

  final String id;
  final String label;
  final String? description;
}

abstract class AlarmAttentionController {
  Future<void> initialize();
  Future<void> startRingingAttention(Alarm alarm);
  Future<void> stopRingingAttention();
  Future<List<AlarmOutputDevice>> listOutputDevices() async {
    return const <AlarmOutputDevice>[];
  }

  Future<void> setPreferredOutputDevice(String? deviceId) async {}
  Future<AlarmAttentionState> readAttentionState() async {
    return const AlarmAttentionState(isActive: false);
  }

  void dispose();
}

class NoopAlarmAttentionController implements AlarmAttentionController {
  @override
  void dispose() {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> startRingingAttention(Alarm alarm) async {}

  @override
  Future<void> stopRingingAttention() async {}

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
}
