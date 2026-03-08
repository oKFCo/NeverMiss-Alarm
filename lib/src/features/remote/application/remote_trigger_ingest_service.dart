import '../domain/remote_trigger.dart';
import 'remote_trigger_handler.dart';

class RemoteTriggerIngestService {
  const RemoteTriggerIngestService({
    required RemoteTriggerHandler handler,
  }) : _handler = handler;

  final RemoteTriggerHandler _handler;

  Future<TriggerVerificationResult> ingest(Map<String, dynamic> payload) async {
    final trigger = RemoteTrigger.fromPayload(payload);
    return _handler.tryHandle(trigger);
  }
}
