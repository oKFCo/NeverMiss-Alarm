import '../data/in_memory_alarm_repository.dart';
import '../domain/alarm_scheduler.dart';

class AlarmSchedulerSync {
  AlarmSchedulerSync({
    required InMemoryAlarmRepository repository,
    required AlarmScheduler scheduler,
  })  : _repository = repository,
        _scheduler = scheduler;

  final InMemoryAlarmRepository _repository;
  final AlarmScheduler _scheduler;
  bool _started = false;
  bool _syncing = false;
  bool _needsSync = false;
  Set<String> _knownIds = <String>{};

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _repository.addListener(_onRepositoryChange);
    _onRepositoryChange();
  }

  void dispose() {
    _repository.removeListener(_onRepositoryChange);
  }

  Future<void> requestPermissions() {
    return _scheduler.requestPermissions();
  }

  Future<void> syncNow() {
    return _onRepositoryChange();
  }

  Future<void> _onRepositoryChange() async {
    if (_syncing) {
      _needsSync = true;
      return;
    }
    _syncing = true;
    do {
      _needsSync = false;
      final alarms = _repository.getAll();
      final currentIds = alarms.map((a) => a.id).toSet();

      for (final removedId in _knownIds.difference(currentIds)) {
        await _scheduler.cancel(removedId);
      }
      for (final alarm in alarms) {
        await _scheduler.schedule(alarm);
      }
      _knownIds = currentIds;
    } while (_needsSync);
    _syncing = false;
  }
}
