import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:daakia_vc_flutter_sdk/utils/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';

import '../../presentation/widgets/annotation_toolbar.dart';
import '../../resources/colors/color.dart';
import '../../viewmodel/rtc_viewmodel.dart';
import 'annotation_overlay.dart';
import 'no_video.dart';
import 'participant_info.dart';

abstract class ParticipantWidget extends StatefulWidget {
  // Convenience method to return relevant widget for participant
  static ParticipantWidget widgetFor(ParticipantTrack participantTrack,
      {bool showStatsLayer = false, bool isSpeaker = false}) {
    if (participantTrack.participant is LocalParticipant) {
      return LocalParticipantWidget(
          participantTrack.participant as LocalParticipant,
          participantTrack.type,
          showStatsLayer,
          isSpeaker);
    } else if (participantTrack.participant is RemoteParticipant) {
      return RemoteParticipantWidget(
          participantTrack.participant as RemoteParticipant,
          participantTrack.type,
          showStatsLayer,
          isSpeaker);
    }
    throw UnimplementedError('Unknown participant type');
  }

  // Must be implemented by child class
  abstract final Participant participant;
  abstract final ParticipantTrackType type;
  abstract final bool showStatsLayer;
  final VideoQuality quality;
  abstract final bool isSpeaker;

  const ParticipantWidget({
    this.quality = VideoQuality.MEDIUM,
    super.key,
  });
}

class LocalParticipantWidget extends ParticipantWidget {
  @override
  final LocalParticipant participant;
  @override
  final ParticipantTrackType type;
  @override
  final bool showStatsLayer;
  @override
  final bool isSpeaker;

