import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../grid_order.dart';
import 'participant.dart';
import 'participant_info.dart';

/// Grid view: up to [gridSize] people in equal tiles that fill the stage,
/// and everyone else in a scrolling strip (along the bottom in portrait, a
/// rail on the right in landscape), the same strip the speaker layout uses.
///
/// No pages: a page turn swaps a whole page of video at once, which makes
/// video show up late and gets worse as meetings grow. The strip is built
/// lazily, so only the tiles on screen get video and scrolling adds them one
/// at a time. People who talk move from the strip into the grid (see
/// [GridOrder]).
///
/// Every tile is keyed by person with a [GlobalKey], so moving between strip
/// and grid, a change in the grid's shape and rotating the phone all carry
/// the existing tile (and its video renderer) over instead of recreating it.
class MeetingGrid extends StatefulWidget {
  const MeetingGrid({
    required this.room,
    required this.tracks,
    super.key,
  });

  /// Most tiles in the grid itself.
  static const gridSize = 6;

  final Room room;

  /// Everyone in the meeting, as sorted for the stage. A newcomer takes the
  /// first free spot in this order.
  final List<ParticipantTrack> tracks;

  @override
  State<MeetingGrid> createState() => _MeetingGridState();
}

class _MeetingGridState extends State<MeetingGrid> {
  static const _tick = Duration(milliseconds: 250);
  static const _gap = 4.0;

  /// Strip size, matching the speaker layout's filmstrip.
  static const _stripHeight = 120.0;
  static const _stripTileWidth = 160.0;

  final _order = GridOrder();
  final Map<String, GlobalKey> _keys = {};
  Timer? _timer;
  List<String> _ids = const [];

  @override
  void initState() {
    super.initState();
    _update(rebuild: false);
    _timer = Timer.periodic(_tick, (_) => _update());
  }

  @override
  void didUpdateWidget(covariant MeetingGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuilding already, so no setState needed.
    _update(rebuild: false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// One camera tile per person, in the stage's order.
  Map<String, ParticipantTrack> get _cameraTracks {
    final byId = <String, ParticipantTrack>{};
    for (final t in widget.tracks) {
      if (t.type != ParticipantTrackType.kUserMedia) continue;
      byId.putIfAbsent(t.participant.identity, () => t);
    }
    return byId;
  }

  void _update({bool rebuild = true}) {
    if (!mounted) return;
    final people = _cameraTracks.keys.toList();
    final speaking = {
      for (final p in widget.room.activeSpeakers)
        if (p.isSpeaking) p.identity: p.audioLevel,
    };
    final ids = _order.update(
      people: people,
      speakingLevels: speaking,
      pageSize: MeetingGrid.gridSize,
    );
    _keys.removeWhere((id, _) => !people.contains(id));
    if (listEquals(ids, _ids)) return;
    if (rebuild) {
      setState(() => _ids = ids);
    } else {
      _ids = ids;
    }
  }

  GlobalKey _keyFor(ParticipantTrack t) =>
      _keys.putIfAbsent(t.participant.identity, () => GlobalKey());

  Widget _tile(ParticipantTrack t) =>
      ParticipantWidget.widgetFor(t, key: _keyFor(t));

  /// Tiles per row for [count] grid tiles. A row with fewer tiles stretches
  /// them, so the grid always fills the stage with no holes.
  static List<int> _rows(int count, bool landscape) {
    if (landscape) {
      return switch (count) {
        <= 3 => [math.max(count, 1)],
        4 => [2, 2],
        5 => [3, 2],
        _ => [3, 3],
      };
    }
    return switch (count) {
      <= 1 => [1],
      2 => [1, 1],
      3 => [1, 2],
      4 => [2, 2],
      5 => [2, 2, 1],
      _ => [2, 2, 2],
    };
  }

  @override
  Widget build(BuildContext context) {
    final byId = _cameraTracks;
    final everyone = [
      for (final id in _ids)
        if (byId[id] != null) byId[id]!,
    ];
    final inGrid = everyone.take(MeetingGrid.gridSize).toList();
    final inStrip = everyone.skip(MeetingGrid.gridSize).toList();
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final railWidth =
        (MediaQuery.of(context).size.width * 0.18).clamp(130.0, 190.0);

    // One Flex whose direction flips, so rotating keeps every child (same
    // reason as the meeting layout in room.dart).
    return Flex(
      direction: landscape ? Axis.horizontal : Axis.vertical,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          key: const ValueKey('grid'),
          child: LayoutBuilder(
            builder: (context, box) => _grid(inGrid, box, landscape),
          ),
        ),
        if (inStrip.isNotEmpty)
          SizedBox(
            key: const ValueKey('strip'),
            width: landscape ? railWidth : null,
            height: landscape ? null : _stripHeight,
            child: _strip(
              inStrip,
              axis: landscape ? Axis.vertical : Axis.horizontal,
              tileWidth: landscape ? railWidth : _stripTileWidth,
              tileHeight: landscape ? railWidth * 2 / 3 : _stripHeight,
            ),
          ),
      ],
    );
  }

  Widget _grid(
      List<ParticipantTrack> tracks, BoxConstraints box, bool landscape) {
    final rows = _rows(tracks.length, landscape);
    final rowH = (box.maxHeight - _gap * (rows.length + 1)) / rows.length;
    final children = <Widget>[];
    var i = 0;
    for (var r = 0; r < rows.length && i < tracks.length; r++) {
      final perRow = rows[r];
      final cellW = (box.maxWidth - _gap * (perRow + 1)) / perRow;
      for (var c = 0; c < perRow && i < tracks.length; c++, i++) {
        final t = tracks[i];
        children.add(Positioned(
          key: ValueKey('cell_${t.participant.identity}'),
          left: _gap + c * (cellW + _gap),
          top: _gap + r * (rowH + _gap),
          width: cellW,
          height: rowH,
          child: _tile(t),
        ));
      }
    }
    return Stack(children: children);
  }

  Widget _strip(
    List<ParticipantTrack> tracks, {
    required Axis axis,
    required double tileWidth,
    required double tileHeight,
  }) {
    final vertical = axis == Axis.vertical;
    return ListView.builder(
      scrollDirection: axis,
      padding: vertical
          ? const EdgeInsets.symmetric(vertical: 4)
          : EdgeInsets.zero,
      itemCount: tracks.length,
      itemBuilder: (context, index) => Padding(
        key: ValueKey('strip_${tracks[index].participant.identity}'),
        padding:
            vertical ? const EdgeInsets.only(bottom: 4) : EdgeInsets.zero,
        child: SizedBox(
          width: tileWidth,
          height: tileHeight,
          child: _tile(tracks[index]),
        ),
      ),
    );
  }
}
