import 'dart:async';
import 'dart:convert';

import 'package:animated_emoji/emoji_data.dart';
import 'package:animated_emoji/emojis.g.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:daakia_vc_flutter_sdk/events/meeting_end_events.dart';
import 'package:daakia_vc_flutter_sdk/events/rtc_events.dart';
import 'package:daakia_vc_flutter_sdk/model/action_model.dart';
import 'package:daakia_vc_flutter_sdk/model/meeting_details.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/emoji_reaction_widget.dart';
import 'package:daakia_vc_flutter_sdk/rtc/lobby_request_manager.dart';
import 'package:daakia_vc_flutter_sdk/rtc/widgets/connectivity_banner.dart';
import 'package:daakia_vc_flutter_sdk/rtc/widgets/participant.dart';
import 'package:daakia_vc_flutter_sdk/rtc/widgets/participant_info.dart';
import 'package:daakia_vc_flutter_sdk/rtc/widgets/pip_screen.dart';
import 'package:daakia_vc_flutter_sdk/rtc/widgets/rtc_controls.dart';
import 'package:daakia_vc_flutter_sdk/rtc/widgets/white_board_widget.dart';
import 'package:daakia_vc_flutter_sdk/utils/constants.dart';
import 'package:daakia_vc_flutter_sdk/utils/datadog_disconnect_logger.dart';
import 'package:daakia_vc_flutter_sdk/utils/datadog_reconnect_logger.dart';
import 'package:daakia_vc_flutter_sdk/utils/rtc_ext.dart';
import 'package:daakia_vc_flutter_sdk/utils/storage_helper.dart';
import 'package:daakia_vc_flutter_sdk/viewmodel/rtc_provider.dart';
import 'package:daakia_vc_flutter_sdk/viewmodel/rtc_viewmodel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:simple_pip_mode/simple_pip.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../model/emoji_message.dart';
import '../model/remote_activity_data.dart';
import '../presentation/dialog/screen_share_request_dialog.dart';
import '../presentation/pages/transcription_screen.dart';
import '../utils/consent_status_enum.dart';
import '../utils/meeting_actions.dart';
import '../utils/utils.dart';
import 'meeting_manager.dart';
import 'method_channels/daakia_pip.dart';

class RoomPage extends StatefulWidget {
  final Room room;
  final EventsListener<RoomEvent> listener;
  final MeetingDetails meetingDetails;

  const RoomPage(
    this.room,
    this.listener,
    this.meetingDetails, {
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> with WidgetsBindingObserver {
  List<ParticipantTrack> participantTracks = [];

  EventsListener<RoomEvent> get _listener => widget.listener;

  bool get fastConnection => widget.room.engine.fastConnectOptions != null;
  bool _flagStartedReplayKit = false;

  bool _isInForeground = true;

  SimplePip? pip;
  bool _isInPipMode = false;

  bool _isProgrammaticPop = false; // Flag to track programmatic pop

  Timer? _configRecordingTimer;

  late final MeetingManager meetingManager;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    setState(() {
      _isInForeground = state == AppLifecycleState.resumed;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(statusBarColor: Colors.black));
    WakelockPlus.enable();
    if (lkPlatformIs(PlatformType.android)) {
      pip = SimplePip(onPipEntered: () {
        setState(() {
          _isInPipMode = true;
        });
      }, onPipExited: () {
        setState(() {
          _isInPipMode = false;
        });
      })
        ..setAutoPipMode(
            aspectRatio: (1, 1), seamlessResize: true, autoEnter: true);
    }
    isCheckedWhileJoining = false;
    player = AudioPlayer();
    // add callback for a `RoomEvent` as opposed to a `ParticipantEvent`
    widget.room.addListener(_onRoomDidUpdate);
    // add callbacks for finer grained events
    _setUpListeners();
    _sortParticipants();
    WidgetsBindingCompatible.instance?.addPostFrameCallback((_) {
      var viewModel = _livekitProviderKey.currentState?.viewModel;
      lobbyManager = LobbyRequestManager(context, viewModel);
      viewModel?.context = context;
      if (!fastConnection) {
        _askPublish();
      }
      meetingManager = MeetingManager(
          endDate: viewModel?.getMeetingEndDate(),
          isAutoMeetingEnd: viewModel?.isAutoMeetingEndEnable(),
          endMeetingCallBack: (event) {
            if (event is MeetingEnd) {
              _meetingEndLogic(viewModel);
            } else if (event is MeetingExtends) {
              viewModel?.meetingTimeExtend();
            }
          },
          context: context);
      meetingManager.startMeetingEndScheduler();
      _initializeWebViewController();
      viewModel?.getWhiteboardData();
      viewModel?.getAttendanceListForParticipant();
      if (viewModel?.meetingDetails.features?.isRecordingConsentAllowed() ==
          true) {
        viewModel?.checkSessionStatus(
            asUser: true,
            callBack: () {
              showRecordingConsentDialog(viewModel);
            });
      }

      if (viewModel?.meetingDetails.features?.isScreenShareRequestAllowed() == true) {
        viewModel?.getScreenShareConsent();
      }

      if (viewModel?.meetingDetails.features?.isConferenceChatAttachmentAllowed() == true) {
        viewModel?.getChatAttachmentConsent();
      }

      viewModel?.getAudioPermission();
      viewModel?.getVideoPermission();

      DaakiaPiP.createPipVideoCall(
          name: widget.room.localParticipant?.name ?? "Unknown",
          avatar: Utils.extractUserAvatar(widget.room.localParticipant?.metadata),
      );

      viewModel?.registerCaption();
      viewModel?.storeMeetingDetails();
      viewModel?.requestChatHistory();
    });

    if (lkPlatformIs(PlatformType.android)) {
      Hardware.instance.setSpeakerphoneOn(false);
    }

    if (lkPlatformIsDesktop()) {
      onWindowShouldClose = () async {
        unawaited(widget.room.disconnect());
        await _listener.waitFor<RoomDisconnectedEvent>(
            duration: const Duration(seconds: 5));
      };
    }

    handleAndroidNotification(enable: true);
  }

  bool _isReconnecting = false;
  bool _isConnected = false;

  void onReconnectStart() {
    setState(() {
      _isReconnecting = true;
      _isConnected = false;
    });
    // Fallback: clear reconnecting state if no event comes back within 8 sec
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && _isReconnecting) {
        setState(() {
          _isReconnecting = false;
        });
      }
    });
  }

