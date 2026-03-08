import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../alarm/domain/alarm.dart';
import '../data/fail_safe_store.dart';
import '../domain/fail_safe_models.dart';
import 'fail_safe_transport.dart';
import 'local_lan_fail_safe_node.dart';

class FailSafeController extends ChangeNotifier {
  FailSafeController({
    required FailSafeStore store,
    required FailSafeTransport localTransport,
    required DevicePlatform localPlatform,
  })  : _store = store,
        _localTransport = localTransport,
        _localPlatform = localPlatform {
    _store.seedLocalIdentity(
      id: _buildLocalDeviceId(localPlatform),
      name: _defaultLocalDeviceName(localPlatform),
    );
    _store.addListener(notifyListeners);
  }

  final FailSafeStore _store;
  final FailSafeTransport _localTransport;
  final DevicePlatform _localPlatform;
  static const MethodChannel _androidChannel =
      MethodChannel('verint_alarm/android_alarm');
  static const MethodChannel _identityChannel =
      MethodChannel('verint_alarm/android_alarm');
  LocalLanFailSafeNode? _lanNode;
  Future<void> Function(
          String sourceName, String alarmLabel, FailSafeReason reason)?
      _incomingAlertHandler;
  int _idSequence = 0;
  bool _androidKeepAliveEnabled = false;
  bool _androidIgnoringBatteryOptimizations = false;
  Map<String, dynamic> _androidFailSafeDebugState = <String, dynamic>{};
  bool _uiOwnsSockets = false;
  Timer? _backgroundStoreSyncTimer;

  bool get localFailSafeEnabled => _store.localFailSafeEnabled;
  List<PairedDevice> get devices => _store.devices;
  List<FailSafeRoute> get routes => _store.routes;
  List<FailSafeLogEntry> get logs => _store.logs;
  DevicePlatform get localPlatform => _localPlatform;
  String get localDeviceName => _store.localDeviceName;
  String get localDeviceId => _store.localDeviceId;
  int get listenPort => _store.listenPort;
  bool get androidKeepAliveEnabled => _androidKeepAliveEnabled;
  bool get androidIgnoringBatteryOptimizations =>
      _androidIgnoringBatteryOptimizations;
  Map<String, dynamic> get androidFailSafeDebugState =>
      Map<String, dynamic>.unmodifiable(_androidFailSafeDebugState);

  @override
  void dispose() {
    _backgroundStoreSyncTimer?.cancel();
    _lanNode?.stop();
    _store.removeListener(notifyListeners);
    super.dispose();
  }

  Future<void> initializeUi() async {
    await _ensureLocalIdentity();
    if (Platform.isAndroid && localFailSafeEnabled) {
      try {
        await _androidChannel.invokeMethod<void>('startFailSafeKeepAliveNow');
      } catch (_) {
        // Fall back to sync path below if direct start is unavailable.
      }
    }
    await refreshAndroidPowerState();
    if (Platform.isAndroid &&
        (localFailSafeEnabled || _androidKeepAliveEnabled)) {
      await _syncAndroidKeepAlive(true);
    }
    await _reconcileUiLanNodeOwnership();
  }

  Future<void> initializeBackground() async {
    await _ensureLocalIdentity();
    await _ensureLanNodeStarted();
  }

  Future<void> initialize() async {
    await initializeUi();
  }

