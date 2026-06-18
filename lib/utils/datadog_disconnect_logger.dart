import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../service/daakia_vc_logger.dart';
import 'device_network_info.dart';

class DatadogDisconnectLogger {
  static Future<void> logDisconnectEvent({
    required String meetingId,
    required Room room,
    required String? reason,
  }) async {
    final local = room.localParticipant;

    Map<String, dynamic> metadataJson = {};
    try {
      if (local?.metadata != null) {
        metadataJson = Map<String, dynamic>.from(
          jsonDecode(local!.metadata!),
        );
      }
    } catch (_) {
      // Ignore metadata parsing errors
    }

    final attributes = <String, Object?>{
      'meetingId': meetingId,
      'disconnectReason': _formatDisconnectReason(reason),
      'participant': {
        'name': local?.name,
        'identity': local?.identity,
        'metadata': local?.metadata,
        'role': metadataJson['role_name'],
        'meetingAttendanceId': metadataJson['meeting_attendance_id'],
        'connectionQuality': local?.connectionQuality.name,
        'isSpeaking': local?.isSpeaking,
        'platform': defaultTargetPlatform.name,
        'userAgent': await DeviceNetworkInfo.getDeviceDetails(),
        'network': await DeviceNetworkInfo.getNetworkType()
      }
    };

    DaakiaVcLogger.logInfo(
      'DISCONNECT REASON: ${_formatDisconnectReason(reason)}',
      attributes: attributes,
    );
  }

  static String _formatDisconnectReason(String? reason) {
    if (reason == null) return "UNKNOWN";
    // Convert camelCase → SNAKE_CASE
    final snake = reason.replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (match) => '${match.group(1)}_${match.group(2)}',
    );

    return snake.toUpperCase();
  }
}
