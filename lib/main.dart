import 'dart:io';

import 'package:flutter/material.dart';

import 'src/core/app_paths.dart';
import 'src/app.dart';
import 'src/features/failsafe/application/fail_safe_background_entrypoint.dart'
    as failsafe_background;
import 'src/features/alarm/data/alarm_attention_controller_factory.dart';
import 'src/features/alarm/data/alarm_scheduler_factory.dart';
import 'src/features/alarm/data/alarm_settings_store.dart';
import 'src/features/alarm/data/in_memory_alarm_repository.dart';
import 'src/features/failsafe/application/fail_safe_controller.dart';
import 'src/features/failsafe/application/fail_safe_transport.dart';
import 'src/features/failsafe/data/fail_safe_store.dart';
import 'src/features/failsafe/domain/fail_safe_models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final launchTriggerAlarmId = _parseLaunchAlarmId();
  final basePath = await resolveAppStorageBasePath();
  final sep = Platform.pathSeparator;
  final repository = await InMemoryAlarmRepository.loadFromDisk(
    storageFilePath: '$basePath${sep}alarms.v1.json',
  );
  final settingsStore = await AlarmSettingsStore.loadFromDisk(
    storageFilePath: '$basePath${sep}settings.v1.json',
  );
  final scheduler = await createAlarmScheduler();
  final attentionController =
      await createAlarmAttentionController(settingsStore);
  final failSafeStore = await FailSafeStore.loadFromDisk(
    storageFilePath: '$basePath${sep}failsafe.v1.json',
  );
  final localPlatform =
      Platform.isWindows ? DevicePlatform.windows : DevicePlatform.android;
  final failSafeController = FailSafeController(
    store: failSafeStore,
    localTransport: LocalLanFailSafeTransport(),
    localPlatform: localPlatform,
  );
  try {
    await failSafeController.initializeUi();
  } catch (error, stackTrace) {
    stderr.writeln('Fail-safe initialization failed: $error');
    stderr.writeln(stackTrace);
  }
  runApp(
    NeverMissAlarmApp(
      repository: repository,
      settingsStore: settingsStore,
      scheduler: scheduler,
      attentionController: attentionController,
      failSafeController: failSafeController,
      launchTriggerAlarmId: launchTriggerAlarmId,
    ),
  );
}

@pragma('vm:entry-point')
Future<void> backgroundMain() async {
  await failsafe_background.backgroundMain();
}

String? _parseLaunchAlarmId() {
  for (final arg in Platform.executableArguments) {
    const key = '--trigger-alarm-id=';
    if (arg.startsWith(key)) {
      final value = arg.substring(key.length).trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
  }
  return null;
}
