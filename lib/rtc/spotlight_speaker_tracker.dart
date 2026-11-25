/// Decides whose camera the Spotlight card shows, using the same rules as
/// web so every platform puts the same person on the card:
///
/// * Someone takes the card after talking for [qualifyAfter] (a cough or a
///   short "mm-hm" doesn't count).
/// * Pauses shorter than [pauseTolerance] don't restart that clock.
/// * After the card changes it stays put for at least [holdFor].
/// * The person on the card is never replaced while still talking. When they
///   stop, the loudest qualified talker takes over.
/// * In silence the last speaker stays.
/// * Before anyone has really talked, or when the person on the card leaves,
///   the card shows the first entry of the fallback order, and the first real
///   voice replaces that default straight away.
///
/// The tracker has no timers of its own. Call [update] whenever speaking
/// state changes and on a short regular tick while Spotlight is visible, so
/// time-based decisions (the 0.6 s and 3 s rules) happen without an event.
class SpotlightSpeakerTracker {
  SpotlightSpeakerTracker({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const qualifyAfter = Duration(milliseconds: 600);
  static const holdFor = Duration(seconds: 3);
  static const pauseTolerance = Duration(milliseconds: 500);

  final DateTime Function() _clock;

  /// When each person's current stretch of talking started.
  final Map<String, DateTime> _talkStartedAt = {};

  /// When each person was last heard.
  final Map<String, DateTime> _lastHeardAt = {};

  String? _current;
  DateTime? _changedAt;

  /// True while the card shows a fallback pick nobody earned by talking.
  bool _isDefault = true;

  /// Identity on the card, or null when there is nobody to show.
  String? get current => _current;

  /// Forget everything, for example when a new share starts.
  void reset() {
    _talkStartedAt.clear();
    _lastHeardAt.clear();
    _current = null;
    _changedAt = null;
    _isDefault = true;
  }

  /// [speakingLevels]: identity → audio level for everyone talking right now.
  /// [fallbackOrder]: everyone who can be shown, best default first (the
  /// presenter, then hosts and co-hosts, then you, then others by join time).
  /// Returns the identity to show.
  String? update({
    required Map<String, double> speakingLevels,
    required List<String> fallbackOrder,
  }) {
    final now = _clock();
    final present = fallbackOrder.toSet();

    // Track continuous talking, allowing short pauses.
    for (final id in speakingLevels.keys) {
      if (!present.contains(id)) continue;
      _talkStartedAt.putIfAbsent(id, () => now);
      _lastHeardAt[id] = now;
    }
    _lastHeardAt.removeWhere((id, heard) {
      final gone =
          !present.contains(id) || now.difference(heard) > pauseTolerance;
      if (gone) _talkStartedAt.remove(id);
      return gone;
    });

    bool stillTalking(String id) => _lastHeardAt.containsKey(id);

    // Loudest first among those who have talked long enough. Talking time
    // runs to when they were last heard, not to now, so a cough followed by
    // a short silence never adds up to a real turn.
    final qualified = _talkStartedAt.entries
        .where((e) => _lastHeardAt[e.key]!.difference(e.value) >= qualifyAfter)
        .map((e) => e.key)
        .toList()
      ..sort((a, b) =>
          (speakingLevels[b] ?? 0).compareTo(speakingLevels[a] ?? 0));

    void show(String? id, {required bool isDefault}) {
      if (id != _current) _changedAt = now;
      _current = id;
      _isDefault = isDefault;
    }

    // Nobody on the card, or they left: fall back.
    if (_current == null || !present.contains(_current)) {
      if (qualified.isNotEmpty) {
        show(qualified.first, isDefault: false);
      } else {
        show(fallbackOrder.isEmpty ? null : fallbackOrder.first,
            isDefault: true);
      }
      return _current;
    }

    final challengers = qualified.where((id) => id != _current).toList();
    if (challengers.isEmpty) {
      // The person on the card spoke for real: it is no longer a default.
      if (qualified.contains(_current)) _isDefault = false;
      return _current;
    }

    if (_isDefault) {
      // The first real voice replaces the default with no wait.
      show(challengers.first, isDefault: false);
    } else if (!stillTalking(_current!) &&
        now.difference(_changedAt!) >= holdFor) {
      show(challengers.first, isDefault: false);
    }
    return _current;
  }
}
