import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../domain/fail_safe_models.dart';
import 'fail_safe_protocol.dart';

class IncomingFailSafeAlert {
  const IncomingFailSafeAlert({
    required this.sourceDeviceId,
    required this.sourceDeviceName,
    required this.reason,
    required this.alarmId,
    required this.alarmLabel,
  });

  final String sourceDeviceId;
  final String sourceDeviceName;
  final FailSafeReason reason;
  final String alarmId;
  final String alarmLabel;
}

class LocalLanFailSafeNode {
  LocalLanFailSafeNode({
    required this.localDeviceId,
    required this.localDeviceName,
    required this.localPlatform,
    required this.listenPort,
    required this.resolveSharedKeyForSourceDevice,
    required this.onIncomingAlert,
    required this.onPeerDiscovered,
    required this.onLog,
  });

  final String localDeviceId;
  final String localDeviceName;
  final DevicePlatform localPlatform;
  final int listenPort;
  final String? Function({
    required String sourceDeviceId,
    String? sourceDeviceName,
    String? sourceAddress,
    String? sourcePlatform,
  }) resolveSharedKeyForSourceDevice;
  final Future<void> Function(IncomingFailSafeAlert alert) onIncomingAlert;
  final void Function(PairedDevice device) onPeerDiscovered;
  final void Function(String level, String message) onLog;

  static const int discoveryPort = 9852;
  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  final Set<String> _seenNonces = <String>{};
  bool _running = false;

  Future<void> start() async {
    if (_running) {
      return;
    }
    _running = true;
    await _startHttpServer();
    await _startDiscoverySocket();
  }

  Future<void> stop() async {
    _running = false;
    await _server?.close(force: true);
    _server = null;
    _discoverySocket?.close();
    _discoverySocket = null;
  }

  Future<void> discoverPeers({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final socket = _discoverySocket;
    if (socket == null) {
      return;
    }
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
      try {
        socket.send(bytes, target, discoveryPort);
      } catch (error) {
        onLog(
            'warn', 'LAN discovery send failed for ${target.address}: $error');
      }
    }
    onLog(
        'info', 'LAN discovery sent to ${targets.length} broadcast target(s).');
    await Future<void>.delayed(timeout);
  }

