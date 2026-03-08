import 'alarm.dart';

abstract class AlarmScheduler {
  Future<void> initialize();
  Future<void> schedule(Alarm alarm);
  Future<void> cancel(String alarmId);
  Future<void> cancelAll();
  Future<void> requestPermissions();
}

class LocalAlarmScheduler implements AlarmScheduler {
  const LocalAlarmScheduler();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> schedule(Alarm alarm) async {
    // Platform-specific scheduling will be implemented for Android/Windows.
  }

  @override
  Future<void> cancel(String alarmId) async {
    // Platform-specific cancellation will be implemented for Android/Windows.
  }

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> requestPermissions() async {}
}
