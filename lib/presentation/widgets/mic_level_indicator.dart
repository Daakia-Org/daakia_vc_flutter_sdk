import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

/// Small live level bars for a local microphone track, so the user can see the
/// mic picking them up.
///
/// Only reads the track: the visualizer is attached when [track] is set and
/// detached when it changes or this widget goes away, leaving the track itself
/// exactly as it was (it may be published later).
class MicLevelIndicator extends StatefulWidget {
  final LocalAudioTrack? track;
  final Color color;

  const MicLevelIndicator({
    super.key,
    required this.track,
    this.color = const Color(0xFF4ADE80),
  });

  @override
  State<MicLevelIndicator> createState() => _MicLevelIndicatorState();
}

class _MicLevelIndicatorState extends State<MicLevelIndicator> {
  static const _barCount = 5;
  static const _maxHeight = 16.0;
  static const _minHeight = 4.0;

  /// Shape of the bars at full level, so they read as a level meter (tallest
  /// in the middle) rather than five copies of one number.
  static const _barShape = [0.55, 0.8, 1.0, 0.8, 0.55];

  AudioVisualizer? _visualizer;

  /// Smoothed peak of the spectrum, 0..1. Speech energy sits in only a few of
  /// the visualizer's bands and those stay low on iOS, so per-band bars barely
  /// moved there; the loudest band, as the device test page uses, does.
  double _level = 0;

  @override
  void initState() {
    super.initState();
    _attach(widget.track);
  }

  @override
  void didUpdateWidget(MicLevelIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.track, widget.track)) {
      _detach();
      _attach(widget.track);
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _attach(LocalAudioTrack? track) {
    if (track == null) return;
    _IosAudioPipeline.acquire();
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
        // Rise at once, fall gently, so the bars don't flicker.
        _level = peak > _level ? peak : _level * 0.8 + peak * 0.2;
      });
    });
    visualizer.start().catchError((Object e) {
      debugPrint('Mic level indicator failed to start: $e');
    });
  }

  void _detach() {
    final visualizer = _visualizer;
    _visualizer = null;
    _level = 0;
    if (visualizer == null) return;
    _IosAudioPipeline.release();
    unawaited(() async {
      try {
        await visualizer.stop();
      } catch (e) {
        debugPrint('Mic level indicator failed to stop: $e');
      }
      await visualizer.dispose();
    }());
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Microphone level',
      child: SizedBox(
        height: _maxHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < _barCount; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 4,
                height:
                    _minHeight +
                    (_maxHeight - _minHeight) *
                        math.min(1.0, _level * 1.6) *
                        _barShape[i],
                decoration: BoxDecoration(
                  color: _level > 0.15 ? widget.color : Colors.white38,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Keeps an idle, never-connected peer connection open on iOS while a level
/// indicator is showing.
///
/// On iOS the native audio device records as soon as a mic track starts, but
/// WebRTC only hooks its audio pipeline up to the device once a peer
/// connection exists ("Invalid audio transport" until then). Before joining
/// there is none, so the visualizer never got any audio. In the meeting the
/// room's own connection does this. Android delivers the level without it.
class _IosAudioPipeline {
  static int _users = 0;
  static Future<rtc.RTCPeerConnection?>? _pc;

  static void acquire() {
    if (!Platform.isIOS) return;
    _users++;
    _pc ??= rtc
        .createPeerConnection(<String, dynamic>{})
        .then<rtc.RTCPeerConnection?>(
          (pc) => pc,
          onError: (Object e) {
            debugPrint(
              'Mic level indicator: could not open audio pipeline: $e',
            );
            return null;
          },
        );
  }

  static void release() {
    if (!Platform.isIOS || _users == 0) return;
    _users--;
    if (_users > 0) return;
    final pending = _pc;
    _pc = null;
    pending?.then((pc) async {
      try {
        await pc?.close();
        await pc?.dispose();
      } catch (_) {}
    });
  }
}
