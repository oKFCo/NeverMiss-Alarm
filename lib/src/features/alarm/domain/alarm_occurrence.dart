import 'alarm.dart';

DateTime? computeNextOccurrence({
  required Alarm alarm,
  required DateTime from,
}) {
  if (!alarm.isEnabled) {
    return null;
  }

  final scheduledAt = alarm.scheduledAt;
  if (scheduledAt != null) {
    if (scheduledAt.isAfter(from)) {
      return scheduledAt;
    }
    return null;
  }

  if (alarm.daysOfWeek.isEmpty) {
    final today = DateTime(from.year, from.month, from.day, alarm.hour, alarm.minute);
    if (today.isAfter(from)) {
      return today;
    }
    return today.add(const Duration(days: 1));
  }

  for (var offset = 0; offset <= 7; offset++) {
    final date = DateTime(from.year, from.month, from.day).add(Duration(days: offset));
    if (!alarm.daysOfWeek.contains(date.weekday)) {
      continue;
    }
    final candidate = DateTime(date.year, date.month, date.day, alarm.hour, alarm.minute);
    if (candidate.isAfter(from)) {
      return candidate;
    }
  }
  return null;
}
