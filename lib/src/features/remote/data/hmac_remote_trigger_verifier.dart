import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/remote_trigger.dart';

class HmacRemoteTriggerVerifier implements RemoteTriggerVerifier {
  HmacRemoteTriggerVerifier({
    required String sharedSecret,
    this.maxSkew = const Duration(minutes: 1),
  }) : _sharedSecret = sharedSecret;

  final String _sharedSecret;
  final Duration maxSkew;
  final Set<String> _seenNonces = <String>{};

  @override
  TriggerVerificationResult verify(RemoteTrigger trigger) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final deltaMs = (nowMs - trigger.timestampEpochMs).abs();
    if (deltaMs > maxSkew.inMilliseconds) {
      return const TriggerVerificationResult(
        isValid: false,
        reason: 'Trigger timestamp outside allowed window.',
      );
    }

    final nonceKey = '${trigger.nonce}:${trigger.timestampEpochMs}';
    if (_seenNonces.contains(nonceKey)) {
      return const TriggerVerificationResult(
        isValid: false,
        reason: 'Replay detected.',
      );
    }

    final expected = _buildSignature(trigger);
    if (expected != trigger.signatureHex.toLowerCase()) {
      return const TriggerVerificationResult(
        isValid: false,
        reason: 'Invalid signature.',
      );
    }

    _seenNonces.add(nonceKey);
    return const TriggerVerificationResult(isValid: true);
  }

  String _buildSignature(RemoteTrigger trigger) {
    final canonical = [
      trigger.eventType,
      trigger.statusText,
      trigger.scheduledAt.toUtc().millisecondsSinceEpoch.toString(),
      trigger.timeoutAt.toUtc().millisecondsSinceEpoch.toString(),
      trigger.timestampEpochMs.toString(),
      trigger.nonce,
    ].join('|');
    final bytes = utf8.encode(canonical);
    final hmac = Hmac(sha256, utf8.encode(_sharedSecret));
    return hmac.convert(bytes).toString().toLowerCase();
  }
}
