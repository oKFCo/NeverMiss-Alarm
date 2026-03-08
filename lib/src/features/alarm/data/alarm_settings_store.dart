import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/alarm_settings.dart';

class AlarmSettingsStore extends ChangeNotifier {
  AlarmSettingsStore(this._storageFilePath);

  final String _storageFilePath;
  AlarmSettings _settings = AlarmSettings.defaults;

  AlarmSettings get settings => _settings;

  static Future<AlarmSettingsStore> loadFromDisk({
    String? storageFilePath,
  }) async {
    final store = AlarmSettingsStore(storageFilePath ?? _defaultStoragePath());
    await store._load();
    return store;
  }

  void update(AlarmSettings value) {
    _settings = value;
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
    _settings = AlarmSettings.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<void> _persist() async {
    final file = File(_storageFilePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_settings.toJson()), flush: true);
  }

  static String _defaultStoragePath() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return '$appData\\nevermiss_alarm\\settings.v1.json';
      }
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return '$home/.nevermiss_alarm/settings.v1.json';
  }
}
