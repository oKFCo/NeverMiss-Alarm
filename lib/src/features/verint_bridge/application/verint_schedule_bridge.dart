import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../alarm/data/in_memory_alarm_repository.dart';
import '../../alarm/domain/alarm.dart';

class VerintScheduleBridge extends ChangeNotifier {
  VerintScheduleBridge({
    required InMemoryAlarmRepository repository,
    this.port = 38941,
  }) : _repository = repository;

  final InMemoryAlarmRepository _repository;
  final int port;

  HttpServer? _server;
  bool _isRunning = false;
  String _status = 'Stopped';
  DateTime? _lastImportAt;
  int _lastImportedCount = 0;

  bool get isRunning => _isRunning;
  String get status => _status;
  DateTime? get lastImportAt => _lastImportAt;
  int get lastImportedCount => _lastImportedCount;
  String get endpoint => 'http://127.0.0.1:$port/verint/schedule';

  Future<void> start() async {
    if (!Platform.isWindows || _isRunning) {
      return;
    }
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      _server!.listen(_handleRequest);
      _isRunning = true;
      _status = 'Listening on $endpoint';
      notifyListeners();
    } catch (error) {
      _status = 'Failed to start bridge: $error';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _isRunning = false;
    if (server != null) {
      await server.close(force: true);
    }
    _status = 'Stopped';
    notifyListeners();
  }

  @override
  void dispose() {
    final server = _server;
    _server = null;
    _isRunning = false;
    if (server != null) {
      unawaited(server.close(force: true));
    }
    super.dispose();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method == 'OPTIONS') {
        _setCors(request.response);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }

      if (request.method != 'POST' || request.uri.path != '/verint/schedule') {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not found');
        await request.response.close();
        return;
      }

      _setCors(request.response);
      final body = await utf8.decoder.bind(request).join();
      final parsed = jsonDecode(body);
      final drafts = _parseDrafts(parsed);
      _applyDrafts(drafts);

