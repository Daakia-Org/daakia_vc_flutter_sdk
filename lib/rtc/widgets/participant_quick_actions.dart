import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../presentation/pages/chat_controller.dart';
import '../../presentation/widgets/role_pill.dart';
import '../../utils/participant_action_specs.dart';
import '../../utils/utils.dart';
import '../../viewmodel/rtc_viewmodel.dart';

/// Shows a quick-action bottom sheet anchored to [participant].
/// The participant reference is captured at call time, so even if the tile
/// layout shuffles while the sheet is open, all actions operate on the
/// exact participant the host pressed.
void showParticipantQuickActions(
  BuildContext context,
  Participant participant,
  RtcViewmodel viewModel,
) {
  Utils.showAdaptiveSheet<void>(
    context,
    backgroundColor: Colors.transparent,
    forceFullHeight: true,
    // The identity header plus a role-dependent action list can outgrow a
    // landscape phone.
    scrollable: true,
    builder: (_) => ParticipantQuickActionsSheet(
      participant: participant,
      viewModel: viewModel,
      // Capture navigator now so navigation still works after the sheet
      // is dismissed (sheet context may already be unmounted by then).
      onNavigateTo: (route) => Navigator.of(context).push(route),
    ),
  );
}

class ParticipantQuickActionsSheet extends StatefulWidget {
  final Participant participant;
  final RtcViewmodel viewModel;
  final void Function(Route<dynamic>) onNavigateTo;

  const ParticipantQuickActionsSheet({
    super.key,
    required this.participant,
    required this.viewModel,
    required this.onNavigateTo,
  });

  @override
  State<ParticipantQuickActionsSheet> createState() =>
      _ParticipantQuickActionsSheetState();
}

class _ParticipantQuickActionsSheetState
    extends State<ParticipantQuickActionsSheet> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) => _buildSheet(context),
    );
  }

  Widget _buildSheet(BuildContext context) {
    final participant = widget.participant;
    final viewModel = widget.viewModel;

    final bool isSelf =
        participant.identity == viewModel.room.localParticipant?.identity;

    final actions = buildParticipantActionSpecs(
      participant: participant,
      viewModel: viewModel,
      onDismiss: () => Navigator.pop(context),
      onRename: () {
        Navigator.pop(context);
        // Use the root navigator's context: the sheet is already dismissed
        // at this point, so the builder's `context` param may be unmounted.
        showParticipantRenameDialog(
            Navigator.of(this.context, rootNavigator: false).context,
            participant,
            viewModel);
      },
      onRemoveFromCall: () {
        Navigator.pop(context);
        showRemoveParticipantConfirmDialog(
            Navigator.of(this.context, rootNavigator: false).context,
            participant,
            viewModel);
      },
      onMoveToLobby: () {
        Navigator.pop(context);
        showMoveToLobbyConfirmDialog(
            Navigator.of(this.context, rootNavigator: false).context,
            participant,
            viewModel);
      },
      onOpenPrivateChat: () {
        Navigator.pop(context);
        widget.onNavigateTo(
          MaterialPageRoute(
            builder: (_) => ChatController(
              identity: participant.identity,
              name: participant.name,
              viewModel: viewModel,
            ),
            fullscreenDialog: true,
          ),
        );
      },
      onAnnotationUnavailable: () => showAnnotationUnavailableDialog(
          Navigator.of(this.context, rootNavigator: false).context),
    );

    final String displayName = participant.name.isNotEmpty
        ? participant.name
        : participant.identity;
    // Every role the participant holds, not just the first that matches:
    // the guest flag is independent of the meeting role.
    final rolePills = buildRolePills(participant.metadata);

    return Material(
      color: const Color(0xFF1E1E1E),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Participant identity header ──────────────────────────────────
            // Shown prominently so the host can confirm the right person
            // even if tiles shifted while the sheet was opening.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.blueGrey[700],
                    child: Text(
                      displayName[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Surfaced explicitly so a host isn't confused
                            // about why fewer actions show up when they open
                            // this sheet on their own tile — most actions
                            // only apply to remote participants.
                            if (isSelf) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
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
                        if (rolePills.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: rolePills,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 4),

            // ── Actions ─────────────────────────────────────────────────────
            for (final action in actions)
              _ActionTile(
                icon: action.icon,
                label: action.label,
                visible: action.visible,
                onTap: action.onTap,
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Private list-tile item ───────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool visible;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.visible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return ListTile(
      dense: true,
      leading: Icon(icon, color: Colors.white, size: 22),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      onTap: onTap,
    );
  }
}
