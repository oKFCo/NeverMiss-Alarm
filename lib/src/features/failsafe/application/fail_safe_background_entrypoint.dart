import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/app_paths.dart';
import '../data/fail_safe_store.dart';
import '../domain/fail_safe_models.dart';
import 'fail_safe_controller.dart';
import 'fail_safe_transport.dart';

const _backgroundChannel = MethodChannel('verint_alarm/failsafe_background');
const _androidChannel = MethodChannel('verint_alarm/android_alarm');

@pragma('vm:entry-point')
Future<void> backgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  try {
    final basePath = await resolveAppStorageBasePath();
    final sep = Platform.pathSeparator;
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
    failSafeController.setIncomingAlertHandler(
      (sourceName, alarmLabel, reason) async {
        if (!Platform.isAndroid) {
          return;
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        final id =
            'failsafe_incoming_${reason.name}_${now}_${sourceName.hashCode}';
        await _androidChannel.invokeMethod<void>(
          'startNow',
          <String, dynamic>{
            'alarm': <String, dynamic>{
              'id': id,
              'label': '[Fail-safe] $alarmLabel',
              'hour': 0,
              'minute': 0,
              'daysOfWeek': const <int>[],
              'scheduledAtEpochMs': now,
              'snoozeMinutes': 5,
              'isEnabled': true,
            },
          },
        );
      },
    );
    await failSafeController.initializeBackground();
    await _setBackgroundSocketState(true);
  } catch (_) {
    await _setBackgroundSocketState(false);
    rethrow;
  }

  _startBestEffortHeartbeat();
  await Completer<void>().future;
}

void _startBestEffortHeartbeat() {
  Timer.periodic(const Duration(seconds: 10), (_) async {
    try {
      await _backgroundChannel.invokeMethod<void>('heartbeat');
      await _setBackgroundSocketState(true);
    } catch (_) {
      // Keep heartbeats best-effort while native side is being rolled out.
    }
  });
}

Future<void> _setBackgroundSocketState(bool ownsSockets) async {
  try {
    await _androidChannel.invokeMethod<void>(
      'setFailSafeBackgroundSocketState',
      <String, dynamic>{'ownsSockets': ownsSockets},
    );
  } catch (_) {
    // Best-effort debug state reporting.
  }
}
