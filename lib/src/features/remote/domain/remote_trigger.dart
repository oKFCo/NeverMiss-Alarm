class RemoteTrigger {
  RemoteTrigger({
    required this.eventType,
    required this.statusText,
    required this.scheduledAt,
    required this.timeoutAt,
    required this.nonce,
    required this.timestampEpochMs,
    required this.signatureHex,
  });

  final String eventType;
  final String statusText;
  final DateTime scheduledAt;
  final DateTime timeoutAt;
  final String nonce;
  final int timestampEpochMs;
  final String signatureHex;

  factory RemoteTrigger.fromPayload(Map<String, dynamic> payload) {
    final eventType = payload['event_type'] as String?;
    final statusText = payload['status_text'] as String?;
    final scheduledMs = payload['scheduled_at_ms'];
    final timeoutMs = payload['timeout_at_ms'];
    final timestampMs = payload['timestamp_ms'];
    final nonce = payload['nonce'] as String?;
    final signature = payload['signature'] as String?;

    if (eventType == null ||
        statusText == null ||
        scheduledMs is! int ||
        timeoutMs is! int ||
        timestampMs is! int ||
        nonce == null ||
        signature == null) {
      throw const FormatException('Invalid remote trigger payload.');
    }

    return RemoteTrigger(
      eventType: eventType,
      statusText: statusText,
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(scheduledMs),
      timeoutAt: DateTime.fromMillisecondsSinceEpoch(timeoutMs),
      nonce: nonce,
      timestampEpochMs: timestampMs,
      signatureHex: signature,
    );
  }
}

class TriggerVerificationResult {
  const TriggerVerificationResult({
    required this.isValid,
    this.reason,
  });

  final bool isValid;
  final String? reason;
}

abstract class RemoteTriggerVerifier {
  TriggerVerificationResult verify(RemoteTrigger trigger);
}
