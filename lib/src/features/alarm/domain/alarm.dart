import 'package:intl/intl.dart';

class Alarm {
  Alarm({
    required this.id,
    required this.label,
    required this.hour,
    required this.minute,
    required this.daysOfWeek,
    required this.isEnabled,
    required this.ringOnce,
    required this.createdAt,
    this.snoozeMinutes,
    this.scheduledAt,
  });

  final String id;
  final String label;
  final int hour;
  final int minute;
  final Set<int> daysOfWeek;
  final bool isEnabled;
  final bool ringOnce;
  final DateTime createdAt;
  final int? snoozeMinutes;
  final DateTime? scheduledAt;

  String get timeLabel {
    final now = DateTime.now();
    final value = DateTime(now.year, now.month, now.day, hour, minute);
    return DateFormat('hh:mm a').format(value);
  }

  String get daysLabel {
    if (daysOfWeek.length == 7) {
      return 'Every day';
    }
    if (daysOfWeek.isEmpty) {
      return 'One-time';
    }

    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sorted = daysOfWeek.toList()..sort();
    return sorted.map((d) => labels[d - 1]).join(' ');
  }

  Alarm copyWith({
    String? label,
    int? hour,
    int? minute,
    Set<int>? daysOfWeek,
    bool? isEnabled,
    bool? ringOnce,
    int? snoozeMinutes,
    bool clearSnoozeMinutes = false,
    DateTime? scheduledAt,
    bool clearScheduledAt = false,
  }) {
    return Alarm(
      id: id,
      label: label ?? this.label,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      isEnabled: isEnabled ?? this.isEnabled,
      ringOnce: ringOnce ?? this.ringOnce,
      createdAt: createdAt,
      snoozeMinutes: clearSnoozeMinutes ? null : (snoozeMinutes ?? this.snoozeMinutes),
      scheduledAt: clearScheduledAt ? null : (scheduledAt ?? this.scheduledAt),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'hour': hour,
      'minute': minute,
      'daysOfWeek': daysOfWeek.toList()..sort(),
      'isEnabled': isEnabled,
      'ringOnce': ringOnce,
      'createdAt': createdAt.toUtc().millisecondsSinceEpoch,
      'snoozeMinutes': snoozeMinutes,
      'scheduledAt': scheduledAt?.toUtc().millisecondsSinceEpoch,
    };
  }

  factory Alarm.fromJson(Map<String, dynamic> json) {
    return Alarm(
      id: json['id'] as String,
      label: json['label'] as String? ?? 'Alarm',
      hour: json['hour'] as int? ?? 7,
      minute: json['minute'] as int? ?? 0,
      daysOfWeek: ((json['daysOfWeek'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<int>())
          .toSet(),
      isEnabled: json['isEnabled'] as bool? ?? true,
      ringOnce: json['ringOnce'] as bool? ?? false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        isUtc: true,
      ).toLocal(),
      snoozeMinutes: json['snoozeMinutes'] as int?,
      scheduledAt: (json['scheduledAt'] as int?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              json['scheduledAt'] as int,
              isUtc: true,
            ).toLocal(),
    );
  }
}

class AlarmDraft {
  AlarmDraft({
    required this.label,
    required this.hour,
    required this.minute,
    required this.daysOfWeek,
    required this.isEnabled,
    this.ringOnce = false,
    this.snoozeMinutes,
    this.scheduledAt,
  });

  final String label;
  final int hour;
  final int minute;
  final Set<int> daysOfWeek;
  final bool isEnabled;
  final bool ringOnce;
  final int? snoozeMinutes;
  final DateTime? scheduledAt;
}