  Future<void> _ensureLanNodeStarted() async {
    if (_lanNode != null) {
      return;
    }
    _lanNode = LocalLanFailSafeNode(
      localDeviceId: localDeviceId,
      localDeviceName: localDeviceName,
      localPlatform: localPlatform,
      listenPort: listenPort,
      resolveSharedKeyForSourceDevice: ({
        required sourceDeviceId,
        sourceDeviceName,
        sourceAddress,
        sourcePlatform,
      }) {
        final byId = _findDevice(sourceDeviceId);
        if (byId != null && byId.sharedKeyHint.trim().isNotEmpty) {
          return byId.sharedKeyHint;
        }
        final platform = DevicePlatform.values.firstWhere(
          (v) => v.name == sourcePlatform,
          orElse: () => DevicePlatform.android,
        );
        final byEndpoint = sourceAddress == null
            ? null
            : _findDeviceByAddressAndPlatform(
                address: sourceAddress,
                platform: platform,
              );
        if (byEndpoint != null && byEndpoint.sharedKeyHint.trim().isNotEmpty) {
          if (byEndpoint.id != sourceDeviceId) {
            _migrateDeviceId(
              previousId: byEndpoint.id,
              replacement: PairedDevice(
                id: sourceDeviceId,
                name: sourceDeviceName ?? byEndpoint.name,
                platform: platform,
                address: byEndpoint.address,
                port: byEndpoint.port,
                sharedKeyHint: byEndpoint.sharedKeyHint,
                lastSeenAtEpochMs: DateTime.now().millisecondsSinceEpoch,
                isOnline: true,
                isTrusted: byEndpoint.isTrusted,
                isEnabled: byEndpoint.isEnabled,
              ),
            );
          }
          return byEndpoint.sharedKeyHint;
        }
        return null;
      },
      onIncomingAlert: (alert) async {
        _log(
          'warn',
          '[incoming ${alert.reason.name}] ${alert.sourceDeviceName} -> "${alert.alarmLabel}"',
        );
        final handler = _incomingAlertHandler;
        if (handler != null) {
          await handler(alert.sourceDeviceName, alert.alarmLabel, alert.reason);
        }
      },
      onPeerDiscovered: (device) {
        final existing = _findDevice(device.id) ??
            _findDeviceByEndpoint(
              address: device.address,
              port: device.port,
              platform: device.platform,
            );
        if (existing == null) {
          _store.upsertDevice(device);
        } else {
          if (existing.id != device.id) {
            _migrateDeviceId(
              previousId: existing.id,
              replacement: device.copyWith(
                sharedKeyHint: existing.sharedKeyHint,
                isTrusted: existing.isTrusted,
                isEnabled: existing.isEnabled,
                isOnline: true,
                lastSeenAtEpochMs: DateTime.now().millisecondsSinceEpoch,
              ),
            );
          } else {
            _store.upsertDevice(
              existing.copyWith(
                name: device.name,
                platform: device.platform,
                address: device.address,
                port: device.port,
                isOnline: true,
                lastSeenAtEpochMs: DateTime.now().millisecondsSinceEpoch,
              ),
            );
          }
        }
      },
      onLog: _log,
    );
    await _lanNode?.start();
    _uiOwnsSockets = true;
    await _reportUiSocketState();
  }

  Future<void> _stopLanNode() async {
    final node = _lanNode;
    if (node == null) {
      return;
    }
    await node.stop();
    _lanNode = null;
    _uiOwnsSockets = false;
    await _reportUiSocketState();
  }

  Future<void> _reconcileUiLanNodeOwnership() async {
    final shouldOwnLanNode = !Platform.isAndroid || !_androidKeepAliveEnabled;
    if (shouldOwnLanNode) {
      await _ensureLanNodeStarted();
      _stopBackgroundStoreSync();
      return;
    }
    await _stopLanNode();
    _startBackgroundStoreSync();
    _log(
      'info',
      'Android keep-alive background runtime is active; UI isolate released fail-safe sockets.',
    );
  }

  void setIncomingAlertHandler(
    Future<void> Function(
            String sourceName, String alarmLabel, FailSafeReason reason)
        handler,
  ) {
    _incomingAlertHandler = handler;
  }

  void setLocalFailSafeEnabled(bool value) {
    _store.setLocalFailSafeEnabled(value);
    _log('info', 'Local fail-safe ${value ? 'enabled' : 'disabled'}.');
    unawaited(_syncAndroidKeepAlive(value));
    unawaited(_notifyAndroidFailSafeConfigChanged());
  }

