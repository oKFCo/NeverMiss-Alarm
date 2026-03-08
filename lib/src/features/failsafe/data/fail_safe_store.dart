import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/fail_safe_models.dart';

class FailSafeStore extends ChangeNotifier {
  FailSafeStore(this._storageFilePath);

  final String _storageFilePath;

  bool _localFailSafeEnabled = false;
  String _localDeviceId = '';
  String _localDeviceName = '';
  int _listenPort = 9851;
  final List<PairedDevice> _devices = <PairedDevice>[];
  final List<FailSafeRoute> _routes = <FailSafeRoute>[];
  final List<FailSafeLogEntry> _logs = <FailSafeLogEntry>[];

  bool get localFailSafeEnabled => _localFailSafeEnabled;
  String get localDeviceId => _localDeviceId;
  String get localDeviceName => _localDeviceName;
  int get listenPort => _listenPort;
  List<PairedDevice> get devices => List.unmodifiable(_devices);
  List<FailSafeRoute> get routes => List.unmodifiable(_routes);
  List<FailSafeLogEntry> get logs => List.unmodifiable(_logs);

  static Future<FailSafeStore> loadFromDisk({String? storageFilePath}) async {
    final store = FailSafeStore(storageFilePath ?? _defaultStoragePath());
    await store._load();
    return store;
  }

  Future<void> reloadFromDisk() async {
    await _load();
    notifyListeners();
  }

  void setLocalFailSafeEnabled(bool value) {
    _localFailSafeEnabled = value;
    _persistAndNotify();
  }

  void setLocalDeviceName(String value) {
    _localDeviceName = value;
    _persistAndNotify();
  }

  void setListenPort(int value) {
    _listenPort = value;
    _persistAndNotify();
  }

  void upsertDevice(PairedDevice value) {
    final index = _devices.indexWhere((d) => d.id == value.id);
    if (index == -1) {
      _devices.add(value);
    } else {
      _devices[index] = value;
    }
    _persistAndNotify();
  }

  void removeDevice(String id) {
    _devices.removeWhere((d) => d.id == id);
    _routes.removeWhere((r) => r.targetDeviceId == id);
    _persistAndNotify();
  }

  void upsertRoute(FailSafeRoute value) {
    final index = _routes.indexWhere((r) => r.id == value.id);
    if (index == -1) {
      _routes.add(value);
    } else {
      _routes[index] = value;
    }
    _persistAndNotify();
  }

  void removeRoute(String id) {
    _routes.removeWhere((r) => r.id == id);
    _persistAndNotify();
  }

  void addLog(FailSafeLogEntry value) {
    _logs.insert(0, value);
    if (_logs.length > 150) {
      _logs.removeRange(150, _logs.length);
    }
    _persistAndNotify();
  }

  void clearLogs() {
    _logs.clear();
    _persistAndNotify();
  }

  void _persistAndNotify() {
    unawaited(_persist());
    notifyListeners();
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
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return;
    }
    _localFailSafeEnabled = decoded['localFailSafeEnabled'] as bool? ?? false;
    _localDeviceId = decoded['localDeviceId'] as String? ?? _localDeviceId;
    _localDeviceName =
        decoded['localDeviceName'] as String? ?? _localDeviceName;
    _listenPort = decoded['listenPort'] as int? ?? _listenPort;

    final devicesRaw = decoded['devices'];
    if (devicesRaw is List) {
      _devices
        ..clear()
        ..addAll(
          devicesRaw.whereType<Map>().map(
                (e) => PairedDevice.fromJson(
                    e.map((k, v) => MapEntry(k.toString(), v))),
              ),
        );
    }
    final routesRaw = decoded['routes'];
    if (routesRaw is List) {
      _routes
        ..clear()
        ..addAll(
          routesRaw.whereType<Map>().map(
                (e) => FailSafeRoute.fromJson(
                    e.map((k, v) => MapEntry(k.toString(), v))),
              ),
        );
    }
    final logsRaw = decoded['logs'];
    if (logsRaw is List) {
      _logs
        ..clear()
        ..addAll(
          logsRaw.whereType<Map>().map(
                (e) => FailSafeLogEntry.fromJson(
                    e.map((k, v) => MapEntry(k.toString(), v))),
              ),
        );
    }
  }

  Future<void> _persist() async {
    final file = File(_storageFilePath);
    await file.parent.create(recursive: true);
    final payload = jsonEncode({
      'localFailSafeEnabled': _localFailSafeEnabled,
      'localDeviceId': _localDeviceId,
      'localDeviceName': _localDeviceName,
      'listenPort': _listenPort,
      'devices': _devices.map((d) => d.toJson()).toList(),
      'routes': _routes.map((r) => r.toJson()).toList(),
      'logs': _logs.map((l) => l.toJson()).toList(),
    });
    await file.writeAsString(payload, flush: true);
  }

  static String _defaultStoragePath() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return '$appData\\nevermiss_alarm\\failsafe.v1.json';
      }
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return '$home/.nevermiss_alarm/failsafe.v1.json';
  }

  void seedLocalIdentity({
    required String id,
    required String name,
  }) {
    var changed = false;
    if (_localDeviceId.isEmpty) {
      _localDeviceId = id;
      changed = true;
    }
    if (_localDeviceName.isEmpty) {
      _localDeviceName = name;
      changed = true;
    }
    if (changed) {
      _persistAndNotify();
    }
  }

  void setLocalIdentity({
    required String id,
    required String name,
  }) {
    var changed = false;
    if (id.isNotEmpty && _localDeviceId != id) {
      _localDeviceId = id;
      changed = true;
    }
    if (name.isNotEmpty && _localDeviceName != name) {
      _localDeviceName = name;
      changed = true;
    }
    if (changed) {
      _persistAndNotify();
    }
  }
}
