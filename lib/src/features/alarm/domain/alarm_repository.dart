import 'alarm.dart';

abstract class AlarmRepository {
  List<Alarm> getAll();
  Alarm create(AlarmDraft draft);
  Alarm update(Alarm alarm);
  bool delete(String alarmId);
  Alarm? findById(String alarmId);
}
