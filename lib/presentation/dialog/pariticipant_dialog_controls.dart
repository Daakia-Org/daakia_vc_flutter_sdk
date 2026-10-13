import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../model/action_model.dart';
import '../../utils/meeting_actions.dart';
import '../../utils/participant_action_specs.dart';
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
    final actions = buildParticipantActionSpecs(
      participant: widget.participant,
      viewModel: widget.viewModel,
      onDismiss: () => Navigator.pop(context),
      // No rename here: the participant row on this page already edits the
      // name from its initials avatar, so offering it again is duplicate.
      onRemoveFromCall: () {
        // Capture the navigator before popping — this dialog's context is
        // unmounted once it closes.
        final navigator = Navigator.of(context);
        navigator.pop();
        showRemoveParticipantConfirmDialog(
            navigator.context, widget.participant, widget.viewModel);
      },
      onOpenPrivateChat: () {
        // Capture navigator before closing anything — context becomes
        // invalid once the dialog is popped.
        final navigator = Navigator.of(context);
        navigator.pop(); // close this dialog
        if (widget.onDismissBottomSheet != null) {
          widget.onDismissBottomSheet!(); // close participant page
        }
        navigator.push(MaterialPageRoute<void>(
          builder: (_) => ChatController(
            identity: widget.participant.identity,
            name: widget.participant.name,
            viewModel: widget.viewModel,
          ),
          fullscreenDialog: true,
        ));
      },
      onAnnotationUnavailable: () => showAnnotationUnavailableDialog(context),
    );

    // In landscape the action list is taller than the screen, so the list
    // scrolls and the header (with its close button) stays put.
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
          horizontal: 40, vertical: isLandscape ? 12 : 24),
      // Keep the portrait width in landscape instead of spanning the screen.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          color: Colors.grey[900], // Replace with your color
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          widget.isForIndividual
                              ? widget.participant.name
                              : 'All participants',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final action in actions)
                          CustomTextItem(
                            icon: action.icon,
                            text: action.label,
                            onTap: action.onTap,
                            isVisible: widget.isForIndividual && action.visible,
                          ),
                        CustomTextItem(
                          icon: Icons.mic_off,
                          text: "Mute all",
                          onTap: () {
                            Navigator.pop(context);
                            widget.viewModel.sendAction(ActionModel(action: MeetingActions.muteMic));
                          },
                          isVisible: !widget.isForIndividual,
                        ),
                        CustomTextItem(
                          icon: Icons.videocam_off,
                          text: "Video off all",
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
              ],
            ),
          ),
        ),
      ),
    );
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
