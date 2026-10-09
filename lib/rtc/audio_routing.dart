// The iOS policy below needs LiveKit's experimental audio-session types and its
// internal Native.configureAudio, the same internals the LiveKit 2.7 override
// relied on. Re-check this file on every livekit_client upgrade.
// ignore_for_file: experimental_member_use, invalid_use_of_internal_member

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';
// ignore: implementation_imports
import 'package:livekit_client/src/support/native.dart' show Native;
// ignore: implementation_imports
import 'package:livekit_client/src/support/native_audio.dart'
    show NativeAudioConfiguration;

import '../service/daakia_meeting_service.dart';
import '../service/daakia_vc_logger.dart';

/// Keeps the SDK's speaker / earpiece / headset behaviour identical to what it
/// was on LiveKit 2.7, on top of LiveKit 2.13's audio management.
///
/// Two things changed upstream that this class compensates for:
///
/// * **iOS**: LiveKit 2.9 removed `onConfigureNativeAudio`. LiveKit 2.13 picks
///   the `playback` category whenever only remote audio is playing (local mic
///   never enabled), and `playback` ignores both a forced speaker and an
///   earpiece choice. Our old override kept `playAndRecord` in that state, so
///   we push the same `playAndRecord` policy with engine-state category
///   selection turned off whenever the user forced the speaker or chose a
///   non-speaker output. With the plain speaker preference LiveKit's own policy
///   already matches the old behaviour, so it is left alone.
/// * **Android**: LiveKit 2.13 turns off flutter_webrtc's audio manager, so
///   `enumerateDevices()` no longer lists `audiooutput` entries and output
///   changes no longer raise `onDeviceChange`. The native side of this plugin
///   now lists the outputs the same way the old audioswitch scanner did
///   (same labels and ids), and reports output changes.
///
/// Android routing also changed: flutter_webrtc used to *select* the speaker
/// explicitly on `setSpeakerphoneOn(true)`, which LiveKit 2.13 expresses as a
/// forced speaker preference.
class DaakiaAudioRouting {
  DaakiaAudioRouting._();

  static const _channel = MethodChannel('io.daakia/audio_devices');
  static const _events = EventChannel('io.daakia/audio_devices/events');

  static bool _iosPolicyActive = false;
  static bool _iosOverridePushed = false;
  static StreamSubscription<AudioEngineState>? _engineSub;

  static StreamController<List<MediaDevice>>? _deviceChange;
  static StreamSubscription<List<MediaDevice>>? _hardwareSub;
  static StreamSubscription<dynamic>? _nativeSub;

  /// Audio routing trace. Prints `[AudioDiag] <event> {...}` to the console
  /// and sends the same record to Datadog (message `audio_diag`), so a
  /// TestFlight build can be diagnosed from Datadog without a cable.
  static void diag(String event, [Map<String, Object?> attrs = const {}]) {
    final manager = AudioManager.instance;
    final record = <String, Object?>{
      'event': event,
      'preferSpeaker': manager.isSpeakerOutputPreferred,
      'forceSpeaker': manager.isSpeakerOutputForced,
      'overridePushed': _iosOverridePushed,
      ...attrs,
    };
    debugPrint('[AudioDiag] $event $record');
    DaakiaVcLogger.logInfo('audio_diag', attributes: record);
  }

  /// Logs the live iOS AVAudioSession state under [event].
  static Future<void> diagRoute(String event) async {
    final route = await DaakiaMeetingService.getAudioRoute();
    if (route != null) diag(event, route);
  }

  static bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;
  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  // ---------------------------------------------------------------------------
  // Routing
  // ---------------------------------------------------------------------------

  /// Drop-in replacement for `Hardware.instance.setSpeakerphoneOn` that keeps
  /// the LiveKit 2.7 routing semantics on both platforms.
  static Future<void> setSpeakerphoneOn(
    bool enable, {
    bool forceSpeakerOutput = false,
  }) async {
    diag('setSpeakerphoneOn', {'enable': enable, 'force': forceSpeakerOutput});
    if (_isAndroid) {
      // flutter_webrtc (LiveKit 2.7) selected the speakerphone device outright,
      // even over a connected headset. In LiveKit 2.13 that is the forced
      // speaker preference.
      await AudioManager.instance.setSpeakerOutputPreferred(
        enable,
        force: enable,
      );
      await _syncAndroidMic();
      unawaited(Future.delayed(
        const Duration(milliseconds: 500),
        () => diagRoute('setSpeakerphoneOn.route'),
      ));
      return;
    }
    // LiveKit 2.7 never cleared an existing speaker override on a non-forced
    // setSpeakerphoneOn(true); 2.13 does. rtc_controls relies on the old
    // behaviour: with a wired headset and Speaker forced, iOS hides the headset
    // from the route, _loadDevices reads that as "headset unplugged" and calls
    // setSpeakerphoneOn(true), which would otherwise drop audio back to it.
    final keepForced = _isIos &&
        enable &&
        !forceSpeakerOutput &&
        AudioManager.instance.isSpeakerOutputForced;
    await AudioManager.instance.setSpeakerOutputPreferred(
      enable,
      force: forceSpeakerOutput || keepForced,
    );
    if (_isIos) {
      await _applyIosPolicy();
      // What iOS actually routed to once the change settled.
      unawaited(Future.delayed(
        const Duration(milliseconds: 500),
        () => diagRoute('setSpeakerphoneOn.route'),
      ));
    }
  }