      _lastImportAt = DateTime.now();
      _lastImportedCount = drafts.length;
      _status =
          'Imported ${drafts.length} alarms at ${_lastImportAt!.toLocal()}';
      notifyListeners();

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'ok': true,
          'imported': drafts.length,
        }),
      );
      await request.response.close();
    } catch (error) {
      _status = 'Import error: $error';
      notifyListeners();
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'ok': false,
          'error': error.toString(),
        }),
      );
      await request.response.close();
    }
  }

  void _setCors(HttpResponse response) {
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type');
  }

  List<AlarmDraft> _parseDrafts(dynamic payload) {
    final items = switch (payload) {
      {'alarms': final List alarms} => alarms,
      List values => values,
      _ => throw const FormatException(
          'Expected {"alarms":[...]} or [...] payload.'),
    };

    if (items.isEmpty) {
      throw const FormatException('No alarms provided.');
    }

    final drafts = <AlarmDraft>[];
    for (final item in items) {
      if (item is! Map) {
        continue;
      }
      final map = item.map((key, value) => MapEntry(key.toString(), value));
      final label =
          (map['label'] as String? ?? map['name'] as String? ?? 'Shift').trim();
      final hour = _intField(map, const ['hour', 'h']);
      final minute = _intField(map, const ['minute', 'm']);
      final days = _daysField(map);
      final enabled = map['enabled'] is bool ? map['enabled'] as bool : true;
      final snooze =
          _optionalIntField(map, const ['snooze_minutes', 'snoozeMinutes']);
      final durationMinutes = _durationMinutesField(map);
      final scheduledAt = _scheduledAtField(map, hour: hour, minute: minute);
      final resolvedHour = hour ?? scheduledAt?.hour;
      final resolvedMinute = minute ?? scheduledAt?.minute;

      if (resolvedHour == null || resolvedMinute == null) {
        continue;
      }
      if (scheduledAt != null && !scheduledAt.isAfter(DateTime.now())) {
        continue;
      }
      final safeLabel = label.isEmpty ? 'Shift' : label;
      drafts.add(
        AlarmDraft(
          label: '[Verint] $safeLabel',
          hour: resolvedHour.clamp(0, 23),
          minute: resolvedMinute.clamp(0, 59),
          daysOfWeek: scheduledAt != null ? const <int>{} : days,
          isEnabled: enabled,
          ringOnce: true,
          snoozeMinutes: snooze?.clamp(1, 60),
          scheduledAt: scheduledAt,
        ),
      );

      final endHour =
          _intField(map, const ['end_hour', 'endHour', 'hour_end', 'end_h']);
      final endMinute = _intField(
          map, const ['end_minute', 'endMinute', 'minute_end', 'end_m']);
      final endScheduledAt = _scheduledAtField(
        map,
        hour: endHour,
        minute: endMinute,
        epochKeys: const [
          'end_scheduled_at_ms',
          'endScheduledAtEpochMs',
          'end_date_ms',
        ],
        dateKeys: const ['end_date', 'endDate'],
      );
      final resolvedEndHour = endHour ?? endScheduledAt?.hour;
      final resolvedEndMinute = endMinute ?? endScheduledAt?.minute;
      final computedEnd = _computeEndFromDuration(
        startScheduledAt: scheduledAt,
        startHour: resolvedHour,
        startMinute: resolvedMinute,
        durationMinutes: durationMinutes,
      );
      final finalEndScheduledAt = endScheduledAt ?? computedEnd?.scheduledAt;
      final finalEndHour = resolvedEndHour ?? computedEnd?.hour;
      final finalEndMinute = resolvedEndMinute ?? computedEnd?.minute;
      final isDuplicateEnd = finalEndHour == resolvedHour &&
          finalEndMinute == resolvedMinute &&
          ((finalEndScheduledAt == null && scheduledAt == null) ||
              (finalEndScheduledAt?.millisecondsSinceEpoch ==
                  scheduledAt?.millisecondsSinceEpoch));

      if (finalEndHour != null &&
          finalEndMinute != null &&
          !isDuplicateEnd &&
          (finalEndScheduledAt == null ||
              finalEndScheduledAt.isAfter(DateTime.now()))) {
        drafts.add(
          AlarmDraft(
            label: '[Verint] $safeLabel (End shift)',
            hour: finalEndHour.clamp(0, 23),
            minute: finalEndMinute.clamp(0, 59),
            daysOfWeek: finalEndScheduledAt != null ? const <int>{} : days,
            isEnabled: enabled,
            ringOnce: true,
            snoozeMinutes: snooze?.clamp(1, 60),
            scheduledAt: finalEndScheduledAt,
          ),
        );
      }
    }

    if (drafts.isEmpty) {
      throw const FormatException('No valid alarm entries found.');
    }
    return drafts;
  }

  int? _intField(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is int) {
        return value;
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  int? _optionalIntField(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) {
        continue;
      }
      if (value is int) {
        return value;
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  int? _durationMinutesField(Map<String, dynamic> map) {
    final direct = _optionalIntField(
      map,
      const [
        'duration_minutes',
        'durationMinutes',
        'duration_mins',
        'durationMins',
      ],
    );
    if (direct != null) {
      return direct <= 0 ? null : direct;
    }

    final text = map['duration'] as String?;
    if (text == null) {
      return null;
    }
    final parsed = _parseDurationText(text);
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  int? _parseDurationText(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) {
      return null;
    }

    final hm = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value);
    if (hm != null) {
      final h = int.tryParse(hm.group(1)!);
      final m = int.tryParse(hm.group(2)!);
      if (h != null && m != null) {
        return h * 60 + m;
      }
    }

    final hoursAndMinutes = RegExp(
      r'^(\d+)\s*h(?:ours?)?\s*(\d+)?\s*m?(?:in(?:ute)?s?)?$',
    ).firstMatch(value);
    if (hoursAndMinutes != null) {
      final h = int.tryParse(hoursAndMinutes.group(1)!);
      final mRaw = hoursAndMinutes.group(2);
      final m = mRaw == null ? 0 : int.tryParse(mRaw);
      if (h != null && m != null) {
        return h * 60 + m;
      }
    }

    final mins = RegExp(r'^(\d+)\s*m(?:in(?:ute)?s?)?$').firstMatch(value);
    if (mins != null) {
      return int.tryParse(mins.group(1)!);
    }

    return null;
  }

  Set<int> _daysField(Map<String, dynamic> map) {
    final value = map['days_of_week'] ?? map['daysOfWeek'] ?? map['days'];
    if (value is List) {
      return value
          .map((v) => v is int ? v : int.tryParse(v.toString()))
          .whereType<int>()
          .where((d) => d >= 1 && d <= 7)
          .toSet();
    }
    return <int>{};
  }

  DateTime? _scheduledAtField(
    Map<String, dynamic> map, {
    required int? hour,
    required int? minute,
    List<String> epochKeys = const [
      'scheduled_at_ms',
      'scheduledAtEpochMs',
      'date_ms'
    ],
    List<String> dateKeys = const ['date'],
  }) {
    for (final key in epochKeys) {
      final epoch = map[key];
      if (epoch is int) {
        return DateTime.fromMillisecondsSinceEpoch(epoch);
      }
      if (epoch is String) {
        final parsed = int.tryParse(epoch);
        if (parsed != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsed);
        }
      }
    }

    for (final key in dateKeys) {
      final dateString = map[key] as String?;
      if (dateString != null && hour != null && minute != null) {
        final parsed = DateTime.tryParse(dateString);
        if (parsed != null) {
          return DateTime(parsed.year, parsed.month, parsed.day, hour, minute);
        }
      }
    }
    return null;
  }

  _ComputedEnd? _computeEndFromDuration({
    required DateTime? startScheduledAt,
    required int? startHour,
    required int? startMinute,
    required int? durationMinutes,
  }) {
    if (durationMinutes == null || durationMinutes <= 0) {
      return null;
    }
    if (startScheduledAt != null) {
      final value = startScheduledAt.add(Duration(minutes: durationMinutes));
      return _ComputedEnd(
        hour: value.hour,
        minute: value.minute,
        scheduledAt: value,
      );
    }
    if (startHour == null || startMinute == null) {
      return null;
    }
    final base = DateTime(2000, 1, 1, startHour, startMinute);
    final value = base.add(Duration(minutes: durationMinutes));
    return _ComputedEnd(
      hour: value.hour,
      minute: value.minute,
      scheduledAt: null,
    );
  }

  void _applyDrafts(List<AlarmDraft> drafts) {
    final existing = _repository.getAll();
    for (final alarm in existing) {
      if (alarm.label.startsWith('[Verint] ')) {
        _repository.delete(alarm.id);
      }
    }
    for (final draft in drafts) {
      _repository.create(draft);
    }
  }
}

class _ComputedEnd {
  const _ComputedEnd({
    required this.hour,
    required this.minute,
    required this.scheduledAt,
  });

  final int hour;
  final int minute;
  final DateTime? scheduledAt;
}
