import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../resources/colors/color.dart';
import '../../rtc/audio_routing.dart';
import '../../service/daakia_meeting_service.dart';
import '../../viewmodel/rtc_viewmodel.dart';
import '../bottom_sheets/audio_output_bottomsheet.dart'
    show
        isExternalAudioDevice,
        isWiredHeadsetPort,
        showMeetingAudioOutputPicker;

/// In-meeting check of the camera, microphone and speaker.
///
/// Nothing here reaches the other participants: while the user is muted (or
/// has the camera off) the page opens its own local tracks that are never
/// published, and releases them on close. When the mic or camera is already
/// live, the page shows that live track instead.
///
/// The mic test starts on its own. The camera preview waits for the user to
/// turn it on, so opening the page never lights the camera unasked; it can be
/// flipped between front and rear, and goes off again on close.
class DeviceTestPage extends StatefulWidget {
  final RtcViewmodel viewModel;

  const DeviceTestPage({super.key, required this.viewModel});

  @override
  State<DeviceTestPage> createState() => _DeviceTestPageState();
}

enum _LoadState { off, loading, ready, failed }

class _DeviceTestPageState extends State<DeviceTestPage> {
  static const _surface = Color(0xFF2A2A2A);
  static const _ok = Color(0xFF4ADE80);

  RtcViewmodel get _vm => widget.viewModel;
  LocalParticipant? get _participant => _vm.room.localParticipant;

  // ---- Microphone
  LocalAudioTrack? _testMicTrack; // local only, never published
  _LoadState _micState = _LoadState.loading;
  AudioVisualizer? _visualizer;
  LocalAudioTrack? _visualizedTrack;
  double _level = 0;
  bool _micHeard = false;

  // ---- Speaker
  bool _playing = false;
  bool _played = false;

