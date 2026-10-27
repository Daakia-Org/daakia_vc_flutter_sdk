import 'dart:async';

import 'package:daakia_vc_flutter_sdk/utils/constants.dart';
import 'package:daakia_vc_flutter_sdk/utils/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

/// The room rules behind the "Still there?" prompt, shared with the web
/// client so a mixed web/mobile room agrees on who is idle and who is asked.
///
/// Every function here must stay in step with web's
/// `utils/inactiveMeetingLogic.js` and `hooks/useExtendMeetingLeader.js`: if
/// two clients elect differently, two people get the prompt, or nobody does.
class InactiveMeetingRules {
  InactiveMeetingRules._();

  /// Recorder, NoteTaker and AI agents. Ignored for head-count, for activity
  /// and when electing who gets the prompt.
  static bool isBot(Participant p) =>
      p.kind == ParticipantKind.AGENT ||
      p.identity.startsWith('agent-') ||
      p.name == 'NoteTaker' ||
      p.identity.contains('NoteTaker');

  static bool isRealHuman(Participant p) => !isBot(p);

  /// Mic on counts even when silent. Chat, hands, reactions and the like don't.
  static bool isActive(Participant p) =>
      p.isMicrophoneEnabled() ||
      p.isCameraEnabled() ||
      p.isScreenShareEnabled();

  static List<Participant> humans(Room room) {
    final local = room.localParticipant;
    return <Participant>[
      ?local,
      ...room.remoteParticipants.values,
    ].where(isRealHuman).toList();
  }

  /// An empty room is not idle: there is nobody to prompt.
  static bool isIdle(Room room) {
    final people = humans(room);
    return people.isNotEmpty && !people.any(isActive);
  }

  static bool isSolo(Room room) => humans(room).length == 1;

  /// Whether this device is the one participant that runs the idle clock.
  ///
  ///   host here               -> me, always
  ///   any host in the room    -> the earliest-joined host
  ///   else any co-host        -> the earliest-joined co-host
  ///   else                    -> the earliest-joined real human
  ///
  /// Ties on join time go to the smaller identity. Two devices on the same
  /// host account both answer yes; ending a meeting twice is harmless.
  static bool isWatcher(Room room) {
    final local = room.localParticipant;
    if (local == null) return false;
    if (Utils.isHost(local.metadata)) return true;

    final everyone = <Participant>[local, ...room.remoteParticipants.values];
    final hosts = everyone.where((p) => Utils.isHost(p.metadata)).toList();
    final coHosts = everyone.where((p) => Utils.isCoHost(p.metadata)).toList();
    final candidates = hosts.isNotEmpty
        ? hosts
        : coHosts.isNotEmpty
            ? coHosts
            : everyone.where(isRealHuman).toList();
    if (candidates.isEmpty) return false;

    candidates.sort((a, b) {
      final byJoin = a.joinedAt.compareTo(b.joinedAt);
      return byJoin != 0 ? byJoin : a.identity.compareTo(b.identity);
    });
    return candidates.first.identity == local.identity;
  }

  /// Hosts and co-hosts may end an idle group meeting; anyone else can only
  /// leave it.
  static bool canEndForAll(Room room) {
    final metadata = room.localParticipant?.metadata;
    return Utils.isHost(metadata) || Utils.isCoHost(metadata);
  }
}

/// Runs the idle clock on the watcher's device and says when to show or hide
/// the "Still there?" prompt.
///
/// Deliberately owns no UI, like [MeetingManager]: the meeting screen decides
/// how the prompt looks, whether it can show right now, and what happens when
/// its countdown runs out.
///
/// Everything is measured against the wall clock, never by counting ticks, so
/// a backgrounded app that had its timers paused catches up on the next check.
class InactiveMeetingWatcher {
  InactiveMeetingWatcher({
    required this.room,
    required this.timeout,
    required this.onShowPrompt,
    required this.onHidePrompt,
  });

  final Room room;

  /// Idle time before the prompt.
  final Duration timeout;

  /// Asks the screen to show the prompt. Returns false when it can't right now
  /// — the meeting-end warning is up — in which case a later check asks again.
  final bool Function() onShowPrompt;

  final VoidCallback onHidePrompt;

  /// Whether the prompt should read as the solo version. Kept live while the
  /// prompt is up: people leaving switch the text without restarting the
  /// countdown.
  final ValueNotifier<bool> solo = ValueNotifier(false);

  DateTime _lastActivityAt = DateTime.now();
  bool _promptShown = false;
  Timer? _checkTimer;
  EventsListener<RoomEvent>? _listener;

  bool get isRunning => _checkTimer != null;

  bool get isPromptShown => _promptShown;

  /// Starts a fresh idle clock. Safe to call while already running.
  void start() {
    if (isRunning) return;
    _lastActivityAt = DateTime.now();
    _promptShown = false;
    _checkTimer = Timer.periodic(
      const Duration(milliseconds: Constant.inactiveCheckIntervalMs),
      (_) => check(),
    );
    _listener = room.createListener()
      ..on<ActiveSpeakersChangedEvent>((event) {
        if (event.speakers.any(InactiveMeetingRules.isRealHuman)) {
          _onActivity();
        }
      })
      // Remote publishes only; our own camera, mic or screen share arrives as
      // LocalTrackPublishedEvent.
      ..on<TrackPublishedEvent>((event) {
        if (InactiveMeetingRules.isRealHuman(event.participant)) _onActivity();
      })
      ..on<LocalTrackPublishedEvent>((_) => _onActivity())
      ..on<TrackUnmutedEvent>((event) {
        if (InactiveMeetingRules.isRealHuman(event.participant)) _onActivity();
      })
      ..on<ParticipantConnectedEvent>((event) {
        if (InactiveMeetingRules.isRealHuman(event.participant)) _onJoin();
      })
      // Leaving is not activity. It only changes which text the prompt shows.
      ..on<ParticipantDisconnectedEvent>(
          (_) => solo.value = InactiveMeetingRules.isSolo(room));
  }

  /// Stops the clock, drops the listeners and takes the prompt down.
  void stop() {
    _checkTimer?.cancel();
    _checkTimer = null;
    unawaited(_listener?.dispose());
    _listener = null;
    _hide();
  }

  /// One idle check. Runs every [Constant.inactiveCheckIntervalMs], and right
  /// away when the app comes back to the foreground.
  void check() {
    if (!isRunning) return;
    // A recording or livestream is never interrupted.
    if (room.isRecording || !InactiveMeetingRules.isIdle(room)) {
      _lastActivityAt = DateTime.now();
      _hide();
      return;
    }
    if (DateTime.now().difference(_lastActivityAt) < timeout) return;
    solo.value = InactiveMeetingRules.isSolo(room);
    // Already up: leave its countdown running.
    if (_promptShown) return;
    _promptShown = onShowPrompt();
  }

  /// The person tapped Stay / Continue.
  void stay() {
    _lastActivityAt = DateTime.now();
    _hide();
  }

  /// The prompt was taken down by the screen itself (its countdown ran out on
  /// a room that turned out to be active, or a button acted on it).
  void promptClosed() {
    _promptShown = false;
  }

  void _onActivity() {
    _lastActivityAt = DateTime.now();
    _hide();
  }

  /// Someone joining restarts the clock but must not close a prompt that is
  /// already up — only its buttons or real activity do that.
  void _onJoin() {
    _lastActivityAt = DateTime.now();
  }

  void _hide() {
    if (!_promptShown) return;
    _promptShown = false;
    onHidePrompt();
  }

  void dispose() {
    stop();
    solo.dispose();
  }
}
