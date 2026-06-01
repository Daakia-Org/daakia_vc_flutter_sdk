import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../events/rtc_events.dart';
import '../../model/action_model.dart';
import '../../presentation/pages/chat_controller.dart';
import '../../utils/meeting_actions.dart';
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
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
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
    final bool isRemote = !isSelf;

    final String? myMetadata = viewModel.room.localParticipant?.metadata;
    final String? targetMetadata = participant.metadata;

    final bool amIHost = Utils.isHost(myMetadata);
    final bool amICoHost = Utils.isCoHost(myMetadata);
    final bool isTargetHost = Utils.isHost(targetMetadata);
    final bool isTargetCoHost = Utils.isCoHost(targetMetadata);

    final bool micOn = participant.isMicrophoneEnabled();
    final bool cameraOn = participant.isCameraEnabled();
    final bool micPermGranted = Utils.isMicEnabled(participant.attributes);
    final bool videoPermGranted = Utils.isVideoEnabled(participant.attributes);
    final bool isPinned =
        viewModel.pinnedParticipantId == participant.identity;

    // ── Visibility guards (mirrors pariticipant_dialog_controls.dart logic) ──

    // Rename: self if self-edit allowed; remote if host/cohost + host-edit allowed
    final bool canRename = isSelf
        ? viewModel.meetingDetails.features?.isProfileEditBySelfAllowed() == true
        : (amIHost || amICoHost) &&
            viewModel.meetingDetails.features?.isProfileEditByHostAllowed() ==
                true;

    // Private message: remote only, feature-gated
    final bool canPrivateChat = isRemote &&
        viewModel.meetingDetails.features?.isPrivateChatAllowed() == true;

    // Mic direct control: remote, host/cohost; restricted to mute-only when
    // audio permission mode is active (same rule as the dialog)
    final bool showMicControl = isRemote &&
        (amIHost || amICoHost) &&
        (!viewModel.isAudioModeEnable || micOn);

    // Camera direct control: remote, host/cohost; restricted to turn-off-only
    // when video permission mode is active
    final bool showCameraControl = isRemote &&
        (amIHost || amICoHost) &&
        (!viewModel.isVideoModeEnable || cameraOn);

    // Allow / Revoke mic permission (workshop audio mode)
    final bool showMicPermission = isRemote &&
        viewModel.isAudioModeEnable &&
        !isTargetHost &&
        !isTargetCoHost &&
        (amIHost || amICoHost);

    // Allow / Revoke video permission (workshop video mode)
    final bool showVideoPermission = isRemote &&
        viewModel.isVideoModeEnable &&
        !isTargetHost &&
        !isTargetCoHost &&
        (amIHost || amICoHost);

    final String displayName = participant.name.isNotEmpty
        ? participant.name
        : participant.identity;
    final String roleLabel =
        isTargetHost ? 'Host' : (isTargetCoHost ? 'Co-Host' : '');

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
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
                        Text(
                          displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (roleLabel.isNotEmpty)
                          Text(
                            roleLabel,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
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

            _ActionTile(
              icon: Icons.edit_outlined,
              label: 'Rename',
              visible: canRename,
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(participant, viewModel);
              },
            ),
            _ActionTile(
              icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin,
              label: isPinned ? 'Unpin' : 'Pin to screen',
              visible: true,
              onTap: () {
                Navigator.pop(context);
                viewModel.pinnedParticipantId =
                    isPinned ? null : participant.identity;
                viewModel.sendEvent(SortParticipants());
              },
            ),
            _ActionTile(
              icon: Icons.chat_bubble_outline,
              label: 'Send private message',
              visible: canPrivateChat,
              onTap: () {
                Navigator.pop(context);
                viewModel.checkAndCreatePrivateChat(
                    participant.identity, participant.name);
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
            ),
            _ActionTile(
              icon: micOn ? Icons.mic_off : Icons.mic,
              label: micOn ? 'Mute Mic' : 'Ask To Unmute Mic',
              visible: showMicControl,
              onTap: () {
                Navigator.pop(context);
                viewModel.sendPrivateAction(
                  ActionModel(
                    action: micOn
                        ? MeetingActions.muteMic
                        : MeetingActions.askToUnmuteMic,
                  ),
                  participant.identity,
                );
              },
            ),
            _ActionTile(
              icon: cameraOn ? Icons.videocam_off : Icons.videocam,
              label: cameraOn ? 'Turn Off Camera' : 'Ask To Turn ON Camera',
              visible: showCameraControl,
              onTap: () {
                Navigator.pop(context);
                viewModel.sendPrivateAction(
                  ActionModel(
                    action: cameraOn
                        ? MeetingActions.muteCamera
                        : MeetingActions.askToUnmuteCamera,
                  ),
                  participant.identity,
                );
              },
            ),
            _ActionTile(
              icon: micPermGranted ? Icons.mic_off : Icons.mic,
              label: micPermGranted
                  ? 'Revoke Mic Permission'
                  : 'Allow Mic Permission',
              visible: showMicPermission,
              onTap: () {
                Navigator.pop(context);
                viewModel.updateAudioPermissionForParticipant(
                    participant.identity, !micPermGranted);
              },
            ),
            _ActionTile(
              icon: videoPermGranted ? Icons.videocam_off : Icons.videocam,
              label: videoPermGranted
                  ? 'Revoke Video Permission'
                  : 'Allow Video Permission',
              visible: showVideoPermission,
              onTap: () {
                Navigator.pop(context);
                viewModel.updateVideoPermissionForParticipant(
                    participant.identity, !videoPermGranted);
              },
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(Participant participant, RtcViewmodel viewModel) {
    final controller = TextEditingController(text: participant.name);
    // Use root context since the sheet is already dismissed at this point
    final ctx = Navigator.of(context, rootNavigator: false).context;
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Enter new name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                viewModel.updateParticipantName(
                    participant: participant.identity, newName: newName);
              }
              Navigator.pop(dialogCtx);
            },
            child: const Text('Save'),
          ),
        ],
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
