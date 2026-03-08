import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../../core/audio/fail_safe_volume_booster.dart';
import 'alarm_attention_controller.dart';
import '../data/alarm_settings_store.dart';
import '../data/in_memory_alarm_repository.dart';
import '../domain/alarm.dart';
import '../domain/alarm_occurrence.dart';
import '../../failsafe/domain/fail_safe_models.dart';

class AlarmOccurrence {
  const AlarmOccurrence({
    required this.alarmId,
    required this.alarmLabel,
    required this.when,
  });

  final String alarmId;
  final String alarmLabel;
  final DateTime when;

  String get formatted {
    return DateFormat('EEE, MMM d - hh:mm a').format(when);
  }
}

class ActiveAlarmState {
  const ActiveAlarmState({
    required this.alarmId,
    required this.label,
    required this.triggeredAt,
    required this.autoStopAt,
    required this.snoozeMinutes,
    required this.isManualTest,
  });

  final String alarmId;
  final String label;
  final DateTime triggeredAt;
  final DateTime autoStopAt;
  final int snoozeMinutes;
  final bool isManualTest;

  ActiveAlarmState copyWith({
    DateTime? autoStopAt,
    int? snoozeMinutes,
    bool? isManualTest,
  }) {
    return ActiveAlarmState(
      alarmId: alarmId,
      label: label,
      triggeredAt: triggeredAt,
      autoStopAt: autoStopAt ?? this.autoStopAt,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      isManualTest: isManualTest ?? this.isManualTest,
    );
  }
}

class AlarmHistoryEntry {
  const AlarmHistoryEntry({
    required this.at,
    required this.message,
  });

  final DateTime at;
  final String message;
}

class AlarmEngine extends ChangeNotifier with WidgetsBindingObserver {
  AlarmEngine({
    required InMemoryAlarmRepository repository,
    required AlarmSettingsStore settingsStore,
    required AlarmAttentionController attentionController,
    this.onAlarmTimeoutAutoStop,
  })  : _repository = repository,
        _settingsStore = settingsStore,
        _attentionController = attentionController;

  final InMemoryAlarmRepository _repository;
  final AlarmSettingsStore _settingsStore;
  final AlarmAttentionController _attentionController;
  final Future<void> Function(Alarm alarm)? onAlarmTimeoutAutoStop;
  final List<AlarmHistoryEntry> _history = <AlarmHistoryEntry>[];

  AlarmOccurrence? _nextOccurrence;
  ActiveAlarmState? _activeAlarm;
  Timer? _scheduleTimer;
  Timer? _ringTimeoutTimer;
  Timer? _attentionSyncTimer;
  bool _started = false;
  int _lastAttentionActionSeq = 0;
  bool _attentionSyncInFlight = false;

