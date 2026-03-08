import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verint_alarm_flutter/src/features/alarm/data/alarm_settings_store.dart';
import 'package:verint_alarm_flutter/src/features/alarm/domain/alarm_settings.dart';

void main() {
  test('settings persist across reloads', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('verint_alarm_settings_test_');
    final storageFile = '${tempDir.path}${Platform.pathSeparator}settings.json';

    final storeA =
        await AlarmSettingsStore.loadFromDisk(storageFilePath: storageFile);
    storeA.update(
      const AlarmSettings(
        snoozeMinutes: 7,
        ringTimeoutMinutes: 12,
        use24HourFormat: true,
        useDarkMode: false,
        alarmToneId: 'fresh_morning',
        minimizeToTrayOnClose: false,
        showCloseBehaviorPrompt: false,
        alarmOutputDeviceId: 'device-123',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final storeB =
        await AlarmSettingsStore.loadFromDisk(storageFilePath: storageFile);
    expect(storeB.settings.snoozeMinutes, 7);
    expect(storeB.settings.ringTimeoutMinutes, 12);
    expect(storeB.settings.use24HourFormat, isTrue);
    expect(storeB.settings.useDarkMode, isFalse);
    expect(storeB.settings.alarmToneId, 'fresh_morning');
    expect(storeB.settings.minimizeToTrayOnClose, isFalse);
    expect(storeB.settings.showCloseBehaviorPrompt, isFalse);
    expect(storeB.settings.alarmOutputDeviceId, 'device-123');

    await tempDir.delete(recursive: true);
  });
}
