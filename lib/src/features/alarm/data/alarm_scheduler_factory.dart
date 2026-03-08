import 'dart:io';

import '../domain/alarm_scheduler.dart';
import 'android_notification_alarm_scheduler.dart';
import 'windows_task_alarm_scheduler.dart';

Future<AlarmScheduler> createAlarmScheduler() async {
  final scheduler = Platform.isAndroid
      ? AndroidNotificationAlarmScheduler()
      : Platform.isWindows
          ? WindowsTaskAlarmScheduler()
          : const LocalAlarmScheduler();
  await scheduler.initialize();
  return scheduler;
}
