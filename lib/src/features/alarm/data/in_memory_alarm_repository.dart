import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/alarm.dart';
import '../domain/alarm_repository.dart';

class InMemoryAlarmRepository extends ChangeNotifier
    implements AlarmRepository {
  InMemoryAlarmRepository(this._storageFilePath);

  final List<Alarm> _alarms = [];
  final String _storageFilePath;
  int _sequence = 0;
  Future<void> _persistQueue = Future<void>.value();

  static Future<InMemoryAlarmRepository> loadFromDisk({
    String? storageFilePath,
  }) async {
    final repo =
        InMemoryAlarmRepository(storageFilePath ?? _defaultStoragePath());
    await repo._load();
    return repo;
  }

  void seedDefaults(List<AlarmDraft> drafts) {
    if (_alarms.isNotEmpty) {
      return;
    }
    for (final draft in drafts) {
      create(draft);
    }
  }

  @override
  Alarm create(AlarmDraft draft) {
    final alarm = Alarm(
      id: 'alarm_${++_sequence}',
      label: draft.label,
      hour: draft.hour,
      minute: draft.minute,
      daysOfWeek: {...draft.daysOfWeek},
      isEnabled: draft.isEnabled,
      ringOnce: draft.ringOnce,
      createdAt: DateTime.now(),
      snoozeMinutes: draft.snoozeMinutes,
      scheduledAt: draft.scheduledAt,
    );
    _alarms.add(alarm);
    _sort();
    _persist();
    notifyListeners();
    return alarm;
  }

  @override
  bool delete(String alarmId) {
    final before = _alarms.length;
    _alarms.removeWhere((a) => a.id == alarmId);
    final removed = _alarms.length < before;
    if (removed) {
      _persist();
      notifyListeners();
    }
    return removed;
  }

  @override
  Alarm? findById(String alarmId) {
    for (final alarm in _alarms) {
      if (alarm.id == alarmId) {
        return alarm;
      }
    }
    return null;
  }

  @override
  List<Alarm> getAll() {
    return List.unmodifiable(_alarms);
  }

  @override
  Alarm update(Alarm alarm) {
    final index = _alarms.indexWhere((a) => a.id == alarm.id);
    if (index == -1) {
      _alarms.add(alarm);
    } else {
      _alarms[index] = alarm;
    }
    _sort();
    _persist();
    notifyListeners();
    return alarm;
  }

  void _sort() {
    _alarms.sort((a, b) {
      final byHour = a.hour.compareTo(b.hour);
      if (byHour != 0) {
        return byHour;
      }
      return a.minute.compareTo(b.minute);
    });
  }

  Future<void> _load() async {
    final file = File(_storageFilePath);
    if (!await file.exists()) {
      return;
    }
    final raw = await file.readAsString();
    if (raw.isEmpty) {
      return;
    }
    final loadedAlarms = _decodeAlarmPayload(raw);
    if (loadedAlarms.isEmpty) {
      return;
    }
    _alarms
      ..clear()
      ..addAll(loadedAlarms);
    _sort();
    _syncSequence();
    // Self-heal corrupted/concatenated JSON by rewriting canonical payload.
    await _persistToDisk(jsonEncode(_alarms.map((a) => a.toJson()).toList()));
  }

  void _persist() {
    final payload = jsonEncode(_alarms.map((a) => a.toJson()).toList());
    _persistQueue = _persistQueue
        .catchError((_) {})
        .then((_) => _persistToDisk(payload));
    unawaited(_persistQueue);
  }

  Future<void> _persistToDisk(String payload) async {
    final file = File(_storageFilePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(payload, flush: true);
  }

  List<Alarm> _decodeAlarmPayload(String raw) {
    final values = <dynamic>[];
    try {
      values.add(jsonDecode(raw));
    } on FormatException {
      final chunks = _splitTopLevelJsonValues(raw);
      for (final chunk in chunks) {
        try {
          values.add(jsonDecode(chunk));
        } on FormatException {
          // Skip malformed chunk and continue salvage.
        }
      }
    }

    final alarms = <Alarm>[];
    for (final value in values) {
      if (value is List) {
        for (final item in value.whereType<Map>()) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          if (_looksLikeAlarmJson(map)) {
            alarms.add(Alarm.fromJson(map));
          }
        }
        continue;
      }
      if (value is Map) {
        final map = value.map((k, v) => MapEntry(k.toString(), v));
        final nested = map['alarms'];
        if (nested is List) {
          for (final item in nested.whereType<Map>()) {
            final nestedMap = item.map((k, v) => MapEntry(k.toString(), v));
            if (_looksLikeAlarmJson(nestedMap)) {
              alarms.add(Alarm.fromJson(nestedMap));
            }
          }
        } else if (_looksLikeAlarmJson(map)) {
          alarms.add(Alarm.fromJson(map));
        }
      }
    }
    return alarms;
  }

  bool _looksLikeAlarmJson(Map<String, dynamic> map) {
    return map['id'] is String &&
        map['hour'] is num &&
        map['minute'] is num;
  }

  List<String> _splitTopLevelJsonValues(String raw) {
    final values = <String>[];
    var depth = 0;
    var inString = false;
    var escaped = false;
    var start = -1;

    for (var i = 0; i < raw.length; i++) {
      final char = raw[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        if (inString) {
          escaped = true;
        }
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (char == '{' || char == '[') {
        if (depth == 0) {
          start = i;
        }
        depth++;
        continue;
      }
      if (char == '}' || char == ']') {
        if (depth > 0) {
          depth--;
          if (depth == 0 && start != -1) {
            values.add(raw.substring(start, i + 1));
            start = -1;
          }
        }
      }
    }
    return values;
  }

  void _syncSequence() {
    for (final alarm in _alarms) {
      final suffix = alarm.id.split('_').last;
      final parsed = int.tryParse(suffix);
      if (parsed != null && parsed > _sequence) {
        _sequence = parsed;
      }
    }
  }

  static String _defaultStoragePath() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return '$appData\\nevermiss_alarm\\alarms.v1.json';
      }
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return '$home/.nevermiss_alarm/alarms.v1.json';
  }
}
