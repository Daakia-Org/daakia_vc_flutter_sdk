import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The three participant controls Workshop mode flips at once.
enum WorkshopRestriction { mic, camera, participantList }

/// Who the notice is being shown to. The same state reads differently
/// depending on where you sit relative to the toggle.
enum WorkshopAudience {
  /// Whoever flipped the switch — they need to see what they just did to the
  /// room, phrased as their own action.
  host,

  /// A host or co-host who *didn't* flip it. Exempt from the restrictions, so
  /// this is purely "here's what changed for everyone else".
  moderator,

  /// Everyone the restrictions actually apply to.
  participant,
}

/// What a Workshop-mode notice is about.
///
/// When [enabled] is true this is a live picture of what's currently locked
/// down: the three flags are the restrictions **in force right now**, and the
/// dialog lists exactly those. Re-allowing a control drops it from the list
/// rather than announcing it — the notice only ever says what's taken away.
///
/// When [enabled] is false the notice is the host's own "mode switched off"
/// confirmation, and the flags carry what was lifted so the copy can name it.
/// That case shows no badges; there are no restrictions left to list.
class WorkshopModeNotice {
  const WorkshopModeNotice({
    required this.enabled,
    required this.audience,
    this.micLocked = false,
    this.cameraLocked = false,
    this.participantListHidden = false,
    this.actorName,
  });

  final bool enabled;
  final WorkshopAudience audience;
  final bool micLocked;
  final bool cameraLocked;
  final bool participantListHidden;

  /// Who made the change, when the notice is about somebody else's action.
  /// Naming them beats "the host" — a co-host can flip this switch too.
  final String? actorName;

  List<WorkshopRestriction> get restrictions => [
        if (micLocked) WorkshopRestriction.mic,
        if (cameraLocked) WorkshopRestriction.camera,
        if (participantListHidden) WorkshopRestriction.participantList,
      ];

  /// Whether Workshop mode itself is in force. Only the mic and camera locks
  /// count: hiding the participant list is a host control in its own right
  /// that the Workshop switch happens to flip too, so on its own it isn't
  /// worth a dialog — it's only worth mentioning alongside the real ones.
  bool get isWorkshopActive => micLocked || cameraLocked;
}

/// Shows the Workshop-mode summary dialog.
///
/// [updates] lets an already-visible dialog be rewritten as further changes
/// arrive, and [onDialogContext] hands back its context so it can be popped
/// again — see [WorkshopModeNoticeController], which needs both because the
/// host's changes reach everyone else as a stream of separate data messages.
Future<void> showWorkshopModeDialog(
  BuildContext context, {
  required WorkshopModeNotice notice,
  ValueListenable<WorkshopModeNotice>? updates,
  ValueChanged<BuildContext>? onDialogContext,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      onDialogContext?.call(ctx);
      if (updates == null) return _WorkshopModeDialog(notice: notice);
      return ValueListenableBuilder<WorkshopModeNotice>(
        valueListenable: updates,
        builder: (_, value, _) => _WorkshopModeDialog(notice: value),
      );
    },
  );
}

/// Keeps a single, always-current Workshop-mode dialog on screen.
///
/// A host toggling Workshop mode fires three independent API calls, so the
/// change reaches everyone else as separate actions a few hundred milliseconds
/// apart, and a host fiddling with the individual switches keeps producing
/// more. Every report is the full current picture rather than a delta, which
/// makes the rules simple:
///
///  * reports are buffered for [groupingWindow], so one intentional change
///    shows up as one dialog instead of three;
///  * while a dialog is on screen it is rewritten in place — a control that
///    gets re-allowed just drops off the list, and nothing ever stacks;
///  * once the mic and camera are both back the dialog has nothing left to
///    say, so it closes itself — a still-hidden participant list doesn't keep
///    it alive.
///
/// Deriving all of this from the actions themselves (instead of a new
/// "workshop toggled" message) keeps it working when the host is on the web
/// client.
class WorkshopModeNoticeController {
  WorkshopModeNoticeController({
    this.groupingWindow = const Duration(milliseconds: 1200),
  });

  final Duration groupingWindow;

  Timer? _timer;
  WorkshopModeNotice? _pending;

  /// Non-null while a notice dialog is on screen.
  ValueNotifier<WorkshopModeNotice>? _live;

