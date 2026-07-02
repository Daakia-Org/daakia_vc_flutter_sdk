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
List<ParticipantActionSpec> buildParticipantActionSpecs({
  required Participant participant,
  required RtcViewmodel viewModel,
  required VoidCallback onDismiss,
  required VoidCallback onRename,
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
  final bool micPermGranted = Utils.isMicEnabled(participant.attributes);
  final bool videoPermGranted = Utils.isVideoEnabled(participant.attributes);
  final bool annotationPermGranted =
      Utils.isAnnotationAllowed(participant.attributes);
  final bool targetIsOnMobile = Utils.isMobilePlatform(participant.metadata);
  final bool isPinned = viewModel.pinnedParticipantId == participant.identity;
  final bool isHandRaised = viewModel.raisedHandQueue
      .any((raisedHand) => raisedHand.identity == participant.identity);

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
    ParticipantActionSpec(
      icon: micPermGranted ? Icons.mic_off : Icons.mic,
      label:
          micPermGranted ? 'Revoke Mic Permission' : 'Allow Mic Permission',
      visible: isRemote &&
          viewModel.isAudioModeEnable &&
          !isTargetHost &&
          !isTargetCoHost &&
          (amIHost || amICoHost),
      onTap: () {
        onDismiss();
        viewModel.updateAudioPermissionForParticipant(
            participant.identity, !micPermGranted);
      },
    ),
    ParticipantActionSpec(
      icon: micOn ? Icons.mic_off : Icons.mic,
      label: micOn ? 'Mute Mic' : 'Ask To Unmute Mic',
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
    ParticipantActionSpec(
      icon: videoPermGranted ? Icons.videocam_off : Icons.videocam,
      label: videoPermGranted
          ? 'Revoke Video Permission'
          : 'Allow Video Permission',
      visible: isRemote &&
          viewModel.isVideoModeEnable &&
          !isTargetHost &&
          !isTargetCoHost &&
          (amIHost || amICoHost),
      onTap: () {
        onDismiss();
        viewModel.updateVideoPermissionForParticipant(
            participant.identity, !videoPermGranted);
      },
    ),
    ParticipantActionSpec(
      icon: cameraOn ? Icons.videocam_off : Icons.videocam,
      label: cameraOn ? 'Turn Off Camera' : 'Ask To Turn ON Camera',
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
          ? 'Revoke Annotation Permission'
          : 'Allow to Annotate',
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
      visible: isSelf
          ? viewModel.meetingDetails.features?.isProfileEditBySelfAllowed() ==
              true
          : (amIHost || amICoHost) &&
              viewModel.meetingDetails.features?.isProfileEditByHostAllowed() ==
                  true,
      onTap: onRename,
    ),
    ParticipantActionSpec(
      icon:
          isTargetCoHost ? Icons.remove_moderator : Icons.admin_panel_settings,
      label: isTargetCoHost ? 'Remove Co-Host' : 'Make Co-Host',
      visible: isRemote && canToggleCoHost(),
      onTap: () {
        onDismiss();
        viewModel.makeCoHost(participant.identity, !isTargetCoHost);
      },
    ),
    ParticipantActionSpec(
      icon: Icons.front_hand_outlined,
      label: 'Lower Hand',
      visible: isRemote &&
          isHandRaised &&
          (amIHost || amICoHost) &&
          viewModel.meetingDetails.features?.isRaiseHandAllowed() == true,
      onTap: () {
        onDismiss();
        viewModel.lowerHand(participant.identity);
      },
    ),
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
    ParticipantActionSpec(
      icon: Icons.person_remove,
      label: 'Remove From Call',
      visible: isRemote && (amIHost || (amICoHost && !isTargetHost)),
      onTap: () {
        onDismiss();
        viewModel.removeFromCall(participant.identity);
      },
    ),
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

/// Shared "Rename participant" dialog, used by every surface that exposes
/// the Rename action from [buildParticipantActionSpecs].
void showParticipantRenameDialog(
  BuildContext context,
  Participant participant,
  RtcViewmodel viewModel,
) {
  final controller = TextEditingController(text: participant.name);
  showDialog(
    context: context,
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
