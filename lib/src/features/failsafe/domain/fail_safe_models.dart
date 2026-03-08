enum DevicePlatform {
  windows,
  android,
}

enum FailSafeReason {
  alarmTimeout,
  alarmFailure,
  manualTest,
}

class PairedDevice {
  const PairedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.address,
    required this.port,
    required this.sharedKeyHint,
    required this.lastSeenAtEpochMs,
    required this.isOnline,
    required this.isTrusted,
    required this.isEnabled,
  });

  final String id;
  final String name;
  final DevicePlatform platform;
  final String address;
  final int port;
  final String sharedKeyHint;
  final int lastSeenAtEpochMs;
  final bool isOnline;
  final bool isTrusted;
  final bool isEnabled;

  PairedDevice copyWith({
    String? name,
    DevicePlatform? platform,
    String? address,
    int? port,
    String? sharedKeyHint,
    int? lastSeenAtEpochMs,
    bool? isOnline,
    bool? isTrusted,
    bool? isEnabled,
  }) {
    return PairedDevice(
      id: id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      address: address ?? this.address,
      port: port ?? this.port,
      sharedKeyHint: sharedKeyHint ?? this.sharedKeyHint,
      lastSeenAtEpochMs: lastSeenAtEpochMs ?? this.lastSeenAtEpochMs,
      isOnline: isOnline ?? this.isOnline,
      isTrusted: isTrusted ?? this.isTrusted,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'platform': platform.name,
      'address': address,
      'port': port,
      'sharedKeyHint': sharedKeyHint,
      'lastSeenAtEpochMs': lastSeenAtEpochMs,
      'isOnline': isOnline,
      'isTrusted': isTrusted,
      'isEnabled': isEnabled,
    };
  }

  factory PairedDevice.fromJson(Map<String, dynamic> json) {
    final platformName = json['platform'] as String? ?? DevicePlatform.android.name;
    return PairedDevice(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Device',
      platform: DevicePlatform.values.firstWhere(
        (v) => v.name == platformName,
        orElse: () => DevicePlatform.android,
      ),
      address: json['address'] as String? ?? '',
      port: json['port'] as int? ?? 9851,
      sharedKeyHint: json['sharedKeyHint'] as String? ?? '',
      lastSeenAtEpochMs: json['lastSeenAtEpochMs'] as int? ?? 0,
      isOnline: json['isOnline'] as bool? ?? false,
      isTrusted: json['isTrusted'] as bool? ?? false,
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }
}

class FailSafeRoute {
  const FailSafeRoute({
    required this.id,
    required this.sourcePlatform,
    required this.targetDeviceId,
    required this.isEnabled,
    required this.triggerOnTimeout,
    required this.retryCount,
  });

  final String id;
  final DevicePlatform sourcePlatform;
  final String targetDeviceId;
  final bool isEnabled;
  final bool triggerOnTimeout;
  final int retryCount;

  FailSafeRoute copyWith({
    String? targetDeviceId,
    bool? isEnabled,
    bool? triggerOnTimeout,
    int? retryCount,
  }) {
    return FailSafeRoute(
      id: id,
      sourcePlatform: sourcePlatform,
      targetDeviceId: targetDeviceId ?? this.targetDeviceId,
      isEnabled: isEnabled ?? this.isEnabled,
      triggerOnTimeout: triggerOnTimeout ?? this.triggerOnTimeout,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourcePlatform': sourcePlatform.name,
      'targetDeviceId': targetDeviceId,
      'isEnabled': isEnabled,
      'triggerOnTimeout': triggerOnTimeout,
      'retryCount': retryCount,
    };
  }

  factory FailSafeRoute.fromJson(Map<String, dynamic> json) {
    final sourceName = json['sourcePlatform'] as String? ?? DevicePlatform.windows.name;
    return FailSafeRoute(
      id: json['id'] as String,
      sourcePlatform: DevicePlatform.values.firstWhere(
        (v) => v.name == sourceName,
        orElse: () => DevicePlatform.windows,
      ),
      targetDeviceId: json['targetDeviceId'] as String,
      isEnabled: json['isEnabled'] as bool? ?? true,
      triggerOnTimeout: json['triggerOnTimeout'] as bool? ?? true,
      retryCount: json['retryCount'] as int? ?? 1,
    );
  }
}

class FailSafeLogEntry {
  const FailSafeLogEntry({
    required this.id,
    required this.createdAtEpochMs,
    required this.message,
    required this.level,
  });

  final String id;
  final int createdAtEpochMs;
  final String message;
  final String level;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAtEpochMs': createdAtEpochMs,
      'message': message,
      'level': level,
    };
  }

  factory FailSafeLogEntry.fromJson(Map<String, dynamic> json) {
    return FailSafeLogEntry(
      id: json['id'] as String,
      createdAtEpochMs: json['createdAtEpochMs'] as int? ?? 0,
      message: json['message'] as String? ?? '',
      level: json['level'] as String? ?? 'info',
    );
  }
}
