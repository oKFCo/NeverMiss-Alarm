class AlarmToneOption {
  const AlarmToneOption({
    required this.id,
    required this.label,
    required this.assetPath,
  });

  final String id;
  final String label;
  final String assetPath;
}

const String alarmToneMarimba = 'marimba';
const String alarmToneFreshMorning = 'fresh_morning';
const String alarmTonePixelAlarm = 'pixel_alarm';
const String alarmToneNeverMiss = 'never_miss';
const String alarmToneSystemDefault = 'system_default';

const List<AlarmToneOption> alarmToneOptions = <AlarmToneOption>[
  AlarmToneOption(
    id: alarmToneMarimba,
    label: 'Marimba',
    assetPath: 'assets/sounds/marimba.mp3',
  ),
  AlarmToneOption(
    id: alarmToneFreshMorning,
    label: 'Fresh Morning',
    assetPath: 'assets/sounds/fresh_morning.mp3',
  ),
  AlarmToneOption(
    id: alarmTonePixelAlarm,
    label: 'Pixel Alarm',
    assetPath: 'assets/sounds/pixel_alarm.mp3',
  ),
  AlarmToneOption(
    id: alarmToneNeverMiss,
    label: 'Never Miss',
    assetPath: 'assets/sounds/alarm_loop.wav',
  ),
];

String normalizeAlarmToneId(String? toneId) {
  if (toneId == null) {
    return alarmToneMarimba;
  }
  if (toneId == alarmToneSystemDefault) {
    return alarmToneSystemDefault;
  }
  for (final option in alarmToneOptions) {
    if (option.id == toneId) {
      return toneId;
    }
  }
  return alarmToneMarimba;
}

AlarmToneOption alarmToneById(String? toneId) {
  final normalized = normalizeAlarmToneId(toneId);
  if (normalized == alarmToneSystemDefault) {
    return alarmToneOptions.firstWhere((tone) => tone.id == alarmToneMarimba);
  }
  return alarmToneOptions.firstWhere((tone) => tone.id == normalized);
}