  AlarmOccurrence? get nextOccurrence => _nextOccurrence;
  ActiveAlarmState? get activeAlarm => _activeAlarm;
  List<AlarmHistoryEntry> get history => List.unmodifiable(_history);

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _repository.addListener(_onAlarmsChanged);
    _settingsStore.addListener(_onSettingsChanged);
    _reschedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _repository.removeListener(_onAlarmsChanged);
    _settingsStore.removeListener(_onSettingsChanged);
    _scheduleTimer?.cancel();
    _ringTimeoutTimer?.cancel();
    _attentionSyncTimer?.cancel();
    _attentionController.dispose();
    super.dispose();
  }

  void dismissActive() {
    final active = _activeAlarm;
    if (active == null) {
      return;
    }
    final alarm = _repository.findById(active.alarmId);
    _appendHistory('Dismissed alarm "${active.label}"');
    _activeAlarm = null;
    _ringTimeoutTimer?.cancel();
    _attentionSyncTimer?.cancel();
    _attentionController.stopRingingAttention();
    _finalizeCompletedAlarm(alarm, wasManualTest: active.isManualTest);
    notifyListeners();
    _reschedule();
  }

  void snoozeActive() {
    final active = _activeAlarm;
    if (active == null) {
      return;
    }
    final alarm = _repository.findById(active.alarmId);
    if (alarm == null) {
      dismissActive();
      return;
    }
    _appendHistory(
        'Snoozed alarm "${active.label}" for ${active.snoozeMinutes} min');
    _activeAlarm = null;
    _ringTimeoutTimer?.cancel();
    _attentionSyncTimer?.cancel();
    _attentionController.stopRingingAttention();
    notifyListeners();

    _scheduleTimer?.cancel();
    _scheduleTimer = Timer(Duration(minutes: active.snoozeMinutes), () {
      _startRinging(alarm, DateTime.now(), source: 'Snooze');
    });
  }

  void triggerNow(String alarmId) {
    final alarm = _repository.findById(alarmId);
    if (alarm == null) {
      return;
    }
    _startRinging(alarm, DateTime.now(), source: 'Manual test');
  }

  void triggerFromPlatformSchedule(String alarmId) {
    final alarm = _repository.findById(alarmId);
    if (alarm == null) {
      return;
    }
    _startRinging(alarm, DateTime.now(), source: 'Platform schedule');
    if ((alarm.daysOfWeek.isEmpty || alarm.scheduledAt != null) &&
        alarm.isEnabled &&
        !alarm.ringOnce) {
      _repository.update(alarm.copyWith(isEnabled: false));
    }
  }

  Future<void> triggerIncomingFailSafeAlert({
    required String sourceName,
    required String alarmLabel,
    required FailSafeReason reason,
  }) async {
    await FailSafeVolumeBooster.boostToMaximumForFailSafe();
    final alarm = Alarm(
      id: 'failsafe_${DateTime.now().millisecondsSinceEpoch}',
      label: '[Fail-safe] $alarmLabel',
      hour: DateTime.now().hour,
      minute: DateTime.now().minute,
      daysOfWeek: const <int>{},
      isEnabled: true,
      ringOnce: false,
      createdAt: DateTime.now(),
      snoozeMinutes: _defaultSnoozeMinutes,
    );
    _startRinging(
      alarm,
      DateTime.now(),
      source: 'Incoming ${reason.name} from $sourceName',
    );
  }

  void disableAll() {
    for (final alarm in _repository.getAll()) {
      if (alarm.isEnabled) {
        _repository.update(alarm.copyWith(isEnabled: false));
      }
    }
    _appendHistory('Disabled all alarms');
    _reschedule();
  }

  void clearHistory() {
    _history.clear();
    notifyListeners();
  }

  List<AlarmOccurrence> upcoming({int limit = 5}) {
    final now = DateTime.now();
    final values = _repository
        .getAll()
        .map((alarm) {
          final when = computeNextOccurrence(alarm: alarm, from: now);
          if (when == null) {
            return null;
          }
          return AlarmOccurrence(
            alarmId: alarm.id,
            alarmLabel: alarm.label,
            when: when,
          );
        })
        .whereType<AlarmOccurrence>()
        .toList()
      ..sort((a, b) => a.when.compareTo(b.when));
    return values.take(limit).toList(growable: false);
  }

  void _onAlarmsChanged() {
    _reschedule();
  }

  void _onSettingsChanged() {
    if (_activeAlarm case final active?) {
      final autoStopAt = DateTime.now().add(_ringTimeout);
      final alarm = _repository.findById(active.alarmId);
      _activeAlarm = active.copyWith(autoStopAt: autoStopAt);
      if (alarm != null) {
        _activeAlarm = _activeAlarm?.copyWith(
          snoozeMinutes: alarm.snoozeMinutes ?? _defaultSnoozeMinutes,
        );
      }
      _startRingTimeoutTimer();
    }
    notifyListeners();
  }

  void _reschedule() {
    if (_activeAlarm != null) {
      return;
    }

    _scheduleTimer?.cancel();
    _nextOccurrence = _computeNearest();
    notifyListeners();

    final occurrence = _nextOccurrence;
    if (occurrence == null) {
      return;
    }

    final duration = occurrence.when.difference(DateTime.now());
    if (duration.isNegative) {
      _fireForOccurrence(occurrence);
      return;
    }
    _scheduleTimer = Timer(duration, () {
      _fireForOccurrence(occurrence);
    });
  }

  AlarmOccurrence? _computeNearest() {
    final now = DateTime.now();
    AlarmOccurrence? nearest;

    for (final alarm in _repository.getAll()) {
      final when = computeNextOccurrence(alarm: alarm, from: now);
      if (when == null) {
        continue;
      }
      final occurrence = AlarmOccurrence(
        alarmId: alarm.id,
        alarmLabel: alarm.label,
        when: when,
      );
      if (nearest == null || occurrence.when.isBefore(nearest.when)) {
        nearest = occurrence;
      }
    }

    return nearest;
  }

  void _fireForOccurrence(AlarmOccurrence occurrence) {
    final alarm = _repository.findById(occurrence.alarmId);
    if (alarm == null || !alarm.isEnabled) {
      _reschedule();
      return;
    }
    _startRinging(alarm, occurrence.when, source: 'Scheduled');

    if (alarm.daysOfWeek.isEmpty || alarm.scheduledAt != null) {
      if (!alarm.ringOnce) {
        _repository.update(alarm.copyWith(isEnabled: false));
      }
    }
  }

  void _startRinging(
    Alarm alarm,
    DateTime when, {
    required String source,
  }) {
    _scheduleTimer?.cancel();
    _ringTimeoutTimer?.cancel();

    final autoStopAt = DateTime.now().add(_ringTimeout);
    _activeAlarm = ActiveAlarmState(
      alarmId: alarm.id,
      label: alarm.label,
      triggeredAt: when,
      autoStopAt: autoStopAt,
      snoozeMinutes: alarm.snoozeMinutes ?? _defaultSnoozeMinutes,
      isManualTest: source == 'Manual test',
    );
    _appendHistory(
        '$source ring "${alarm.label}" at ${DateFormat('hh:mm a').format(when)}');
    _attentionController.startRingingAttention(alarm);
    notifyListeners();

    _startRingTimeoutTimer();
    _startAttentionSyncTimer();
  }

  void _appendHistory(String message) {
    _history.insert(
      0,
      AlarmHistoryEntry(
        at: DateTime.now(),
        message: message,
      ),
    );
    if (_history.length > 50) {
      _history.removeRange(50, _history.length);
    }
  }

  Duration get _ringTimeout =>
      Duration(minutes: _settingsStore.settings.ringTimeoutMinutes);

  void _startRingTimeoutTimer() {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = Timer(_ringTimeout, () {
      final active = _activeAlarm;
      if (active == null) {
        return;
      }
      _appendHistory('Auto-stopped alarm "${active.label}" after timeout');
      _activeAlarm = null;
      _attentionController.stopRingingAttention();
      _attentionSyncTimer?.cancel();
      final alarm = _repository.findById(active.alarmId);
      if (alarm != null) {
        onAlarmTimeoutAutoStop?.call(alarm);
      }
      _finalizeCompletedAlarm(alarm, wasManualTest: active.isManualTest);
      notifyListeners();
      _reschedule();
    });
  }

  int get _defaultSnoozeMinutes => _settingsStore.settings.snoozeMinutes;

  void _startAttentionSyncTimer() {
    _attentionSyncTimer?.cancel();
    if (!Platform.isAndroid) {
      return;
    }
    unawaited(_syncAttentionState());
    _attentionSyncTimer =
        Timer.periodic(const Duration(milliseconds: 200), (_) {
      unawaited(_syncAttentionState());
    });
  }

  Future<void> _syncAttentionState() async {
    if (!Platform.isAndroid || _attentionSyncInFlight) {
      return;
    }
    _attentionSyncInFlight = true;
    try {
      final state = await _attentionController.readAttentionState();
      var active = _activeAlarm;
      if (active == null && state.isActive) {
        final alarm =
            state.alarmId == null ? null : _repository.findById(state.alarmId!);
        active = ActiveAlarmState(
          alarmId: state.alarmId ?? 'native_active_alarm',
          label: alarm?.label ?? 'Alarm',
          triggeredAt: DateTime.now(),
          autoStopAt: DateTime.now().add(_ringTimeout),
          snoozeMinutes: alarm?.snoozeMinutes ?? _defaultSnoozeMinutes,
          isManualTest: false,
        );
        _activeAlarm = active;
        _startRingTimeoutTimer();
        notifyListeners();
      }
      if (active == null) {
        return;
      }
      if (state.actionSeq > _lastAttentionActionSeq) {
        _lastAttentionActionSeq = state.actionSeq;
        if (state.alarmId == active.alarmId || state.alarmId == null) {
          if (state.action == AlarmAttentionAction.dismiss ||
              state.action == AlarmAttentionAction.snooze) {
            _appendHistory(
              state.action == AlarmAttentionAction.snooze
                  ? 'Snoozed alarm "${active.label}" from notification'
                  : 'Dismissed alarm "${active.label}" from notification',
            );
            final alarm = _repository.findById(active.alarmId);
            _activeAlarm = null;
            _ringTimeoutTimer?.cancel();
            _attentionSyncTimer?.cancel();
            if (state.action == AlarmAttentionAction.dismiss) {
              _finalizeCompletedAlarm(alarm, wasManualTest: active.isManualTest);
            }
            notifyListeners();
            _reschedule();
            return;
          }
        }
      }
      if (!state.isActive) {
        _appendHistory('Alarm "${active.label}" ended from native UI');
        final alarm = _repository.findById(active.alarmId);
        _activeAlarm = null;
        _ringTimeoutTimer?.cancel();
        _attentionSyncTimer?.cancel();
        _finalizeCompletedAlarm(alarm, wasManualTest: active.isManualTest);
        notifyListeners();
        _reschedule();
      }
    } finally {
      _attentionSyncInFlight = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncAttentionState());
    }
  }

  void _finalizeCompletedAlarm(
    Alarm? alarm, {
    required bool wasManualTest,
  }) {
    if (alarm == null) {
      return;
    }
    if (wasManualTest) {
      return;
    }
    if (alarm.ringOnce) {
      _repository.delete(alarm.id);
      return;
    }
    if ((alarm.daysOfWeek.isEmpty || alarm.scheduledAt != null) &&
        alarm.isEnabled) {
      _repository.update(alarm.copyWith(isEnabled: false));
    }
  }
}
