import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verint_alarm_flutter/src/features/remote/data/hmac_remote_trigger_verifier.dart';
import 'package:verint_alarm_flutter/src/features/remote/domain/remote_trigger.dart';

void main() {
  group('HmacRemoteTriggerVerifier', () {
    const secret = 'super-secret';

    test('accepts a valid trigger', () {
      final now = DateTime.now();
      final ts = now.millisecondsSinceEpoch;
      final trigger = RemoteTrigger(
        eventType: 'panic',
        statusText: 'Door forced',
        scheduledAt: now,
        timeoutAt: now.add(const Duration(minutes: 10)),
        nonce: 'abc123',
        timestampEpochMs: ts,
        signatureHex: _sign(
          secret: secret,
          eventType: 'panic',
          statusText: 'Door forced',
          scheduledAt: now,
          timeoutAt: now.add(const Duration(minutes: 10)),
          timestampEpochMs: ts,
          nonce: 'abc123',
        ),
      );

      final verifier = HmacRemoteTriggerVerifier(sharedSecret: secret);
      final result = verifier.verify(trigger);

      expect(result.isValid, isTrue);
    });

    test('rejects replayed nonce', () {
      final now = DateTime.now();
      final ts = now.millisecondsSinceEpoch;
      final signature = _sign(
        secret: secret,
        eventType: 'panic',
        statusText: 'Door forced',
        scheduledAt: now,
        timeoutAt: now.add(const Duration(minutes: 10)),
        timestampEpochMs: ts,
        nonce: 'same-nonce',
      );

      final trigger = RemoteTrigger(
        eventType: 'panic',
        statusText: 'Door forced',
        scheduledAt: now,
        timeoutAt: now.add(const Duration(minutes: 10)),
        nonce: 'same-nonce',
        timestampEpochMs: ts,
        signatureHex: signature,
      );

      final verifier = HmacRemoteTriggerVerifier(sharedSecret: secret);
      expect(verifier.verify(trigger).isValid, isTrue);
      final replay = verifier.verify(trigger);
      expect(replay.isValid, isFalse);
      expect(replay.reason, contains('Replay'));
    });
  });
}

String _sign({
  required String secret,
  required String eventType,
  required String statusText,
  required DateTime scheduledAt,
  required DateTime timeoutAt,
  required int timestampEpochMs,
  required String nonce,
}) {
  final canonical = [
    eventType,
    statusText,
    scheduledAt.toUtc().millisecondsSinceEpoch.toString(),
    timeoutAt.toUtc().millisecondsSinceEpoch.toString(),
    timestampEpochMs.toString(),
    nonce,
  ].join('|');
  return Hmac(sha256, utf8.encode(secret))
      .convert(utf8.encode(canonical))
      .toString();
}
