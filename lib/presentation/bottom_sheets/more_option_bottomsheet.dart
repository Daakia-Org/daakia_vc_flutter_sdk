import 'package:daakia_vc_flutter_sdk/presentation/pages/chat_controller.dart';
import 'package:daakia_vc_flutter_sdk/presentation/pages/recording_consent_page.dart';
import 'package:daakia_vc_flutter_sdk/presentation/pages/webinar_controls.dart';
import 'package:daakia_vc_flutter_sdk/utils/rtc_ext.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';

import '../../model/action_model.dart';
import '../../service/daakia_meeting_service.dart';
import '../../resources/colors/color.dart';
import '../../utils/meeting_actions.dart';
import '../../utils/utils.dart';
import '../../viewmodel/rtc_viewmodel.dart';
import '../dialog/emoji_dialog.dart';
import '../pages/all_participant_page.dart';
import '../pages/permission_request_page.dart';
import '../pages/transcription_screen.dart';

class MoreOptionBottomSheet extends StatefulWidget {
  const MoreOptionBottomSheet({super.key});

  @override
  State<StatefulWidget> createState() {
    // TODO: implement createState
    return _MoreOptionState();
  }
}

class _MoreOptionState extends State<MoreOptionBottomSheet> {
  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<RtcViewmodel>(context);
    return Container(
      width: double.maxFinite,
      color: emptyVideoColor,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 25.0), // Margin bottom
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top View (like the handle in a bottom sheet)
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10.0, bottom: 30.0),
                  width: 50,
                  height: 5,
                  color: Colors.white,
                ),
              ),
              // Chats Section
              buildOption(context,
                  icon: Icons.message,
                  text: 'Chats',
                  isVisible: viewModel.meetingDetails.features!.isChatAllowed(),
                  setBadge: BadgeData(viewModel.getUnReadCount() +
                      viewModel.getUnreadCountPrivateChat()), onTap: () {
                Navigator.pop(context);
                showChatBottomSheet(viewModel);
              }),
              // Recording Section
              buildOption(context,
                  icon: Icons.fiber_manual_record,
                  // Replace with your recording icon
                  text: viewModel.isRecording
                      ? 'Stop Recording'
                      : 'Start Recording',
                  iconColor: viewModel.isRecording ? Colors.red : Colors.white,
                  isVisible: (viewModel.isHost() || viewModel.isCoHost()) &&
                      viewModel.meetingDetails.features!.isRecordingAllowed(),
                  isEnabled: !viewModel.isRecordingActionInProgress, onTap: () {
                Navigator.pop(context);
                if (viewModel.meetingDetails.features
                            ?.isRecordingConsentAllowed() ==
                        true &&
                    !viewModel.isRecording) {
                  showRecordingConsentPage();
                  viewModel.startRecordingConsentFlow();
                } else {
                  viewModel.isRecording
                      ? viewModel.stopRecording()
                      : viewModel.startRecording();
                }
              }),
              // Live Caption
              buildOption(context,
                  icon: Icons.closed_caption,
                  // Replace with your host control icon
                  text: 'Live Captions',
                  isVisible: viewModel.meetingDetails.features!
                          .isVoiceTranscriptionAllowed() &&
                      (viewModel.isHost() ||
                          viewModel.isCoHost() ||
                          viewModel.isTranscriptionLanguageSelected),
                  onTap: () async {
                Navigator.pop(context);
                showLiveCaptions(viewModel);
              }),
              // Host Controls
              buildOption(context,
                  icon: Icons.security, // Replace with your host control icon
                  text: 'Host Control',
                  isVisible: viewModel.isHost() || viewModel.isCoHost(), onTap: () {
                Navigator.pop(context);
                showWebinarControls();
              }),
              // Screen Share
              buildOption(context,
                  icon: Icons.screen_share,
                  // Replace with your screen share icon
                  text:
                      '${(viewModel.room.localParticipant?.isScreenShareEnabled() == true) ? "Stop" : "Start"} Screen Sharing',
                  isVisible: viewModel.meetingDetails.features!
                      .isScreenSharingAllowed(), onTap: () {
                Navigator.pop(context);
                if (viewModel.room.localParticipant?.isScreenShareEnabled() ==
                    true) {
                  _disableScreenShare(viewModel);
                } else {
                  _enableScreenShare(viewModel);
                }
              }),
              // Raise Hand
              buildOption(context,
                  icon: Icons.pan_tool, // Replace with your raise hand icon
                  text: viewModel.isMyHandRaised
                      ? 'Stop Raise Hand'
                      : 'Start Raise Hand',
                  isVisible: viewModel.meetingDetails.features!
                      .isRaiseHandAllowed(), onTap: () {
                viewModel.setMyHandRaised(!viewModel.isMyHandRaised);
                var raisedHand = viewModel.isMyHandRaised
                    ? MeetingActions.raiseHand
                    : MeetingActions.stopRaiseHand;
                viewModel.sendAction(ActionModel(action: raisedHand, timeStamp: DateTime.now().millisecondsSinceEpoch));
                Navigator.pop(context);
              }),
              // Reaction
              buildOption(context,
                  icon: Icons.emoji_emotions, // Replace with your reaction icon
                  text: 'Reaction',
                  isVisible: viewModel.meetingDetails.features!
                      .isReactionAllowed(), onTap: () {
                Navigator.pop(context);
                showEmojiDialog(viewModel);
              }),
              // Participants
              buildOption(
                context,
                icon: Icons.people,
                text: 'Participants',
                isVisible: viewModel.isHost() || viewModel.isCoHost() || !viewModel.isParticipantDrawerHidden,
                onTap: () {
                  showParticipantBottomSheet(viewModel);
                },
              ),
              buildOption(context,
                  icon: Icons.lock,
                  text: 'Permissions',
                  isVisible: viewModel.screenShareRequestCount > 0,
                  setBadge: BadgeData(viewModel.screenShareRequestCount), onTap: () {
                    Navigator.pop(context);
                    showPermissionBottomSheet(viewModel);
                  }),
              // Live Stream
              buildOption(
                context,
                icon: Icons.live_tv, // Replace with your live stream icon
                text: 'Live Stream',
                isVisible: false, //TODO::
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showParticipantBottomSheet(RtcViewmodel viewModel) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(); // This will dismiss the BottomSheet
    }
    viewModel.isParticipantPageOpen = true;
    Navigator.of(context).push(MaterialPageRoute<Null>(
        builder: (BuildContext context) {
          return const AllParticipantPage();
        },
        fullscreenDialog: true)).then((_) {
      viewModel.isParticipantPageOpen = false;
    });
  }

  void showEmojiDialog(RtcViewmodel viewModel) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(); // This will dismiss the BottomSheet
    }
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return EmojiDialog(
            viewModel,
          );
        });
  }

  void showChatBottomSheet(RtcViewmodel viewModel) {
    Navigator.of(context).push(MaterialPageRoute<Null>(
        builder: (BuildContext context) {
          return ChatController(
            viewModel: viewModel,
          );
        },
        fullscreenDialog: true));
  }

  void showRecordingConsentPage() {
    Navigator.of(context).push(MaterialPageRoute<Null>(
        builder: (BuildContext context) {
          return const RecordingConsentPage();
        },
        fullscreenDialog: true));
  }

  void showWebinarControls() {
    Navigator.of(context).push(MaterialPageRoute<Null>(
        builder: (BuildContext context) {
          return const WebinarControls();
        },
        fullscreenDialog: true));
  }

  void showLiveCaptions(RtcViewmodel viewModel) {
    Navigator.of(context).push(MaterialPageRoute<Null>(
        builder: (BuildContext context) {
          return TranscriptionScreen(viewModel);
        },
        fullscreenDialog: true));
  }

  void showPermissionBottomSheet(RtcViewmodel viewModel) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(); // This will dismiss the BottomSheet
    }
    Navigator.of(context).push(MaterialPageRoute<Null>(
        builder: (BuildContext context) {
          return const PermissionRequestPage();
        },
        fullscreenDialog: true));
  }

  void _enableScreenShare(RtcViewmodel viewModel) async {
    final participant = viewModel.room.localParticipant;

    if (viewModel.isScreenSharePermissionNeeded()) {
      final adminType = viewModel.getAdminType();
      final message = adminType == null
          ? "No Host or Co-Host available to approve screen sharing."
          : "Screen share request sent to the $adminType.";

      viewModel.sendMessageToUI(message);
      return;
    }

    viewModel.isScreenShareRequestAccepted = false;

    if (lkPlatformIsDesktop()) {
      try {
        final source = await showDialog<DesktopCapturerSource>(
          context: context,
          builder: (context) => ScreenSelectDialog(),
        );
        if (source == null) {
          if (kDebugMode) {
            print('cancelled screenshare');
          }
          return;
        }
        if (kDebugMode) {
          print('DesktopCapturerSource: ${source.id}');
        }
        var track = await LocalVideoTrack.createScreenShareTrack(
          ScreenShareCaptureOptions(
            sourceId: source.id,
            maxFrameRate: 15.0,
          ),
        );
        await participant?.publishVideoTrack(track);
      } catch (e) {
        if (kDebugMode) {
          print('could not publish video: $e');
        }
      }
      return;
    }

    if (lkPlatformIs(PlatformType.android)) {
      // Android specific
      bool hasCapturePermission = await Helper.requestCapturePermission();
      if (!hasCapturePermission) {
        return;
      }

      final androidVersion = await Utils.getAndroidVersion();
      if (androidVersion >= 34) {
        // On Android 14+ use DaakiaMeetingService (already running for the
        // meeting). Calling addMediaProjectionType() on the main thread is
        // synchronous, so the FGS type is registered before getDisplayMedia
        // is called — no race condition on rapid stop/start.
        await DaakiaMeetingService.startScreenShare();
      } else {
        requestBackgroundPermission([bool isRetry = false]) async {
          try {
            bool hasPermissions = await FlutterBackground.hasPermissions;
            var appName = await Utils.getAppName();
            if (!isRetry) {
              var androidConfig = FlutterBackgroundAndroidConfig(
                notificationTitle: 'Screen Sharing',
                notificationText: '$appName is sharing the screen.',
                notificationImportance: AndroidNotificationImportance.high,
              );
              hasPermissions = await FlutterBackground.initialize(
                  androidConfig: androidConfig);
            }
            if (hasPermissions &&
                !FlutterBackground.isBackgroundExecutionEnabled) {
              await FlutterBackground.enableBackgroundExecution();
            }
          } catch (e) {
            if (!isRetry) {
              return await Future<void>.delayed(const Duration(seconds: 1),
                  () => requestBackgroundPermission(true));
            }
            if (kDebugMode) {
              print('could not publish video: $e');
            }
          }
        }

        await requestBackgroundPermission();
      }
    }

    if (lkPlatformIs(PlatformType.iOS)) {
      try {
        await participant?.setScreenShareEnabled(true,
            captureScreenAudio: false,
            screenShareCaptureOptions: const ScreenShareCaptureOptions(
                useiOSBroadcastExtension: true));
        return;
      } catch (e) {
        if (kDebugMode) {
          print('could not publish screen share on iOS: $e');
        }
      }
      return;
    }

    if (lkPlatformIsWebMobile()) {
      if (mounted) {
        await context
            .showErrorDialog('Screen share is not supported on mobile web');
      }
      return;
    }

    await participant?.setScreenShareEnabled(true, captureScreenAudio: true);
  }

  void _disableScreenShare(RtcViewmodel viewModel) async {
    final participant = viewModel.room.localParticipant;
    await participant?.setScreenShareEnabled(false);
    viewModel
        .sendAction(ActionModel(action: MeetingActions.screenShareStopped));
    if (lkPlatformIs(PlatformType.android)) {
      final androidVersion = await Utils.getAndroidVersion();
      if (androidVersion >= 34) {
        await DaakiaMeetingService.stopScreenShare();
      } else {
        try {
          await FlutterBackground.disableBackgroundExecution();
        } catch (error) {
          if (kDebugMode) {
            print('error disabling screen share: $error');
          }
        }
      }
    }
  }
}

Widget buildOption(
  BuildContext context, {
  required IconData icon,
  Color iconColor = Colors.white,
  required String text,
  bool isVisible = true,
  bool isEnabled = true,
  Function? onTap,
  BadgeData? setBadge,
}) {
  return GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: () {
      if (isEnabled) {
        onTap?.call();
      }
    },
    child: Visibility(
      visible: isVisible,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          child: Row(
            children: [
              if (setBadge == null)
                Icon(icon, color: iconColor, size: 24)
              else
                Badge(
                  isLabelVisible: setBadge.unreadCount > 0,
                  label: Text(
                    setBadge.unreadCount.toString(),
                    style: const TextStyle(color: Colors.white),
                  ),
                  offset: const Offset(4, 4),
                  backgroundColor: Colors.red,
                  child: Icon(icon, color: iconColor, size: 24),
                ),
              const SizedBox(width: 10),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class BadgeData {
  int unreadCount;

  BadgeData(this.unreadCount);
}
