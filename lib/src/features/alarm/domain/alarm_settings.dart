import 'alarm_tone.dart';

class AlarmSettings {
  const AlarmSettings({
    required this.snoozeMinutes,
    required this.ringTimeoutMinutes,
    required this.use24HourFormat,
    required this.useDarkMode,
    required this.alarmToneId,
    required this.minimizeToTrayOnClose,
    required this.showCloseBehaviorPrompt,
    this.alarmOutputDeviceId,
  });

  static const defaults = AlarmSettings(
    snoozeMinutes: 5,
    ringTimeoutMinutes: 10,
    use24HourFormat: false,
    useDarkMode: true,
    alarmToneId: alarmToneMarimba,
    minimizeToTrayOnClose: true,
    showCloseBehaviorPrompt: true,
  );

  final int snoozeMinutes;
  final int ringTimeoutMinutes;
  final bool use24HourFormat;
  final bool useDarkMode;
  final String alarmToneId;
  final bool minimizeToTrayOnClose;
  final bool showCloseBehaviorPrompt;
  final String? alarmOutputDeviceId;

  AlarmSettings copyWith({
    int? snoozeMinutes,
    int? ringTimeoutMinutes,
    bool? use24HourFormat,
    bool? useDarkMode,
    String? alarmToneId,
    bool? minimizeToTrayOnClose,
    bool? showCloseBehaviorPrompt,
    String? alarmOutputDeviceId,
    bool clearAlarmOutputDeviceId = false,
  }) {
    return AlarmSettings(
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      ringTimeoutMinutes: ringTimeoutMinutes ?? this.ringTimeoutMinutes,
      use24HourFormat: use24HourFormat ?? this.use24HourFormat,
      useDarkMode: useDarkMode ?? this.useDarkMode,
      alarmToneId: normalizeAlarmToneId(alarmToneId ?? this.alarmToneId),
      minimizeToTrayOnClose:
          minimizeToTrayOnClose ?? this.minimizeToTrayOnClose,
      showCloseBehaviorPrompt:
          showCloseBehaviorPrompt ?? this.showCloseBehaviorPrompt,
      alarmOutputDeviceId: clearAlarmOutputDeviceId
          ? null
          : (alarmOutputDeviceId ?? this.alarmOutputDeviceId),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'snoozeMinutes': snoozeMinutes,
      'ringTimeoutMinutes': ringTimeoutMinutes,
      'use24HourFormat': use24HourFormat,
      'useDarkMode': useDarkMode,
      'alarmToneId': alarmToneId,
      'minimizeToTrayOnClose': minimizeToTrayOnClose,
      'showCloseBehaviorPrompt': showCloseBehaviorPrompt,
      'alarmOutputDeviceId': alarmOutputDeviceId,
    };
  }

  factory AlarmSettings.fromJson(Map<String, dynamic> json) {
    return AlarmSettings(
      snoozeMinutes: json['snoozeMinutes'] as int? ?? 5,
      ringTimeoutMinutes: json['ringTimeoutMinutes'] as int? ?? 10,
      use24HourFormat: json['use24HourFormat'] as bool? ?? false,
      useDarkMode: json['useDarkMode'] as bool? ?? true,
      alarmToneId: normalizeAlarmToneId(json['alarmToneId'] as String?),
      minimizeToTrayOnClose: json['minimizeToTrayOnClose'] as bool? ?? true,
      showCloseBehaviorPrompt: json['showCloseBehaviorPrompt'] as bool? ?? true,
      alarmOutputDeviceId: json['alarmOutputDeviceId'] as String?,
    );
  }
}