  const LocalParticipantWidget(
    this.participant,
    this.type,
    this.showStatsLayer,
    this.isSpeaker, {
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _LocalParticipantWidgetState();
}

class RemoteParticipantWidget extends ParticipantWidget {
  @override
  final RemoteParticipant participant;
  @override
  final ParticipantTrackType type;
  @override
  final bool showStatsLayer;
  @override
  final bool isSpeaker;

  const RemoteParticipantWidget(
    this.participant,
    this.type,
    this.showStatsLayer,
    this.isSpeaker, {
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _RemoteParticipantWidgetState();
}

abstract class _ParticipantWidgetState<T extends ParticipantWidget>
    extends State<T> {
  bool _visible = true;

  VideoTrack? get activeVideoTrack;

  AudioTrack? get activeAudioTrack;

  TrackPublication? get videoPublication;

  TrackPublication? get audioPublication;

  bool get isScreenShare => widget.type == ParticipantTrackType.kScreenShare;
  EventsListener<ParticipantEvent>? _listener;

  @override
  void initState() {
    super.initState();
    _listener = widget.participant.createListener();
    _listener?.on<TranscriptionEvent>((e) {
      for (var seg in e.segments) {
        if (kDebugMode) {
          print('Transcription: ${seg.text} ${seg.isFinal}');
        }
      }
    });

    widget.participant.addListener(_onParticipantChanged);
    _onParticipantChanged();
  }

  @override
  void dispose() {
    widget.participant.removeListener(_onParticipantChanged);
    _listener?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    oldWidget.participant.removeListener(_onParticipantChanged);
    widget.participant.addListener(_onParticipantChanged);
    _onParticipantChanged();
    super.didUpdateWidget(oldWidget);
  }

  // Notify Flutter that UI re-build is required, but we don't set anything here
  // since the updated values are computed properties.
  void _onParticipantChanged() => setState(() {});

  // Widgets to show above the info bar
  List<Widget> extraWidgets(bool isScreenShare) => [];

  @override
  Widget build(BuildContext ctx) {
    final viewModel = Provider.of<RtcViewmodel>(context);
    final isAnnotationForThisShare = isScreenShare &&
        viewModel.isAnnotationActive &&
        viewModel.activeAnnotationSharerIdentity == widget.participant.identity;

    return Card(
      elevation: 10,
      color: emptyVideoColor,
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: Container(
        foregroundDecoration: BoxDecoration(
          border: widget.participant.isSpeaking && !isScreenShare
              ? Border.all(
                  width: 5,
                  color: Colors.blue,
                )
              : null,
        ),
        decoration: const BoxDecoration(
          color: emptyVideoColor,
        ),
        child: Stack(
          children: [
            // Video
            InkWell(
              onTap: () => setState(() => _visible = !_visible),
              child: activeVideoTrack != null && !activeVideoTrack!.muted
                  ? VideoTrackRenderer(
                      renderMode: VideoRenderMode.auto,
                      activeVideoTrack!,
                      fit: VideoViewFit.contain,
                    )
                  : NoVideoWidget(
                      name: widget.participant.name,
                      userAvatar:
                          Utils.extractUserAvatar(widget.participant.metadata),
                      isSpeaker: widget.isSpeaker,
                    ),
            ),
            // Annotation overlay — renders remote strokes + drawing input on screen-share tiles
            if (isScreenShare && videoPublication != null)
              Positioned.fill(
                child: AnnotationOverlay(
                  publication: videoPublication!,
                  participant: widget.participant,
                  sharerIdentity: widget.participant.identity,
                  trackSid: videoPublication?.sid ?? '',
                  room: viewModel.room,
                ),
              ),
            // Bottom bar
            Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Annotation toolbar — shown at bottom of tile when annotation is active
                  if (isAnnotationForThisShare)
                    AnnotationToolbar(
                      sharerIdentity: widget.participant.identity,
                      room: viewModel.room,
                    ),
                  // ...extraWidgets(isScreenShare),
                  ParticipantInfoWidget(
                    title: widget.participant.name.isNotEmpty
                        ? widget.participant.name
                        : widget.participant.identity,
                    audioAvailable: audioPublication?.muted == false &&
                        audioPublication?.subscribed == true,
                    connectionQuality: widget.participant.connectionQuality,
                    isScreenShare: isScreenShare,
                    enabledE2EE: widget.participant.isEncrypted,
                  ),
                ],
              ),
            ),
            // if (widget.showStatsLayer)
            // Positioned(
            //     top: 130,
            //     right: 30,
            //     child: ParticipantStatsWidget(
            //       participant: widget.participant,
            //     )),
            if (viewModel.isHandRaised(widget.participant.identity))
              Positioned(
                top: 5,
                left: 5,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.isSpeaker ? 10 : 6,
                    vertical: widget.isSpeaker ? 4 : 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(
                      widget.isSpeaker ? 50 : 12,
                    ),
                    border: Border.all(
                      color: handRaiseColor,
                      width: widget.isSpeaker ? 1.5 : 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.front_hand,
                        color: handRaiseColor,
                        size: widget.isSpeaker ? 24 : 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        viewModel
                            .getRaisePosition(widget.participant.identity)
                            .toString(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: widget.isSpeaker ? 18 : 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Annotation launch button — pencil icon in top-right corner of screen-share tile
            // Hidden when annotation is already active for this share
            if (isScreenShare && !isAnnotationForThisShare)
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => viewModel.setAnnotationActive(
                    true,
                    sharerIdentity: widget.participant.identity,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit, color: Colors.white, size: 18),
                  ),
                ),
              ),
            // Local screen-share blur — suppressed when annotation is active so the
            // sharer can see what they're annotating on
            if (widget.isSpeaker &&
                isScreenShare &&
                widget.participant is LocalParticipant &&
                !isAnnotationForThisShare)
              Positioned.fill(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.screen_share_rounded,
                              color: Colors.white, size: 48),
                          SizedBox(height: 12),
                          Text(
                            'You are sharing your screen',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LocalParticipantWidgetState
    extends _ParticipantWidgetState<LocalParticipantWidget> {
  @override
  LocalTrackPublication<LocalVideoTrack>? get videoPublication =>
      widget.participant.videoTrackPublications
          .where((element) => element.source == widget.type.lkVideoSourceType)
          .firstOrNull;

  @override
  LocalTrackPublication<LocalAudioTrack>? get audioPublication =>
      widget.participant.audioTrackPublications
          .where((element) => element.source == widget.type.lkAudioSourceType)
          .firstOrNull;

  @override
  VideoTrack? get activeVideoTrack => videoPublication?.track;

  @override
  AudioTrack? get activeAudioTrack => audioPublication?.track;
}

class _RemoteParticipantWidgetState
    extends _ParticipantWidgetState<RemoteParticipantWidget> {
  @override
  RemoteTrackPublication<RemoteVideoTrack>? get videoPublication =>
      widget.participant.videoTrackPublications
          .where((element) => element.source == widget.type.lkVideoSourceType)
          .firstOrNull;

  @override
  RemoteTrackPublication<RemoteAudioTrack>? get audioPublication =>
      widget.participant.audioTrackPublications
          .where((element) => element.source == widget.type.lkAudioSourceType)
          .firstOrNull;

  @override
  VideoTrack? get activeVideoTrack => videoPublication?.track;

  @override
  AudioTrack? get activeAudioTrack => audioPublication?.track;

  @override
  List<Widget> extraWidgets(bool isScreenShare) => [
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Menu for RemoteTrackPublication<RemoteAudioTrack>
            if (audioPublication != null)
              RemoteTrackPublicationMenuWidget(
                pub: audioPublication!,
                icon: Icons.volume_up,
              ),
            // Menu for RemoteTrackPublication<RemoteVideoTrack>
            if (videoPublication != null)
              RemoteTrackPublicationMenuWidget(
                pub: videoPublication!,
                icon: isScreenShare ? Icons.monitor : Icons.videocam,
              ),
            if (videoPublication != null)
              RemoteTrackFPSMenuWidget(
                pub: videoPublication!,
                icon: Icons.menu,
              ),
            if (videoPublication != null)
              RemoteTrackQualityMenuWidget(
                pub: videoPublication!,
                icon: Icons.monitor_outlined,
              ),
          ],
        ),
      ];
}

class RemoteTrackPublicationMenuWidget extends StatelessWidget {
  final IconData icon;
  final RemoteTrackPublication pub;

  const RemoteTrackPublicationMenuWidget({
    required this.pub,
    required this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.3),
        child: PopupMenuButton<Function>(
          tooltip: 'Subscribe menu',
          icon: Icon(icon,
              color: {
                TrackSubscriptionState.notAllowed: Colors.red,
                TrackSubscriptionState.unsubscribed: Colors.grey,
                TrackSubscriptionState.subscribed: Colors.green,
              }[pub.subscriptionState]),
          onSelected: (value) => value(),
          itemBuilder: (BuildContext context) => <PopupMenuEntry<Function>>[
            // Subscribe/Unsubscribe
            if (pub.subscribed == false)
              PopupMenuItem(
                child: const Text('Subscribe'),
                value: () => pub.subscribe(),
              )
            else if (pub.subscribed == true)
              PopupMenuItem(
                child: const Text('Un-subscribe'),
                value: () => pub.unsubscribe(),
              ),
          ],
        ),
      );
}

class RemoteTrackFPSMenuWidget extends StatelessWidget {
  final IconData icon;
  final RemoteTrackPublication pub;

  const RemoteTrackFPSMenuWidget({
    required this.pub,
    required this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.3),
        child: PopupMenuButton<Function>(
          tooltip: 'Preferred FPS',
          icon: Icon(icon, color: Colors.white),
          onSelected: (value) => value(),
          itemBuilder: (BuildContext context) => <PopupMenuEntry<Function>>[
            PopupMenuItem(
              child: const Text('30'),
              value: () => pub.setVideoFPS(30),
            ),
            PopupMenuItem(
              child: const Text('15'),
              value: () => pub.setVideoFPS(15),
            ),
            PopupMenuItem(
              child: const Text('8'),
              value: () => pub.setVideoFPS(8),
            ),
          ],
        ),
      );
}

class RemoteTrackQualityMenuWidget extends StatelessWidget {
  final IconData icon;
  final RemoteTrackPublication pub;

  const RemoteTrackQualityMenuWidget({
    required this.pub,
    required this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.3),
        child: PopupMenuButton<Function>(
          tooltip: 'Preferred Quality',
          icon: Icon(icon, color: Colors.white),
          onSelected: (value) => value(),
          itemBuilder: (BuildContext context) => <PopupMenuEntry<Function>>[
            PopupMenuItem(
              child: const Text('HIGH'),
              value: () => pub.setVideoQuality(VideoQuality.HIGH),
            ),
            PopupMenuItem(
              child: const Text('MEDIUM'),
              value: () => pub.setVideoQuality(VideoQuality.MEDIUM),
            ),
            PopupMenuItem(
              child: const Text('LOW'),
              value: () => pub.setVideoQuality(VideoQuality.LOW),
            ),
          ],
        ),
      );
}