  Future<void> _startHttpServer() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, listenPort);
    unawaited(() async {
      await for (final request in _server!) {
        if (request.method == 'GET' && request.uri.path == '/failsafe/ping') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'deviceId': localDeviceId,
            'name': localDeviceName,
            'platform': localPlatform.name,
            'port': listenPort,
          }));
          await request.response.close();
          continue;
        }

        if (request.method == 'POST' &&
            request.uri.path == '/failsafe/trigger') {
          await _handleTriggerRequest(request);
          continue;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    }());
    onLog('info', 'Fail-safe receiver listening on :$listenPort');
  }

  Future<void> _startDiscoverySocket() async {
    _discoverySocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
      reusePort: Platform.isLinux || Platform.isMacOS,
    );
    _discoverySocket!
      ..broadcastEnabled = true
      ..listen((event) {
        if (event != RawSocketEvent.read) {
          return;
        }
        // Drain all queued packets. Windows can queue multiple datagrams per
        // readiness notification, and reading only once drops peer replies.
        while (true) {
          final dg = _discoverySocket?.receive();
          if (dg == null) {
            break;
          }
          _handleDiscoveryDatagram(dg);
        }
      });
    onLog('info', 'LAN discovery socket listening on UDP :$discoveryPort');
  }

  Future<void> _handleTriggerRequest(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body);
      if (json is! Map) {
        throw const FormatException('Invalid JSON');
      }
      final payload = json.map((k, v) => MapEntry(k.toString(), v));
      final sourceDeviceId = payload['sourceDeviceId'] as String?;
      final sourceDeviceName = payload['sourceDeviceName'] as String?;
      final sourcePlatform = payload['sourcePlatform'] as String?;
      final targetDeviceId = payload['targetDeviceId'] as String?;
      final reasonName = payload['reason'] as String?;
      final alarmId = payload['alarmId'] as String?;
      final alarmLabel = payload['alarmLabel'] as String?;
      final timestampMs = payload['timestampMs'];
      final nonce = payload['nonce'] as String?;
      final signature = payload['signature'] as String?;

      if (sourceDeviceId == null ||
          sourceDeviceName == null ||
          targetDeviceId == null ||
          reasonName == null ||
          alarmId == null ||
          alarmLabel == null ||
          timestampMs is! int ||
          nonce == null ||
          signature == null) {
        throw const FormatException('Missing required fields');
      }
      if (targetDeviceId != localDeviceId) {
        throw const FormatException('Wrong target device');
      }
      final skewMs =
          (DateTime.now().millisecondsSinceEpoch - timestampMs).abs();
      if (skewMs > const Duration(minutes: 2).inMilliseconds) {
        throw const FormatException('Timestamp skew');
      }
      final nonceKey = '$sourceDeviceId:$nonce:$timestampMs';
      if (_seenNonces.contains(nonceKey)) {
        throw const FormatException('Replay');
      }
      _seenNonces.add(nonceKey);
      if (_seenNonces.length > 1000) {
        _seenNonces.remove(_seenNonces.first);
      }
      final sourceAddress = request.connectionInfo?.remoteAddress.address;
      final sharedKey = resolveSharedKeyForSourceDevice(
        sourceDeviceId: sourceDeviceId,
        sourceDeviceName: sourceDeviceName,
        sourceAddress: sourceAddress,
        sourcePlatform: sourcePlatform,
      );
      if (sharedKey == null || sharedKey.isEmpty) {
        throw const FormatException('Unknown source key');
      }
      final ok = FailSafeProtocol.verify(
        sharedKey: sharedKey,
        sourceDeviceId: sourceDeviceId,
        targetDeviceId: targetDeviceId,
        reason: reasonName,
        alarmId: alarmId,
        alarmLabel: alarmLabel,
        timestampMs: timestampMs,
        nonce: nonce,
        providedSignature: signature,
      );
      if (!ok) {
        throw const FormatException('Invalid signature');
      }

      final reason = FailSafeReason.values.firstWhere(
        (v) => v.name == reasonName,
        orElse: () => FailSafeReason.alarmFailure,
      );
      await onIncomingAlert(
        IncomingFailSafeAlert(
          sourceDeviceId: sourceDeviceId,
          sourceDeviceName: sourceDeviceName,
          reason: reason,
          alarmId: alarmId,
          alarmLabel: alarmLabel,
        ),
      );

      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'ok': true}));
      await request.response.close();
    } catch (e) {
      onLog('warn', 'Incoming fail-safe trigger rejected: $e');
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({'ok': false, 'error': e.toString()}));
      await request.response.close();
    }
  }

  void _handleDiscoveryDatagram(Datagram dg) {
    final text = utf8.decode(dg.data, allowMalformed: true);
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return;
      }
      payload = decoded.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return;
    }
    final type = payload['type'] as String?;
    if (type == null) {
      return;
    }

    if (type == 'discover') {
      final deviceId = payload['deviceId'] as String?;
      if (deviceId == null || deviceId == localDeviceId) {
        return;
      }
      _recordDiscoveredPeer(payload, dg.address);
      final response = jsonEncode({
        'type': 'hello',
        'deviceId': localDeviceId,
        'name': localDeviceName,
        'platform': localPlatform.name,
        'port': listenPort,
      });
      _discoverySocket?.send(utf8.encode(response), dg.address, dg.port);
      return;
    }

    if (type == 'hello') {
      _recordDiscoveredPeer(payload, dg.address);
    }
  }

  void _recordDiscoveredPeer(
    Map<String, dynamic> payload,
    InternetAddress senderAddress,
  ) {
    final deviceId = payload['deviceId'] as String?;
    if (deviceId == null || deviceId == localDeviceId) {
      return;
    }
    final name = payload['name'] as String? ?? 'Device';
    final platformName =
        payload['platform'] as String? ?? DevicePlatform.android.name;
    final port = _readPort(payload['port']) ?? 9851;
    final platform = DevicePlatform.values.firstWhere(
      (v) => v.name == platformName,
      orElse: () => DevicePlatform.android,
    );
    onPeerDiscovered(
      PairedDevice(
        id: deviceId,
        name: name,
        platform: platform,
        address: senderAddress.address,
        port: port,
        sharedKeyHint: '',
        lastSeenAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        isOnline: true,
        isTrusted: false,
        isEnabled: true,
      ),
    );
  }

  int? _readPort(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw.trim());
    }
    return null;
  }

  static String createNonce() {
    final r = Random.secure();
    return '${DateTime.now().millisecondsSinceEpoch}${r.nextInt(1 << 32)}';
  }

  Future<Set<InternetAddress>> _buildDiscoveryTargets() async {
    final targets = <InternetAddress>{
      InternetAddress('255.255.255.255'),
    };
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

          if (o0 == 10) {
            targets.add(InternetAddress('10.255.255.255'));
          } else if (o0 == 172 && o1 >= 16 && o1 <= 31) {
            targets.add(InternetAddress('172.$o1.255.255'));
          } else if (o0 == 192 && o1 == 168) {
            targets.add(InternetAddress('192.168.255.255'));
          }
        }
      }
    } catch (_) {
      // Fall back to limited broadcast if interface enumeration fails.
    }
    return targets;
  }
}
