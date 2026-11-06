import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../utils/utils.dart';
import '../../viewmodel/rtc_viewmodel.dart';
import '../spotlight_speaker_tracker.dart';
import 'participant.dart';
import 'participant_info.dart';

/// The Spotlight card: one floating camera over the full-size share that
/// follows whoever is talking (see [SpotlightSpeakerTracker]). It can be
/// dragged and snaps to the nearest corner, and folds away to a small tab.
///
/// Until it has been dragged, it starts where it covers nothing: in the empty
/// band under a wide share (a laptop screen on a portrait phone), otherwise in
/// the bottom-right corner (a tall share from a phone, or landscape).
///
/// Fills the stage; only the card itself takes touches, so pinch-zoom and
/// taps on the share underneath keep working.
class SpotlightCardLayer extends StatefulWidget {
  const SpotlightCardLayer({
    required this.room,
    required this.viewModel,
    required this.tracks,
    required this.share,
    super.key,
  });

  final Room room;
  final RtcViewmodel viewModel;

  /// Everyone in the meeting, as sorted for the stage.
  final List<ParticipantTrack> tracks;

  /// The share on the stage.
  final ParticipantTrack share;

  @override
  State<SpotlightCardLayer> createState() => _SpotlightCardLayerState();
}

class _SpotlightCardLayerState extends State<SpotlightCardLayer> {
  static const _tick = Duration(milliseconds: 250);
  static const _margin = 12.0;

  /// Height of the hide tab that sits on the card's top edge.
  static const _handleHeight = 24.0;

  final _tracker = SpotlightSpeakerTracker();
  Timer? _timer;
  String? _shownIdentity;

  /// Card position while a drag is in progress, else null.
  Offset? _dragOffset;

  String get _shareKey =>
      '${widget.share.participant.identity}:${_sharePublication?.sid}';
  late String _lastShareKey;

