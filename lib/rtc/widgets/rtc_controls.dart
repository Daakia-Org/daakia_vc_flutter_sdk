import 'package:daakia_vc_flutter_sdk/events/rtc_events.dart';
import 'package:daakia_vc_flutter_sdk/presentation/bottom_sheets/end_meeting_bottomsheet.dart';
import 'package:daakia_vc_flutter_sdk/utils/rtc_ext.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
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

class _RtcControlState extends State<RtcControls> with WidgetsBindingObserver {
  CameraPosition position = CameraPosition.front;

  bool _speakerphoneOn = Hardware.instance.preferSpeakerOutput;

  PermissionStatus _micOsStatus = PermissionStatus.granted;
  PermissionStatus _cameraOsStatus = PermissionStatus.granted;

  LocalParticipant get participant => widget.participant;

  @override
  void initState() {
    super.initState();
    participant.addListener(_onChange);
    Hardware.instance.enumerateDevices().then(_loadDevices);
    WidgetsBinding.instance.addObserver(this);
    _checkOsPermissions();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check after user returns from Settings.
    if (state == AppLifecycleState.resumed) {
      _checkOsPermissions();
    }
  }

  Future<void> _checkOsPermissions() async {
    final mic = await Permission.microphone.status;
    final cam = await Permission.camera.status;
    if (mounted) {
      setState(() {
        _micOsStatus = mic;
        _cameraOsStatus = cam;
      });
    }
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

  bool get _isMicOsDenied =>
      _micOsStatus.isDenied || _micOsStatus.isPermanentlyDenied;

  bool get _isCameraOsDenied =>
      _cameraOsStatus.isDenied || _cameraOsStatus.isPermanentlyDenied;

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

  Future<void> _onMicPressed(RtcViewmodel viewModel) async {
    if (viewModel.isAudioInterrupted) return;

    // Check OS-level permission first — this is the most actionable issue.
    final status = await Permission.microphone.status;
    if (status.isPermanentlyDenied) {
      _showSettingsDialog('Microphone');
      return;
    }
    if (status.isDenied) {
      final result = await Permission.microphone.request();
      await _checkOsPermissions();
      if (!result.isGranted) return;
    } else {
      await _checkOsPermissions();
    }

    // Check meeting-level permission.
    final isHostOrCoHost = viewModel.isHost() || viewModel.isCoHost();
    final hasMeetingPermission = isHostOrCoHost ||
        viewModel.isAudioPermissionEnable ||
        viewModel.isMicPermissionGranted;

    if (!hasMeetingPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The host has not granted you microphone permission'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    participant.isMicrophoneEnabled()
        ? viewModel.disableAudio()
        : viewModel.enableAudio();
  }

  Future<void> _onCameraPressed(RtcViewmodel viewModel) async {
    // Check OS-level permission first.
    final status = await Permission.camera.status;
    if (status.isPermanentlyDenied) {
      _showSettingsDialog('Camera');
      return;
    }
    if (status.isDenied) {
      final result = await Permission.camera.request();
      await _checkOsPermissions();
      if (!result.isGranted) return;
    } else {
      await _checkOsPermissions();
    }

    // Check meeting-level permission.
    final isHostOrCoHost = viewModel.isHost() || viewModel.isCoHost();
    final hasMeetingPermission = isHostOrCoHost ||
        viewModel.isVideoPermissionEnable ||
        viewModel.isVideoPermissionGranted;

    if (!hasMeetingPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The host has not granted you camera permission'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    participant.isCameraEnabled()
        ? viewModel.disableVideo()
        : viewModel.enableVideo();
  }

  void _showSettingsDialog(String permissionType) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$permissionType Access Blocked'),
        content: Text(
          '$permissionType access is blocked by your device. '
          'Open Settings to allow this app to use your $permissionType.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.of(ctx).pop();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildMicButton(RtcViewmodel viewModel) {
    return _ControlButton(
      icon: participant.isMicrophoneEnabled() ? Icons.mic : Icons.mic_off,
      iconColor: _isMicOsDenied
          ? Colors.orange
          : Colors.white.withValues(alpha: viewModel.getMicAlpha()),
      showWarning: _isMicOsDenied,
      onPressed: () => _onMicPressed(viewModel),
    );
  }

  Widget _buildCameraButton(RtcViewmodel viewModel) {
    return _ControlButton(
      icon: participant.isCameraEnabled() ? Icons.videocam : Icons.videocam_off,
      iconColor: _isCameraOsDenied
          ? Colors.orange
          : Colors.white.withValues(alpha: viewModel.getCameraAlpha()),
      showWarning: _isCameraOsDenied,
      onPressed: () => _onCameraPressed(viewModel),
    );
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
          _buildCameraButton(viewModel),
          _buildMicButton(viewModel),
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
                      viewModel.getUnreadCountPrivateChat() +
                      viewModel.screenShareRequestCount) >
                  0,
              label: Text(
                (viewModel.getUnReadCount() +
                        viewModel.getUnreadCountPrivateChat() +
                        viewModel.screenShareRequestCount)
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
            Navigator.pop(context);
            viewModel.endMeetingForAll();
          },
          onLeaveCall: () {
            Navigator.pop(context);
            viewModel.sendEvent(EndMeeting(reason: "clientInitiated"));
          },
        );
      },
    );
  }

  @override
  void dispose() {
    participant.removeListener(_onChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final bool showWarning;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.iconColor,
    required this.showWarning,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: iconColor),
          iconSize: 30,
        ),
        if (showWarning)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.priority_high,
                  size: 10, color: Colors.white),
            ),
          ),
      ],
    );
  }
}
