import 'package:daakia_vc_flutter_sdk/events/rtc_events.dart';
import 'package:daakia_vc_flutter_sdk/presentation/bottom_sheets/end_meeting_bottomsheet.dart';
import 'package:daakia_vc_flutter_sdk/utils/rtc_ext.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';

import '../../resources/colors/color.dart';
import '../../presentation/bottom_sheets/more_option_bottomsheet.dart';
import '../../viewmodel/rtc_viewmodel.dart';

class RtcControls extends StatefulWidget {
  final Room room;
  final LocalParticipant participant;

  const RtcControls(
    this.room,
    this.participant, {
    super.key,
  });

  @override
  State<StatefulWidget> createState() {
    return _RtcControlState();
  }
}

class _RtcControlState extends State<RtcControls> {
  CameraPosition position = CameraPosition.front;

  bool _speakerphoneOn = Hardware.instance.preferSpeakerOutput;

  LocalParticipant get participant => widget.participant;

  @override
  void initState() {
    super.initState();
    participant.addListener(_onChange);
    Hardware.instance.enumerateDevices().then(_loadDevices);
  }

  void _loadDevices(List<MediaDevice> devices) async {
    if (mounted) {
      setState(() {});
    }
  }

  void _onChange() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get isMuted => participant.isMuted;

  void _toggleCamera() async {
    final track = participant.videoTrackPublications.firstOrNull?.track;
    if (track == null) return;

    try {
      final newPosition = position.switched();
      await track.setCameraPosition(newPosition);
      setState(() {
        position = newPosition;
      });
    } catch (error) {
      if (kDebugMode) {
        print('could not restart track: $error');
      }
      return;
    }
  }

  void _setSpeakerphoneOn() {
    _speakerphoneOn = !_speakerphoneOn;
    Hardware.instance.setSpeakerphoneOn(_speakerphoneOn);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<RtcViewmodel>(context);
    return Container(
      color: transparentMaskColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            onPressed: Hardware.instance.canSwitchSpeakerphone
                ? _setSpeakerphoneOn
                : null,
            icon: Icon(
              _speakerphoneOn ? Icons.speaker_phone : Icons.phone_android,
              color: Colors.white.withValues(
                  alpha: Hardware.instance.canSwitchSpeakerphone ? 1.0 : 0.5),
            ),
            iconSize: 30,
          ),
          IconButton(
            onPressed: () {
              final isHostOrCoHost = viewModel.isHost() ||
                  viewModel.isCoHost();

              if (isHostOrCoHost || viewModel.isVideoPermissionEnable || viewModel.isVideoPermissionGranted) {
                participant.isCameraEnabled()
                    ? viewModel.disableVideo()
                    : viewModel.enableVideo();
              }
            },
            icon: Icon(
              participant.isCameraEnabled()
                  ? Icons.videocam
                  : Icons.videocam_off,
              color: Colors.white.withValues(alpha: viewModel.getCameraAlpha()),
            ),
            iconSize: 30,
          ),
          IconButton(
            onPressed: () {
              if (viewModel.isAudioInterrupted) return;
              final isHostOrCoHost = viewModel.isHost() ||
                  viewModel.isCoHost();

              if (isHostOrCoHost || viewModel.isAudioPermissionEnable || viewModel.isMicPermissionGranted) {
                participant.isMicrophoneEnabled()
                    ? viewModel.disableAudio()
                    : viewModel.enableAudio();
              }
            },
            icon: Icon(
              participant.isMicrophoneEnabled() ? Icons.mic : Icons.mic_off,
              color: Colors.white.withValues(alpha: viewModel.getMicAlpha()),
            ),
            iconSize: 30,
          ),
          IconButton(
            onPressed: () {
              if (participant.isCameraEnabled()) {
                _toggleCamera();
              }
            },
            icon: Icon(
              Icons.flip_camera_android,
              color: Colors.white
                  .withValues(alpha: participant.isCameraEnabled() ? 1 : 0.5),
            ),
            iconSize: 30,
          ),
          IconButton(
            onPressed: () {
              showMoreOptionBottomSheet();
            },
            icon: Badge(
              isLabelVisible: (viewModel.getUnReadCount() +
                      viewModel.getUnreadCountPrivateChat() + viewModel.screenShareRequestCount) >
                  0,
              label: Text(
                (viewModel.getUnReadCount() +
                        viewModel.getUnreadCountPrivateChat() + viewModel.screenShareRequestCount)
                    .toString(),
                style: const TextStyle(color: Colors.white),
              ),
              offset: const Offset(8, 8),
              backgroundColor: Colors.red,
              child: const Icon(
                Icons.more_horiz,
                color: Colors.white,
              ),
            ),
            iconSize: 30,
          ),
          IconButton(
            onPressed: () {
              if (viewModel.isHost() || viewModel.isCoHost()) {
                _endMeetingOptions(viewModel);
              } else {
                _onTapDisconnect(viewModel);
              }
            },
            icon: const Icon(
              Icons.call_end,
              color: Colors.redAccent,
            ),
            iconSize: 30,
          )
        ],
      ),
    );
  }

  void showMoreOptionBottomSheet() {
    showModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return const MoreOptionBottomSheet();
        });
  }

  void _onTapDisconnect(RtcViewmodel viewModel) async {
    if (!mounted) return;
    final result = await context.showDisconnectDialog();
    if (result == true) {
      viewModel.isMeetingEnded = true;
      viewModel.sendEvent(EndMeeting(reason: "clientInitiated"));
    }
  }

  void _endMeetingOptions(RtcViewmodel viewModel) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return EndMeetingBottomSheet(
          onEndCall: () {
            Navigator.pop(context); // Close the BottomSheet
            viewModel.endMeetingForAll();
          },
          onLeaveCall: () {
            Navigator.pop(context); // Close the BottomSheet
            viewModel.sendEvent(EndMeeting(reason: "clientInitiated"));
          },
        );
      },
    );
  }

  @override
  void dispose() {
    participant.removeListener(_onChange);
    super.dispose();
  }
}
