import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class DaakiaMeetingService {
  static const _channel = MethodChannel('io.daakia/meeting_service');

  // Cached params so restartIfActive() can refresh the notification.
  static String? _title;
  static bool _showMuteButton = false;
  static bool _isMuted = false;

  // Callbacks wired up by RoomPage to handle Android notification button presses.
  static VoidCallback? onMuteToggle;
  static VoidCallback? onEndCall;

  // Fired on iOS when a phone call (or other audio interruption) begins or ends.
  // RoomPage uses these to disable/re-enable the mic button and restart the track.
  static VoidCallback? onAudioInterruptionBegan;
  static VoidCallback? onAudioInterruptionEnded;

  /// Must be called once (e.g. in RoomPage.initState) before any [start] call
  /// so that notification button presses from Android are dispatched back here.
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
      case 'audioInterruptionBegan':
        onAudioInterruptionBegan?.call();
        break;
      case 'audioInterruptionEnded':
        onAudioInterruptionEnded?.call();
        break;
    }
  }

  /// Starts the meeting service.
  ///
  /// **Android**: starts a foreground service with a persistent notification
  /// showing Mute/Unmute and End Call actions.
  ///
  /// **iOS**: activates `AVAudioSession` (.playAndRecord / .videoChat) so that
  /// the app continues running in the background under the `audio`
  /// UIBackgroundMode even when the user's microphone is muted.
  static Future<void> start({
    required String title,
    String text = 'Tap to return to the meeting',
    bool isMuted = false,
    bool showMuteButton = false,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    _title = title;
    _isMuted = isMuted;
    _showMuteButton = showMuteButton;

    if (Platform.isAndroid) {
      // POST_NOTIFICATIONS is a runtime permission on Android 13+.
      final notifStatus = await Permission.notification.status;
      if (notifStatus.isDenied) {
        await Permission.notification.request();
      }
    }

    try {
      await _channel.invokeMethod('startMeetingService', {
        'title': title,
        'text': text,
        'isMuted': isMuted,
        'showMuteButton': showMuteButton,
      });
    } catch (e) {
      debugPrint('DaakiaMeetingService start error: $e');
    }
  }

  /// Updates the mute button label in the Android notification.
  /// No-op on iOS (audio session stays active regardless of mute state).
  static Future<void> updateMuteState({
    required bool isMuted,
    bool? showMuteButton,
  }) async {
    if (!Platform.isAndroid || _title == null) return;
    _isMuted = isMuted;
    if (showMuteButton != null) _showMuteButton = showMuteButton;
    try {
      await _channel.invokeMethod('updateMuteState', {
        'isMuted': isMuted,
        'showMuteButton': _showMuteButton,
      });
    } catch (e) {
      debugPrint('DaakiaMeetingService updateMuteState error: $e');
    }
  }

  /// Whether the app currently has permission to show notifications.
  /// Always true on iOS and on Android versions where POST_NOTIFICATIONS
  /// isn't a runtime permission (Android < 13). Does not request — callers
  /// use this after [start] to decide whether to prompt the user themselves.
  static Future<bool> hasNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    return (await Permission.notification.status).isGranted;
  }

  /// Re-attaches the Android notification after returning from system Settings
  /// (e.g. user just granted POST_NOTIFICATIONS mid-meeting). No-op on iOS.
  ///
  /// This is called on every app resume (see RoomPage.didChangeAppLifecycleState),
  /// which includes the resume that happens right after the screen-capture
  /// permission dialog closes. It must NOT call start() / startForegroundService()
  /// here: that re-arms Android's "must call startForeground() within a few
  /// seconds" watchdog, and racing it against the screen-share flow's own
  /// startForeground() call (addMediaProjectionType) on a busy main thread can
  /// throw ForegroundServiceDidNotStartInTimeException (ANR) on slower devices.
  /// updateMuteState only does a plain startService() + notify() refresh, which
  /// carries no such timing requirement.
  static Future<void> restartIfActive() async {
    if (!Platform.isAndroid || _title == null) return;
    try {
      await _channel.invokeMethod('updateMuteState', {
        'isMuted': _isMuted,
        'showMuteButton': _showMuteButton,
      });
    } catch (e) {
      debugPrint('DaakiaMeetingService restartIfActive error: $e');
    }
  }

  /// Upgrades the running FGS to include mediaProjection type so that
  /// flutter_webrtc can call getDisplayMedia. Must be called after the user
  /// grants screen capture permission and before setScreenShareEnabled(true).
  /// No-op on iOS and Android < 14 (flutter_background handles it there).
  /// Returns false if the service is not running (e.g. killed by OS).
  /// Callers must bail early on false — proceeding to setScreenShareEnabled
  /// without the FGS mediaProjection type crashes on Android 14+.
  static Future<bool> startScreenShare() async {
    if (!Platform.isAndroid) return true;
    try {
      await _channel.invokeMethod('startScreenShareService');
      return true;
    } catch (e) {
      debugPrint('DaakiaMeetingService startScreenShare error: $e');
      return false;
    }
  }

  /// Removes the mediaProjection type from the FGS after screen share ends.
  static Future<void> stopScreenShare() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopScreenShareService');
    } catch (e) {
      debugPrint('DaakiaMeetingService stopScreenShare error: $e');
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _title = null;
    _isMuted = false;
    _showMuteButton = false;
    onMuteToggle = null;
    onEndCall = null;
    onAudioInterruptionBegan = null;
    onAudioInterruptionEnded = null;
    try {
      await _channel.invokeMethod('stopMeetingService');
    } catch (e) {
      debugPrint('DaakiaMeetingService stop error: $e');
    }
  }
}
