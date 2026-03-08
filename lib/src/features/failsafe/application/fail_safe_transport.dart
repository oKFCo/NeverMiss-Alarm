import 'dart:convert';
import 'dart:io';

import '../domain/fail_safe_models.dart';
import 'fail_safe_protocol.dart';
import 'local_lan_fail_safe_node.dart';

class FailSafeDispatchRequest {
  const FailSafeDispatchRequest({
    required this.target,
    required this.reason,
    required this.alarmId,
    required this.alarmLabel,
    required this.sourceDeviceId,
    required this.sourceDeviceName,
    required this.sourcePlatform,
  });

  final PairedDevice target;
  final FailSafeReason reason;
  final String alarmId;
  final String alarmLabel;
  final String sourceDeviceId;
  final String sourceDeviceName;
  final DevicePlatform sourcePlatform;
}

class FailSafeDispatchResult {
  const FailSafeDispatchResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

abstract class FailSafeTransport {
  Future<FailSafeDispatchResult> dispatch(FailSafeDispatchRequest request);
}

class LocalLanFailSafeTransport implements FailSafeTransport {
  @override
  Future<FailSafeDispatchResult> dispatch(
      FailSafeDispatchRequest request) async {
    final targetAddress = request.target.address.trim().toLowerCase();
    final isLoopbackTarget = targetAddress == 'localhost' ||
        targetAddress == '127.0.0.1' ||
        targetAddress == '::1' ||
        targetAddress == '0.0.0.0';
    if (isLoopbackTarget && request.target.id != request.sourceDeviceId) {
      return FailSafeDispatchResult(
        success: false,
        message:
            'Route target address is loopback (${request.target.address}). '
            'Update paired device IP to Android LAN address.',
      );
    }

    final sharedKey = request.target.sharedKeyHint.trim();
    if (sharedKey.isEmpty || !request.target.isTrusted) {
      return const FailSafeDispatchResult(
        success: false,
        message: 'Target is not trusted/paired with a shared key.',
      );
    }
    final timestampMs = DateTime.now().millisecondsSinceEpoch;
    final nonce = LocalLanFailSafeNode.createNonce();
    final signature = FailSafeProtocol.sign(
      sharedKey: sharedKey,
      sourceDeviceId: request.sourceDeviceId,
      targetDeviceId: request.target.id,
      reason: request.reason.name,
      alarmId: request.alarmId,
      alarmLabel: request.alarmLabel,
      timestampMs: timestampMs,
      nonce: nonce,
    );

    final client = HttpClient();
    try {
      final uri = Uri.parse(
        'http://${request.target.address}:${request.target.port}/failsafe/trigger',
      );
      final httpRequest = await client.postUrl(uri);
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.write(
        jsonEncode({
          'sourceDeviceId': request.sourceDeviceId,
          'sourceDeviceName': request.sourceDeviceName,
          'sourcePlatform': request.sourcePlatform.name,
          'targetDeviceId': request.target.id,
          'reason': request.reason.name,
          'alarmId': request.alarmId,
          'alarmLabel': request.alarmLabel,
          'timestampMs': timestampMs,
          'nonce': nonce,
          'signature': signature,
        }),
      );
      final response = await httpRequest.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return FailSafeDispatchResult(
          success: true,
          message:
              'Local dispatch acknowledged by ${request.target.address}:${request.target.port}.',
        );
      }
      return FailSafeDispatchResult(
        success: false,
        message: 'HTTP ${response.statusCode}: $body',
      );
    } catch (e) {
      return FailSafeDispatchResult(
        success: false,
        message: 'Dispatch error: $e',
      );
    } finally {
      client.close(force: true);
    }
  }
}
