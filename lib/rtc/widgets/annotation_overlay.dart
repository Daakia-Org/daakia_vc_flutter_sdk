import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../model/annotation_stroke.dart';
import '../../utils/annotation_actions.dart';
import '../../viewmodel/rtc_viewmodel.dart';
import 'annotation_painter.dart';

class AnnotationOverlay extends StatefulWidget {
  final TrackPublication publication;
  final Participant participant;
  final String sharerIdentity;
  final String trackSid;
  final Room room;

  const AnnotationOverlay({
    super.key,
    required this.publication,
    required this.participant,
    required this.sharerIdentity,
    required this.trackSid,
    required this.room,
  });

  @override
  State<AnnotationOverlay> createState() => _AnnotationOverlayState();
}

class _AnnotationOverlayState extends State<AnnotationOverlay> {
  Size _videoSize = Size.zero;
  EventsListener<TrackEvent>? _trackListener;
  rtc.RTCVideoRenderer? _dimRenderer;

  @override
  void initState() {
    super.initState();
    _readDimensions();
    widget.participant.addListener(_onParticipantChanged);
    _setupStatsListener();
    _initDimRenderer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestSnapshotIfNeeded());
  }

  @override
  void didUpdateWidget(covariant AnnotationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.participant != widget.participant) {
      oldWidget.participant.removeListener(_onParticipantChanged);
      widget.participant.addListener(_onParticipantChanged);
    }
    if (oldWidget.publication != widget.publication) {
      _trackListener?.dispose();
      _trackListener = null;
      _readDimensions();
      _setupStatsListener();
      _disposeDimRenderer();
      _initDimRenderer();
    }
  }

  @override
  void dispose() {
    widget.participant.removeListener(_onParticipantChanged);
    _trackListener?.dispose();
    _disposeDimRenderer();
    super.dispose();
  }

  /// Creates a hidden RTCVideoRenderer attached to the track's media stream.
  /// Its onResize fires at the exact same instant as VideoTrackRenderer's
  /// internal renderer — when the native layer delivers the first video frame.
  void _initDimRenderer() {
    final mediaStream = widget.publication.track?.mediaStream;
    if (mediaStream == null) return;
    final renderer = rtc.RTCVideoRenderer();
    _dimRenderer = renderer;
    renderer.initialize().then((_) {
      if (!mounted || _dimRenderer != renderer) {
        try {
          renderer.dispose();
        } catch (_) {}
        return;
      }
      try {
        renderer.srcObject = mediaStream;
        renderer.onResize = () {
          if (!mounted) return;
          final w = renderer.videoWidth;
          final h = renderer.videoHeight;
          if (w > 0 && h > 0) {
            final newSize = Size(w.toDouble(), h.toDouble());
            if (newSize != _videoSize) setState(() => _videoSize = newSize);
          }
        };
      } catch (e) {
        // ignore — renderer may have been disposed concurrently
      }
    });
  }

  void _disposeDimRenderer() {
    final r = _dimRenderer;
    _dimRenderer = null;
    if (r == null) return;
    try {
      r.onResize = null;
      r.srcObject = null;
      r.dispose();
    } catch (_) {}
  }

  void _onParticipantChanged() {
    final prev = _videoSize;
    _readDimensions();
    if (_videoSize != prev && mounted) setState(() {});
  }

  /// Reads video dimensions from the publication meta-data.
  /// - Remote: uses `videoDimensions` set from server-side track info.
  /// - Local: uses the configured capture parameters.
  void _readDimensions() {
    final pub = widget.publication;
    if (pub is RemoteTrackPublication) {
      final dims = pub.videoDimensions;
      if (dims != null) {
        _videoSize = Size(dims.width.toDouble(), dims.height.toDouble());
      }
    } else if (pub is LocalTrackPublication) {
      final track = pub.track;
      if (track is LocalVideoTrack) {
        final dims = track.currentOptions.params.dimensions;
        _videoSize = Size(dims.width.toDouble(), dims.height.toDouble());
      }
    }
  }

  /// Secondary listener: stats events fire once video frames are flowing and
  /// give us the actual decoded frame size (most accurate for remote tracks).
  void _setupStatsListener() {
    final track = widget.publication.track;
    if (track == null) return;
    _trackListener = track.createListener();
    if (track is RemoteVideoTrack) {
      _trackListener!.on<VideoReceiverStatsEvent>((event) {
        final w = event.stats.frameWidth;
        final h = event.stats.frameHeight;
        if (w != null && h != null && mounted) {
          final newSize = Size(w.toDouble(), h.toDouble());
          if (newSize != _videoSize) setState(() => _videoSize = newSize);
        }
      });
    } else if (track is LocalVideoTrack) {
      _trackListener!.on<VideoSenderStatsEvent>((event) {
        final s = event.stats['f'] ?? event.stats['h'] ?? event.stats['q'];
        final w = s?.frameWidth;
        final h = s?.frameHeight;
        if (w != null && h != null && mounted) {
          final newSize = Size(w.toDouble(), h.toDouble());
          if (newSize != _videoSize) setState(() => _videoSize = newSize);
        }
      });
    }
  }

  void _requestSnapshotIfNeeded() {
    if (!mounted) return;
    final viewModel = context.read<RtcViewmodel>();
    final localIdentity = widget.room.localParticipant?.identity ?? '';
    if (widget.sharerIdentity == localIdentity) return;

    final key = '${widget.sharerIdentity}:${widget.trackSid}';
    if (viewModel.hasRequestedAnnotationSnapshot(key)) return;
    viewModel.markAnnotationSnapshotRequested(key);

    viewModel.publishAnnotationData(
      widget.room,
      {
        'action': AnnotationActions.snapshotRequest,
        'requesterIdentity': localIdentity,
        'sharerIdentity': widget.sharerIdentity,
      },
      destinationIdentities: [widget.sharerIdentity],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RtcViewmodel>(builder: (context, viewModel, _) {
      final strokes = viewModel.getAnnotationStrokes(widget.sharerIdentity);
      final isAnnotationForThisShare = viewModel.isAnnotationActive &&
          viewModel.activeAnnotationSharerIdentity == widget.sharerIdentity;

      return LayoutBuilder(builder: (context, constraints) {
        final containerWidth = constraints.maxWidth;
        final containerHeight = constraints.maxHeight;

        final bounds = _videoSize == Size.zero
            ? VideoContentBounds(
                left: 0,
                top: 0,
                width: containerWidth,
                height: containerHeight)
            : getRenderedVideoContentBounds(
                containerWidth: containerWidth,
                containerHeight: containerHeight,
                videoWidth: _videoSize.width,
                videoHeight: _videoSize.height,
              );

        return Stack(children: [
          // Committed strokes — always visible, never interactive
          IgnorePointer(
            child: CustomPaint(
              size: Size(containerWidth, containerHeight),
              painter: AnnotationPainter(strokes: strokes, bounds: bounds),
            ),
          ),
          // Drawing input layer — only when this user is annotating this share
          if (isAnnotationForThisShare)
            _AnnotationInputLayer(
              bounds: bounds,
              sharerIdentity: widget.sharerIdentity,
              room: widget.room,
            ),
        ]);
      });
    });
  }
}

