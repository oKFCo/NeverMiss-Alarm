import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verint_alarm_flutter/src/features/alarm/data/in_memory_alarm_repository.dart';
import 'package:verint_alarm_flutter/src/features/alarm/domain/alarm.dart';

void main() {
  test('repository persists alarms across reloads', () async {
    final tempDir = await Directory.systemTemp.createTemp('verint_alarm_test_');
    final storageFile = '${tempDir.path}${Platform.pathSeparator}alarms.json';

    final repoA =
        await InMemoryAlarmRepository.loadFromDisk(storageFilePath: storageFile);
    repoA.create(
      AlarmDraft(
        label: 'Persist me',
        hour: 9,
        minute: 45,
        daysOfWeek: {1, 3, 5},
        isEnabled: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final repoB =
        await InMemoryAlarmRepository.loadFromDisk(storageFilePath: storageFile);
    final alarms = repoB.getAll();

    expect(alarms, hasLength(1));
    expect(alarms.first.label, 'Persist me');
    expect(alarms.first.hour, 9);
    expect(alarms.first.minute, 45);

    await tempDir.delete(recursive: true);
  });
}