  /// Re-applies the current speaker / earpiece choice to the audio session.
  /// Used after something outside LiveKit (e.g. a phone call) reconfigured it.
  static Future<void> reapply() async {
    diag('reapply');
    final manager = AudioManager.instance;
    await manager.setSpeakerOutputPreferred(
      manager.isSpeakerOutputPreferred,
      force: manager.isSpeakerOutputForced,
    );
    if (_isIos) await _applyIosPolicy();
    if (_isAndroid) await _syncAndroidMic();
  }

  // Input id last handed to flutter_webrtc, so repeated syncs are no-ops.
  static String? _androidMicId;

  /// Android keeps capturing from a connected headset's mic even after the
  /// call is moved to the loudspeaker, so the far end hears the headset mic
  /// instead of the phone. Point capture at the mic that belongs to the
  /// current output: the built-in mic for a forced speaker, the headset's own
  /// mic otherwise. With no headset or Bluetooth mic connected nothing is
  /// changed, so Android's default choice stands.
  static Future<void> _syncAndroidMic() async {
    if (!_isAndroid) return;
    try {
      final raw = await _channel.invokeListMethod<Map>('getAudioInputs') ??
          const <Map>[];
      final inputs = raw
          .map((m) => (id: m['deviceId'] as String, kind: m['kind'] as String))
          .toList();
      if (!inputs.any((i) => i.kind != 'builtin')) {
        _androidMicId = null;
        return;
      }

      final String? target;
      if (AudioManager.instance.isSpeakerOutputForced) {
        final builtin = inputs.where((i) => i.kind == 'builtin');
        // The bottom mic is the one Android uses for calls by default.
        target = (builtin.where((i) => i.id == 'microphone-bottom').firstOrNull ??
                builtin.firstOrNull)
            ?.id;
      } else {
        // Android routes a non-speaker call to Bluetooth ahead of a wired
        // headset (audioswitch priority); follow the same order. A Bluetooth
        // mic only appears once its SCO link is up, which raises another
        // device change and another sync.
        final outputs = await _androidAudioOutputs();
        final kind = outputs.any((o) => o.deviceId == 'bluetooth')
            ? 'bluetooth'
            : 'wired-headset';
        target = inputs.where((i) => i.kind == kind).firstOrNull?.id;
      }

      diag('micInput', {
        'inputs': inputs.map((i) => '${i.kind}|${i.id}').toList(),
        'target': target,
        'previous': _androidMicId,
      });
      if (target == null || target == _androidMicId) return;
      await rtc.Helper.selectAudioInput(target);
      _androidMicId = target;
    } catch (e) {
      diag('micInputError', {'error': '$e'});
    }
  }

  /// Starts enforcing the meeting's iOS routing policy. Call when the meeting
  /// screen is created. No-op on Android.
  // Audio-output picker state for the current meeting. Kept here rather than
  // in RtcControls' State because RtcControls is rebuilt from scratch whenever
  // the meeting layout switches between portrait and landscape; keeping it in
  // the widget reset the user's earpiece choice back to speaker.
  static bool uiSpeakerphoneOn = true;
  static bool uiEarpieceChoice = false;
  static List<MediaDevice> uiOutputs = const [];
  static bool uiInitialRouteApplied = false;

  static void _resetUiState() {
    uiSpeakerphoneOn = true;
    uiEarpieceChoice = false;
    uiOutputs = const [];
    uiInitialRouteApplied = false;
  }

  static void attach() {
    _resetUiState();
    _androidMicId = null;
    if (_isAndroid) unawaited(diagRoute('attach'));
    if (!_isIos) return;
    _iosPolicyActive = true;
    // LiveKit re-pushes its own policy at a few points (e.g. when local audio
    // capture starts). Re-assert ours whenever the audio engine changes state
    // so playout-only never falls back to the `playback` category.
    _engineSub ??= AudioManager.instance.audioEngineStateStream.listen((s) {
      diag('engineState', {
        'playout': s.isPlayoutEnabled,
        'recording': s.isRecordingEnabled,
      });
      unawaited(_applyIosPolicy());
    });
    DaakiaMeetingService.onAudioRouteChanged =
        (route) => diag('routeChanged', route);
    unawaited(diagRoute('attach'));
    unawaited(_applyIosPolicy());
  }

  /// Stops enforcing the iOS policy and hands routing back to LiveKit's
  /// default. Call when the meeting screen is disposed. No-op on Android.
  static Future<void> detach() async {
    if (!_isIos) return;
    _iosPolicyActive = false;
    DaakiaMeetingService.onAudioRouteChanged = null;
    await _engineSub?.cancel();
    _engineSub = null;
    if (_iosOverridePushed) {
      _iosOverridePushed = false;
      final manager = AudioManager.instance;
      // Re-pushes LiveKit's own policy for the current preference.
      await manager.setSpeakerOutputPreferred(
        manager.isSpeakerOutputPreferred,
        force: manager.isSpeakerOutputForced,
      );
    }
  }