class _AnnotationInputLayer extends StatefulWidget {
  final VideoContentBounds bounds;
  final String sharerIdentity;
  final Room room;

  const _AnnotationInputLayer({
    required this.bounds,
    required this.sharerIdentity,
    required this.room,
  });

  @override
  State<_AnnotationInputLayer> createState() => _AnnotationInputLayerState();
}

class _AnnotationInputLayerState extends State<_AnnotationInputLayer> {
  List<List<double>> _currentPoints = [];
  List<List<double>> _shapePreviewPoints = [];
  String? _currentStrokeId;

  @override
  void didUpdateWidget(covariant _AnnotationInputLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If video content bounds changed mid-stroke, the already-captured points
    // are normalised against the old coordinate system. Discard to avoid
    // misaligned strokes being sent to remote participants.
    if (oldWidget.bounds != widget.bounds && _currentStrokeId != null) {
      _currentStrokeId = null;
      _currentPoints = [];
      _shapePreviewPoints = [];
    }
  }

  bool get _isFreehandTool {
    final tool = context.read<RtcViewmodel>().annotationTool;
    return tool == 'pen' || tool == 'highlighter';
  }

  void _onPointerDown(PointerDownEvent e) {
    final norm = canvasToNormalised(e.localPosition, widget.bounds);
    if (norm == null) return;
    _currentStrokeId = const Uuid().v4();
    _currentPoints = [norm];
    _shapePreviewPoints = [norm, norm];
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_currentStrokeId == null) return;
    final norm = canvasToNormalised(e.localPosition, widget.bounds);
    if (norm == null) return;
    if (_isFreehandTool) {
      _currentPoints.add(norm);
    } else {
      _shapePreviewPoints = [_currentPoints.first, norm];
    }
    setState(() {});
  }

  Future<void> _onPointerUp(PointerUpEvent e) async {
    if (_currentStrokeId == null) return;
    final viewModel = context.read<RtcViewmodel>();
    final tool = viewModel.annotationTool;

    final finalPoints = _isFreehandTool
        ? List<List<double>>.from(_currentPoints)
        : List<List<double>>.from(_shapePreviewPoints);

    _currentStrokeId = null;
    _currentPoints = [];
    _shapePreviewPoints = [];

    if (finalPoints.isEmpty) {
      setState(() {});
      return;
    }

    final stroke = AnnotationStroke(
      id: const Uuid().v4(),
      fromIdentity: widget.room.localParticipant?.identity ?? '',
      tool: tool,
      color: viewModel.annotationColor,
      width: viewModel.annotationWidth,
      points: finalPoints,
    );

    viewModel.addAnnotationStroke(widget.sharerIdentity, stroke);
    await viewModel.publishAnnotationData(
      widget.room,
      {
        'action': AnnotationActions.stroke,
        'sharerIdentity': widget.sharerIdentity,
        'stroke': stroke.toJson(),
      },
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<RtcViewmodel>();
    final tool = viewModel.annotationTool;

    final previewStrokes = <AnnotationStroke>[];
    if (_currentStrokeId != null) {
      final pts = (tool == 'pen' || tool == 'highlighter')
          ? _currentPoints
          : _shapePreviewPoints;
      if (pts.isNotEmpty) {
        previewStrokes.add(AnnotationStroke(
          id: _currentStrokeId!,
          fromIdentity: '',
          tool: tool,
          color: viewModel.annotationColor,
          width: viewModel.annotationWidth,
          points: pts,
        ));
      }
    }

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      child: CustomPaint(
        painter: AnnotationPainter(
          strokes: previewStrokes,
          bounds: widget.bounds,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