  TrackPublication? get _sharePublication => widget.share.participant
      .videoTrackPublications
      .where((p) => p.isScreenShare)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    _lastShareKey = _shareKey;
    _update();
    _timer = Timer.periodic(_tick, (_) => _update());
  }

  @override
  void didUpdateWidget(covariant SpotlightCardLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new share starts the card again from its presenter.
    if (_shareKey != _lastShareKey) {
      _lastShareKey = _shareKey;
      _tracker.reset();
    }
    _update();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Presenter, then hosts and co-hosts, then you, then everyone else by
  /// join time — the order the card falls back to when nobody has talked.
  List<Participant> _fallbackOrder() {
    final presenter = widget.share.participant.identity;
    final seen = <String>{};
    final people = <Participant>[];
    for (final t in widget.tracks) {
      if (t.type != ParticipantTrackType.kUserMedia) continue;
      if (seen.add(t.participant.identity)) people.add(t.participant);
    }
    int rank(Participant p) {
      if (p.identity == presenter) return 0;
      if (Utils.isHost(p.metadata) || Utils.isCoHost(p.metadata)) return 1;
      if (p is LocalParticipant) return 2;
      return 3;
    }

    people.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.joinedAt.compareTo(b.joinedAt);
    });
    return people;
  }

  void _update() {
    if (!mounted) return;
    final speaking = {
      for (final p in widget.room.activeSpeakers)
        if (p.isSpeaking) p.identity: p.audioLevel,
    };
    final shown = _tracker.update(
      speakingLevels: speaking,
      fallbackOrder: _fallbackOrder().map((p) => p.identity).toList(),
    );
    if (shown != _shownIdentity) setState(() => _shownIdentity = shown);
  }

  Participant? get _shownParticipant {
    final id = _shownIdentity;
    if (id == null) return null;
    for (final t in widget.tracks) {
      if (t.participant.identity == id) return t.participant;
    }
    return null;
  }

  /// Wide share on a tall stage leaves a band underneath; null otherwise.
  Rect? _emptyBandBelowShare(Size stage, Size card) {
    final dims = _sharePublication?.dimensions;
    final aspect =
        (dims != null && dims.height > 0) ? dims.width / dims.height : 16 / 9;
    final shareHeight = stage.width / aspect;
    if (shareHeight >= stage.height) return null;
    final bandTop = (stage.height + shareHeight) / 2;
    final band = Rect.fromLTRB(0, bandTop, stage.width, stage.height);
    return band.height >= card.height + 2 * _margin ? band : null;
  }

  Offset _cornerOffset(int corner, Size stage, Size card) {
    final left = corner == 0 || corner == 2;
    final top = corner == 0 || corner == 1;
    return Offset(
      left ? _margin : stage.width - card.width - _margin,
      top ? _margin : stage.height - card.height - _margin,
    );
  }

  Offset _restingOffset(Size stage, Size card) {
    final corner = widget.viewModel.spotlightCorner;
    if (corner != null) return _cornerOffset(corner, stage, card);
    final band = _emptyBandBelowShare(stage, card);
    if (band != null) {
      return Offset(
        (stage.width - card.width) / 2,
        band.center.dy - card.height / 2,
      );
    }
    return _cornerOffset(3, stage, card);
  }

  int _nearestCorner(Offset cardCenter, Size stage) {
    final left = cardCenter.dx < stage.width / 2;
    final top = cardCenter.dy < stage.height / 2;
    return top ? (left ? 0 : 1) : (left ? 2 : 3);
  }

  /// The card plus the hide tab above it; everything is placed by this box.
  Size _cardSize(Size stage) {
    if (stage.height >= stage.width) {
      // Portrait: a larger card, since a wide share leaves lots of room.
      final width = stage.width * 0.38;
      return Size(width, width * 4 / 3 + _handleHeight);
    }
    final height = stage.height * 0.36;
    return Size(height * 4 / 3, height + _handleHeight);
  }

  @override
  Widget build(BuildContext context) {
    final participant = _shownParticipant;
    if (participant == null) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, constraints) {
      final stage = constraints.biggest;
      final card = _cardSize(stage);

      if (widget.viewModel.spotlightCollapsed) {
        return Stack(children: [
          Positioned(
            right: 0,
            // Clear of the share's name bar along the bottom.
            bottom: 56,
            child: _CollapsedTab(
              participant: participant,
              onTap: () =>
                  setState(() => widget.viewModel.spotlightCollapsed = false),
            ),
          ),
        ]);
      }

      final offset = _dragOffset ?? _restingOffset(stage, card);
      return Stack(children: [
        AnimatedPositioned(
          duration: _dragOffset == null
              ? const Duration(milliseconds: 200)
              : Duration.zero,
          curve: Curves.easeOut,
          left: offset.dx,
          top: offset.dy,
          width: card.width,
          height: card.height,
          child: GestureDetector(
            onPanStart: (_) => setState(() => _dragOffset = offset),
            onPanUpdate: (d) => setState(() {
              final next = (_dragOffset ?? offset) + d.delta;
              _dragOffset = Offset(
                next.dx.clamp(0, stage.width - card.width),
                next.dy.clamp(0, stage.height - card.height),
              );
            }),
            onPanEnd: (_) => setState(() {
              final center = (_dragOffset ?? offset) +
                  Offset(card.width / 2, card.height / 2);
              widget.viewModel.spotlightCorner = _nearestCorner(center, stage);
              _dragOffset = null;
            }),
            // The hide tab sits on the card's top edge, outside the tile,
            // so it never covers the "Presenting" badge or the tile menu.
            child: Column(
              children: [
                Semantics(
                  button: true,
                  label: 'Hide speaker',
                  child: GestureDetector(
                    onTap: () => setState(
                        () => widget.viewModel.spotlightCollapsed = true),
                    child: Container(
                      height: _handleHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10)),
                      ),
                      child: const Icon(Icons.keyboard_arrow_down,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ParticipantWidget.widgetFor(
                      ParticipantTrack(participant: participant),
                      key: ValueKey('spotlight_${participant.identity}'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]);
    });
  }
}

/// The folded-away card: a small tab on the right edge showing who is
/// talking. Tap to bring the card back.
class _CollapsedTab extends StatelessWidget {
  const _CollapsedTab({required this.participant, required this.onTap});

  final Participant participant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name =
        participant.name.isNotEmpty ? participant.name : participant.identity;
    return Semantics(
      button: true,
      label: 'Show speaker, $name',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chevron_left, color: Colors.white, size: 20),
              const SizedBox(width: 4),
              CircleAvatar(
                radius: 13,
                backgroundColor: Colors.blueGrey,
                child: Text(
                  Utils.getInitials(name),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
