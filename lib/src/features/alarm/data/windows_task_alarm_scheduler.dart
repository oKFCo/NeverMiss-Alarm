import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../domain/alarm.dart';
import '../domain/alarm_occurrence.dart';
import '../domain/alarm_scheduler.dart';

class WindowsTaskAlarmScheduler implements AlarmScheduler {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> schedule(Alarm alarm) async {
    if (!Platform.isWindows) {
      return;
    }
    await cancel(alarm.id);
    if (!alarm.isEnabled) {
      return;
    }

    if (alarm.daysOfWeek.isEmpty) {
      final next = computeNextOccurrence(alarm: alarm, from: DateTime.now());
      if (next == null) {
        return;
      }
      await _createOneTimeTask(
        alarmId: alarm.id,
        when: next,
      );
      return;
    }

    final days = alarm.daysOfWeek.toList()..sort();
    await _createWeeklyTask(
      alarmId: alarm.id,
      weekdays: days,
      hour: alarm.hour,
      minute: alarm.minute,
    );
  }

  @override
  Future<void> cancel(String alarmId) async {
    if (!Platform.isWindows) {
      return;
    }
    for (var slot = 0; slot <= 7; slot++) {
      final taskName = _taskName(alarmId, slot);
      await _runSchtasks(
        ['/Delete', '/TN', taskName, '/F'],
        ignoreFailure: true,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!Platform.isWindows) {
      return;
    }
    // We only delete tasks created by this app prefix.
    final query = await Process.run('schtasks', ['/Query', '/FO', 'LIST', '/V']);
    if (query.exitCode != 0) {
      return;
    }
    final lines = (query.stdout as String).split(RegExp(r'\r?\n'));
    for (final line in lines) {
      if (!line.startsWith('TaskName:')) {
        continue;
      }
      final taskName = line.replaceFirst('TaskName:', '').trim();
      if (!taskName.contains('VerintAlarm_')) {
        continue;
      }
      await _runSchtasks(
        ['/Delete', '/TN', taskName, '/F'],
        ignoreFailure: true,
      );
    }
  }

  Future<void> _createWeeklyTask({
    required String alarmId,
    required List<int> weekdays,
    required int hour,
    required int minute,
  }) async {
    final dayMap = <int, String>{
      1: 'MON',
      2: 'TUE',
      3: 'WED',
      4: 'THU',
      5: 'FRI',
      6: 'SAT',
      7: 'SUN',
    };
    final daysArg = weekdays.map((d) => dayMap[d]).whereType<String>().join(',');
    if (daysArg.isEmpty) {
      return;
    }

    final timeArg = DateFormat('HH:mm').format(
      DateTime(2000, 1, 1, hour, minute),
    );
    final taskName = _taskName(alarmId, 7);
    final command = _buildLaunchCommand(alarmId);

    await _runSchtasks(
      [
        '/Create',
        '/TN',
        taskName,
        '/SC',
        'WEEKLY',
        '/D',
        daysArg,
        '/ST',
        timeArg,
        '/TR',
        command,
        '/F',
      ],
    );
  }

  Future<void> _createOneTimeTask({
    required String alarmId,
    required DateTime when,
  }) async {
    final taskName = _taskName(alarmId, 0);
    final dateArg = DateFormat('MM/dd/yyyy').format(when);
    final timeArg = DateFormat('HH:mm').format(when);
    final command = _buildLaunchCommand(alarmId);

    await _runSchtasks(
      [
        '/Create',
        '/TN',
        taskName,
        '/SC',
        'ONCE',
        '/SD',
        dateArg,
        '/ST',
        timeArg,
        '/TR',
        command,
        '/F',
      ],
    );
  }

  Future<void> _runSchtasks(
    List<String> args, {
    bool ignoreFailure = false,
  }) async {
    final result = await Process.run('schtasks', args);
    if (result.exitCode == 0 || ignoreFailure) {
      return;
    }
    debugPrint('schtasks failed: ${result.stderr}');
  }

  String _taskName(String alarmId, int slot) {
    final safe = alarmId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    return 'VerintAlarm_${safe}_$slot';
  }

  String _buildLaunchCommand(String alarmId) {
    final executable = Platform.resolvedExecutable;
    return '"$executable" --trigger-alarm-id=$alarmId';
  }
}
