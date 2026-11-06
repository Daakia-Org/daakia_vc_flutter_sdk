import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../model/action_model.dart';
import '../../model/raised_hand.dart';
import '../../resources/colors/color.dart';
import '../../utils/meeting_actions.dart';
import '../../utils/participant_action_specs.dart';
import '../../utils/utils.dart';
import '../../viewmodel/rtc_viewmodel.dart';
import '../dialog/action_specs_dialog.dart';
import 'initials_circle.dart';

class RaisedHandParticipantWidget extends StatefulWidget {
  const RaisedHandParticipantWidget({required this.viewModel, super.key});

  final RtcViewmodel viewModel;

  @override
  State<RaisedHandParticipantWidget> createState() =>
      _RaisedHandParticipantWidgetState();
}

class _RaisedHandParticipantWidgetState
    extends State<RaisedHandParticipantWidget> {
  bool isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final raisedQueue = widget.viewModel.raisedHandQueue;

    // Only keep entries for participants still present in the room.
    // getParticipantNameOrNull returns null for stale/ghost identities.
    // The live Participant is resolved too — the actions menu needs it.
    final participantsByIdentity = {
      for (final track in widget.viewModel.getParticipantList())
        track.participant.identity: track.participant,
    };
    final raisedEntries = raisedQueue
        .map((e) {
          final name = widget.viewModel.getParticipantNameOrNull(e.identity);
          return name != null
              ? (e, name, participantsByIdentity[e.identity])
              : null;
        })
        .whereType<(RaisedHand, String, Participant?)>()
        .toList();

    if (raisedEntries.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    // A sliver: the participants page builds rows only as they scroll in.
    // The header keeps the collapse arrow the old expansion tile had.
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Raised Hands',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      // 🔹 Bulk actions (host/cohost only). Outside workshop mode
                      // the menu would hold nothing but "Lower all hands", so the
                      // direct button is kept for that case — no point making the
                      // host open a dialog to reach a single action.
                      if (widget.viewModel.isHost() ||
                          widget.viewModel.isCoHost())
                        widget.viewModel.isWebinarModeEnable
                            ? IconButton(
                                onPressed: () => _showBulkActions(context),
                                icon: const Icon(
                                  Icons.more_vert,
                                  color: Colors.white,
                                ),
                                iconSize: 22,
                                visualDensity: VisualDensity.compact,
                              )
                            : GestureDetector(
                                onTap: _lowerAllHands,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.redAccent),
                                  ),
                                  child: const Text(
                                    "Lower all",
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => isExpanded = !isExpanded),
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          SliverList.builder(
            itemCount: raisedEntries.length,
            itemBuilder: (context, index) {
              final (entry, name, participant) = raisedEntries[index];
              final isSelf = entry.identity == widget.viewModel.selfIdentity;

              return Container(
                width: double.maxFinite,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 5),
                child: Row(
                  children: [
                    InitialsCircle(
                      initials: Utils.getInitials(name),
                      size: 30,
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.0,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Your own raised hand carries no actions, so say
                          // which row is yours rather than leaving the host
                          // wondering why this one has no menu.
                          if (isSelf) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'You',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 🔹 Raised-hand visual badge (no click)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: handRaiseColor,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.front_hand,
                                color: handRaiseColor,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "${index + 1}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 🔹 Actions menu — hidden unless it would hold at
                        // least one action (never for your own hand, and only
                        // while the participant is still in the room).
                        if (participant != null &&
                            hasRaisedHandActions(
                              participant,
                              widget.viewModel,
                            )) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: () => _showParticipantActions(
                              context,
                              participant,
                              name,
                            ),
                            icon: const Icon(
                              Icons.more_vert,
                              color: Colors.white,
                            ),
                            iconSize: 20,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  void _lowerAllHands() {
    widget.viewModel.sendAction(
      ActionModel(action: MeetingActions.stopRaiseHandAll),
    );
    widget.viewModel.stopHandRaisedForAll();
  }

  /// Header menu: workshop-mode bulk grants for the people who raised their
  /// hand, plus "Lower all hands". Only shown in workshop mode — see the
  /// header for what replaces it otherwise.
  void _showBulkActions(BuildContext context) {
    showActionSpecsDialog(
      context: context,
      viewModel: widget.viewModel,
      buildActions: (dialogContext) => buildRaisedHandBulkActionSpecs(
        viewModel: widget.viewModel,
        onDismiss: () => Navigator.pop(dialogContext),
        onLowerAllHands: () {
          Navigator.pop(dialogContext);
          _lowerAllHands();
        },
      ),
    );
  }

  /// Row menu: the same actions for one raiser, plus removal. Lowering and
  /// removal both confirm first, so the menu is popped before either dialog
  /// opens — hence the captured navigator.
  void _showParticipantActions(
    BuildContext context,
    Participant participant,
    String name,
  ) {
    showActionSpecsDialog(
      context: context,
      viewModel: widget.viewModel,
      buildActions: (dialogContext) => buildRaisedHandActionSpecs(
        participant: participant,
        viewModel: widget.viewModel,
        onDismiss: () => Navigator.pop(dialogContext),
        onLowerHand: () async {
          final navigator = Navigator.of(dialogContext);
          navigator.pop();
          final confirm = await showLowerHandDialog(navigator.context, name);
          if (confirm == true) {
            widget.viewModel.lowerHand(participant.identity);
          }
        },
        onRemoveFromCall: () {
          final navigator = Navigator.of(dialogContext);
          navigator.pop();
          showRemoveParticipantConfirmDialog(
            navigator.context,
            participant,
            widget.viewModel,
          );
        },
      ),
    );
  }

  Future<bool?> showLowerHandDialog(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            "Lower Hand",
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            "Are you sure you want to lower $name's hand?",
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Lower", style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}
