import 'package:flutter_test/flutter_test.dart';
import 'package:verint_alarm_flutter/src/features/alarm/domain/alarm.dart';
import 'package:verint_alarm_flutter/src/features/alarm/domain/alarm_occurrence.dart';

void main() {
  Alarm buildAlarm({
    required Set<int> days,
    required int hour,
    required int minute,
    bool isEnabled = true,
  }) {
    return Alarm(
      id: 'a1',
      label: 'Test',
      hour: hour,
      minute: minute,
      daysOfWeek: days,
      isEnabled: isEnabled,
      ringOnce: false,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  test('returns today for one-time alarm in future', () {
    final now = DateTime(2026, 3, 3, 8, 0);
    final alarm = buildAlarm(days: {}, hour: 8, minute: 30);
    final next = computeNextOccurrence(alarm: alarm, from: now);
    expect(next, DateTime(2026, 3, 3, 8, 30));
  });

  test('returns tomorrow for one-time alarm already passed', () {
    final now = DateTime(2026, 3, 3, 8, 0);
    final alarm = buildAlarm(days: {}, hour: 7, minute: 45);
    final next = computeNextOccurrence(alarm: alarm, from: now);
    expect(next, DateTime(2026, 3, 4, 7, 45));
  });

  test('returns next valid weekday for recurring alarm', () {
    final now = DateTime(2026, 3, 3, 10, 0); // Tue
    final alarm = buildAlarm(days: {1, 3}, hour: 9, minute: 0); // Mon Wed
    final next = computeNextOccurrence(alarm: alarm, from: now);
    expect(next, DateTime(2026, 3, 4, 9, 0)); // Wed
  });

  test('returns null for disabled alarm', () {
    final now = DateTime(2026, 3, 3, 10, 0);
    final alarm =
        buildAlarm(days: {1, 2, 3}, hour: 9, minute: 0, isEnabled: false);
    final next = computeNextOccurrence(alarm: alarm, from: now);
    expect(next, isNull);
  });
}
