import 'dart:convert';

import 'package:crypto/crypto.dart';

class FailSafeProtocol {
  static String sign({
    required String sharedKey,
    required String sourceDeviceId,
    required String targetDeviceId,
    required String reason,
    required String alarmId,
    required String alarmLabel,
    required int timestampMs,
    required String nonce,
  }) {
    final canonical = [
      sourceDeviceId,
      targetDeviceId,
      reason,
      alarmId,
      alarmLabel,
      timestampMs.toString(),
      nonce,
    ].join('|');
    return Hmac(sha256, utf8.encode(sharedKey)).convert(utf8.encode(canonical)).toString();
  }

  static bool verify({
    required String sharedKey,
    required String sourceDeviceId,
    required String targetDeviceId,
    required String reason,
    required String alarmId,
    required String alarmLabel,
    required int timestampMs,
    required String nonce,
    required String providedSignature,
  }) {
    final expected = sign(
      sharedKey: sharedKey,
      sourceDeviceId: sourceDeviceId,
      targetDeviceId: targetDeviceId,
      reason: reason,
      alarmId: alarmId,
      alarmLabel: alarmLabel,
      timestampMs: timestampMs,
      nonce: nonce,
    );
    return expected.toLowerCase() == providedSignature.toLowerCase();
  }
}
