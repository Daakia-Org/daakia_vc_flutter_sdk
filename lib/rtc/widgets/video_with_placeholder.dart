import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import 'no_video.dart';

/// A video that shows [placeholder] until its first frame is on screen, then
/// fades in.
///
/// The video view is transparent until the first frame arrives, which can
/// take a moment (subscribing, a slow network, a tile scrolled into view),
/// and an empty tile looks broken. This widget owns the renderer so it can
/// tell when the first frame has really been drawn: the renderer reports
/// the video size at that moment.
class VideoWithPlaceholder extends StatefulWidget {
  const VideoWithPlaceholder({
    required this.track,
    required this.placeholder,
    this.fit = VideoViewFit.contain,
    super.key,
  });

  final VideoTrack track;
  final Widget placeholder;
  final VideoViewFit fit;

  @override
  State<VideoWithPlaceholder> createState() => _VideoWithPlaceholderState();
}

class _VideoWithPlaceholderState extends State<VideoWithPlaceholder> {
  rtc.RTCVideoRenderer? _renderer;
  bool _hasFrame = false;

  @override
  void initState() {
    super.initState();
    _createRenderer();
  }

  Future<void> _createRenderer() async {
    final renderer = rtc.RTCVideoRenderer();
    await renderer.initialize();
    if (!mounted) {
      await renderer.dispose();
      return;
    }
    renderer.addListener(_onRendererChanged);
    setState(() => _renderer = renderer);
  }

  void _onRendererChanged() {
    final renderer = _renderer;
    if (_hasFrame || renderer == null || !mounted) return;
    if (renderer.value.width > 0) setState(() => _hasFrame = true);
  }

  @override
  void dispose() {
    // The video view inside has already been unmounted (children go first)
    // and doesn't dispose a renderer it was handed, so release it here.
    final renderer = _renderer;
    _renderer = null;
    if (renderer != null) {
      renderer.removeListener(_onRendererChanged);
      unawaited(renderer.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!_hasFrame) widget.placeholder,
        if (renderer != null)
          AnimatedOpacity(
            opacity: _hasFrame ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: VideoTrackRenderer(
              widget.track,
              renderMode: VideoRenderMode.auto,
              fit: widget.fit,
              cachedRenderer: renderer,
              autoDisposeRenderer: false,
            ),
          ),
      ],
    );
  }
}

/// What a tile shows while its video is on the way: a soft shimmer
/// sweeping across the tile, with the person's picture or initials (or a
/// share icon for a screen share) and a short note held still on top. The
/// note changes if it takes long, so a slow video never looks like a frozen
/// app. Small tiles skip the note. With animations turned off in the phone's
/// settings the shimmer stays still.
class VideoLoadingPlaceholder extends StatefulWidget {
  const VideoLoadingPlaceholder({
    this.name,
    this.userAvatar,
    this.isSpeaker = false,
    this.isScreenShare = false,
    super.key,
  });

  final String? name;
  final String? userAvatar;
  final bool isSpeaker;
  final bool isScreenShare;

  @override
  State<VideoLoadingPlaceholder> createState() =>
      _VideoLoadingPlaceholderState();
}

class _VideoLoadingPlaceholderState extends State<VideoLoadingPlaceholder>
    with SingleTickerProviderStateMixin {
  static const _slowAfter = Duration(seconds: 6);

  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  Timer? _slowTimer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _slowTimer = Timer(_slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _shimmer.stop();
      _shimmer.value = 0.5;
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _shimmer.dispose();
    super.dispose();
  }

  String get _note {
    if (widget.isScreenShare) {
      return _slow ? 'Screen share is taking a while…' : 'Loading screen share…';
    }
    return _slow ? 'Video is taking a while…' : 'Starting video…';
  }

  @override
  Widget build(BuildContext context) {
    final avatar = widget.isSpeaker ? 90.0 : 50.0;

    return LayoutBuilder(builder: (context, box) {
      // Leave room for the name bar along the bottom of the tile.
      final showNote = box.maxHeight >= 150;
      return Semantics(
        label: _note,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The sweep: a light band crossing the tile on a slant.
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _shimmer,
                builder: (context, _) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: const [
                        Color(0x00FFFFFF),
                        Color(0x24FFFFFF),
                        Color(0x00FFFFFF),
                      ],
                      stops: const [0.3, 0.5, 0.7],
                      transform: _SlideGradient(_shimmer.value),
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.isScreenShare)
                    Icon(Icons.screen_share_outlined,
                        color: Colors.white70, size: avatar * 0.7)
                  else
                    SizedBox(
                      width: avatar,
                      height: avatar,
                      child: NoVideoWidget(
                        name: widget.name,
                        userAvatar: widget.userAvatar,
                        isSpeaker: widget.isSpeaker,
                      ),
                    ),
                  if (showNote) ...[
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _note,
                        key: ValueKey(_note),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: widget.isSpeaker ? 14 : 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Moves the shimmer band from off the left edge to off the right edge as
/// [progress] goes from 0 to 1.
class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.progress);

  final double progress;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final dx = bounds.width * (progress * 2 - 1);
    return Matrix4.translationValues(dx, 0, 0);
  }
}
