import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:verint_alarm_flutter/src/features/failsafe/data/fail_safe_store.dart';
import 'package:verint_alarm_flutter/src/features/failsafe/domain/fail_safe_models.dart';

void main() {
  test('fail-safe store persists devices/routes/enabled flag', () async {
    final tempDir = await Directory.systemTemp.createTemp('verint_failsafe_test_');
    final file = '${tempDir.path}${Platform.pathSeparator}failsafe.json';

    final storeA = await FailSafeStore.loadFromDisk(storageFilePath: file);
    storeA.setLocalFailSafeEnabled(true);
    storeA.upsertDevice(
      const PairedDevice(
        id: 'd1',
        name: 'Phone',
        platform: DevicePlatform.android,
        address: '192.168.1.2',
        port: 9851,
        sharedKeyHint: 'k1',
        lastSeenAtEpochMs: 123,
        isOnline: true,
        isTrusted: true,
        isEnabled: true,
      ),
    );
    storeA.upsertRoute(
      const FailSafeRoute(
        id: 'r1',
        sourcePlatform: DevicePlatform.windows,
        targetDeviceId: 'd1',
        isEnabled: true,
        triggerOnTimeout: true,
        retryCount: 2,
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));

    final storeB = await FailSafeStore.loadFromDisk(storageFilePath: file);
    expect(storeB.localFailSafeEnabled, isTrue);
    expect(storeB.devices, hasLength(1));
    expect(storeB.routes, hasLength(1));
    expect(storeB.routes.first.retryCount, 2);

    await tempDir.delete(recursive: true);
  });
}
