import '../../alarm/domain/alarm.dart';
import '../../alarm/domain/alarm_repository.dart';
import '../../alarm/domain/alarm_scheduler.dart';
import '../domain/remote_trigger.dart';

class RemoteTriggerHandler {
  RemoteTriggerHandler({
    required AlarmRepository repository,
    required AlarmScheduler scheduler,
    required RemoteTriggerVerifier verifier,
  })  : _repository = repository,
        _scheduler = scheduler,
        _verifier = verifier;

  final AlarmRepository _repository;
  final AlarmScheduler _scheduler;
  final RemoteTriggerVerifier _verifier;

  Future<TriggerVerificationResult> tryHandle(RemoteTrigger trigger) async {
    final verification = _verifier.verify(trigger);
    if (!verification.isValid) {
      return verification;
    }

    final local = _repository.create(
      AlarmDraft(
        label: '[Remote] ${trigger.statusText}',
        hour: trigger.scheduledAt.hour,
        minute: trigger.scheduledAt.minute,
        daysOfWeek: const <int>{},
        isEnabled: true,
        ringOnce: false,
        scheduledAt: trigger.scheduledAt,
      ),
    );

    await _scheduler.schedule(local);
    return verification;
  }
}