  // Mirrors the LiveKit 2.7 override from room.dart (forced speaker) and the
  // 2.7 default for a non-speaker preference (playAndRecordReceiver): both used
  // playAndRecord regardless of whether the local mic had been enabled.
  static Future<void> _applyIosPolicy() async {
    if (!_iosPolicyActive) return;
    final manager = AudioManager.instance;
    if (manager.managementMode != AudioSessionManagementMode.automatic) return;

    final forced = manager.isSpeakerOutputForced;
    final preferred = manager.isSpeakerOutputPreferred;
    if (preferred && !forced) {
      // LiveKit's policy for a plain speaker preference already matches 2.7
      // (playback when playout-only, playAndRecord + videoChat when recording).
      // setSpeakerOutputPreferred has just pushed it, replacing ours.
      _iosOverridePushed = false;
      return;
    }

    _iosOverridePushed = true;
    diag('pushIosPolicy', {'mode': forced ? 'videoChat' : 'voiceChat'});
    await Native.configureAudio(
      NativeAudioConfiguration(
        appleAudioCategory: AppleAudioCategory.playAndRecord,
        appleAudioCategoryOptions: {
          AppleAudioCategoryOption.allowBluetooth,
          AppleAudioCategoryOption.allowBluetoothA2DP,
          AppleAudioCategoryOption.allowAirPlay,
          if (forced) AppleAudioCategoryOption.defaultToSpeaker,
        },
        appleAudioMode:
            forced ? AppleAudioMode.videoChat : AppleAudioMode.voiceChat,
      ),
      automatic: true,
      selectCategoryByEngineState: false,
      forceSpeakerOutput: forced,
    );
  }

  // ---------------------------------------------------------------------------
  // Device listing
  // ---------------------------------------------------------------------------

  /// `Hardware.instance.enumerateDevices()` plus, on Android, the audio
  /// outputs LiveKit 2.13 no longer reports.
  static Future<List<MediaDevice>> enumerateDevices() async {
    final devices = await Hardware.instance.enumerateDevices();
    if (!_isAndroid) return devices;
    return [
      ...devices.where((d) => d.kind != 'audiooutput'),
      ...await _androidAudioOutputs(),
    ];
  }

  /// Like `Hardware.instance.onDeviceChange`, but on Android also fires when an
  /// audio output (Bluetooth / wired headset) connects or disconnects, and
  /// every event carries the full list from [enumerateDevices].
  static Stream<List<MediaDevice>> get onDeviceChange {
    if (!_isAndroid) return Hardware.instance.onDeviceChange.stream;
    return (_deviceChange ??= StreamController<List<MediaDevice>>.broadcast(
      onListen: _startAndroidDeviceWatch,
      onCancel: _stopAndroidDeviceWatch,
    ))
        .stream;
  }

  static void _startAndroidDeviceWatch() {
    _hardwareSub = Hardware.instance.onDeviceChange.stream
        .listen((_) => _emitAndroidDevices());
    _nativeSub = _events.receiveBroadcastStream().listen(
          (_) => _emitAndroidDevices(),
          onError: (Object e) => debugPrint('Audio device events error: $e'),
        );
  }

  static void _stopAndroidDeviceWatch() {
    _hardwareSub?.cancel();
    _hardwareSub = null;
    _nativeSub?.cancel();
    _nativeSub = null;
  }

  static Future<void> _emitAndroidDevices() async {
    final controller = _deviceChange;
    if (controller == null || !controller.hasListener) return;
    final devices = await enumerateDevices();
    if (!controller.isClosed) controller.add(devices);
    // A headset or Bluetooth mic came or went (a Bluetooth mic also appears
    // only once its SCO link is up, without any output change).
    await _syncAndroidMic();
  }

  // Same shape as flutter_webrtc's old audiooutput entries: deviceId/groupId
  // are the kind ("bluetooth", "wired-headset", "speaker", "earpiece") and the
  // label is the audioswitch device name.
  static Future<List<MediaDevice>> _androidAudioOutputs() async {
    try {
      final raw = await _channel.invokeListMethod<Map>('getAudioOutputs') ??
          const <Map>[];
      final outputs = raw
          .map((m) => MediaDevice(
                m['deviceId'] as String,
                m['label'] as String,
                'audiooutput',
                m['deviceId'] as String,
              ))
          .toList();
      // audioswitch ordered its list by the preferred-device list, which
      // flutter_webrtc rebuilt on every speakerphone toggle.
      final order = AudioManager.instance.isSpeakerOutputPreferred
          ? const ['bluetooth', 'wired-headset', 'speaker', 'earpiece']
          : const ['bluetooth', 'wired-headset', 'earpiece', 'speaker'];
      outputs.sort((a, b) =>
          order.indexOf(a.deviceId).compareTo(order.indexOf(b.deviceId)));
      return outputs;
    } catch (e) {
      debugPrint('getAudioOutputs error: $e');
      return const [];
    }
  }
}
