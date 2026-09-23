import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../events/rtc_events.dart';
import '../model/action_model.dart';
import '../viewmodel/rtc_viewmodel.dart';
import 'meeting_actions.dart';
import 'utils.dart';

/// One row in a participant actions menu (quick-actions sheet, participant
/// dialog, ...).
class ParticipantActionSpec {
  final IconData icon;
  final String label;
  final bool visible;
  final VoidCallback onTap;

  const ParticipantActionSpec({
    required this.icon,
    required this.label,
    required this.visible,
    required this.onTap,
  });
}

/// Canonical list of per-participant actions (rename, pin, private message,
/// mic/camera control, permissions, co-host, remove...) shared by every
/// surface that shows individual participant controls. Add new
/// individual-participant actions here once so every surface picks them up —
/// do not re-implement this logic per surface.
///
/// [onDismiss] closes the caller's menu/sheet before a simple viewmodel
/// action runs. [onRename] and [onOpenPrivateChat] are left to the caller
/// because they need to dismiss the menu and then open another dialog/route,
/// and the correct sequencing differs depending on what else the caller's
/// screen needs to close first.
///
/// [onRename] is optional: pass null on surfaces that already expose their
/// own rename affordance (the all-participants list edits the name straight
/// from the initials avatar) so the action isn't offered twice.
List<ParticipantActionSpec> buildParticipantActionSpecs({
  required Participant participant,
  required RtcViewmodel viewModel,
  required VoidCallback onDismiss,
  VoidCallback? onRename,
  required VoidCallback onRemoveFromCall,
  required VoidCallback onOpenPrivateChat,
  required VoidCallback onAnnotationUnavailable,
}) {
  final String? myMetadata = viewModel.room.localParticipant?.metadata;
  final String? targetMetadata = participant.metadata;

  final bool amIHost = Utils.isHost(myMetadata);
  final bool amICoHost = Utils.isCoHost(myMetadata);
  final bool isTargetHost = Utils.isHost(targetMetadata);
  final bool isTargetCoHost = Utils.isCoHost(targetMetadata);
  final bool isTargetGuest = !isTargetHost && !isTargetCoHost;

  final bool isSelf =
      participant.identity == viewModel.room.localParticipant?.identity;
  final bool isRemote = !isSelf;

  final bool micOn = participant.isMicrophoneEnabled();
  final bool cameraOn = participant.isCameraEnabled();
  final bool annotationPermGranted =
      Utils.isAnnotationAllowed(participant.attributes);
  final bool targetIsOnMobile = Utils.isMobilePlatform(participant.metadata);
  final bool isPinned = viewModel.pinnedParticipantId == participant.identity;

  bool canToggleCoHost() {
    // Host can never be demoted/promoted from this menu.
    if (isTargetHost) return false;

    // Host or co-host can demote an existing co-host.
    if ((amIHost || amICoHost) && isTargetCoHost) return true;

    // Host or co-host can promote a guest, subject to the multi-co-host
    // feature flag / current co-host count.
    if ((amIHost || amICoHost) && isTargetGuest) {
      final allowMultiple =
          viewModel.meetingDetails.features?.isAllowMultipleCoHost() == true;
      return allowMultiple || viewModel.coHostCount < 1;
    }

    return false;
  }

  // Order matches the web client's participant actions menu, agreed with
  // the web team, so hosts see the same layout on every platform. Mic/camera
  // direct control have no web equivalent (web only exposes the permission
  // toggles here) so they're placed right next to their matching permission
  // action.
  return [
    micPermissionSpec(participant, viewModel, onDismiss),
    ParticipantActionSpec(
      icon: micOn ? Icons.mic_off : Icons.mic,
      label: micOn ? 'Mute mic' : 'Ask to unmute mic',
      visible: isRemote &&
          (amIHost || amICoHost) &&
          (!viewModel.isAudioModeEnable || micOn),
      onTap: () {
        onDismiss();
        viewModel.sendPrivateAction(
          ActionModel(
            action:
                micOn ? MeetingActions.muteMic : MeetingActions.askToUnmuteMic,
          ),
          participant.identity,
        );
      },
    ),
    videoPermissionSpec(participant, viewModel, onDismiss),
    ParticipantActionSpec(
      icon: cameraOn ? Icons.videocam_off : Icons.videocam,
      label: cameraOn ? 'Turn off camera' : 'Ask to turn on camera',
      visible: isRemote &&
          (amIHost || amICoHost) &&
          (!viewModel.isVideoModeEnable || cameraOn),
      onTap: () {
        onDismiss();
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
    ParticipantActionSpec(
      icon: annotationPermGranted ? Icons.draw : Icons.draw_outlined,
      label: annotationPermGranted
          ? 'Revoke annotation permission'
          : 'Allow to annotate',
      visible: isRemote &&
          viewModel.isAnnotationEnabled &&
          !isTargetHost &&
          !isTargetCoHost &&
          (amIHost || amICoHost),
      onTap: () {
        onDismiss();
        if (targetIsOnMobile) {
          onAnnotationUnavailable();
          return;
        }
        viewModel.updateAnnotationPermissionForParticipant(
            participant.identity, !annotationPermGranted);
      },
    ),
    ParticipantActionSpec(
      icon: Icons.edit_outlined,
      label: 'Rename',
      visible: onRename != null &&
          (isSelf
              ? viewModel.meetingDetails.features
                      ?.isProfileEditBySelfAllowed() ==
                  true
              : (amIHost || amICoHost) &&
                  viewModel.meetingDetails.features
                          ?.isProfileEditByHostAllowed() ==
                      true),
      onTap: onRename ?? () {},
    ),
    ParticipantActionSpec(
      icon:
          isTargetCoHost ? Icons.remove_moderator : Icons.admin_panel_settings,
      label: isTargetCoHost ? 'Remove co-host' : 'Make co-host',
      visible: isRemote && canToggleCoHost(),
      onTap: () {
        onDismiss();
        viewModel.makeCoHost(participant.identity, !isTargetCoHost);
      },
    ),
    lowerHandSpec(participant, viewModel, onDismiss),
    ParticipantActionSpec(
      icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin,
      label: isPinned ? 'Unpin' : 'Pin to screen',
      visible: true,
      onTap: () {
        onDismiss();
        viewModel.pinnedParticipantId =
            isPinned ? null : participant.identity;
        viewModel.sendEvent(SortParticipants());
      },
    ),
    removeFromCallSpec(participant, viewModel, onRemoveFromCall),
    ParticipantActionSpec(
      icon: Icons.chat_bubble_outline,
      label: 'Send private message',
      visible: isRemote &&
          viewModel.meetingDetails.features?.isPrivateChatAllowed() == true,
      onTap: () {
        viewModel.checkAndCreatePrivateChat(
            participant.identity, participant.name);
        viewModel.setPrivateChatIdentity(participant.identity);
        viewModel.setPrivateChatUserName(participant.name);
        onOpenPrivateChat();
      },
    ),
  ];
}

// ── Specs shared with the raised-hands section ───────────────────────────────
// Pulled out of [buildParticipantActionSpecs] so the raised-hands menus can
// offer the same actions under the same role/mode rules without dragging in
// the whole participant menu. Change a rule here and every surface follows.

/// True when the local participant may manage [participant]'s workshop-mode
/// media permissions: hosts and co-hosts may, but never for themselves and
/// never for another host/co-host.
bool _canManageMediaPermissions(
    Participant participant, RtcViewmodel viewModel) {
  final String? myMetadata = viewModel.room.localParticipant?.metadata;
  final bool isSelf =
      participant.identity == viewModel.room.localParticipant?.identity;
  return !isSelf &&
      (Utils.isHost(myMetadata) || Utils.isCoHost(myMetadata)) &&
      !Utils.isHost(participant.metadata) &&
      !Utils.isCoHost(participant.metadata);
}

/// Workshop-mode mic permission toggle. Only meaningful while audio mode is
/// on — outside workshop mode everyone already has mic permission.
ParticipantActionSpec micPermissionSpec(
  Participant participant,
  RtcViewmodel viewModel,
  VoidCallback onDismiss,
) {
  final bool granted = Utils.isMicEnabled(participant.attributes);
  return ParticipantActionSpec(
    icon: granted ? Icons.mic_off : Icons.mic,
    label: granted ? 'Revoke mic permission' : 'Allow mic permission',
    visible: viewModel.isAudioModeEnable &&
        _canManageMediaPermissions(participant, viewModel),
    onTap: () {
      onDismiss();
      viewModel.updateAudioPermissionForParticipant(
          participant.identity, !granted);
    },
  );
}

/// Workshop-mode video permission toggle, mirroring [micPermissionSpec].
ParticipantActionSpec videoPermissionSpec(
  Participant participant,
  RtcViewmodel viewModel,
  VoidCallback onDismiss,
) {
  final bool granted = Utils.isVideoEnabled(participant.attributes);
  return ParticipantActionSpec(
    icon: granted ? Icons.videocam_off : Icons.videocam,
    label: granted ? 'Revoke video permission' : 'Allow video permission',
    visible: viewModel.isVideoModeEnable &&
        _canManageMediaPermissions(participant, viewModel),
    onTap: () {
      onDismiss();
      viewModel.updateVideoPermissionForParticipant(
          participant.identity, !granted);
    },
  );
}

/// Lowers [participant]'s raised hand. [onTap] overrides the default
/// dismiss-then-lower for surfaces that confirm first.
ParticipantActionSpec lowerHandSpec(
  Participant participant,
  RtcViewmodel viewModel,
  VoidCallback onDismiss, {
  VoidCallback? onTap,
}) {
  final String? myMetadata = viewModel.room.localParticipant?.metadata;
  final bool isSelf =
      participant.identity == viewModel.room.localParticipant?.identity;
  final bool isHandRaised = viewModel.raisedHandQueue
      .any((raisedHand) => raisedHand.identity == participant.identity);
  return ParticipantActionSpec(
    icon: Icons.front_hand_outlined,
    label: 'Lower hand',
    visible: !isSelf &&
        isHandRaised &&
        (Utils.isHost(myMetadata) || Utils.isCoHost(myMetadata)) &&
        viewModel.meetingDetails.features?.isRaiseHandAllowed() == true,
    onTap: onTap ??
        () {
          onDismiss();
          viewModel.lowerHand(participant.identity);
        },
  );
}

/// Removes [participant] from the call. Removal is immediate and can't be
/// undone, so [onRemoveFromCall] is expected to confirm first via
/// [showRemoveParticipantConfirmDialog].
ParticipantActionSpec removeFromCallSpec(
  Participant participant,
  RtcViewmodel viewModel,
  VoidCallback onRemoveFromCall,
) {
  final String? myMetadata = viewModel.room.localParticipant?.metadata;
  final bool isSelf =
      participant.identity == viewModel.room.localParticipant?.identity;
  final bool amIHost = Utils.isHost(myMetadata);
  final bool amICoHost = Utils.isCoHost(myMetadata);
  return ParticipantActionSpec(
    icon: Icons.person_remove,
    label: 'Remove from call',
    visible: !isSelf &&
        (amIHost || (amICoHost && !Utils.isHost(participant.metadata))),
    onTap: onRemoveFromCall,
  );
}

// ── Raised-hands menus ───────────────────────────────────────────────────────

/// Actions for a single entry in the raised-hands list. Deliberately a subset
/// of [buildParticipantActionSpecs]: a host manages the raised hand itself,
/// the raiser's workshop-mode media permissions, and — role permitting —
/// removal. Outside workshop mode only "Lower hand" (and removal) remain.
///
/// [onLowerHand] and [onRemoveFromCall] are the caller's, because both
/// confirm before acting and the caller owns the dismiss sequencing.
List<ParticipantActionSpec> buildRaisedHandActionSpecs({
  required Participant participant,
  required RtcViewmodel viewModel,
  required VoidCallback onDismiss,
  required VoidCallback onLowerHand,
  required VoidCallback onRemoveFromCall,
}) {
  return [
    micPermissionSpec(participant, viewModel, onDismiss),
    videoPermissionSpec(participant, viewModel, onDismiss),
    lowerHandSpec(participant, viewModel, onDismiss, onTap: onLowerHand),
    removeFromCallSpec(participant, viewModel, onRemoveFromCall),
  ];
}

/// Whether [participant]'s raised-hand menu would offer anything at all.
/// Every action is role- and mode-gated, so a menu can come up empty — most
/// obviously on your own raised hand, where nothing applies. Callers use this
/// to hide the menu button instead of opening an empty dialog.
bool hasRaisedHandActions(Participant participant, RtcViewmodel viewModel) {
  return buildRaisedHandActionSpecs(
    participant: participant,
    viewModel: viewModel,
    onDismiss: () {},
    onLowerHand: () {},
    onRemoveFromCall: () {},
  ).any((action) => action.visible);
}

/// Actions for the raised-hands section header. The bulk media grants apply
/// only to the people currently in the raised-hand queue and only make sense
/// in workshop mode, so outside it the menu is just "Lower all hands".
List<ParticipantActionSpec> buildRaisedHandBulkActionSpecs({
  required RtcViewmodel viewModel,
  required VoidCallback onDismiss,
  required VoidCallback onLowerAllHands,
}) {
  final String? myMetadata = viewModel.room.localParticipant?.metadata;
  final bool canManage =
      Utils.isHost(myMetadata) || Utils.isCoHost(myMetadata);

  return [
    ParticipantActionSpec(
      icon: Icons.mic,
      label: 'Allow mic for all',
      visible: canManage && viewModel.isAudioModeEnable,
      onTap: () {
        onDismiss();
        viewModel.allowMicForRaisedHands();
      },
    ),
    ParticipantActionSpec(
      icon: Icons.videocam,
      label: 'Allow video for all',
      visible: canManage && viewModel.isVideoModeEnable,
      onTap: () {
        onDismiss();
        viewModel.allowVideoForRaisedHands();
      },
    ),
    ParticipantActionSpec(
      icon: Icons.front_hand_outlined,
      label: 'Lower all hands',
      visible: canManage,
      onTap: onLowerAllHands,
    ),
  ];
}

/// Shared "Rename participant" dialog, used by every surface that exposes
/// the Rename action from [buildParticipantActionSpecs].
void showParticipantRenameDialog(
  BuildContext context,
  Participant participant,
  RtcViewmodel viewModel, {
  String title = 'Rename',
}) {
  showDialog(
    context: context,
    builder: (_) => _RenameDialog(
      title: title,
      initialName: participant.name,
      onSave: (newName) => viewModel.updateParticipantName(
          participant: participant.identity, newName: newName),
    ),
  );
}

class _RenameDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final ValueChanged<String> onSave;

  const _RenameDialog({
    required this.title,
    required this.initialName,
    required this.onSave,
  });

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final newName = _controller.text.trim();
    if (newName.isNotEmpty) widget.onSave(newName);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // Landscape leaves ~150dp above the keyboard, and the dialog scrolled the
    // field out of view, so you typed blind. Tighten it to field + buttons.
    // Only paddings change and the title is hidden rather than removed: a
    // changed tree would rebuild the field, drop focus and close the keyboard.
    final media = MediaQuery.of(context);
    final isCompact = media.orientation == Orientation.landscape &&
        media.viewInsets.bottom > 0;

    return AlertDialog(
      scrollable: true,
      insetPadding: isCompact
          ? const EdgeInsets.symmetric(horizontal: 40, vertical: 8)
          : null,
      titlePadding: isCompact ? EdgeInsets.zero : null,
      contentPadding:
          isCompact ? const EdgeInsets.fromLTRB(24, 8, 24, 0) : null,
      actionsPadding:
          isCompact ? const EdgeInsets.fromLTRB(16, 0, 16, 4) : null,
      title: Visibility(visible: !isCompact, child: Text(widget.title)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onTapOutside: Utils.dismissKeyboardOnTapOutside,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: 'Enter new name',
          isDense: isCompact,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Shared "Remove from call" confirmation, used by every surface that
/// exposes the Remove action from [buildParticipantActionSpecs]. Removal is
/// immediate and irreversible, so the participant is named in the prompt to
/// make sure the host is removing the person they meant to.
void showRemoveParticipantConfirmDialog(
  BuildContext context,
  Participant participant,
  RtcViewmodel viewModel,
) {
  final displayName =
      participant.name.isNotEmpty ? participant.name : participant.identity;
  showDialog(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('Remove from call'),
      content: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Are you sure you want to remove '),
            TextSpan(
              text: displayName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const TextSpan(text: '?'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(dialogCtx);
            viewModel.removeFromCall(participant.identity);
          },
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
}

/// Shared "Annotation unavailable on mobile" dialog, used by every surface
/// that exposes the Annotation Permission action from
/// [buildParticipantActionSpecs].
void showAnnotationUnavailableDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: Color(0xFFECECF8),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.draw_outlined,
                  color: Color(0xFF7B7BED), size: 24),
            ),
            const SizedBox(height: 16),
            const Text(
              "Annotation Unavailable",
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              "This Participant is using a mobile device. Annotation is available only on desktop/laptop device.",
              style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B7BED),
                  foregroundColor: Colors.white,
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: const Text("Got it",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