  /// The on-screen dialog's own context, so it can be popped from here.
  BuildContext? _dialogContext;

  /// Reports the restrictions in force right now, after whatever just changed.
  /// A notice only exists while the mic or camera is locked; see
  /// [WorkshopModeNotice.isWorkshopActive].
  void report(
    BuildContext context, {
    required bool micLocked,
    required bool cameraLocked,
    required bool participantListHidden,
    required WorkshopAudience audience,
    String? actorName,
  }) {
    final notice = WorkshopModeNotice(
      enabled: true,
      audience: audience,
      actorName: actorName,
      micLocked: micLocked,
      cameraLocked: cameraLocked,
      participantListHidden: participantListHidden,
    );

    // Mic and camera are back, so Workshop mode is effectively off — even if
    // the participant list is still hidden, that alone isn't news.
    if (!notice.isWorkshopActive) {
      _timer?.cancel();
      _timer = null;
      _pending = null;
      _dismiss();
      return;
    }

    final live = _live;
    if (live != null) {
      live.value = notice;
      return;
    }

    _pending = notice;
    _timer?.cancel();
    _timer = Timer(groupingWindow, () => _flush(context));
  }

  void _flush(BuildContext context) {
    _timer?.cancel();
    _timer = null;

    final notice = _pending;
    _pending = null;
    if (notice == null || !notice.isWorkshopActive) return;
    if (!context.mounted) return;

    final live = ValueNotifier<WorkshopModeNotice>(notice);
    _live = live;
    showWorkshopModeDialog(
      context,
      notice: notice,
      updates: live,
      onDialogContext: (ctx) => _dialogContext = ctx,
    ).whenComplete(() {
      if (identical(_live, live)) {
        _live = null;
        _dialogContext = null;
      }
      live.dispose();
    });
  }

  void _dismiss() {
    final ctx = _dialogContext;
    _live = null;
    _dialogContext = null;
    if (ctx != null && ctx.mounted) Navigator.of(ctx).pop();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _live = null;
    _dialogContext = null;
  }
}

const _accentColor = Color(0xFF7B7BED);
const _accentTintColor = Color(0xFFECECF8);

class _WorkshopModeDialog extends StatelessWidget {
  const _WorkshopModeDialog({required this.notice});

  final WorkshopModeNotice notice;

  bool get _enabled => notice.enabled;

