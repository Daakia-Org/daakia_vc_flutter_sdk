import 'spotlight_speaker_tracker.dart';

/// Keeps the order of the tiles in Grid view.
///
/// The order stays put so tiles don't jump around: people who join go to the
/// end, people who leave just drop out. The one exception is talking:
/// someone who really talks (same rules as the Spotlight card, see
/// [SpotlightSpeakerTracker]) while off the first page swaps places with a
/// tile on the first page, so the people talking are always on the page
/// you see first.
///
/// * A turn counts after [SpotlightSpeakerTracker.qualifyAfter] of talking;
///   pauses shorter than [SpotlightSpeakerTracker.pauseTolerance] don't
///   restart that clock.
/// * The tile given up is someone not talking right now who hasn't just been
///   moved in (they stay at least [SpotlightSpeakerTracker.holdFor]), and of
///   those, the one who talked longest ago.
/// * Only those two tiles change places; everyone else stays where they are.
///
/// Like the tracker it has no timers: call [update] whenever speaking state
/// changes and on a short regular tick while the grid is on screen.
class GridOrder {
  GridOrder({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  final List<String> _order = [];

  final Map<String, DateTime> _talkStartedAt = {};
  final Map<String, DateTime> _lastHeardAt = {};

  /// When each person last had a real turn of talking.
  final Map<String, DateTime> _lastTurnAt = {};

  /// When each person was last moved onto the first page.
  final Map<String, DateTime> _movedInAt = {};

  /// The current order, first page first.
  List<String> get order => List.unmodifiable(_order);

  /// Forget everything; the next [update] starts from its default order.
  void reset() {
    _order.clear();
    _talkStartedAt.clear();
    _lastHeardAt.clear();
    _lastTurnAt.clear();
    _movedInAt.clear();
  }

  /// [people]: everyone to show, in the order a newcomer should take (the
  /// first call uses it as the starting order).
  /// [speakingLevels]: identity → audio level for everyone talking right now.
  /// [pageSize]: tiles on one page.
  /// Returns the order to show.
  List<String> update({
    required List<String> people,
    required Map<String, double> speakingLevels,
    required int pageSize,
  }) {
    final now = _clock();
    final present = people.toSet();

    // Keep the order: drop who left, add who's new at the end.
    _order.removeWhere((id) => !present.contains(id));
    final known = _order.toSet();
    for (final id in people) {
      if (known.add(id)) _order.add(id);
    }
    _lastTurnAt.removeWhere((id, _) => !present.contains(id));
    _movedInAt.removeWhere((id, _) => !present.contains(id));

    // Track continuous talking, allowing short pauses.
    for (final id in speakingLevels.keys) {
      if (!present.contains(id)) continue;
      _talkStartedAt.putIfAbsent(id, () => now);
      _lastHeardAt[id] = now;
    }
    _lastHeardAt.removeWhere((id, heard) {
      final gone = !present.contains(id) ||
          now.difference(heard) > SpotlightSpeakerTracker.pauseTolerance;
      if (gone) _talkStartedAt.remove(id);
      return gone;
    });

    // Loudest first among those who have talked long enough. Talking time
    // runs to when they were last heard, so a cough never adds up to a turn.
    final talkers = _talkStartedAt.entries
        .where((e) =>
            _lastHeardAt[e.key]!.difference(e.value) >=
            SpotlightSpeakerTracker.qualifyAfter)
        .map((e) => e.key)
        .toList()
      ..sort((a, b) =>
          (speakingLevels[b] ?? 0).compareTo(speakingLevels[a] ?? 0));
    for (final id in talkers) {
      _lastTurnAt[id] = now;
    }

    if (pageSize <= 0 || _order.length <= pageSize) return order;

    for (final id in talkers) {
      final from = _order.indexOf(id);
      if (from < pageSize) continue;
      final to = _slotToGiveUp(pageSize, now);
      if (to == null) break;
      _order[from] = _order[to];
      _order[to] = id;
      _movedInAt[id] = now;
    }
    return order;
  }

  /// The first-page slot whose tile should make room, or null if every tile
  /// there is talking or was only just moved in.
  int? _slotToGiveUp(int pageSize, DateTime now) {
    int? best;
    DateTime? bestTurn;
    for (var i = 0; i < pageSize; i++) {
      final id = _order[i];
      if (_lastHeardAt.containsKey(id)) continue;
      final movedIn = _movedInAt[id];
      if (movedIn != null &&
          now.difference(movedIn) < SpotlightSpeakerTracker.holdFor) {
        continue;
      }
      final turn = _lastTurnAt[id];
      // Never talked beats talked long ago; among equals the later slot goes,
      // so the top of the page changes least.
      final older = best == null ||
          (turn == null && bestTurn != null) ||
          (turn == null && bestTurn == null) ||
          (turn != null && bestTurn != null && !turn.isAfter(bestTurn));
      if (older) {
        best = i;
        bestTurn = turn;
      }
    }
    return best;
  }
}