  void onReconnectSuccess() {
    setState(() {
      _isReconnecting = false;
      _isConnected = true;
    });

    // Auto hide success banner after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isConnected = false;
        });
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    WidgetsBinding.instance.removeObserver(this);
    var viewModel = _livekitProviderKey.currentState?.viewModel;
    clearMemory(viewModel);
    viewModel?.stopLobbyCheck();
    viewModel?.cancelRoomEvents();
    meetingManager.cancelMeetingEndScheduler();
    lobbyManager?.dispose();
    widget.room.disconnect();
    handleAndroidNotification(enable: false);
    // always dispose listener
    (() async {
      DaakiaPiP.disposePiP();
      widget.room.removeListener(_onRoomDidUpdate);
      await _listener.dispose();
      await widget.room.dispose();
    })();
    onWindowShouldClose = null;
    WakelockPlus.disable();
    player.stop();
  }

  void _setUpListeners() => _listener
    ..on<RoomConnectedEvent>((event) {
      // Successfully connected
      onReconnectSuccess();
    })
    ..on<RoomReconnectedEvent>((event) {
      // Successfully reconnected
      onReconnectSuccess();
    })
    ..on<RoomDisconnectedEvent>((event) async {
      if (event.reason != null) {
        DatadogDisconnectLogger.logDisconnectEvent(
            meetingId: widget.meetingDetails.meetingUid,
            room: widget.room,
            reason: event.reason?.name);
        _livekitProviderKey.currentState?.viewModel.isMeetingEnded = true;
        clearMemory(_livekitProviderKey.currentState?.viewModel);
        switch (event.reason) {
          case DisconnectReason.participantRemoved:
            {
              showSnackBar(message: "Host has removed you from the meeting!");
              Timer(const Duration(seconds: 3), () {
                if (mounted) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    closeMeetingProgrammatically(context);
                  });
                }
              });
              break;
            }
          case DisconnectReason.duplicateIdentity:
            {
              showSnackBar(message: "You have joined with another device");
              Timer(const Duration(seconds: 3), () {
                if (mounted) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    closeMeetingProgrammatically(context);
                  });
                }
              });
              break;
            }
          case DisconnectReason.roomDeleted:
            {
              showSnackBar(message: "Meeting ended");
              Timer(const Duration(seconds: 3), () {
                if (mounted) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    closeMeetingProgrammatically(context);
                  });
                }
              });
              break;
            }

          // ✅ New cases with user-friendly messages
          case null:
          case DisconnectReason.unknown:
            _handleGenericDisconnect("Disconnected due to unknown reason.");
            break;
          case DisconnectReason.clientInitiated:
            _handleGenericDisconnect("You have left the meeting.");
            break;
          case DisconnectReason.serverShutdown:
            _handleGenericDisconnect("Meeting ended by the server.");
            break;
          case DisconnectReason.stateMismatch:
            _handleGenericDisconnect("Connection lost due to state mismatch.");
            break;
          case DisconnectReason.joinFailure:
            _handleGenericDisconnect("Failed to join the meeting.");
            break;
          case DisconnectReason.disconnected:
            _handleGenericDisconnect("You have been disconnected.");
            break;
          case DisconnectReason.signalingConnectionFailure:
            _handleGenericDisconnect("Signaling connection failed.");
            break;
          case DisconnectReason.reconnectAttemptsExceeded:
            _handleGenericDisconnect(
                "Could not reconnect. Please check your internet.");
            break;
        }
      }
    })
    ..on<ParticipantConnectedEvent>((event) {
      var viewModel = _livekitProviderKey.currentState?.viewModel;
      viewModel?.setRecording(widget.room.isRecording);
      _sortParticipants();
    })
    ..on<ParticipantEvent>((event) {
      var viewModel = _livekitProviderKey.currentState?.viewModel;
      viewModel?.setRecording(widget.room.isRecording);

      checkRecordingPlayer(widget.room.isRecording);
      // sort participants on many track events as noted in documentation linked above
      _sortParticipants();

      // Debounce `configAutoRecording` to ensure it is called only once within 1 second
      if (_configRecordingTimer?.isActive ?? false) {
        _configRecordingTimer?.cancel();
      }
      _configRecordingTimer = Timer(const Duration(seconds: 7), () {
        viewModel?.configAutoRecording();
      });
    })
    ..on<ParticipantConnectedEvent>((event) {
      _livekitProviderKey.currentState?.viewModel
          .getAttendanceListForParticipant();
      _livekitProviderKey.currentState?.viewModel
          .addParticipantToConsentList(event.participant);
      _sortParticipants();
    })
    ..on<ParticipantDisconnectedEvent>((event) {
      _livekitProviderKey.currentState?.viewModel
          .clearScreenShareRequest(event.participant.identity);
      _livekitProviderKey.currentState?.viewModel
          .removeParticipantFromConsentList(event.participant.identity);
      _livekitProviderKey.currentState?.viewModel
          .getAttendanceListForParticipant();
      _sortParticipants();
    })
    ..on<RoomRecordingStatusChanged>((event) {
      var viewModel = _livekitProviderKey.currentState?.viewModel;
      viewModel?.setRecording(event.activeRecording);
      viewModel?.isRecordingActionInProgress = false;
      if (!event.activeRecording) {
        clearConsentList(viewModel);
      }
      var recordingAudioPath = event.activeRecording
          ? Constant.startRecordingUrl
          : Constant.stopRecordingUrl;
      playAudio(recordingAudioPath);
      handleRecordingButton(viewModel, event.activeRecording);
    })
    ..on<RoomAttemptReconnectEvent>((event) {
      debugPrint(
          '[Livekit] - Attempting to reconnect ${event.attempt}/${event.maxAttemptsRetry}, '
          '(${event.nextRetryDelaysInMs}ms delay until next attempt)');
      onReconnectStart();
      DatadogReconnectLogger.logReconnectEvent(
          meetingId: widget.meetingDetails.meetingUid,
          room: widget.room,
          state: "RoomAttemptReconnectEvent",
          attempt: event.attempt,
          maxAttempts: event.maxAttemptsRetry,
          delayMs: event.nextRetryDelaysInMs);
    })
    ..on<LocalTrackSubscribedEvent>((event) {
      if (kDebugMode) {
        print('Local track subscribed: ${event.trackSid}');
      }
    })
    ..on<TrackPublishedEvent>((track) {
      var viewModel = _livekitProviderKey.currentState?.viewModel;
      final localParticipant = widget.room.localParticipant;
      if (localParticipant?.isScreenShareEnabled() == true) {
        if (localParticipant?.identity != track.participant.identity) {
          if (track.participant.isScreenShareEnabled()) {
            viewModel?.disposeScreenShare();
          }
        }
      }
    })
    ..on<LocalTrackPublishedEvent>((track){
      var viewModel = _livekitProviderKey.currentState?.viewModel;
      final localParticipant = widget.room.localParticipant;
      if (localParticipant?.isScreenShareEnabled() == true) {
        viewModel?.sendAction(ActionModel(
            action: MeetingActions.screenShareStarted,
            timeStamp: DateTime.now().microsecondsSinceEpoch));
      }
      _sortParticipants();
    })
    ..on<LocalTrackUnpublishedEvent>((track){
      _sortParticipants();
    })
    ..on<TrackSubscribedEvent>((_) => _sortParticipants())
    ..on<TrackUnsubscribedEvent>((_) => _sortParticipants())
    ..on<TrackE2EEStateEvent>(_onE2EEStateEvent)
    ..on<ParticipantNameUpdatedEvent>((event) {
      _sortParticipants();
    })
    ..on<ParticipantMetadataUpdatedEvent>((event) {})
    ..on<RoomMetadataChangedEvent>((event) {})
    ..on<DataReceivedEvent>((event) {
      _handleDataChannel(event);
    })
    ..on<AudioPlaybackStatusChanged>((event) async {
      if (!widget.room.canPlaybackAudio) {
        if (kDebugMode) {
          print('Audio playback failed for iOS Safari ..........');
        }
        bool? yesno = await context.showPlayAudioManuallyDialog();
        if (yesno == true) {
          await widget.room.startAudio();
        }
      }
    });

  void _handleDataChannel(DataReceivedEvent event) {
    var eventData0 = parseJsonData(event.data);
    var eventData = eventData0.copyWith(identity: event.participant);
    _checkReceivedDataType(eventData);
  }

  late LobbyRequestManager? lobbyManager;

  Future<void> _checkReceivedDataType(RemoteActivityData remoteData) async {
    var viewModel = _livekitProviderKey.currentState?.viewModel;
    if (!MeetingActions.isValidAction(remoteData.action)) return;
    switch (remoteData.action) {
      case MeetingActions.raiseHand:
        viewModel?.setHandRaised(remoteData);
        showSnackBar(message: "${remoteData.identity?.name ?? ''} raised hand");
        break;

      case MeetingActions.stopRaiseHand:
        viewModel?.setHandRaised(remoteData);
        break;

      case MeetingActions.stopRaiseHandAll:
        viewModel?.stopHandRaisedForAll();
        break;

      case MeetingActions.sendPrivateMessage:
        if (remoteData.message?.isNotEmpty == true) {
          viewModel?.addPrivateMessage(remoteData);
        }
        break;

      case MeetingActions.sendPublicMessage:
        if (remoteData.message?.isNotEmpty == true) {
          viewModel?.addMessage(remoteData);
        }
        break;

      case MeetingActions.lobby:
        if (viewModel?.isHost() == true || viewModel?.isCoHost() == true) {
          viewModel?.checkAndAddUserToLobbyList(remoteData);
          lobbyManager?.showLobbyRequestDialog(remoteData);
        }
        break;

      case MeetingActions.heart:
      case MeetingActions.blush:
      case MeetingActions.clap:
      case MeetingActions.smile:
      case MeetingActions.thumbsUp:
        showReaction(remoteData.action, viewModel,
            name: remoteData.identity?.name ?? '');
        break;

      case MeetingActions.muteCamera:
        viewModel?.disableVideo();
        showSnackBar(message: "Camera off!");
        break;

      case MeetingActions.muteMic:
        viewModel?.disableAudio();
        showSnackBar(message: "Microphone muted!");
        break;

      case MeetingActions.askToUnmuteMic:
        final result = await context
            .showPermissionAskDialog("Host is asking you to turn on your mic");
        if (result == true) viewModel?.enableAudio();
        break;

      case MeetingActions.askToUnmuteCamera:
        final result = await context.showPermissionAskDialog(
            "Host is asking you to turn on your camera");
        if (result == true) viewModel?.enableVideo();
        break;

      case MeetingActions.makeCoHost:
        if (Utils.isCoHost(viewModel?.room.localParticipant?.metadata)) {
          viewModel?.setCoHost(true);
          viewModel?.meetingDetails.authorizationToken = remoteData.token ?? "";
          var metadata = viewModel?.room.localParticipant?.metadata;
          final storageHelper = StorageHelper();
          storageHelper
              .setMeetingUid(viewModel?.meetingDetails.meetingUid ?? "");
          storageHelper.setSessionUid(Utils.getMetadataSessionUid(metadata));
          storageHelper
              .setAttendanceId(Utils.getMetadataAttendanceId(metadata));
          storageHelper.setHostToken(remoteData.token ?? "");
          viewModel?.getAttendanceListForParticipant();
          showSnackBar(message: "${remoteData.identity?.name} made you a Co-Host");
        } else {
          viewModel?.setCoHost(false);
          clearConsentList(viewModel);
          showSnackBar(message: "${remoteData.identity?.name} remove you as a Co-Host");
        }
        break;

      case MeetingActions.removeCoHost:
        viewModel?.setCoHost(false);
        clearConsentList(viewModel);
        showSnackBar(message: "${remoteData.identity?.name} remove you as a Co-Host");
        break;

      case MeetingActions.forceMuteAll:
        viewModel?.isAudioPermissionEnable = !remoteData.value;
        if (!(viewModel?.isAudioPermissionEnable ?? false)) {
          viewModel?.disableAudio();
        }
        break;

      case MeetingActions.forceVideoOffAll:
        viewModel?.isVideoPermissionEnable = !remoteData.value;
        if (!(viewModel?.isVideoPermissionEnable ?? false)) {
          viewModel?.disableVideo();
        }
        break;

      case MeetingActions.showLiveCaption:
        if (remoteData.liveCaptionsData != null) {
          if (viewModel == null) return;
          if (!viewModel.meetingDetails.features!
              .isVoiceTranscriptionAllowed()) {
            return;
          }
          viewModel.saveTranscriptionLanguage(remoteData.liveCaptionsData);
          if (remoteData.liveCaptionsData?.isLanguageSelected == true) {
            showSnackBar(
                message: "Live Caption is started",
                actionText: "Show",
                actionCallBack: () {
                  Navigator.of(context).push(MaterialPageRoute<Null>(
                      builder: (BuildContext context) {
                        return TranscriptionScreen(viewModel);
                      },
                      fullscreenDialog: true));
                });
          }
        }
        break;

      case MeetingActions.liveCaption:
        viewModel?.collectTranscriptionData(remoteData);
        break;

      case MeetingActions.requestLiveCaptionDrawerState:
        viewModel?.checkTranscriptionStateAndReturn(remoteData);
        break;

      case MeetingActions.extendMeetingEndTime:
        showSnackBar(message: "Meeting has been extended by 10 minutes.");
        meetingManager.extendMeetingBy10Minutes();
        break;

      case MeetingActions.whiteboardState:
        if (remoteData.value) {
          showSnackBar(message: "Whiteboard Opened");
          setState(() {
            _isWhiteBoardEnabled = true;
            loadWhiteboardUrl(Utils.generateWhiteboardUrl(
                meetingId: widget.meetingDetails.meetingUid,
                livekitToken: widget.meetingDetails.livekitToken));
          });
        } else {
          showSnackBar(message: "Whiteboard Closed");
          setState(() {
            _isWhiteBoardEnabled = false;
          });
        }
        break;

      case MeetingActions.recordingConsentModal:
        if (remoteData.value &&
            !_isConsentDialogOpen &&
            !_isConsentRejectedDialogOpen &&
            !viewModel!.hasAlreadyAcceptedConsent()) {
          showRecordingConsentDialog(viewModel);
        }
        break;

      case MeetingActions.recordingConsentStatus:
        final status = parseConsentStatus(remoteData.consent);
        if (status == ConsentStatus.reject) {
          showSnackBar(
              message: "Some participant have rejected the recording consent");
        }
        viewModel?.verifyRecordingConsent(remoteData);
        break;

      case MeetingActions.screenShareStarted:
        showSnackBar(message: "${remoteData.identity?.name} has started sharing their screen.");
        break;

      case MeetingActions.screenShareStopped:
        showSnackBar(message: "${remoteData.identity?.name} has stopped sharing their screen.");
        break;

      case MeetingActions.startRecording:
        viewModel?.dispatchId = remoteData.dispatchId;
        viewModel?.resetRecordingActionInProgressAfterDelay(10);
        break;

      case MeetingActions.stopRecording:
        viewModel?.dispatchId = null;
        viewModel?.resetRecordingActionInProgressAfterDelay(30);
        break;

      case MeetingActions.finallyStartRecording:
      case MeetingActions.finallyStopRecording:
        viewModel?.isRecordingActionInProgress = false;
        break;

      case MeetingActions.deleteMessage:
        viewModel?.deleteMessage(remoteData.mode??"", remoteData.id, remoteData.identity?.identity);
        break;

      case MeetingActions.editMessage:
        viewModel?.editMessage(remoteData.mode??"", remoteData.id, remoteData.identity?.identity, remoteData.message);
        break;

      case MeetingActions.addReaction:
        viewModel?.handleReaction(remoteData);
        break;

      case MeetingActions.allowScreenShareForAll:
        viewModel?.isScreenShareEnable = remoteData.value;
        break;

      case MeetingActions.requestScreenSharePermission:
        viewModel?.addScreenShareRequest(remoteData);
        showScreenShareDialog(context, viewModel!);
        break;

      case MeetingActions.requestScreenSharePermissionResponse:
        viewModel?.isScreenShareRequestAccepted = remoteData.isScreenShareAllowed;
        showSnackBar(
            message: remoteData.isScreenShareAllowed ? "Screen share permission granted. Now you can share your screen." : "Screen share permission denied."
        );
        break;

      case MeetingActions.canDownloadChatAttachment:
        viewModel?.isChatAttachmentDownloadEnable = remoteData.value;
        break;

      case MeetingActions.requestPublicChat:
        viewModel?.sendPublicChatHistory(remoteData.identity?.identity);
        break;

      case MeetingActions.responsePublicChat:
        viewModel?.restorePublicChat(remoteData);
        break;

      case "":
      // Handle empty action case if needed
        break;

      default:
        // Handle null or unknown action
        break;
    }
  }

  RemoteActivityData parseJsonData(List<int> jsonData) {
    final jsonString = utf8.decode(jsonData); // Convert Uint8List to String
    final Map<String, dynamic> jsonMap =
        json.decode(jsonString); // Decode the JSON string
    return RemoteActivityData.fromJson(
        jsonMap); // Convert to RemoteActivityData
  }

  void _askPublish() async {
    final result = await context.showPublishDialog();
    if (result != true) return;
    // video will fail when running in ios simulator
    try {
      await widget.room.localParticipant?.setCameraEnabled(true);
    } catch (error) {
      if (kDebugMode) {
        print('could not publish video: $error');
      }
      if (mounted) {
        await context.showErrorDialog(error);
      }
    }
    try {
      await widget.room.localParticipant?.setMicrophoneEnabled(true);
    } catch (error) {
      if (kDebugMode) {
        print('could not publish audio: $error');
      }
      if (mounted) {
        await context.showErrorDialog(error);
      }
    }
  }

  void _onRoomDidUpdate() {
    _sortParticipants();
  }

  void _onE2EEStateEvent(TrackE2EEStateEvent e2eeState) {
    if (kDebugMode) {
      print('e2ee state: $e2eeState');
    }
  }

  void _sortParticipants() {
    final viewmodel = _livekitProviderKey.currentState?.viewModel;
    List<ParticipantTrack> userMediaTracks = [];
    List<ParticipantTrack> screenTracks = [];
    var coHostCount = 0;
    viewmodel?.adminList = [];
    // Add remote participants
    for (var participant in widget.room.remoteParticipants.values) {
      bool hasVideoTrack = false;

      if (Utils.isCoHost(participant.metadata)) {
        coHostCount++;
      }

      viewmodel?.updateAdminList(participant);

      for (var t in participant.videoTrackPublications) {
        if (t.isScreenShare) {
          screenTracks.add(ParticipantTrack(
            participant: participant,
            type: ParticipantTrackType.kScreenShare,
          ));
        } else {
          hasVideoTrack = true;
          userMediaTracks.add(ParticipantTrack(participant: participant));
        }
      }

      // Add participant if they don't have any video tracks
      if (!hasVideoTrack) {
        userMediaTracks.add(ParticipantTrack(participant: participant));
      }
    }

    // Add local participant if they exist
    final localParticipant = widget.room.localParticipant;
    if (localParticipant != null) {
      userMediaTracks.add(ParticipantTrack(participant: localParticipant));

      // Handle local video tracks (for screen share and video)
      for (var t in localParticipant.videoTrackPublications) {
        if (t.isScreenShare) {
          if (lkPlatformIs(PlatformType.iOS) && !_flagStartedReplayKit) {
            _flagStartedReplayKit = true;
          }
          screenTracks.add(ParticipantTrack(
            participant: localParticipant,
            type: ParticipantTrackType.kScreenShare,
          ));
        }
      }
    }

    // Sort the user media tracks
    userMediaTracks.sort((a, b) {
      if (a.participant.isSpeaking && b.participant.isSpeaking) {
        return a.participant.audioLevel > b.participant.audioLevel ? -1 : 1;
      }

      final aSpokeAt = a.participant.lastSpokeAt?.millisecondsSinceEpoch ?? 0;
      final bSpokeAt = b.participant.lastSpokeAt?.millisecondsSinceEpoch ?? 0;

      if (aSpokeAt != bSpokeAt) {
        return aSpokeAt > bSpokeAt ? -1 : 1;
      }

      if (a.participant.hasVideo != b.participant.hasVideo) {
        return a.participant.hasVideo ? -1 : 1;
      }

      return a.participant.joinedAt.millisecondsSinceEpoch -
          b.participant.joinedAt.millisecondsSinceEpoch;
    });

    // Handle pinned participant
    ParticipantTrack? pinnedTrack;
    if (viewmodel?.pinnedParticipantId != null) {
      final idx = userMediaTracks.indexWhere(
        (t) => t.participant.identity == viewmodel?.pinnedParticipantId,
      );
      if (idx != -1) {
        pinnedTrack = userMediaTracks.removeAt(idx);
      }
    }

    // Update the participant tracks
    setState(() {
      participantTracks = [
        ...screenTracks, // Screen shares always first
        if (pinnedTrack != null) pinnedTrack, // Then pinned participant
        ...userMediaTracks, // Then remaining participants
      ];
    });
    viewmodel?.coHostCount = coHostCount;
    viewmodel?.addParticipant(participantTracks);
  }

  final GlobalKey<RtcProviderState> _livekitProviderKey =
      GlobalKey<RtcProviderState>();

  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  late final WebViewController _webViewController;
  bool _webViewInitialized = false;

  bool _isWhiteBoardEnabled = false;

  void _initializeWebViewController() {
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          )
        : const PlatformWebViewControllerCreationParams();

    _webViewController = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            return NavigationDecision.navigate;
          },
        ),
      );
  }

  /// 👇 Call this function from your event listener to load the URL
  void loadWhiteboardUrl(String url) {
    if (!_webViewInitialized) {
      _webViewInitialized = true;
      _webViewController.loadRequest(Uri.parse(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(statusBarColor: Colors.black));
    // Ensure the viewModel is accessed after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Check if the viewModel is ready
      final viewModel = _livekitProviderKey.currentState?.viewModel;
      if (viewModel != null) {
        // Start the lobby check
        viewModel.startLobbyCheck();
        // Collect lobby events
        collectLobbyEvents(viewModel, context);
      }
    });
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) async {
            if (_isProgrammaticPop) {
              _isProgrammaticPop = false; // Reset the flag
              return;
            }
            if (!context.mounted) return;
            final shouldExit = await _showExitConfirmationDialog(context);
            if (shouldExit) {
              // Delay the pop operation to avoid navigation conflicts
              Future.delayed(Duration.zero, () {
                if (!context.mounted) return;
                if (Navigator.canPop(context)) {
                  Navigator.of(context).pop(); // Exit to previous page
                }
                _isProgrammaticPop = true;
              });
            }
          },
        );
      },
      child: RtcProvider(
        key: _livekitProviderKey,
        room: widget.room,
        meetingDetails: widget.meetingDetails,
        child: MaterialApp(
          scaffoldMessengerKey: scaffoldMessengerKey,
          debugShowCheckedModeBanner: false,
          home: (_isInPipMode)
              ? PipScreen(
                  name: widget.room.localParticipant?.name,
                )
              : Stack(
                  children: [
                    Scaffold(
                      body: SafeArea(
                        child: Stack(children: [
                          Container(
                            color: Colors.black,
                            child: Column(
                              children: [
                                // Main content area for participants
                                Expanded(
                                  child: Stack(
                                    children: [
                                      Column(
                                        children: [
                                          Expanded(
                                            child: _isWhiteBoardEnabled
                                                ? WhiteBoardWidget(
                                                    key: const ValueKey(
                                                        'whiteboard'),
                                                    controller:
                                                        _webViewController,
                                                  )
                                                : participantTracks.isNotEmpty
                                                    ? ParticipantWidget
                                                        .widgetFor(
                                                            participantTracks
                                                                .first,
                                                            showStatsLayer:
                                                                true,
                                                            isSpeaker: true)
                                                    : Container(),
                                          ),

                                          // Show participant list below (adjusted based on whiteboard status)
                                          if (participantTracks.length > 1 ||
                                              _isWhiteBoardEnabled)
                                            SizedBox(
                                              height: 120,
                                              child: ListView.builder(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                itemCount: _isWhiteBoardEnabled
                                                    ? participantTracks
                                                        .length // show all
                                                    : participantTracks.length -
                                                        1,
                                                // skip first
                                                itemBuilder:
                                                    (BuildContext context,
                                                        int index) {
                                                  final track =
                                                      _isWhiteBoardEnabled
                                                          ? participantTracks[
                                                              index] // show all participants
                                                          : participantTracks[
                                                              index +
                                                                  1]; // skip first

                                                  return SizedBox(
                                                    width: 180,
                                                    height: 120,
                                                    child: ParticipantWidget
                                                        .widgetFor(track),
                                                  );
                                                },
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (_livekitProviderKey.currentState
                                              ?.viewModel.isRecording ==
                                          true)
                                        const Positioned(
                                          right: 10,
                                          top: 10,
                                          child: Icon(
                                              Icons.radio_button_checked,
                                              color: Colors.red),
                                        ),
                                    ],
                                  ),
                                ),
                                if (widget.room.localParticipant != null)
                                  SafeArea(
                                    top: false,
                                    child: RtcControls(
                                      widget.room,
                                      widget.room.localParticipant!,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 50,
                            child: EmojiReactionWidget(
                              viewModel:
                                  _livekitProviderKey.currentState?.viewModel,
                            ),
                          ),
                        ]),
                      ),
                    ),

                    /// Overlay banner
                    if (_isReconnecting)
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: ConnectivityBanner(
                          message: "Reconnecting…\nPlease check your internet",
                          backgroundColor: Colors.orange,
                          showSpinner: true,
                        ),
                      ),
                    if (_isConnected && !_isReconnecting)
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: ConnectivityBanner(
                          message: "You’re back online",
                          backgroundColor: Colors.green,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<bool> _showExitConfirmationDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Exit Meeting'),
              content: const Text('Are you sure you want to exit the meeting?'),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false); // Don't exit
                  },
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(true); // Exit
                  },
                  child: const Text('Exit'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void showSnackBar(
      {required String message, String? actionText, Function? actionCallBack}) {
    scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
      content: Text(message),
      action: actionText != null
          ? SnackBarAction(
              label: actionText,
              onPressed: () {
                actionCallBack?.call();
              },
            )
          : null,
    ));
  }

  bool isEventAdded = false;

  void collectLobbyEvents(RtcViewmodel? viewModel, BuildContext context) {
    if (isEventAdded) return;
    isEventAdded = true;
    viewModel?.roomEvents.listen((event) {
      if (!context.mounted) return;
      if (event is ShowSnackBar) {
        showSnackBar(message: event.message);
      } else if (event is ShowTranscriptionDownload) {
        showSnackBar(
            message: event.message,
            actionText: (event.path == null) ? "" : "Open",
            actionCallBack: () {
              Utils.openMediaFile(event.path ?? "", context);
            });
      } else if (event is ShowReaction) {
        showReaction(event.emoji, viewModel);
      } else if (event is UpdateView) {
        if (mounted) {
          setState(() {});
        }
      } else if (event is EndMeeting) {
        clearMemory(viewModel);
        DatadogDisconnectLogger.logDisconnectEvent(
            meetingId: widget.meetingDetails.meetingUid,
            room: widget.room,
            reason: event.reason);
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            closeMeetingProgrammatically(context);
            widget.room.disconnect();
          });
        }
      } else if (event is WhiteboardStatus) {
        setState(() {
          _isWhiteBoardEnabled = event.status;
        });
        if (!_isWhiteBoardEnabled) return;
        loadWhiteboardUrl(Utils.generateWhiteboardUrl(
            meetingId: widget.meetingDetails.meetingUid,
            livekitToken: widget.meetingDetails.livekitToken));
      } else if (event is SortParticipants) {
        _sortParticipants();
      }
    });
  }

  AnimatedEmojiData? emojiAsset;

  void showReaction(String? emoji, RtcViewmodel? viewModel,
      {String name = "You"}) {
    if (viewModel?.meetingDetails.features!.isReactionAllowed() == false) {
      return;
    }
    switch (emoji) {
      case "heart":
        emojiAsset = AnimatedEmojis.redHeart;
        break;
      case "blush":
        emojiAsset = AnimatedEmojis.blush;
        break;
      case "clap":
        emojiAsset = AnimatedEmojis.clap;
        break;
      case "smile":
        emojiAsset = AnimatedEmojis.smile;
        break;
      case "thumbsUp":
        emojiAsset = AnimatedEmojis.thumbsUp;
        break;
    }
    setState(() {
      addEmojiToQueue(emojiAsset, name, viewModel);
    });
  }

  void addEmojiToQueue(
      AnimatedEmojiData? emoji, String senderName, RtcViewmodel? viewModel) {
    if (viewModel == null) return;
    final newMessage = EmojiMessage(
        emoji: emoji,
        senderName: senderName,
        timestamp: DateTime.now().millisecondsSinceEpoch.toString());
    viewModel.addEmoji(newMessage);
  }

  // When closing the meeting programmatically
  void closeMeetingProgrammatically(BuildContext context) {
    _isProgrammaticPop = true; // Set the flag
    Navigator.popUntil(context, (route) => route.isFirst); // Close all routes
  }

  void _meetingEndLogic(RtcViewmodel? viewModel) {
    //TODO NEED TO UPDATE LOGIC
    if (viewModel?.meetingDetails.meetingBasicDetails?.meetingConfig
            ?.autoMeetingEnd ==
        1) {
      DatadogDisconnectLogger.logDisconnectEvent(
          meetingId: widget.meetingDetails.meetingUid,
          room: widget.room,
          reason: "TIME_EXCEEDED");
      showSnackBar(message: "Meeting ended");
      Timer(const Duration(seconds: 3), () {
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            closeMeetingProgrammatically(context);
          });
        }
      });
      return;
    }
    if (viewModel?.meetingDetails.features?.isBasicPlan() == true) {
      DatadogDisconnectLogger.logDisconnectEvent(
          meetingId: widget.meetingDetails.meetingUid,
          room: widget.room,
          reason: "TIME_EXCEEDED");
      showSnackBar(message: "Meeting ended");
      Timer(const Duration(seconds: 3), () {
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            closeMeetingProgrammatically(context);
          });
        }
      });
    }
    // TODO: Uncomment the following alert if you want to show a "Meeting Ended" dialog to basic users. For basic users, this alert remains visible by default.
    // else {
    //   showDialog(
    //     context: context,
    //     builder: (context) => AlertDialog(
    //       title: const Text("Meeting Ended"),
    //       content: const Text("The meeting has ended."),
    //       actions: [
    //         TextButton(
    //           onPressed: () => Navigator.of(context).pop(),
    //           child: const Text("OK"),
    //         ),
    //       ],
    //     ),
    //   );
    // }
  }

  var _isConsentDialogOpen = false;
  var _isConsentRejectedDialogOpen = false;

  void showRecordingConsentDialog(RtcViewmodel? viewModel) {
    if (_isConsentDialogOpen) return; // Prevent duplicate dialogs
    _isConsentDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Recording Consent',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'The host is requesting your consent to record this meeting. Please choose whether you agree or reject.',
            style: TextStyle(fontSize: 16),
          ),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          actions: [
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                viewModel?.updateRecordingConsentStatus(false);
                showRejectWarningDialog(viewModel);
              },
              icon: const Icon(Icons.close, color: Colors.red),
              label: const Text(
                'Reject',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                viewModel?.updateRecordingConsentStatus(true);
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text(
                'Agree',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      _isConsentDialogOpen = false; // Reset when dialog is dismissed
    });
  }

  void showRejectWarningDialog(RtcViewmodel? viewModel) {
    if (_isConsentRejectedDialogOpen) return; // Prevent duplicate dialogs
    _isConsentRejectedDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Column(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              SizedBox(width: 8),
              Text(
                'Recording Rejected',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            'You rejected the recording request. Would you like to change your response and allow recording?',
            style: TextStyle(fontSize: 16),
          ),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          actions: [
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.cancel, color: Colors.grey),
              label: const Text(
                'Dismiss',
                style:
                    TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                side: const BorderSide(color: Colors.blue),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                viewModel?.updateRecordingConsentStatus(true);
              },
              icon: const Icon(Icons.refresh),
              label: const Text(
                'Change to Agree',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      _isConsentRejectedDialogOpen = false; // Reset when dialog is dismissed
    });
  }

  void clearConsentList(RtcViewmodel? viewModel) {
    if (viewModel?.meetingDetails.features?.isRecordingConsentAllowed() ==
        true) {
      viewModel?.participantListForConsent.clear();
    }
  }

  late final AudioPlayer player;

  void playAudio(String link) {
    player.play(UrlSource(link), mode: PlayerMode.lowLatency);
  }

  var isCheckedWhileJoining = false;

  void checkRecordingPlayer(bool isRecording) {
    if (isRecording && !isCheckedWhileJoining) {
      playAudio(Constant.startRecordingUrl);
      isCheckedWhileJoining = true;
    }
  }

  void _handleGenericDisconnect(String message) {
    showSnackBar(message: message);
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          closeMeetingProgrammatically(context);
        });
      }
    });
  }

  Future<void> handleAndroidNotification({required bool enable}) async {
    if (!lkPlatformIs(PlatformType.android)) return;

    final androidVersion = await Utils.getAndroidVersion();

    if (androidVersion >= 34) return;

    final androidConfig = FlutterBackgroundAndroidConfig(
        notificationTitle:
            widget.meetingDetails.meetingBasicDetails?.eventName ?? "Meeting",
        notificationText: "Tap to return to the meeting",
        notificationImportance: AndroidNotificationImportance.high,
        shouldRequestBatteryOptimizationsOff: false);

    try {
      if (enable) {
        // Step 1: initialize (ask for permission + setup)
        final initialized =
            await FlutterBackground.initialize(androidConfig: androidConfig);

        if (!initialized) {
          debugPrint("Background permission not granted.");
          return;
        }

        // Step 2: only enable if not already running
        if (!FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.enableBackgroundExecution();
        }
      } else {
        // disable if currently enabled
        if (FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.disableBackgroundExecution();
        }
      }
    } catch (e) {
      debugPrint("Error while handling Android background notification: $e");
    }
  }

  void clearMemory(RtcViewmodel? viewModel) {
    viewModel?.disposeScreenShare();
    viewModel?.unregisterCaption();
    handleAndroidNotification(enable: false);
    _disposePip();
    DaakiaPiP.disposePiP();
  }

  void _disposePip() {
    pip?.setAutoPipMode(autoEnter: false);
    pip = null;
  }

  void handleRecordingButton(RtcViewmodel? viewModel, bool activeRecording) {
    if (viewModel?.isRecordingStartByMe == true) {
      viewModel?.sendAction(ActionModel(
        action: activeRecording ? MeetingActions.finallyStartRecording : MeetingActions.finallyStopRecording
      ));
    }
    viewModel?.isRecordingStartByMe = false;
  }

  void showScreenShareDialog(BuildContext context, RtcViewmodel viewModel) {
    if (viewModel.isScreenShareDialogOpen) return; // already open, skip

    viewModel.isScreenShareDialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        // 👇 Rebuilds automatically when notifyListeners() is called
        return AnimatedBuilder(
          animation: viewModel,
          builder: (context, _) {
            return ScreenShareRequestDialog(
              viewModel: viewModel,
              onAction: (request, allow) {
                viewModel.handleScreenShareRequest(allow, request);
                viewModel.removeScreenShareRequest(request);

                if (viewModel.screenShareRequestList.isEmpty) {
                  Navigator.of(context).pop();
                  viewModel.isScreenShareDialogOpen = false;
                }
              },
              onClose: () {
                Navigator.of(context).pop();
                viewModel.isScreenShareDialogOpen = false;
              },
            );
          },
        );
      },
    ).then((_) {
      viewModel.isScreenShareDialogOpen = false;
    });
  }

}
