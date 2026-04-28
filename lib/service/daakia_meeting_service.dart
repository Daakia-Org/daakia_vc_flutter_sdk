import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class DaakiaMeetingService {
  static const _channel = MethodChannel('io.daakia/meeting_service');

  // Cached params so restartIfActive() can replay the last start() call.
  static String? _title;
  static String? _text;

  // Callbacks wired up by RoomPage to handle notification button presses.
  static VoidCallback? onMuteToggle;
  static VoidCallback? onEndCall;

  /// Must be called once (e.g. in RoomPage.initState) to receive button events
  /// from the notification before any [start] call.
  static void initialize() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onMuteToggle':
        onMuteToggle?.call();
        break;
      case 'onEndCall':
        onEndCall?.call();
        break;
    }
  }

  static Future<void> start({
    required String title,
    String text = 'Tap to return to the meeting',
    bool isMuted = false,
    bool hasAudioPermission = true,
  }) async {
    if (!Platform.isAndroid) return;

    _title = title;
    _text = text;

    // POST_NOTIFICATIONS is a runtime permission on Android 13+. Request it
    // upfront so the notification is visible right away when the user joins.
    // The service will still run (and keep the process alive) even if denied.
    final notifStatus = await Permission.notification.status;
    if (notifStatus.isDenied) {
      await Permission.notification.request();
    }

    try {
      await _channel.invokeMethod('startMeetingService', {
        'title': title,
        'text': text,
        'isMuted': isMuted,
        'hasAudioPerm': hasAudioPermission,
      });
    } catch (e) {
      debugPrint('DaakiaMeetingService start error: $e');
    }
  }

  /// Updates the mute button label in the notification without restarting the service.
  static Future<void> updateMuteState({
    required bool isMuted,
    required bool hasAudioPermission,
  }) async {
    if (!Platform.isAndroid || _title == null) return;
    try {
      await _channel.invokeMethod('updateMuteState', {
        'isMuted': isMuted,
        'hasAudioPerm': hasAudioPermission,
      });
    } catch (e) {
      debugPrint('DaakiaMeetingService updateMuteState error: $e');
    }
  }

  /// Re-attaches the notification after returning from system Settings
  /// (e.g. when the user just granted POST_NOTIFICATIONS mid-meeting).
  static Future<void> restartIfActive() async {
    if (!Platform.isAndroid || _title == null) return;
    await start(title: _title!, text: _text ?? 'Tap to return to the meeting');
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    _title = null;
    _text = null;
    onMuteToggle = null;
    onEndCall = null;
    try {
      await _channel.invokeMethod('stopMeetingService');
    } catch (e) {
      debugPrint('DaakiaMeetingService stop error: $e');
    }
  }
}