  Future<void> refreshAndroidPowerState() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final map = await _androidChannel
          .invokeMapMethod<String, dynamic>('getFailSafeKeepAliveState');
      if (map == null) {
        return;
      }
      _androidKeepAliveEnabled = map['enabled'] as bool? ?? false;
      _androidIgnoringBatteryOptimizations =
          map['ignoringBatteryOptimizations'] as bool? ?? false;
      notifyListeners();
      await refreshFailSafeDebugState();
    } catch (error) {
      _log('error', 'Failed to read Android power state: $error');
    }
  }

  Future<void> refreshFailSafeDebugState() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final map = await _androidChannel
          .invokeMapMethod<String, dynamic>('getFailSafeDebugState');
      if (map == null) {
        return;
      }
      _androidFailSafeDebugState = Map<String, dynamic>.from(map);
      notifyListeners();
    } catch (error) {
      _log('error', 'Failed to read fail-safe debug state: $error');
    }
  }

  Future<void> requestAndroidBatteryExemption() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _androidChannel
          .invokeMethod<void>('requestIgnoreBatteryOptimizations');
      await refreshAndroidPowerState();
    } catch (error) {
      _log('error', 'Failed to request battery optimization exemption: $error');
    }
  }

  void addDevice({
    required String deviceId,
    required String name,
    required DevicePlatform platform,
    required String address,
    required int port,
    String sharedKeyHint = '',
    bool isTrusted = true,
  }) {
    final normalizedDeviceId = deviceId.trim();
    if (normalizedDeviceId.isEmpty) {
      _log('error', 'Cannot pair device without a stable device identifier.');
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = _findDevice(normalizedDeviceId) ??
        _findDeviceByEndpoint(
          address: address,
          port: port,
          platform: platform,
        );
    if (existing != null) {
      _store.upsertDevice(
        existing.copyWith(
          name: name,
          platform: platform,
          address: address,
          port: port,
          sharedKeyHint: sharedKeyHint,
          isTrusted: isTrusted || sharedKeyHint.trim().isNotEmpty,
          isOnline: true,
          isEnabled: true,
          lastSeenAtEpochMs: now,
        ),
      );
      _log('info',
          'Updated device "${existing.name}" (${existing.platform.name}).');
      unawaited(_notifyAndroidFailSafeConfigChanged());
      return;
    }

    final device = PairedDevice(
      id: normalizedDeviceId,
      name: name,
      platform: platform,
      address: address,
      port: port,
      sharedKeyHint: sharedKeyHint,
      lastSeenAtEpochMs: now,
      isOnline: true,
      isTrusted: isTrusted,
      isEnabled: true,
    );
    _store.upsertDevice(device);
    _log('info', 'Paired device "${device.name}" (${device.platform.name}).');
    unawaited(_notifyAndroidFailSafeConfigChanged());
  }

  void removeDevice(String deviceId) {
    _store.removeDevice(deviceId);
    _log('warn', 'Removed paired device.');
    unawaited(_notifyAndroidFailSafeConfigChanged());
  }

  void toggleDeviceEnabled(String deviceId, bool enabled) {
    final device = _findDevice(deviceId);
    if (device == null) {
      return;
    }
    _store.upsertDevice(device.copyWith(isEnabled: enabled));
    unawaited(_notifyAndroidFailSafeConfigChanged());
  }

  void setDeviceSharedKey(String deviceId, String sharedKey) {
    final device = _findDevice(deviceId);
    if (device == null) {
      return;
    }
    final trimmed = sharedKey.trim();
    _store.upsertDevice(
      device.copyWith(
        sharedKeyHint: trimmed,
        isTrusted: trimmed.isNotEmpty,
      ),
    );
    unawaited(_notifyAndroidFailSafeConfigChanged());
  }

  void addRoute({
    required String targetDeviceId,
  }) {
    _store.upsertRoute(
      FailSafeRoute(
        id: _newId('route'),
        sourcePlatform: localPlatform,
        targetDeviceId: targetDeviceId,
        isEnabled: true,
        triggerOnTimeout: true,
        retryCount: 1,
      ),
    );
    _log('info', 'Added route ${localPlatform.name} -> device.');
    unawaited(_notifyAndroidFailSafeConfigChanged());
  }

  bool isDeviceFailSafeTarget(String deviceId) {
    return routes.any((r) => r.targetDeviceId == deviceId && r.isEnabled);
  }

  void setDeviceFailSafeTarget(String deviceId, bool enabled) {
    final existing = routes.where((r) => r.targetDeviceId == deviceId).toList();
    if (enabled) {
      if (existing.isEmpty) {
        addRoute(targetDeviceId: deviceId);
        return;
      }
      for (final route in existing) {
        _store.upsertRoute(
            route.copyWith(isEnabled: true, triggerOnTimeout: true));
      }
      unawaited(_notifyAndroidFailSafeConfigChanged());
      return;
    }
    for (final route in existing) {
      _store.upsertRoute(route.copyWith(isEnabled: false));
    }
    unawaited(_notifyAndroidFailSafeConfigChanged());
  }

  Future<void> sendManualTestToDevice(String deviceId) async {
    final route = routes.firstWhere(
      (r) => r.targetDeviceId == deviceId,
      orElse: () => FailSafeRoute(
        id: _newId('route'),
        sourcePlatform: localPlatform,
        targetDeviceId: deviceId,
        isEnabled: true,
        triggerOnTimeout: true,
        retryCount: 1,
      ),
    );
    await _dispatchForRoute(
      route: route,
      reason: FailSafeReason.manualTest,
      alarmId: 'manual-test',
      alarmLabel: 'Manual test alert',
    );
  }

  void updateRoute(FailSafeRoute route) {
    _store.upsertRoute(route);
    unawaited(_notifyAndroidFailSafeConfigChanged());
  }

  void removeRoute(String routeId) {
    _store.removeRoute(routeId);
    unawaited(_notifyAndroidFailSafeConfigChanged());
  }

  Future<void> sendManualTest(String routeId) async {
    final route = _findRoute(routeId);
    if (route == null) {
      return;
    }
    await _dispatchForRoute(
      route: route,
      reason: FailSafeReason.manualTest,
      alarmId: 'manual-test',
      alarmLabel: 'Manual test alert',
    );
  }

  Future<void> handleAlarmTimeout(Alarm alarm) async {
    if (!localFailSafeEnabled) {
      return;
    }
    final candidateRoutes = routes.where(
      (r) =>
          r.sourcePlatform == localPlatform &&
          r.isEnabled &&
          r.triggerOnTimeout,
    );
    if (candidateRoutes.isEmpty) {
      _log('warn', 'Fail-safe timeout fired but no enabled route exists.');
      return;
    }
    for (final route in candidateRoutes) {
      await _dispatchForRoute(
        route: route,
        reason: FailSafeReason.alarmTimeout,
        alarmId: alarm.id,
        alarmLabel: alarm.label,
      );
    }
  }

  void clearLogs() {
    _store.clearLogs();
  }

  void discoverMockDevice() {
    final isWindowsLocal = localPlatform == DevicePlatform.windows;
    addDevice(
      deviceId: _newId('mock_device'),
      name: isWindowsLocal
          ? 'Android Phone (mock)'
          : 'Windows Workstation (mock)',
      platform:
          isWindowsLocal ? DevicePlatform.android : DevicePlatform.windows,
      address: isWindowsLocal ? '192.168.1.25' : '192.168.1.10',
      port: 9851,
      sharedKeyHint: 'local-pair',
    );
  }

  Future<void> discoverOnLan() async {
    if (_lanNode != null) {
      await _lanNode?.discoverPeers();
      _log('info', 'LAN discovery broadcast completed.');
      return;
    }
    if (Platform.isAndroid && _androidKeepAliveEnabled) {
      await _discoverPeersViaEphemeralSocket();
      _log('info', 'LAN discovery broadcast completed via UI fallback socket.');
      return;
    }
    _log('warn', 'LAN discovery skipped: no active discovery socket owner.');
  }

  Future<void> refreshDeviceStatus() async {
    if (_lanNode != null) {
      await _lanNode?.discoverPeers(
          timeout: const Duration(milliseconds: 1200));
    } else if (Platform.isAndroid && _androidKeepAliveEnabled) {
      await _discoverPeersViaEphemeralSocket(
        timeout: const Duration(milliseconds: 1200),
      );
    }
    for (final device in devices) {
      final online = await _pingDevice(device);
      _store.upsertDevice(
        device.copyWith(
          isOnline: online,
          lastSeenAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
  }

  Future<bool> _pingDevice(PairedDevice device) async {
    final client = HttpClient();
    try {
      final uri =
          Uri.parse('http://${device.address}:${device.port}/failsafe/ping');
      final response = await (await client.getUrl(uri)).close();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _dispatchForRoute({
    required FailSafeRoute route,
    required FailSafeReason reason,
    required String alarmId,
    required String alarmLabel,
  }) async {
    final initialTarget = await _resolveCurrentTarget(route.targetDeviceId);
    if (initialTarget == null) {
      _log('error', 'Route target missing for route ${route.id}.');
      return;
    }
    var target = initialTarget;

    FailSafeDispatchResult result = const FailSafeDispatchResult(
      success: false,
      message: 'No dispatch attempts.',
    );
    final attempts = route.retryCount < 1 ? 1 : route.retryCount;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      target = await _resolveCurrentTarget(route.targetDeviceId) ?? target;
      result = await _localTransport.dispatch(
        FailSafeDispatchRequest(
          target: target,
          reason: reason,
          alarmId: alarmId,
          alarmLabel: alarmLabel,
          sourceDeviceId: localDeviceId,
          sourceDeviceName: localDeviceName,
          sourcePlatform: localPlatform,
        ),
      );
      if (result.success) {
        break;
      }
      if (attempt < attempts) {
        await _lanNode?.discoverPeers(
            timeout: const Duration(milliseconds: 1200));
      }
    }

    _log(
      result.success ? 'info' : 'error',
      '[${reason.name}] ${target.name}: ${result.message}',
    );
  }

  void _log(String level, String message) {
    _store.addLog(
      FailSafeLogEntry(
        id: _newId('log'),
        createdAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        message: message,
        level: level,
      ),
    );
  }

  String _newId(String prefix) {
    _idSequence += 1;
    return '${prefix}_${DateTime.now().millisecondsSinceEpoch}_$_idSequence';
  }

  PairedDevice? _findDevice(String id) {
    for (final item in devices) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  PairedDevice? _findDeviceByEndpoint({
    required String address,
    required int port,
    required DevicePlatform platform,
  }) {
    final normalizedAddress = address.trim();
    for (final item in devices) {
      if (item.address.trim() == normalizedAddress &&
          item.port == port &&
          item.platform == platform) {
        return item;
      }
    }
    return null;
  }

  PairedDevice? _findDeviceByAddressAndPlatform({
    required String address,
    required DevicePlatform platform,
  }) {
    final normalizedAddress = address.trim();
    for (final item in devices) {
      if (item.address.trim() == normalizedAddress &&
          item.platform == platform) {
        return item;
      }
    }
    return null;
  }

  FailSafeRoute? _findRoute(String id) {
    for (final item in routes) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  static String _buildLocalDeviceId(DevicePlatform platform) {
    final r = Random.secure().nextInt(1 << 24);
    return '${platform.name}_${DateTime.now().millisecondsSinceEpoch}_$r';
  }

  static String _defaultLocalDeviceName(DevicePlatform platform) {
    final host = Platform.localHostname;
    return '$host (${platform.name})';
  }

  Future<void> _ensureLocalIdentity() async {
    final preferredId = await _resolvePreferredDeviceId();
    if (preferredId == null) {
      return;
    }
    final currentId = _store.localDeviceId.trim();
    final isLegacyGenerated = currentId.startsWith('${_localPlatform.name}_');
    if (currentId.isEmpty || isLegacyGenerated) {
      _store.setLocalIdentity(
        id: preferredId,
        name: _store.localDeviceName.isEmpty
            ? _defaultLocalDeviceName(_localPlatform)
            : _store.localDeviceName,
      );
      _log('info', 'Using OS-based local device identifier.');
    }
  }

  Future<String?> _resolvePreferredDeviceId() async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      return null;
    }
    try {
      final raw =
          await _identityChannel.invokeMethod<String>('getDeviceIdentifier');
      final trimmed = raw?.trim() ?? '';
      if (trimmed.isEmpty) {
        return null;
      }
      if (trimmed.contains(':')) {
        return trimmed;
      }
      return '${_localPlatform.name}:$trimmed';
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncAndroidKeepAlive(bool enabled) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _androidChannel.invokeMethod<void>(
        'setFailSafeKeepAliveEnabled',
        <String, dynamic>{'enabled': enabled},
      );
      if (enabled) {
        await _androidChannel
            .invokeMethod<void>('requestIgnoreBatteryOptimizations');
      }
      await refreshAndroidPowerState();
      await _reconcileUiLanNodeOwnership();
    } catch (error) {
      _log('error', 'Failed to sync Android keep-alive: $error');
    }
  }

  Future<void> _reportUiSocketState() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _androidChannel.invokeMethod<void>(
        'setFailSafeUiSocketState',
        <String, dynamic>{'ownsSockets': _uiOwnsSockets},
      );
      await refreshFailSafeDebugState();
    } catch (_) {
      // Best-effort debug state reporting.
    }
  }

  Future<void> _notifyAndroidFailSafeConfigChanged() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _androidChannel.invokeMethod<void>('notifyFailSafeConfigChanged');
    } catch (_) {
      // Best-effort background runtime reload signal.
    }
  }

  void _startBackgroundStoreSync() {
    if (!Platform.isAndroid || _uiOwnsSockets) {
      return;
    }
    if (_backgroundStoreSyncTimer != null) {
      return;
    }
    _backgroundStoreSyncTimer =
        Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        await _store.reloadFromDisk();
      } catch (_) {
        // Keep background log/device sync best-effort.
      }
    });
  }

  void _stopBackgroundStoreSync() {
    _backgroundStoreSyncTimer?.cancel();
    _backgroundStoreSyncTimer = null;
  }

  Future<PairedDevice?> _resolveCurrentTarget(String deviceId) async {
    var target = _findDevice(deviceId);
    if (target == null) {
      return null;
    }

    if (await _pingDevice(target)) {
      return _findDevice(deviceId) ?? target;
    }

    if (_lanNode != null) {
      await _lanNode?.discoverPeers(
          timeout: const Duration(milliseconds: 1200));
    } else if (Platform.isAndroid && _androidKeepAliveEnabled) {
      await _discoverPeersViaEphemeralSocket(
        timeout: const Duration(milliseconds: 1200),
      );
    }
    target = _findDevice(deviceId) ?? target;
    await _pingDevice(target);
    return _findDevice(deviceId) ?? target;
  }

  Future<void> _discoverPeersViaEphemeralSocket({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      );
      socket.broadcastEnabled = true;
      final payload = jsonEncode({
        'type': 'discover',
        'deviceId': localDeviceId,
        'name': localDeviceName,
        'platform': localPlatform.name,
        'port': listenPort,
        'timestampMs': DateTime.now().millisecondsSinceEpoch,
      });
      final bytes = utf8.encode(payload);
      final targets = await _buildDiscoveryTargets();
      for (final target in targets) {
        socket.send(bytes, target, LocalLanFailSafeNode.discoveryPort);
      }

      final completer = Completer<void>();
      late final StreamSubscription<RawSocketEvent> sub;
      sub = socket.listen((event) {
        if (event != RawSocketEvent.read) {
          return;
        }
        final dg = socket?.receive();
        if (dg == null) {
          return;
        }
        final text = utf8.decode(dg.data, allowMalformed: true);
        try {
          final decoded = jsonDecode(text);
          if (decoded is! Map) {
            return;
          }
          final payload = decoded.map((k, v) => MapEntry(k.toString(), v));
          if (payload['type'] != 'hello') {
            return;
          }
          final deviceId = payload['deviceId'] as String?;
          if (deviceId == null || deviceId == localDeviceId) {
            return;
          }
          final name = payload['name'] as String? ?? 'Device';
          final platformName =
              payload['platform'] as String? ?? DevicePlatform.android.name;
          final port = payload['port'] as int? ?? 9851;
          final platform = DevicePlatform.values.firstWhere(
            (v) => v.name == platformName,
            orElse: () => DevicePlatform.android,
          );
          final now = DateTime.now().millisecondsSinceEpoch;
          final existing = _findDevice(deviceId) ??
              _findDeviceByEndpoint(
                address: dg.address.address,
                port: port,
                platform: platform,
              );
          if (existing == null) {
            _store.upsertDevice(
              PairedDevice(
                id: deviceId,
                name: name,
                platform: platform,
                address: dg.address.address,
                port: port,
                sharedKeyHint: '',
                lastSeenAtEpochMs: now,
                isOnline: true,
                isTrusted: false,
                isEnabled: true,
              ),
            );
          } else if (existing.id != deviceId) {
            _migrateDeviceId(
              previousId: existing.id,
              replacement: PairedDevice(
                id: deviceId,
                name: name,
                platform: platform,
                address: dg.address.address,
                port: port,
                sharedKeyHint: existing.sharedKeyHint,
                isOnline: true,
                lastSeenAtEpochMs: now,
                isTrusted: existing.isTrusted,
                isEnabled: existing.isEnabled,
              ),
            );
          } else {
            _store.upsertDevice(
              existing.copyWith(
                name: name,
                platform: platform,
                address: dg.address.address,
                port: port,
                isOnline: true,
                lastSeenAtEpochMs: now,
              ),
            );
          }
        } catch (_) {
          return;
        }
      });

      unawaited(
        Future<void>.delayed(timeout).then((_) {
          if (!completer.isCompleted) {
            completer.complete();
          }
        }),
      );
      await completer.future;
      await sub.cancel();
    } finally {
      socket?.close();
    }
  }

  Future<Set<InternetAddress>> _buildDiscoveryTargets() async {
    final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length != 4) {
            continue;
          }
          final o0 = int.tryParse(parts[0]);
          final o1 = int.tryParse(parts[1]);
          final o2 = int.tryParse(parts[2]);
          if (o0 == null || o1 == null || o2 == null) {
            continue;
          }
          targets.add(InternetAddress('$o0.$o1.$o2.255'));
        }
      }
    } catch (_) {}
    return targets;
  }

  void _migrateDeviceId({
    required String previousId,
    required PairedDevice replacement,
  }) {
    final oldDevice = _findDevice(previousId);
    if (oldDevice == null) {
      _store.upsertDevice(replacement);
      return;
    }

    for (final route in routes.where((r) => r.targetDeviceId == previousId)) {
      _store.upsertRoute(route.copyWith(targetDeviceId: replacement.id));
    }
    _store.removeDevice(previousId);
    _store.upsertDevice(replacement);
    _log('info', 'Updated device identity for "${replacement.name}".');
  }
}
