import 'package:daakia_vc_flutter_sdk/events/rtc_events.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../model/action_model.dart';
import '../../utils/meeting_actions.dart';
import '../../utils/utils.dart';
import '../../viewmodel/rtc_viewmodel.dart';
import '../pages/chat_controller.dart';

class ParticipantDialogControls extends StatefulWidget {
  const ParticipantDialogControls(
      {required this.participant,
      required this.viewModel,
      this.isForIndividual = true,
      this.onDismissBottomSheet,
      super.key});

  final Participant participant;
  final bool isForIndividual;
  final RtcViewmodel viewModel;
  final VoidCallback? onDismissBottomSheet;

  @override
  State<StatefulWidget> createState() {
    return ParticipantDialogState();
  }
}

class ParticipantDialogState extends State<ParticipantDialogControls> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) => _buildDialog(context),
    );
  }

  Widget _buildDialog(BuildContext context) {
    String? myRoleMataData = widget.viewModel.room.localParticipant?.metadata;
    String? targetRoleMataData = widget.participant.metadata;
    final bool micOn = widget.participant.isMicrophoneEnabled();
    final bool cameraOn = widget.participant.isCameraEnabled();
    final bool micPermissionGranted = Utils.isMicEnabled(widget.participant.attributes);
    final bool videoPermissionGranted = Utils.isVideoEnabled(widget.participant.attributes);
    final bool isCoHost = Utils.isCoHost(widget.participant.metadata);
    final bool isPinned = widget.viewModel.pinnedParticipantId == widget.participant.identity;
    final bool annotationPermissionGranted = Utils.isAnnotationAllowed(widget.participant.attributes);
    final bool targetIsOnMobile = Utils.isMobilePlatform(widget.participant.metadata);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      backgroundColor: Colors.transparent,
      child: Card(
        color: Colors.grey[900], // Replace with your color
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomTextItem(
                icon: micOn ? Icons.mic_off : Icons.mic,
                text: micOn ? "Mute Mic" : "Ask To Unmute Mic",
                onTap: () {
                  Navigator.pop(context);
                  widget.viewModel.sendPrivateAction(
                      ActionModel(
                          action: micOn
                              ? MeetingActions.muteMic
                              : MeetingActions.askToUnmuteMic),
                      widget.participant.identity);
                },
                isVisible: (widget.isForIndividual &&
                    (!widget.viewModel.isAudioModeEnable || micOn) &&
                    (Utils.isHost(myRoleMataData) ||
                        Utils.isCoHost(myRoleMataData))),
              ),
              CustomTextItem(
                icon: cameraOn ? Icons.videocam_off : Icons.videocam,
                text: cameraOn ? "Turn Off Camera" : "Ask To Turn ON Camera",
                onTap: () {
                  Navigator.pop(context);
                  widget.viewModel.sendPrivateAction(
                      ActionModel(
                          action: cameraOn
                              ? MeetingActions.muteCamera
                              : MeetingActions.askToUnmuteCamera),
                      widget.participant.identity);
                },
                isVisible: (widget.isForIndividual &&
                    (!widget.viewModel.isVideoModeEnable || cameraOn) &&
                    (Utils.isHost(myRoleMataData) ||
                        Utils.isCoHost(myRoleMataData))),
              ),
              CustomTextItem(
                icon: micPermissionGranted ? Icons.mic_off : Icons.mic,
                text: micPermissionGranted
                    ? "Revoke Mic Permission"
                    : "Allow Mic Permission",
                onTap: () {
                  Navigator.pop(context);
                  widget.viewModel.updateAudioPermissionForParticipant(
                      widget.participant.identity, !micPermissionGranted);
                },
                isVisible: (widget.isForIndividual && widget.viewModel.isAudioModeEnable &&
                    (!Utils.isHost(targetRoleMataData) && !Utils.isCoHost(targetRoleMataData)) &&
                    (Utils.isHost(myRoleMataData) ||
                        Utils.isCoHost(myRoleMataData))),
              ),
              CustomTextItem(
                icon: videoPermissionGranted ? Icons.videocam_off : Icons.videocam,
                text: videoPermissionGranted
                    ? "Revoke Video Permission"
                    : "Allow Video Permission",
                onTap: () {
                  Navigator.pop(context);
                  widget.viewModel.updateVideoPermissionForParticipant(
                      widget.participant.identity, !videoPermissionGranted);
                },
                isVisible: (widget.isForIndividual && widget.viewModel.isVideoModeEnable &&
                    (!Utils.isHost(targetRoleMataData) && !Utils.isCoHost(targetRoleMataData)) &&
                    (Utils.isHost(myRoleMataData) ||
                        Utils.isCoHost(myRoleMataData))),
              ),
              CustomTextItem(
                icon: annotationPermissionGranted ? Icons.draw : Icons.draw_outlined,
                text: annotationPermissionGranted
                    ? "Revoke Annotation Permission"
                    : "Allow Annotation Permission",
                onTap: () {
                  Navigator.pop(context);
                  if (targetIsOnMobile) {
                    _showAnnotationUnavailableDialog(context);
                    return;
                  }
                  widget.viewModel.updateAnnotationPermissionForParticipant(
                      widget.participant.identity, !annotationPermissionGranted);
                },
                isVisible: widget.isForIndividual &&
                    widget.viewModel.isAnnotationEnabled &&
                    (!Utils.isHost(targetRoleMataData) && !Utils.isCoHost(targetRoleMataData)) &&
                    (Utils.isHost(myRoleMataData) || Utils.isCoHost(myRoleMataData)),
              ),
              CustomTextItem(
                icon: isCoHost ? Icons.remove_moderator : Icons.admin_panel_settings,
                text: isCoHost ? "Remove Co-Host" : "Make Co-Host",
                onTap: () {
                  Navigator.pop(context);
                  widget.viewModel.makeCoHost(widget.participant.identity, !isCoHost);
                },
                isVisible: (widget.isForIndividual && isCoHostButtonEnable()),
              ),
              CustomTextItem(
                icon: Icons.person_remove,
                text: "Remove From Call",
                onTap: () {
                  Navigator.pop(context);
                  widget.viewModel.removeFromCall(widget.participant.identity);
                },
                isVisible: (widget.isForIndividual &&
                    (Utils.isHost(myRoleMataData) ||
                        (Utils.isCoHost(myRoleMataData) &&
                            !Utils.isHost(targetRoleMataData)))),
              ),
              CustomTextItem(
                icon: Icons.chat_bubble_outline,
                text: "Send private message",
                onTap: () {
                  // Dismiss the ParticipantDialogControls
                  Navigator.of(context, rootNavigator: false).pop();
                  if (widget.onDismissBottomSheet != null) {
                    widget.onDismissBottomSheet!();
                  }
                  widget.viewModel.checkAndCreatePrivateChat(
                      widget.participant.identity, widget.participant.name);
                  showChatBottomSheet(widget.viewModel,
                      widget.participant.identity, widget.participant.name);
                },
                isVisible: widget.isForIndividual && (widget.viewModel.meetingDetails.features?.isPrivateChatAllowed() == true),
              ),
              CustomTextItem(
                icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                text: isPinned ? "Unpin" : "Pin to screen",
                onTap: () {
                  // Dismiss the ParticipantDialogControls
                  Navigator.of(context, rootNavigator: false).pop();
                  if (isPinned) {
                    widget.viewModel.pinnedParticipantId = null;
                  } else {
                    widget.viewModel.pinnedParticipantId = widget.participant.identity;
                  }
                  widget.viewModel.sendEvent(SortParticipants());
                },
                isVisible: widget.isForIndividual,
              ),
              CustomTextItem(
                icon: Icons.mic_off,
                text: "Mute All",
                onTap: () {
                  Navigator.pop(context);
                  widget.viewModel.sendAction(ActionModel(action: MeetingActions.muteMic));
                },
                isVisible: !widget.isForIndividual,
              ),
              CustomTextItem(
                icon: Icons.videocam_off,
                text: "Video Off All",
                onTap: () {
                  Navigator.pop(context);
                  widget.viewModel
                      .sendAction(ActionModel(action: MeetingActions.muteCamera));
                },
                isVisible: !widget.isForIndividual,
              ),
              // CustomTextItem(
              //   icon: Icons.front_hand_outlined,
              //   text: "Lower Hands All",
              //   onTap: () {
              //     Navigator.pop(context);
              //     widget.viewModel
              //         .sendAction(ActionModel(action: MeetingActions.stopRaiseHandAll));
              //     widget.viewModel.stopHandRaisedForAll();
              //   },
              //   isVisible: !widget.isForIndividual &&
              //       widget.viewModel.meetingDetails.features!
              //           .isRaiseHandAllowed(),
              // ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAnnotationUnavailableDialog(BuildContext context) {
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
                child: const Icon(Icons.draw_outlined, color: Color(0xFF7B7BED), size: 24),
              ),
              const SizedBox(height: 16),
              const Text(
                "Annotation Unavailable",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: const Text("Got it", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool isCoHostButtonEnable() {
    final String? myMetadata = widget.viewModel.room.localParticipant?.metadata;
    final String? targetMetadata = widget.participant.metadata;

    final bool amIHost = Utils.isHost(myMetadata);
    final bool amICoHost = Utils.isCoHost(myMetadata);

    final bool isTargetHost = Utils.isHost(targetMetadata);
    final bool isTargetCoHost = Utils.isCoHost(targetMetadata);
    final bool isTargetGuest = !isTargetHost && !isTargetCoHost;

    // ❌ Cannot modify the Host
    if (isTargetHost) return false;

    // ✅ Host or Co-Host can demote a Co-Host
    if ((amIHost || amICoHost) && isTargetCoHost) return true;

    // ✅ Host or Co-Host can promote a Guest to Co-Host
    if ((amIHost || amICoHost) && isTargetGuest) {
      final allowMultiple = widget.viewModel.meetingDetails.features?.isAllowMultipleCoHost() == true;
      if (allowMultiple) {
        return true;
      } else {
        return widget.viewModel.coHostCount < 1;
      }
    }

    // ❌ In all other cases
    return false;
  }

  void showChatBottomSheet(
      RtcViewmodel viewmodel, String identity, String name) {
    Navigator.of(context).push(MaterialPageRoute<Null>(
        builder: (BuildContext context) {
          return ChatController(
            identity: identity,
            name: name,
            viewModel: viewmodel,
          );
        },
        fullscreenDialog: true));
  }
}

class CustomTextItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isVisible;
  final VoidCallback onTap;

  const CustomTextItem({
    super.key,
    required this.icon,
    required this.text,
    required this.onTap,
    this.isVisible = true,
  });

  @override
  Widget build(BuildContext context) {
    return Visibility(
      visible: isVisible,
      child: TextButton(
        onPressed: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 16, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