  // ---- Camera
  LocalVideoTrack? _testCameraTrack; // local only, never published
  _LoadState _cameraState = _LoadState.off;
  CameraPosition _cameraPosition = CameraPosition.front;
  bool _canFlipCamera = false;
  bool _flipping = false;

  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _participant?.addListener(_onMeetingChanged);
    _vm.addListener(_onMeetingChanged);
    DaakiaAudioRouting.uiRevision.addListener(_onOutputChanged);
    _syncMic();
    _syncCamera();
    unawaited(_checkCanFlip());
  }

  @override
  void dispose() {
    _disposed = true;
    _participant?.removeListener(_onMeetingChanged);
    _vm.removeListener(_onMeetingChanged);
    DaakiaAudioRouting.uiRevision.removeListener(_onOutputChanged);
    _stopVisualizer();
    _releaseTestMic();
    _releaseTestCamera();
    if (_playing) unawaited(DaakiaMeetingService.stopTestSound());
    super.dispose();
  }

  void _onMeetingChanged() {
    if (!mounted) return;
    _syncMic();
    _syncCamera();
    setState(() {});
  }

  // ================================================================ Microphone

  /// The published mic track, when the user is unmuted.
  LocalAudioTrack? get _liveMicTrack {
    final p = _participant;
    if (p == null || !p.isMicrophoneEnabled()) return null;
    final track = p.audioTrackPublications
        .where((pub) => pub.source == TrackSource.microphone)
        .firstOrNull
        ?.track;
    if (track == null || track.muted) return null;
    return track;
  }

  bool get _usingLiveMic => _liveMicTrack != null;

  Future<void> _syncMic() async {
    if (_vm.isAudioDisconnected) {
      _stopVisualizer();
      _releaseTestMic();
      return;
    }
    final live = _liveMicTrack;
    if (live != null) {
      // Unmuted meanwhile: the live track takes over.
      _releaseTestMic();
      _micState = _LoadState.ready;
      _visualize(live);
      return;
    }
    if (_testMicTrack != null) {
      _visualize(_testMicTrack!);
      return;
    }
    if (_micState == _LoadState.failed) return;
    await _startTestMic();
  }

  bool _startingMic = false;

  Future<void> _startTestMic() async {
    if (_startingMic) return;
    _startingMic = true;
    if (mounted) setState(() => _micState = _LoadState.loading);
    try {
      final track = await LocalAudioTrack.create();
      await track.start();
      if (_disposed || _liveMicTrack != null || _vm.isAudioDisconnected) {
        await _closeAudioTrack(track);
        return;
      }
      _testMicTrack = track;
      _micState = _LoadState.ready;
      _visualize(track);
    } catch (e) {
      debugPrint('Device test: could not open the microphone: $e');
      _micState = _LoadState.failed;
    } finally {
      _startingMic = false;
      if (mounted) setState(() {});
    }
  }

  void _releaseTestMic() {
    final track = _testMicTrack;
    _testMicTrack = null;
    if (track == null) return;
    if (identical(_visualizedTrack, track)) _stopVisualizer();
    unawaited(_closeAudioTrack(track));
  }

  /// Stops the test track and releases the mic recorder it started (see
  /// [DaakiaAudioRouting.releaseMicRecorder]), unless the meeting's own mic is
  /// live and still needs it.
  Future<void> _closeAudioTrack(LocalAudioTrack track) async {
    try {
      await track.stop();
      await track.dispose();
    } catch (e) {
      debugPrint('Device test: could not close the microphone: $e');
    }
    if (_liveMicTrack != null || _vm.isAudioDisconnected) return;
    await DaakiaAudioRouting.releaseMicRecorder();
  }

  void _visualize(LocalAudioTrack track) {
    if (identical(track, _visualizedTrack)) return;
    _stopVisualizer();
    _visualizedTrack = track;
    final visualizer = createVisualizer(
      track,
      options: const AudioVisualizerOptions(barCount: 7, centeredBands: false),
    );
    _visualizer = visualizer;
    visualizer.events.on<AudioVisualizerEvent>((e) {
      if (!mounted || !identical(_visualizer, visualizer)) return;
      var peak = 0.0;
      for (final v in e.event) {
        if (v is num) peak = math.max(peak, v.toDouble());
      }
      peak = peak.clamp(0.0, 1.0);
      setState(() {
        // Rise at once, fall gently, so the meter doesn't flicker.
        _level = peak > _level ? peak : _level * 0.8 + peak * 0.2;
        if (_level > 0.35) _micHeard = true;
      });
    });
    visualizer.start().catchError((Object e) {
      debugPrint('Device test: mic meter failed to start: $e');
    });
  }

  void _stopVisualizer() {
    final visualizer = _visualizer;
    _visualizer = null;
    _visualizedTrack = null;
    _level = 0;
    if (visualizer == null) return;
    unawaited(() async {
      try {
        await visualizer.stop();
      } catch (e) {
        debugPrint('Device test: mic meter failed to stop: $e');
      }
      await visualizer.dispose();
    }());
  }

  void _retryMic() {
    _micState = _LoadState.loading;
    _syncMic();
  }

  // =================================================================== Speaker

  String get _outputLabel {
    if (DaakiaAudioRouting.uiSpeakerphoneOn) return 'Speakerphone';
    final external = DaakiaAudioRouting.uiOutputs
        .where((d) => isExternalAudioDevice(d.label))
        .firstOrNull;
    return external?.label ?? 'Earpiece';
  }

  IconData get _outputIcon {
    if (DaakiaAudioRouting.uiSpeakerphoneOn) return Icons.volume_up_rounded;
    final external = DaakiaAudioRouting.uiOutputs
        .where((d) => isExternalAudioDevice(d.label))
        .firstOrNull;
    if (external == null) return Icons.phone_in_talk_rounded;
    final g = (external.groupId ?? '').toLowerCase();
    final l = external.label.toLowerCase();
    if (g.contains('bluetooth') ||
        l.contains('bluetooth') ||
        l.contains('airpods')) {
      return Icons.bluetooth_audio_rounded;
    }
    if (isWiredHeadsetPort(external.groupId) || l.contains('headset')) {
      return Icons.headset_rounded;
    }
    return Icons.speaker_rounded;
  }

  Future<void> _toggleTestSound() async {
    if (_playing) {
      await DaakiaMeetingService.stopTestSound();
      return;
    }
    setState(() => _playing = true);
    try {
      // Native playback on the call's own route: an ordinary media player
      // would reconfigure the shared audio session and could cut into the
      // meeting's audio.
      final completed = await DaakiaMeetingService.playTestSound();
      if (mounted) {
        setState(() {
          _playing = false;
          if (completed) _played = true;
        });
      }
    } catch (e) {
      debugPrint('Device test: test sound failed: $e');
      if (mounted) {
        setState(() => _playing = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text("Couldn't play the test sound."),
              duration: Duration(seconds: 2),
            ),
          );
      }
    }
  }

  bool get _canChangeOutput => AudioManager.instance.canSwitchSpeakerphone;

  Future<void> _changeOutput() async {
    // The meeting's own picker, minus "Disconnect Audio". Its state lives in
    // DaakiaAudioRouting, so it doesn't depend on the controls bar (which is
    // rebuilt on rotation).
    await showMeetingAudioOutputPicker(context);
  }

  void _onOutputChanged() {
    if (mounted) setState(() {});
  }

  // ==================================================================== Camera

  /// The published camera track, when the camera is on.
  VideoTrack? get _liveCameraTrack {
    final p = _participant;
    if (p == null || !p.isCameraEnabled()) return null;
    final track = p.videoTrackPublications
        .where((pub) => pub.source == TrackSource.camera)
        .firstOrNull
        ?.track;
    if (track == null || track.muted) return null;
    return track;
  }

  VideoTrack? get _cameraTrack => _liveCameraTrack ?? _testCameraTrack;

  bool _startingCamera = false;

  /// The live camera shows on its own; the private preview only on request.
  void _syncCamera() {
    if (_liveCameraTrack != null) {
      _releaseTestCamera();
      _cameraState = _LoadState.ready;
      return;
    }
    // Live camera turned off meanwhile: back to the "turn on preview" prompt,
    // rather than opening the camera again behind the user's back.
    if (_testCameraTrack == null && !_startingCamera) {
      if (_cameraState == _LoadState.ready) _cameraState = _LoadState.off;
    }
  }

  Future<void> _checkCanFlip() async {
    try {
      final devices = await Hardware.instance.enumerateDevices(
        type: 'videoinput',
      );
      if (mounted) setState(() => _canFlipCamera = devices.length > 1);
    } catch (_) {}
  }

  Future<void> _startTestCamera() async {
    if (_startingCamera) return;
    _startingCamera = true;
    if (mounted) setState(() => _cameraState = _LoadState.loading);
    try {
      final track = await LocalVideoTrack.createCameraTrack(
        CameraCaptureOptions(cameraPosition: _cameraPosition),
      );
      if (_disposed || _liveCameraTrack != null) {
        await _closeVideoTrack(track);
        return;
      }
      _testCameraTrack = track;
      _cameraState = _LoadState.ready;
    } catch (e) {
      debugPrint('Device test: could not open the camera: $e');
      _cameraState = _LoadState.failed;
    } finally {
      _startingCamera = false;
      if (mounted) setState(() {});
    }
  }

  void _releaseTestCamera() {
    final track = _testCameraTrack;
    _testCameraTrack = null;
    if (track != null) unawaited(_closeVideoTrack(track));
  }

  Future<void> _closeVideoTrack(LocalVideoTrack track) async {
    try {
      await track.stop();
      await track.dispose();
    } catch (e) {
      debugPrint('Device test: could not close the camera: $e');
    }
  }

  void _stopTestCamera() {
    _releaseTestCamera();
    setState(() => _cameraState = _LoadState.off);
  }

  /// Reopens the preview on the other camera. A fresh track rather than
  /// [LocalVideoTrack.setCameraPosition]: on a track that was never published
  /// that restarts the capture but the preview keeps showing the old stream.
  Future<void> _flipTestCamera() async {
    final track = _testCameraTrack;
    if (track == null || _flipping) return;
    final previous = _cameraPosition;
    setState(() {
      _flipping = true;
      _testCameraTrack = null;
      _cameraState = _LoadState.loading;
    });
    try {
      // Let go of this camera first; some phones can't open both at once.
      await _closeVideoTrack(track);
      if (_disposed) return;
      _cameraPosition = previous == CameraPosition.front
          ? CameraPosition.back
          : CameraPosition.front;
      await _startTestCamera();
      if (_cameraState == _LoadState.failed && !_disposed) {
        // The other camera wouldn't open: go back to the one that worked.
        _cameraPosition = previous;
        await _startTestCamera();
      }
    } finally {
      _flipping = false;
      if (mounted) setState(() {});
    }
  }

  // ======================================================================== UI

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      backgroundColor: emptyVideoColor,
      appBar: AppBar(
        backgroundColor: emptyVideoColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Test your devices',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        top: false,
        child: landscape
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildCamera(expand: true)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildPrivacyNote(),
                            const SizedBox(height: 12),
                            _buildMic(),
                            const SizedBox(height: 12),
                            _buildSpeaker(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  children: [
                    _buildPrivacyNote(),
                    const SizedBox(height: 12),
                    _buildCamera(),
                    const SizedBox(height: 12),
                    _buildMic(),
                    const SizedBox(height: 12),
                    _buildSpeaker(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPrivacyNote() {
    return Row(
      children: [
        const Icon(Icons.lock_outline_rounded, color: Colors.white54, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _usingLiveMic
                ? "You're unmuted, so others can hear you. The camera preview "
                      'and test sound stay on your device.'
                : "Only you can see and hear these tests. You stay muted in "
                      'the meeting.',
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _cardHeader({
    required IconData icon,
    required String title,
    required Widget status,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              status,
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _statusText(String text, {bool ok = false, bool error = false}) {
    final color = ok
        ? _ok
        : error
        ? Colors.redAccent
        : Colors.white60;
    return Row(
      children: [
        if (ok) ...[
          const Icon(Icons.check_circle_rounded, color: _ok, size: 14),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(text, style: TextStyle(color: color, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _retryButton(VoidCallback onPressed) =>
      TextButton(onPressed: onPressed, child: const Text('Try again'));

  // ---- Camera card

  Widget _buildCamera({bool expand = false}) {
    final track = _cameraTrack;
    final Widget content;
    if (track != null) {
      content = VideoTrackRenderer(
        key: ValueKey(track.mediaStreamTrack.id),
        track,
        renderMode: VideoRenderMode.auto,
        fit: VideoViewFit.cover,
      );
    } else if (_cameraState == _LoadState.failed) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_rounded,
                color: Colors.white54,
                size: 36,
              ),
              const SizedBox(height: 8),
              const Text(
                "Couldn't open your camera. Check that camera access is "
                'allowed in Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              _retryButton(_startTestCamera),
            ],
          ),
        ),
      );
    } else if (_cameraState == _LoadState.off) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_rounded,
                color: Colors.white54,
                size: 36,
              ),
              const SizedBox(height: 8),
              const Text(
                'Your camera is off. Preview it here without turning it on '
                'in the meeting.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _startTestCamera,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.videocam_rounded),
                label: const Text('Turn on preview'),
              ),
            ],
          ),
        ),
      );
    } else {
      content = const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }

    final isLive = _liveCameraTrack != null;
    final isTest = !isLive && _testCameraTrack != null;
    final preview = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (track != null)
              Positioned(
                left: 12,
                top: 12,
                child: _Pill(
                  icon: isLive ? Icons.circle : Icons.visibility_rounded,
                  iconColor: isLive ? Colors.redAccent : Colors.white,
                  label: isLive ? 'Others can see you' : 'Only you see this',
                ),
              ),
            // Preview controls. Only for the private preview: the live camera
            // is the meeting's, and is switched from the meeting controls.
            if (isTest)
              Positioned(
                right: 12,
                bottom: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_canFlipCamera) ...[
                      _RoundButton(
                        icon: Icons.flip_camera_ios_rounded,
                        tooltip: _cameraPosition == CameraPosition.front
                            ? 'Switch to rear camera'
                            : 'Switch to front camera',
                        onPressed: _flipping ? null : _flipTestCamera,
                      ),
                      const SizedBox(width: 10),
                    ],
                    _RoundButton(
                      icon: Icons.videocam_off_rounded,
                      tooltip: 'Turn off preview',
                      onPressed: _stopTestCamera,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    if (expand) return preview;
    return AspectRatio(aspectRatio: 4 / 3, child: preview);
  }

  // ---- Microphone card

  Widget _buildMic() {
    final Widget status;
    Widget? trailing;
    if (_vm.isAudioDisconnected) {
      status = _statusText('Meeting audio is off. Reconnect audio to test.');
    } else if (_micState == _LoadState.failed) {
      status = _statusText(
        "Couldn't open your microphone. Check that microphone access is "
        'allowed in Settings.',
        error: true,
      );
      trailing = _retryButton(_retryMic);
    } else if (_micState == _LoadState.loading) {
      status = _statusText('Starting…');
    } else if (_micHeard) {
      status = _statusText('Working. We can hear you.', ok: true);
    } else {
      status = _statusText('Say something to test it');
    }

    final active = !_vm.isAudioDisconnected && _micState == _LoadState.ready;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            icon: Icons.mic_rounded,
            title: 'Microphone',
            status: status,
            trailing: trailing,
          ),
          if (active) ...[
            const SizedBox(height: 14),
            _LevelMeter(level: _level, activeColor: _ok),
          ],
        ],
      ),
    );
  }

  // ---- Speaker card

  Widget _buildSpeaker() {
    if (_vm.isAudioDisconnected) {
      return _card(
        child: _cardHeader(
          icon: Icons.volume_up_rounded,
          title: 'Speaker',
          status: _statusText('Meeting audio is off. Reconnect audio to test.'),
        ),
      );
    }
    final canChange = _canChangeOutput;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            icon: Icons.volume_up_rounded,
            title: 'Speaker',
            status: _statusText(
              _played
                  ? "Didn't hear it? Turn up the volume or switch the output."
                  : 'Play a sound to check you can hear the meeting',
            ),
          ),
          const SizedBox(height: 14),
          // Current output, tappable when it can be switched.
          Material(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: canChange ? _changeOutput : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(_outputIcon, color: Colors.white70, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _outputLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (canChange)
                      const Text(
                        'Change',
                        style: TextStyle(
                          color: Colors.lightBlueAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _toggleTestSound,
              style: FilledButton.styleFrom(
                backgroundColor: _playing ? Colors.white24 : Colors.white,
                foregroundColor: _playing ? Colors.white : Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: Icon(
                _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(
                _playing ? 'Playing… tap to stop' : 'Play test sound',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;

  const _Pill({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 12),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Horizontal segmented input meter.
class _LevelMeter extends StatelessWidget {
  static const _segments = 24;
  final double level;
  final Color activeColor;

  const _LevelMeter({required this.level, required this.activeColor});

  @override
  Widget build(BuildContext context) {
    final lit = (level * _segments).round();
    return SizedBox(
      height: 10,
      child: Row(
        children: [
          for (var i = 0; i < _segments; i++)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: i < lit ? activeColor : Colors.white12,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
