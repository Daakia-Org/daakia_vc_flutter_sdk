import 'package:daakia_vc_flutter_sdk/model/remote_activity_data.dart';
import 'package:daakia_vc_flutter_sdk/presentation/dialog/pariticipant_dialog_controls.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/initials_circle.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/role_pill.dart';
import 'package:daakia_vc_flutter_sdk/utils/participant_action_specs.dart';
import 'package:daakia_vc_flutter_sdk/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';

import '../../viewmodel/rtc_viewmodel.dart';

class ParticipantTile extends StatelessWidget {
  const ParticipantTile(
      {required this.participant,
      this.isForLobby = false,
      super.key,
      this.lobbyRequest,
      this.onDismissBottomSheet});

  final Participant? participant;
  final bool isForLobby;
  final RemoteActivityData? lobbyRequest;
  final VoidCallback? onDismissBottomSheet;

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<RtcViewmodel>(context);
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Initials Circle
          InitialsCircle(
              initials: Utils.getInitials(
                  isForLobby ? lobbyRequest?.displayName : participant?.name),
              onEdit: _canEditProfile(viewModel, participant, isForLobby)
                  ? () {
                      _showEditNameDialog(context, viewModel);
                    }
                  : null),
          const SizedBox(width: 10),
          // Name and Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        (isForLobby
                                ? lobbyRequest?.displayName
                                : participant?.name) ??
                            "Unknown",
                        // Replace with the participant's name
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isForLobby &&
                        participant?.identity ==
                            viewModel.room.localParticipant?.identity) ...[
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
                // Role and joined-time as chips rather than one text line:
                // "guest" is a separate flag from the meeting role, so a
                // promoted guest carries two labels and used to run off the
                // end of a single ellipsised line. Wrap lets the labels drop
                // to a second row instead of being clipped.
                if (!isForLobby)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          "${Utils.calculateMinutesSince(participant?.joinedAt)} mins",
                          style: const TextStyle(
                            color: Color(0xFFC4C1B8),
                            // Equivalent to the text color used
                            fontSize: 12,
                          ),
                        ),
                        ...buildRolePills(participant?.metadata),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Options Icons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Visibility(
                visible: isForLobby,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  iconSize: 25,
                  onPressed: () {
                    viewModel.acceptParticipant(
                        request: lobbyRequest, accept: false);
                  },
                ),
              ),
              Visibility(
                visible: isForLobby,
                child: IconButton(
                  icon: const Icon(Icons.check, color: Colors.white),
                  iconSize: 25,
                  onPressed: () {
                    viewModel.acceptParticipant(
                        request: lobbyRequest, accept: true);
                  },
                ),
              ),
              Visibility(
                visible: !isForLobby,
                child: IconButton(
                  icon: Icon(
                      participant?.isCameraEnabled() == true
                          ? Icons.videocam
                          : Icons.videocam_off,
                      color: Colors.white),
                  iconSize: 25,
                  onPressed: () {
                    // Handle video action
                  },
                ),
              ),
              Visibility(
                visible: !isForLobby,
                child: IconButton(
                  icon: Icon(
                      participant?.isMicrophoneEnabled() == true
                          ? Icons.mic
                          : Icons.mic_off,
                      color: Colors.white),
                  iconSize: 25,
                  onPressed: () {
                    // Handle mic action
                  },
                ),
              ),
              Visibility(
                visible: (!isForLobby &&
                    participant?.identity !=
                        viewModel.room.localParticipant?.identity),
                child: IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  iconSize: 25,
                  onPressed: () {
                    showParticipantDialog(context, viewModel);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void showParticipantDialog(BuildContext context, RtcViewmodel viewModel) {
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return ParticipantDialogControls(
            participant: participant as Participant,
            viewModel: viewModel,
            onDismissBottomSheet: () {
              if (onDismissBottomSheet != null) {
                onDismissBottomSheet!();
              }
            },
          );
        });
  }

  void _showEditNameDialog(BuildContext context, RtcViewmodel viewModel) {
    final participant = this.participant;
    if (participant == null) return;
    showParticipantRenameDialog(context, participant, viewModel,
        title: 'Edit Name');
  }

  bool _canEditProfile(
      RtcViewmodel viewModel, Participant? participant, bool isForLobby) {
    if (isForLobby) return false;

    final localId = viewModel.room.localParticipant?.identity;
    final isSelf = participant?.identity == localId;

    final features = viewModel.meetingDetails.features;

    if (isSelf) {
      return features?.isProfileEditBySelfAllowed() == true;
    } else if (viewModel.isHost() || viewModel.isCoHost()) {
      return features?.isProfileEditByHostAllowed() == true;
    }

    return false;
  }
}