  @override
  Widget build(BuildContext context) {
    // Phones in landscape leave very little vertical room, so the card is
    // capped in both axes and its body scrolls instead of overflowing.
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height - media.viewInsets.vertical - 80;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 360, maxHeight: maxHeight),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Only the body scrolls, so the primary action stays on
                // screen on short viewports (a phone in landscape).
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          // Keeps the centred title clear of the close button
                          // in the corner now that no icon separates them.
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            _title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (_badges.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: _badges,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          _description,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: const Text('Got it',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, size: 20),
                color: Colors.black45,
                // Keeps the 48dp tap target while the icon stays small.
                constraints:
                    const BoxConstraints.tightFor(width: 44, height: 44),
                padding: EdgeInsets.zero,
                splashRadius: 22,
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Naming the mode only makes sense when more than one control is locked
  /// down. Whoever flipped the switch always sees it named, while anyone told
  /// about a single restriction gets that control named instead — the mode may
  /// well have been on already.
  String get _title {
    if (!_enabled) return 'Workshop Mode Disabled';

    final restrictions = notice.restrictions;
    final isParticipant = notice.audience == WorkshopAudience.participant;
    if (notice.audience != WorkshopAudience.host && restrictions.length == 1) {
      switch (restrictions.single) {
        case WorkshopRestriction.mic:
          return isParticipant ? 'Your Mic Is Off' : 'Participant Mics Off';
        case WorkshopRestriction.camera:
          return isParticipant
              ? 'Your Camera Is Off'
              : 'Participant Cameras Off';
        case WorkshopRestriction.participantList:
          return 'Participant List Hidden';
      }
    }
    return 'Workshop Mode Enabled';
  }

  /// One badge per control that is currently locked down. Re-allowing a
  /// control removes its badge — a notice never advertises what's *allowed*,
  /// only what's been taken away, so the "mode off" confirmation has none.
  List<Widget> get _badges {
    if (!_enabled) return const [];
    return [
      if (notice.micLocked)
        const _StatusBadge(icon: Icons.mic_off_outlined, label: 'Mic off'),
      if (notice.cameraLocked)
        const _StatusBadge(
            icon: Icons.videocam_off_outlined, label: 'Camera off'),
      if (notice.participantListHidden)
        const _StatusBadge(
            icon: Icons.person_off_outlined, label: 'List hidden'),
    ];
  }

  String get _description {
    switch (notice.audience) {
      case WorkshopAudience.host:
        return _hostDescription;
      case WorkshopAudience.moderator:
        return _moderatorDescription;
      case WorkshopAudience.participant:
        return _participantDescription;
    }
  }

  /// Whether the notice can attribute the change to somebody. Joining a
  /// meeting that's already in Workshop mode has nobody to name — there was no
  /// action to witness — so that copy describes the state instead.
  bool get _hasActor => (notice.actorName?.trim().isNotEmpty ?? false);

  String get _actor => notice.actorName!.trim();

  /// For whoever flipped the switch: a read-back of what they just did.
  String get _hostDescription {
    if (_enabled) {
      final effects = <String>[
        if (notice.micLocked) 'mics are off',
        if (notice.cameraLocked) 'cameras are off',
        if (notice.participantListHidden) 'the participant list is hidden',
      ];
      if (effects.isEmpty) {
        return 'Adjust participant mic, camera and participant list access '
            'anytime from Host controls.';
      }
      return 'For everyone except you and co-hosts, ${_joinPhrases(effects)}. '
          'Adjust anytime from Host controls.';
    }

    final effects = <String>[
      if (notice.micLocked) 'unmute themselves',
      if (notice.cameraLocked) 'turn their camera on',
      if (notice.participantListHidden) 'open the participant list',
    ];
    if (effects.isEmpty) {
      return 'Participant restrictions have been lifted. Turn Workshop mode '
          'back on anytime from Host controls.';
    }
    return 'Participants can now ${_joinPhrases(effects)}. Turn Workshop mode '
        'back on anytime from Host controls.';
  }

  /// For a host or co-host who didn't make the change: they're exempt, so this
  /// is about what everyone else is living with.
  String get _moderatorDescription {
    if (!_hasActor) {
      final state = <String>[
        if (notice.micLocked) 'mics are off',
        if (notice.cameraLocked) 'cameras are off',
        if (notice.participantListHidden) 'the participant list is hidden',
      ];
      if (state.isEmpty) return 'Workshop restrictions have been lifted.';
      return 'For everyone except hosts and co-hosts, ${_joinPhrases(state)}.';
    }

    final effects = <String>[
      if (notice.micLocked) 'turned off mics',
      if (notice.cameraLocked) 'turned off cameras',
      if (notice.participantListHidden) 'hidden the participant list',
    ];
    if (effects.isEmpty) return 'Workshop restrictions have been lifted.';
    return '$_actor has ${_joinPhrases(effects)} for everyone except hosts '
        'and co-hosts.';
  }

  String get _participantDescription {
    // Raising a hand is how a muted participant asks for the mic back, so
    // it's only worth suggesting when the mic is what was taken away.
    final tail = notice.micLocked
        ? 'Raise your hand if you need to speak.'
        : 'The host can restore access anytime.';

    if (!_hasActor) {
      final state = <String>[
        if (notice.micLocked) 'your mic is off',
        if (notice.cameraLocked) 'your camera is off',
        if (notice.participantListHidden) 'the participant list is hidden',
      ];
      if (state.isEmpty) return 'Workshop restrictions have been lifted.';
      return 'Workshop mode is on: ${_joinPhrases(state)}. $tail';
    }

    final effects = <String>[
      if (notice.micLocked) 'muted you',
      if (notice.cameraLocked) 'turned your camera off',
      if (notice.participantListHidden) 'hidden the participant list',
    ];
    if (effects.isEmpty) return 'Workshop restrictions have been lifted.';
    return '$_actor has ${_joinPhrases(effects)}. $tail';
  }

  /// "a", "a and b", "a, b and c".
  String _joinPhrases(List<String> phrases) {
    if (phrases.length == 1) return phrases.first;
    return '${phrases.sublist(0, phrases.length - 1).join(', ')} '
        'and ${phrases.last}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _accentTintColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _accentColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4B4B9E),
            ),
          ),
        ],
      ),
    );
  }
}
