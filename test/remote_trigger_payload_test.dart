import 'package:flutter_test/flutter_test.dart';
import 'package:verint_alarm_flutter/src/features/remote/domain/remote_trigger.dart';

void main() {
  test('RemoteTrigger.fromPayload parses valid payload', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final trigger = RemoteTrigger.fromPayload({
      'event_type': 'panic',
      'status_text': 'Door forced',
      'scheduled_at_ms': now,
      'timeout_at_ms': now + 60000,
      'timestamp_ms': now,
      'nonce': 'nonce-1',
      'signature': 'abc123',
    });

    expect(trigger.eventType, 'panic');
    expect(trigger.statusText, 'Door forced');
    expect(trigger.signatureHex, 'abc123');
  });

  test('RemoteTrigger.fromPayload throws on invalid payload', () {
    expect(
      () => RemoteTrigger.fromPayload({
        'event_type': 'panic',
      }),
      throwsFormatException,
    );
  });
}
