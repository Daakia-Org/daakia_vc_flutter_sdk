import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class DaakiaMeetingService {
  static const _channel = MethodChannel('io.daakia/meeting_service');

  // Tracks the last-requested title so a lifecycle-resume restart uses the right label.
  static String? _title;
  static String? _text;

  static Future<void> start({
    required String title,
    String text = 'Tap to return to the meeting',
  }) async {
    if (!Platform.isAndroid) return;

    _title = title;
    _text = text;

    // POST_NOTIFICATIONS is a runtime permission on Android 13+.
    // Request it now so the foreground-service notification is visible immediately.
    // The service will still start even if the user denies — it just won't show
    // a notification until permission is eventually granted.
    final notifStatus = await Permission.notification.status;
    if (notifStatus.isDenied) {
      await Permission.notification.request();
    }

    try {
      await _channel.invokeMethod('startMeetingService', {'title': title, 'text': text});
    } catch (e) {
      debugPrint('DaakiaMeetingService start error: $e');
    }
  }

  /// Call this from AppLifecycleState.resumed to re-attach the notification after
  /// the user granted POST_NOTIFICATIONS in system Settings mid-meeting.
  static Future<void> restartIfActive() async {
    if (!Platform.isAndroid || _title == null) return;
    await start(title: _title!, text: _text ?? 'Tap to return to the meeting');
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    _title = null;
    _text = null;
    try {
      await _channel.invokeMethod('stopMeetingService');
    } catch (e) {
      debugPrint('DaakiaMeetingService stop error: $e');
    }
  }
}
