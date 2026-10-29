import 'dart:async';
import 'dart:convert';

import 'package:animated_emoji/emoji_data.dart';
import 'package:animated_emoji/emojis.g.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:daakia_vc_flutter_sdk/events/meeting_end_events.dart';
import 'package:daakia_vc_flutter_sdk/events/rtc_events.dart';
import 'package:daakia_vc_flutter_sdk/presentation/dialog/leave_confirmation_dialog.dart';
import 'package:daakia_vc_flutter_sdk/enum/attendance_role_enum.dart';
import 'package:daakia_vc_flutter_sdk/model/action_model.dart';
import 'package:daakia_vc_flutter_sdk/model/daakia_meeting_configuration.dart';
import 'package:daakia_vc_flutter_sdk/model/meeting_details.dart';
import 'package:daakia_vc_flutter_sdk/presentation/dialog/notification_permission_dialog.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/emoji_reaction_widget.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/workshop_mode_dialog.dart';
import 'package:daakia_vc_flutter_sdk/rtc/lobby_request_manager.dart';
import 'package:daakia_vc_flutter_sdk/rtc/widgets/connectivity_banner.dart';
import 'package:daakia_vc_flutter_sdk/rtc/widgets/participant.dart';
import 'package:daakia_vc_flutter_sdk/rtc/widgets/room_notification.dart';
import 'package:daakia_vc_flutter_sdk/rtc/widgets/participant_info.dart';
import 'package:daakia_vc_flutter_sdk/rtc/widgets/pip_screen.dart';
import 'package:daakia_vc_flutter_sdk/rtc/widgets/rtc_controls.dart';
import 'package:daakia_vc_flutter_sdk/rtc/widgets/white_board_widget.dart';
import 'package:daakia_vc_flutter_sdk/theme/daakia_sdk_theme.dart';
import 'package:daakia_vc_flutter_sdk/utils/cdn_sounds.dart';
import 'package:daakia_vc_flutter_sdk/utils/constants.dart';
import 'package:daakia_vc_flutter_sdk/utils/whiteboard_download.dart';
import 'package:daakia_vc_flutter_sdk/utils/whiteboard_file_selector.dart';
import 'package:daakia_vc_flutter_sdk/utils/datadog_disconnect_logger.dart';
import 'package:daakia_vc_flutter_sdk/utils/datadog_reconnect_logger.dart';
import 'package:daakia_vc_flutter_sdk/service/daakia_vc_logger.dart';
import 'package:daakia_vc_flutter_sdk/utils/rtc_ext.dart';
import 'package:daakia_vc_flutter_sdk/utils/storage_helper.dart';
import 'package:daakia_vc_flutter_sdk/viewmodel/rtc_provider.dart';
import 'package:daakia_vc_flutter_sdk/viewmodel/rtc_viewmodel.dart';
import 'package:flutter/foundation.dart';
// livekit_client's ConnectionState is the one used here.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import '../service/daakia_meeting_service.dart';
import 'audio_routing.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';
import 'package:simple_pip_mode/simple_pip.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../model/annotation_stroke.dart';
import '../model/emoji_message.dart';
import '../model/remote_activity_data.dart';
import '../presentation/dialog/duplicate_identity_dialog.dart';
import '../presentation/dialog/inactive_meeting_dialog.dart';
import '../presentation/dialog/inactivity_ended_dialog.dart';
import '../presentation/dialog/meeting_ending_dialog.dart';
import '../presentation/dialog/screen_share_request_dialog.dart';
import '../presentation/pages/transcription_screen.dart';
import '../utils/consent_status_enum.dart';
import '../utils/annotation_actions.dart';
import '../utils/meeting_actions.dart';
import '../utils/utils.dart';
import 'inactive_meeting_watcher.dart';
import 'meeting_manager.dart';
import 'method_channels/daakia_pip.dart';

class RoomPage extends StatefulWidget {
  final Room room;
  final EventsListener<RoomEvent> listener;
  final MeetingDetails meetingDetails;
  final bool fastConnection;
  final DaakiaMeetingConfiguration? sdkConfiguration;

  /// Shown once the meeting UI is up, to explain something about the join the
  /// user would otherwise have to guess at — currently only that a weak
  /// connection forced them in with mic and camera off.
  final String? joinNotice;

  const RoomPage(
    this.room,
    this.listener,
    this.meetingDetails, {
    this.fastConnection = false,
    this.sdkConfiguration,
    this.joinNotice,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> with WidgetsBindingObserver {
  List<ParticipantTrack> participantTracks = [];

  EventsListener<RoomEvent> get _listener => widget.listener;

  bool get fastConnection => widget.fastConnection;
  bool _flagStartedReplayKit = false;

  SimplePip? pip;
  bool _isInPipMode = false;

  bool _isProgrammaticPop = false; // Flag to track programmatic pop

  // Tracks the last mic-enabled state so we only call updateMuteState when it changes.
  bool? _lastMicEnabled;

  Timer? _configRecordingTimer;

  // Coalesces rapid-fire track add/remove events (e.g. both sides repeatedly
  // toggling screen share) into a single rebuild instead of one per event,
  // to reduce main-thread churn during toggle storms.
  Timer? _sortParticipantsDebounceTimer;

  // Groups the mic / camera / participant-list changes that arrive as three
  // separate actions when the host toggles Workshop mode into one notice.
  final WorkshopModeNoticeController _workshopNotice =
      WorkshopModeNoticeController();

  late final MeetingManager meetingManager;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Re-ensure the meeting notification is visible. Covers the case where the
      // user granted POST_NOTIFICATIONS in system Settings while in the meeting.
      DaakiaMeetingService.restartIfActive();
      // Timers may have been paused in the background; catch up at once.
      _inactivityWatcher?.check();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.black,
          statusBarIconBrightness: Brightness.light, // white icons on Android
          statusBarBrightness: Brightness.dark,      // white icons on iOS
        ));
    WakelockPlus.enable();
    DaakiaAudioRouting.attach();
    if (lkPlatformIs(PlatformType.android)) {
      pip = SimplePip(onPipEntered: () {
        setState(() {
          _isInPipMode = true;
        });
      }, onPipExited: () {
        setState(() {
          _isInPipMode = false;
        });
      });
      pip?.setAutoPipMode(
          aspectRatio: (1, 1), seamlessResize: true, autoEnter: true)
        .catchError((e) {
          // setAutoPipMode requires Android S (API 31+); silently ignore on older versions
          return false;
        });
    }
    _zoomController = TransformationController();
    _zoomController.addListener(_onZoomChanged);
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
      _showJoinNotice();
      // Before the scheduler: its first check runs synchronously, and joining a
      // meeting already inside its final minutes fires the warning there and
      // then. Starting the load first gives that case a head start.
      unawaited(_prepareMeetingEndWarningSound());
      meetingManager = MeetingManager(
          endDate: viewModel?.getMeetingEndDate(),
          isAutoMeetingEnd: viewModel?.isAutoMeetingEndEnable(),
          // Only in-memory otherwise: a rejoin after the extension would offer
          // it again, and the backend would turn the second one down.
          isExtended: viewModel?.isMeetingAlreadyExtended() ?? false,
          endMeetingCallBack: (event) {
            if (event is MeetingEnd) {
              _meetingEndLogic(viewModel);
            } else if (event is MeetingExtends) {
              viewModel?.meetingTimeExtend();
            } else if (event is MeetingEndingSoon) {
              _handleMeetingEndingSoon(viewModel, event);
            }
          });
      meetingManager.startMeetingEndScheduler();
      viewModel?.syncMeetingEndTime(onDone: () {
        if (!mounted) return;
        if (viewModel.isMeetingAlreadyExtended() &&
            meetingManager.adoptExtendedEndDate(viewModel.getMeetingEndDate())) {
          // Warnings already given counted down to the old end.
          _warnedTiers.clear();
          _promptedTiers.clear();
        }
        _isMeetingEndTimeSynced = true;
      });
      _initInactivityWatcher(viewModel);
      _initializeWebViewController();
      viewModel?.getWhiteboardData();
      viewModel?.getAttendanceListForParticipant();
      viewModel?.fetchInvitedParticipants(silent: true);
      if (viewModel?.meetingDetails.features?.isRecordingConsentAllowed() ==
          true) {
        viewModel?.checkSessionStatus(
            asUser: true,
            callBack: () {
              // Joining a meeting that is already recording doesn't ask again.
              if (widget.room.isRecording) return;
              showRecordingConsentDialog(viewModel);
            });
      } else {
        viewModel?.fetchAndStoreSessionUid();
      }

      // Single call fetches all host control states; falls back to individual APIs if endpoint unavailable.
      // ignore: deprecated_member_use
      viewModel?.getHostControls();

      DaakiaPiP.createPipVideoCall(
          name: widget.room.localParticipant?.name ?? "Unknown",
          avatar: Utils.extractUserAvatar(widget.room.localParticipant?.metadata),
      );

      viewModel?.registerCaption();
      viewModel?.storeMeetingDetails();
      viewModel?.notifyParticipantJoinedStatus();
      viewModel?.requestChatHistory();
      viewModel?.requestRaiseHand();

      if (lkPlatformIs(PlatformType.android) || lkPlatformIs(PlatformType.iOS)) {
        _initMeetingNotificationCallbacks(viewModel);
      }
    });

    if (lkPlatformIs(PlatformType.android)) {
      DaakiaAudioRouting.setSpeakerphoneOn(true);
    }

    if (lkPlatformIsDesktop()) {
      onWindowShouldClose = () async {
        unawaited(widget.room.disconnect());
        await _listener.waitFor<RoomDisconnectedEvent>(
            duration: const Duration(seconds: 5));
      };
    }

    unawaited(_setupAndroidMeetingNotification());
  }

  Future<void> _setupAndroidMeetingNotification() async {
    await handleAndroidNotification(enable: true);
    if (!lkPlatformIs(PlatformType.android)) return;
    final hasPermission = await DaakiaMeetingService.hasNotificationPermission();
    if (!hasPermission && mounted) {
      showNotificationPermissionDialog(context);
    }
  }

  bool _isReconnecting = false;
  bool _isConnected = false;
  bool _isPhoneCallActive = false;

  // Debounces the "Reconnecting…" banner so a single brief attempt that
  // resolves instantly (common on an otherwise healthy connection) never
  // flashes it. Only the first attempt of a given outage schedules these;
  // subsequent RoomAttemptReconnectEvents for the same outage are no-ops,
  // which also prevents stacked timers from firing out of order.
  Timer? _reconnectShowDelayTimer;
  // Safety net only, in case a reconnected/disconnected event is ever missed.
  // LiveKit's own reconnectAttemptsExceeded disconnect is the authoritative
  // give-up signal. Kept comfortably longer than LiveKit's worst-case backoff
  // window (~44s across 10 attempts) plus per-attempt connection timeouts.
  Timer? _reconnectFallbackTimer;

  // When the last reconnect attempt started. A DUPLICATE_IDENTITY disconnect
  // that lands during or shortly after a reconnect is almost always this
  // device kicking itself, not a join from another device: a reconnect
  // attempt that timed out on our side can still complete on the server, and
  // the server's kick for that stale session reaches this client and ends the
  // healthy one. See _onDuplicateIdentity.
  DateTime? _lastReconnectAttemptAt;
  static const _selfKickWindow = Duration(seconds: 60);

  // Set by the first RoomDisconnectedEvent; later ones are only logged.
  bool _disconnectHandled = false;

  late final TransformationController _zoomController;
  double _zoomScale = 1.0;

  void onReconnectStart() {
    _lastReconnectAttemptAt = DateTime.now();
    // Already showing (or about to show) the banner for this outage.
    if (_isReconnecting || _reconnectShowDelayTimer != null) return;

    _reconnectFallbackTimer?.cancel();
    _reconnectShowDelayTimer = Timer(const Duration(milliseconds: 800), () {
      _reconnectShowDelayTimer = null;
      if (!mounted) return;
      setState(() {
        _isReconnecting = true;
        _isConnected = false;
      });
    });

    _reconnectFallbackTimer = Timer(const Duration(seconds: 90), () {
      _reconnectFallbackTimer = null;
      if (mounted && _isReconnecting) {
        setState(() {
          _isReconnecting = false;
        });
      }
    });
  }

  void onReconnectSuccess() {
    _reconnectShowDelayTimer?.cancel();
    _reconnectShowDelayTimer = null;
    _reconnectFallbackTimer?.cancel();
    _reconnectFallbackTimer = null;

    if (!mounted) return;

    // Only surface "You're back online" if we actually showed "Reconnecting…"
    // first — otherwise this fires on every fresh join too (RoomConnectedEvent
    // also calls onReconnectSuccess).
    final wasReconnecting = _isReconnecting;
    setState(() {
      _isReconnecting = false;
      _isConnected = wasReconnecting;
    });

    if (!wasReconnecting) return;

    // Auto hide success banner after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isConnected = false;
        });
      }
    });
  }

  void _resetReconnectUiState() {
    _reconnectShowDelayTimer?.cancel();
    _reconnectShowDelayTimer = null;
    _reconnectFallbackTimer?.cancel();
    _reconnectFallbackTimer = null;
  }

  void _onZoomChanged() {
    final scale = _zoomController.value.getMaxScaleOnAxis();
    if ((scale - _zoomScale).abs() > 0.01) {
      setState(() => _zoomScale = scale);
    }
  }

  void _resetZoom() {
    _zoomController.value = Matrix4.identity();
  }

  bool _speakerHasActiveVideo() {
    if (participantTracks.isEmpty) return false;
    final track = participantTracks.first;
    if (track.type == ParticipantTrackType.kScreenShare) return true;
    return track.participant.videoTrackPublications
        .where((p) => !p.isScreenShare)
        .any((p) => p.track != null && !p.muted);
  }

  @override
  void dispose() {
    unawaited(DaakiaAudioRouting.detach());
    _resetReconnectUiState();
    _zoomController.removeListener(_onZoomChanged);
    _zoomController.dispose();
    super.dispose();
    WidgetsBinding.instance.removeObserver(this);
    var viewModel = _livekitProviderKey.currentState?.viewModel;
    clearMemory(viewModel);
    viewModel?.stopLobbyCheck();
    viewModel?.cancelRoomEvents();
    meetingManager.cancelMeetingEndScheduler();
    _inactivityWatcher?.dispose();
    _inactivityWatcher = null;
    lobbyManager?.dispose();
    widget.room.disconnect();
    handleAndroidNotification(enable: false);
    _sortParticipantsDebounceTimer?.cancel();
    _workshopNotice.dispose();
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
    _meetingEndWarningCutoff?.cancel();
    _meetingEndWarningPlayer?.dispose();
    _meetingEndWarningPlayer = null;
  }

  void _setUpListeners() => _listener
    ..on<RoomConnectedEvent>((event) {
      // Successfully connected
      onReconnectSuccess();
      _updateInactivityWatcher();
    })
    ..on<RoomReconnectingEvent>((_) => _updateInactivityWatcher())
    ..on<RoomReconnectedEvent>((event) {
      // Successfully reconnected
      onReconnectSuccess();
      _updateInactivityWatcher();
    })
    ..on<RoomDisconnectedEvent>((event) async {
      // Run cleanup and navigation for ALL disconnect reasons, including null.
      // The outer null-guard that was here made the `case null` in the switch
      // unreachable — any unexpected disconnect (network drop, server kill
      // without a reason) would leave the page open and the service running.
      _resetReconnectUiState();
      // The "Reconnecting…" banner is drawn over the notification overlay, so
      // leaving it up would hide the disconnect message shown below.
      if (mounted && (_isReconnecting || _isConnected)) {
        setState(() {
          _isReconnecting = false;
          _isConnected = false;
        });
      }
      _isProgrammaticPop = true;
      // Down before anything below pops the meeting, or the pop would close
      // the prompt instead.
      _stopInactivityWatcher();
      DatadogDisconnectLogger.logDisconnectEvent(
          meetingId: widget.meetingDetails.meetingUid,
          room: widget.room,
          reason: event.reason?.name);
      // LiveKit can report more than one disconnect for the same ending: a
      // kick during a reconnect is followed by joinFailure from the rejoin
      // still in flight. Handling it again would replace the message the user
      // just got and schedule a second pop, which can close the host app's
      // screen underneath the meeting.
      if (_disconnectHandled) return;
      _disconnectHandled = true;
      _livekitProviderKey.currentState?.viewModel.isMeetingEnded = true;
      clearMemory(_livekitProviderKey.currentState?.viewModel);
      if (_isInactivityEnd(event.reason)) {
        _finishInactivityEnd(_livekitProviderKey.currentState?.viewModel);
        return;
      }
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
          _onDuplicateIdentity();
          break;
        case DisconnectReason.roomDeleted:
        case DisconnectReason.roomClosed:
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
        case DisconnectReason.migration:
        case DisconnectReason.signalClose:
        case DisconnectReason.connectionTimeout:
        case DisconnectReason.mediaFailure:
          _handleGenericDisconnect("You have been disconnected.");
          break;
        // SIP and agent reasons don't apply to Daakia meetings, but keep the
        // switch exhaustive so a stray one still closes the meeting cleanly.
        case DisconnectReason.userUnavailable:
        case DisconnectReason.userRejected:
        case DisconnectReason.sipTrunkFailure:
        case DisconnectReason.agentError:
          _handleGenericDisconnect("Disconnected due to unknown reason.");
          break;
        case DisconnectReason.signalingConnectionFailure:
          _handleGenericDisconnect("Signaling connection failed.");
          break;
        case DisconnectReason.reconnectAttemptsExceeded:
          _handleGenericDisconnect(
              "Could not reconnect. Please check your internet.");
          break;
      }
    })
    ..on<ParticipantEvent>((event) {
      var viewModel = _livekitProviderKey.currentState?.viewModel;
      viewModel?.setRecording(widget.room.isRecording);

      checkRecordingPlayer(widget.room.isRecording);
      // sort participants on many track events as noted in documentation linked above
      _scheduleSortParticipants();

      // Debounce `configAutoRecording` to ensure it is called only once within 1 second
      if (_configRecordingTimer?.isActive ?? false) {
        _configRecordingTimer?.cancel();
      }
      _configRecordingTimer = Timer(const Duration(seconds: 7), () {
        viewModel?.configAutoRecording();
      });
    })
    ..on<ParticipantConnectedEvent>((event) {
      var viewModel = _livekitProviderKey.currentState?.viewModel;
      viewModel?.setRecording(widget.room.isRecording);
      viewModel?.getAttendanceListForParticipant();
      viewModel?.fetchInvitedParticipants(silent: true);
      // The joiner's metadata (with their email) can land just after the
      // connect event, so read it a moment later.
      final joined = event.participant;
      Timer(const Duration(seconds: 2), () {
        if (widget.room.remoteParticipants[joined.identity] == null) return;
        _livekitProviderKey.currentState?.viewModel
            .reportInviteeJoinedStatus(joined, joined: true);
      });
      viewModel?.addParticipantToConsentList(event.participant);
      viewModel?.sendPrivateChatHistory(event.participant.identity);
      _sortParticipants();
      _updateInactivityWatcher();
    })
    ..on<ParticipantDisconnectedEvent>((event) {
      _livekitProviderKey.currentState?.viewModel
          .clearScreenShareRequest(event.participant.identity);
      _livekitProviderKey.currentState?.viewModel
          .removeParticipantFromConsentList(event.participant.identity);
      _livekitProviderKey.currentState?.viewModel
          .getAttendanceListForParticipant();
      _livekitProviderKey.currentState?.viewModel
          .fetchInvitedParticipants(silent: true);
      _livekitProviderKey.currentState?.viewModel
          .reportInviteeJoinedStatus(event.participant, joined: false);
      _livekitProviderKey.currentState?.viewModel.clearRaiseHandMemory(event.participant.identity);
      _sortParticipants();
      _updateInactivityWatcher();
    })
    ..on<RoomRecordingStatusChanged>((event) {
      var viewModel = _livekitProviderKey.currentState?.viewModel;
      viewModel?.setRecording(event.activeRecording);
      viewModel?.isRecordingActionInProgress = false;
      if (!event.activeRecording) {
        clearConsentList(viewModel);
      }
      unawaited(playAudio(event.activeRecording
          ? CdnSounds.recordingStart
          : CdnSounds.recordingStop));
      // The chime is played here, so the join-time check must not repeat it.
      isCheckedWhileJoining = true;
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
            _autoStopLocalScreenShare(viewModel);
          }
        }
      }
      _scheduleSortParticipants();
    })
    ..on<LocalTrackPublishedEvent>((track){
      var viewModel = _livekitProviderKey.currentState?.viewModel;
      final localParticipant = widget.room.localParticipant;
      if (localParticipant?.isScreenShareEnabled() == true) {
        // Reset any prior annotation state for the local sharer
        viewModel?.resetAnnotationSharer(localParticipant!.identity);
        viewModel?.sendAction(ActionModel(
            action: MeetingActions.screenShareStarted,
            timeStamp: DateTime.now().microsecondsSinceEpoch));
      }
      _scheduleSortParticipants();
    })
    ..on<LocalTrackUnpublishedEvent>((track){
      if (track.publication.source == TrackSource.screenShareVideo) {
        final viewModel = _livekitProviderKey.currentState?.viewModel;
        final localId = widget.room.localParticipant?.identity;
        if (localId != null) viewModel?.resetAnnotationSharer(localId);
      }
      _scheduleSortParticipants();
    })
    ..on<TrackSubscribedEvent>((_) => _scheduleSortParticipants())
    ..on<TrackUnsubscribedEvent>((_) => _scheduleSortParticipants())
    ..on<TrackE2EEStateEvent>(_onE2EEStateEvent)
    ..on<ParticipantNameUpdatedEvent>((event) {
      _sortParticipants();
    })
    ..on<ParticipantMetadataUpdatedEvent>((event) {
      // Our role lives in our metadata, so a co-host change from any client
      // lands here even when we miss the makeCoHost/removeCoHost message.
      if (event.participant is LocalParticipant) {
        _notifyWhiteboardPermissionChanged();
      }
      // A role change anywhere can move who watches for inactivity.
      _updateInactivityWatcher();
    })
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
    // Intercept annotation messages before MeetingActions validation
    try {
      final json = jsonDecode(utf8.decode(event.data)) as Map<String, dynamic>;
      if (AnnotationActions.all.contains(json['action'])) {
        _handleAnnotationData(json, event.participant);
        return;
      }
    } catch (_) {}

    var eventData0 = parseJsonData(event.data);
    var eventData = eventData0.copyWith(identity: event.participant);
    _checkReceivedDataType(eventData);
  }

  void _handleAnnotationData(
      Map<String, dynamic> data, RemoteParticipant? participant) {
    final viewModel = _livekitProviderKey.currentState?.viewModel;
    if (viewModel == null) return;

    final action = data['action'] as String;
    final sharerIdentity =
        (data['sharerIdentity'] as String?) ?? participant?.identity ?? '';
    if (sharerIdentity.isEmpty) return;

    final localIdentity = widget.room.localParticipant?.identity ?? '';

    // Ignore echo from self, except snapshotRequest (sharer must respond to own unicast)
    if (participant?.identity == localIdentity &&
        action != AnnotationActions.snapshotRequest) return;

    switch (action) {
      case AnnotationActions.stroke:
        final raw = data['stroke'] as Map<String, dynamic>?;
        if (raw == null) return;
        final stroke = AnnotationStroke.fromJson({
          ...raw,
          'fromIdentity': raw['fromIdentity'] ?? participant?.identity ?? '',
        });
        viewModel.addAnnotationStroke(sharerIdentity, stroke);

      case AnnotationActions.remove:
        final ids = List<String>.from(data['ids'] ?? []);
        viewModel.removeAnnotationStrokes(sharerIdentity, ids);

      case AnnotationActions.clear:
        viewModel.clearAnnotationStrokes(sharerIdentity);

      case AnnotationActions.snapshot:
        final strokes = (data['strokes'] as List? ?? [])
            .map((s) => AnnotationStroke.fromJson(s as Map<String, dynamic>))
            .toList();
        viewModel.replaceAnnotationStrokes(sharerIdentity, strokes);

      case AnnotationActions.snapshotRequest:
        final requesterIdentity =
            (data['requesterIdentity'] as String?) ?? participant?.identity ?? '';
        if (localIdentity == sharerIdentity &&
            requesterIdentity.isNotEmpty &&
            requesterIdentity != localIdentity) {
          viewModel.publishAnnotationSnapshot(
              widget.room, sharerIdentity, [requesterIdentity]);
        }
    }
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

      case MeetingActions.lowerHand:
        viewModel?.lowerHand(widget.room.localParticipant?.identity);
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
        if (result != true) break;
        try {
          await viewModel?.enableAudio();
        } catch (_) {
          showSnackBar(
              message: "Couldn't turn on your microphone. Try again.");
        }
        break;

      case MeetingActions.askToUnmuteCamera:
        final result = await context.showPermissionAskDialog(
            "Host is asking you to turn on your camera");
        if (result != true) break;
        try {
          await viewModel?.enableVideo();
        } catch (_) {
          showSnackBar(message: "Couldn't turn on your camera. Try again.");
        }
        break;

      case MeetingActions.makeCoHost:
        viewModel?.setCoHost(true);
        viewModel?.meetingDetails.authorizationToken = remoteData.token ?? "";
        var metadata = viewModel?.room.localParticipant?.metadata;
        final storageHelper = StorageHelper();
        storageHelper
            .setMeetingUid(viewModel?.meetingDetails.meetingUid ?? "");

        final sessionUid = Utils.getMetadataSessionUid(metadata);

        if (sessionUid != null) {
          storageHelper.setSessionUid(sessionUid);
        }

        storageHelper
            .setAttendanceId(Utils.getMetadataAttendanceId(metadata));
        storageHelper.setAttendanceRole(AttendanceRole.cohost);
        storageHelper.setHostToken(remoteData.token ?? "");
        viewModel?.getAttendanceListForParticipant();
        viewModel?.fetchInvitedParticipants(silent: true);
        showSnackBar(message: "${remoteData.identity?.name} made you a Co-Host");
        _notifyWhiteboardPermissionChanged();
        break;

      case MeetingActions.removeCoHost:
        viewModel?.setCoHost(false);
        StorageHelper().setAttendanceRole(AttendanceRole.participant);
        StorageHelper().setHostToken("");
        clearConsentList(viewModel);
        showSnackBar(message: "${remoteData.identity?.name} remove you as a Co-Host");
        _notifyWhiteboardPermissionChanged();
        break;

      case MeetingActions.allowLiveCollabWhiteboard:
        viewModel?.isWhiteboardCollabEnabled = remoteData.value;
        _notifyWhiteboardPermissionChanged();
        break;

      case MeetingActions.forceMuteAll:
        final isAudioModeEnabled = remoteData.value == true;
        viewModel?.isAudioModeEnable = isAudioModeEnabled;
        viewModel?.isAudioPermissionEnable = !isAudioModeEnabled;
        if (isAudioModeEnabled) {
          viewModel?.disableAudio();
        }
        _announceWorkshopChange(viewModel, remoteData.identity?.name);
        break;

      case MeetingActions.forceVideoOffAll:
        final isVideoModeEnabled = remoteData.value == true;
        viewModel?.isVideoModeEnable = isVideoModeEnabled;
        viewModel?.isVideoPermissionEnable = !isVideoModeEnabled;
        if (isVideoModeEnabled) {
          viewModel?.disableVideo();
        }
        _announceWorkshopChange(viewModel, remoteData.identity?.name);
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

      case MeetingActions.stopLiveCaption:
        viewModel?.resetTranscriptionLanguage();
        Future.microtask(() {
          showSnackBar(message: "Live captions stopped");
        });
        break;

      case MeetingActions.liveCaption:
        viewModel?.collectTranscriptionData(remoteData);
        break;

      case MeetingActions.requestLiveCaptionDrawerState:
        viewModel?.checkTranscriptionStateAndReturn(remoteData);
        break;

      case MeetingActions.extendMeetingEndTime:
        showSnackBar(
            message:
                "Meeting extended by ${Constant.meetingExtendTime} minutes");
        _applyMeetingExtension();
        // Somebody took the decision; nobody else needs the prompt any more.
        _dismissMeetingEndingDialog();
        break;

      case MeetingActions.inactiveMeetingAutoEnd:
        // The ROOM_DELETED that follows is labelled from this.
        _inactivityNoticeAt = DateTime.now();
        break;

      case MeetingActions.notificationSoundSetting:
        _applyRemoteNotificationSoundSetting(viewModel, remoteData);
        break;

      case MeetingActions.whiteboardState:
        showSnackBar(
            message: remoteData.value ? "Whiteboard Opened" : "Whiteboard Closed");
        // Shown/hidden via the WhiteboardStatus event this raises.
        viewModel?.setWhiteboardState(remoteData.value,
            whiteboardId: remoteData.whiteboardId);
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
        // Clear any stale annotation strokes from a previous share session
        final startedSharerId = remoteData.identity?.identity;
        if (startedSharerId != null) viewModel?.clearAnnotationStrokes(startedSharerId);
        break;

      case MeetingActions.screenShareStopped:
        showSnackBar(message: "${remoteData.identity?.name} has stopped sharing their screen.");
        final stoppedSharerId = remoteData.identity?.identity;
        if (stoppedSharerId != null) viewModel?.resetAnnotationSharer(stoppedSharerId);
        break;

      case MeetingActions.requestStartRecording:
        viewModel?.handleStartRecordingRequest();
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
        final requesterIdentity = (remoteData.userIdentity?.isNotEmpty == true)
            ? remoteData.userIdentity
            : remoteData.identity?.identity;
        viewModel?.sendPublicChatHistory(requesterIdentity);
        break;

      case MeetingActions.responsePublicChat:
        viewModel?.restorePublicChat(remoteData);
        break;

      case MeetingActions.sendPrivateChat:
        viewModel?.restorePrivateChat(remoteData);
        break;

      case MeetingActions.requestRaisedHands:
        viewModel?.responseRaiseHand(remoteData);
        break;

      case MeetingActions.responseRaisedHands:
        viewModel?.syncRaiseHand(remoteData.raisedHands);
        break;

      case MeetingActions.allowMicPermission:
        viewModel?.isMicPermissionGranted = true;
        showSnackBar(message: "Your mic permission has been granted");
        break;

      case MeetingActions.revokeMicPermission:
        viewModel?.isMicPermissionGranted = false;
        viewModel?.disableAudio();
        showSnackBar(message: "Your mic permission has been revoked");
        break;

      case MeetingActions.allowVideoPermission:
        viewModel?.isVideoPermissionGranted = true;
        showSnackBar(message: "Your video permission has been granted");
        break;

      case MeetingActions.revokeVideoPermission:
        viewModel?.isVideoPermissionGranted = false;
        viewModel?.disableVideo();
        showSnackBar(message: "Your video permission has been revoked");
        break;

      case MeetingActions.allowScreenShareAnnotation:
        viewModel?.isAnnotationEnabled = remoteData.value == true;
        break;

      case MeetingActions.allowAnnotationPermission:
        viewModel?.isAnnotationPermissionGranted = true;
        showSnackBar(message: "You can now annotate the shared screen");
        break;

      case MeetingActions.revokeAnnotationPermission:
        viewModel?.isAnnotationPermissionGranted = false;
        showSnackBar(message: "Your annotation permission has been revoked");
        break;

      case MeetingActions.hideParticipantDrawer:
        final isHidden = remoteData.value == true;
        viewModel?.isParticipantDrawerHidden = isHidden;
        if (isHidden && viewModel?.isParticipantPageOpen == true) {
          _innerNavigatorKey.currentState?.maybePop();
        }
        _announceWorkshopChange(viewModel, remoteData.identity?.name);
        break;

      case MeetingActions.refreshInvitedParticipants:
        viewModel?.fetchInvitedParticipants(silent: true);
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

  void _initMeetingNotificationCallbacks(RtcViewmodel? viewModel) {
    DaakiaMeetingService.initialize();
    DaakiaMeetingService.onMuteToggle = () => _handleNotificationMuteToggle();
    DaakiaMeetingService.onEndCall = () {
      if (mounted) closeMeetingProgrammatically(context);
    };
    if (lkPlatformIs(PlatformType.iOS)) {
      DaakiaMeetingService.onAudioInterruptionBegan = () => _handleAudioInterruptionBegan();
      DaakiaMeetingService.onAudioInterruptionEnded = _handleAudioInterruptionEnded;
    }
  }

  Future<void> _handleAudioInterruptionBegan() async {
    final vm = _livekitProviderKey.currentState?.viewModel;
    if (vm == null || !mounted) return;
    vm.setAudioInterrupted(true);
    setState(() => _isPhoneCallActive = true);
    // Mute the LiveKit track so other participants see the user as muted,
    // not "mic on but silent" for the duration of the phone call.
    final participant = widget.room.localParticipant;
    if (participant != null && participant.isMicrophoneEnabled()) {
      await participant.setMicrophoneEnabled(false);
    }
  }

  // After a phone-call interruption ends on iOS, AVAudioSession has been reactivated
  // by the native side. The mic is left OFF — the user decides when to re-enable it.
  void _handleAudioInterruptionEnded() {
    final vm = _livekitProviderKey.currentState?.viewModel;
    if (vm != null && mounted) {
      vm.setAudioInterrupted(false);
      setState(() => _isPhoneCallActive = false);
      // The native recovery re-activates the session as playAndRecord/videoChat,
      // which drops an earpiece choice or a forced speaker. Put it back.
      unawaited(DaakiaAudioRouting.reapply());
      showSnackBar(message: "Phone call ended");
    }
  }

  Future<void> _handleNotificationMuteToggle() async {
    final vm = _livekitProviderKey.currentState?.viewModel;
    final participant = widget.room.localParticipant;
    if (participant == null || vm == null) return;

    if (participant.isMicrophoneEnabled()) {
      unawaited(vm.disableAudio()); // fire and don't await
    } else {
      await vm.enableAudio();
    }

    // LiveKit propagates the mic-state change asynchronously. A short delay lets
    // isMicrophoneEnabled() settle before we force a UI rebuild.
    await Future.delayed(const Duration(milliseconds: 150));
    if (mounted) setState(() {});
  }

  void _syncNotificationMuteState() {
    if (!lkPlatformIs(PlatformType.android)) return;
    final micEnabled = widget.room.localParticipant?.isMicrophoneEnabled() ?? false;
    if (micEnabled == _lastMicEnabled) return;
    _lastMicEnabled = micEnabled;
    DaakiaMeetingService.updateMuteState(
      isMuted: !micEnabled,
    );
  }

  void _onRoomDidUpdate() {
    _sortParticipants();
    _syncNotificationMuteState();
  }

  void _onE2EEStateEvent(TrackE2EEStateEvent e2eeState) {
    if (kDebugMode) {
      print('e2ee state: $e2eeState');
    }
  }

  // Auto-stops the local user's screen share when another participant
  // (e.g. a web client) starts theirs. Guarded by the same
  // isScreenShareActionInProgress flag as the manual toggle button so that
  // a remote participant rapidly starting/stopping their share can't stack
  // overlapping native teardown calls on top of (or with) a manual toggle —
  // that race is what triggers ANRs on low-end devices (see 07c022b).
  void _autoStopLocalScreenShare(RtcViewmodel? viewModel) async {
    if (viewModel == null || viewModel.isScreenShareActionInProgress) return;
    viewModel.isScreenShareActionInProgress = true;
    try {
      await viewModel.disposeScreenShare();
    } finally {
      viewModel.isScreenShareActionInProgress = false;
    }
  }

  void _scheduleSortParticipants() {
    _sortParticipantsDebounceTimer?.cancel();
    _sortParticipantsDebounceTimer =
        Timer(const Duration(milliseconds: 200), () {
      if (mounted) _sortParticipants();
    });
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

  final GlobalKey<RoomNotificationState> _notificationKey =
      GlobalKey<RoomNotificationState>();

  final GlobalKey<NavigatorState> _innerNavigatorKey =
      GlobalKey<NavigatorState>();

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
          // Keep the view on the board. The board's image export (and any
          // link inside it) otherwise navigates the whole view away to a
          // blob:/data: image or another site, with no way back short of
          // rejoining.
          onNavigationRequest: (NavigationRequest request) {
            if (!request.isMainFrame || _isWhiteboardPage(request.url)) {
              return NavigationDecision.navigate;
            }
            DaakiaVcLogger.logWarning(
                'Whiteboard navigation blocked: ${_describeUrl(request.url)}',
                reportToSentry: false);
            return NavigationDecision.prevent;
          },
          onPageFinished: (_) {
            if (_webViewController.platform is AndroidWebViewController) {
              _webViewController
                  .runJavaScript(WhiteboardFileSelector.cancelScript)
                  .catchError((Object e) {
                DaakiaVcLogger.logWarning(
                    'Whiteboard file-cancel bridge failed: $e',
                    reportToSentry: false);
              });
            }
            _webViewController
                .runJavaScript(WhiteboardDownload.script)
                .catchError((Object e) {
              DaakiaVcLogger.logWarning(
                  'Whiteboard download bridge failed: $e',
                  reportToSentry: false);
            });
          },
        ),
      )
      ..addJavaScriptChannel(
        WhiteboardDownload.channelName,
        onMessageReceived: (message) async {
          final saved = await WhiteboardDownload.save(message.message);
          _livekitProviderKey.currentState?.viewModel.sendMessageToUI(
              saved != null
                  ? 'Saved $saved to Downloads'
                  : "Couldn't save the whiteboard export");
        },
      );
    final platformController = _webViewController.platform;
    if (platformController is AndroidWebViewController) {
      platformController.setOnShowFileSelector(WhiteboardFileSelector.pick);
    }
  }

  bool _isWhiteboardPage(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == Uri.parse(Constant.whiteboardDomain).host;
  }

  /// Scheme and host only: the board URL carries the LiveKit token and
  /// data: URLs carry the whole image.
  String _describeUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'unparseable';
    return uri.hasAuthority ? '${uri.scheme}://${uri.host}' : '${uri.scheme}:';
  }

  /// 👇 Call this function from your event listener to load the URL
  void loadWhiteboardUrl(String url) {
    if (!_webViewInitialized) {
      _webViewInitialized = true;
      _webViewController.loadRequest(Uri.parse(url));
      return;
    }
    // Reopened: if the view was ever pulled off the board, put it back
    // rather than show whatever it was left on.
    _webViewController.currentUrl().then((current) {
      if (current == null || !_isWhiteboardPage(current)) {
        _webViewController.loadRequest(Uri.parse(url));
      }
    }).catchError((Object e) {
      DaakiaVcLogger.logWarning('Whiteboard URL check failed: $e',
          reportToSentry: false);
    });
  }

  /// Tells the whiteboard page that our role or the collaboration setting
  /// changed so it re-fetches its edit permission from the backend straight
  /// away instead of waiting for its 20 s poll. The page debounces bursts, so
  /// calling this for several overlapping events is fine.
  void _notifyWhiteboardPermissionChanged() {
    if (!_webViewInitialized) return;
    _webViewController
        .runJavaScript('window.dispatchEvent(new CustomEvent('
            '"${Constant.whiteboardPermissionChangedEvent}"));')
        .catchError((Object e) {
      DaakiaVcLogger.logWarning('Whiteboard permission signal failed: $e',
          reportToSentry: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.black,
          statusBarIconBrightness: Brightness.light, // white icons on Android
          statusBarBrightness: Brightness.dark,      // white icons on iOS
        ));
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
        // System Back reaches the host app's navigator first and never the
        // meeting's own one below, so a sheet or page opened inside the
        // meeting (attach sheet, chat, participants...) got "Exit Meeting"
        // instead of closing. Close the topmost of those first.
        if (!didPop) {
          final innerNavigator = _innerNavigatorKey.currentState;
          if (innerNavigator != null && innerNavigator.canPop()) {
            innerNavigator.maybePop();
            return;
          }
        }
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
        sdkConfiguration: widget.sdkConfiguration,
        child: MaterialApp(
          navigatorKey: _innerNavigatorKey,
          // The meeting always handles Back: it closes its own sheet/page or
          // asks to exit. By default this nested app told Android the
          // framework can't handle Back once its own stack emptied (e.g.
          // after closing chat), and the host app never corrected it, so
          // Back skipped Flutter, closed the activity and dropped the call.
          onNavigationNotification: (_) {
            SystemNavigator.setFrameworkHandlesBack(true);
            return true;
          },
          debugShowCheckedModeBanner: false,
          theme: DaakiaSdkTheme.meeting,
          home: AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
            ),
            child: (_isInPipMode)
              ? PipScreen(
                  name: widget.room.localParticipant?.name,
                )
              : Stack(
                  children: [
                    Scaffold(
                      backgroundColor: Colors.black,
                      body: SafeArea(
                        child: Container(
                          color: Colors.black,
                          child: _isLandscape(context)
                              ? _buildLandscapeLayout(context)
                              : _buildPortraitLayout(context),
                        ),
                      ),
                    ),

                    /// Toast notification overlay (top-anchored, deduped)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: RoomNotification(key: _notificationKey),
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
                    if (_isPhoneCallActive)
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: ConnectivityBanner(
                          message: "Phone call in progress — audio unavailable",
                          backgroundColor: Colors.orange,
                        ),
                      ),
                  ],
                ),
          ),        // closes AnnotatedRegion
        ),          // closes MaterialApp
      ),            // closes RtcProvider
    );
  }

  // ---------------------------------------------------------------------------
  // Layout
  //
  // Portrait keeps the classic stack: speaker/whiteboard on top, the filmstrip
  // of the remaining participants below it, controls pinned to the bottom.
  // Landscape mirrors that along the other axis — the stage grows into the
  // width freed up by rotating, and the filmstrip + controls become vertical
  // rails on the trailing edge instead of eating the (now scarce) height.
  // ---------------------------------------------------------------------------

  static const double _filmstripPortraitHeight = 120;
  static const double _filmstripPortraitTileWidth = 180;

  bool _isLandscape(BuildContext context) =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  /// Whether there is anything to show in the filmstrip. With the whiteboard up
  /// every participant goes into the strip; otherwise the first track is the
  /// speaker on stage and only the rest are stripped.
  bool get _hasFilmstrip =>
      participantTracks.length > 1 || _isWhiteBoardEnabled;

  int get _filmstripCount => _isWhiteBoardEnabled
      ? participantTracks.length
      : participantTracks.length - 1;

  ParticipantTrack _filmstripTrackAt(int index) => _isWhiteBoardEnabled
      ? participantTracks[index]
      : participantTracks[index + 1];

  Widget _buildPortraitLayout(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _buildStageArea(context, isLandscape: false)),
        if (_hasFilmstrip)
          SizedBox(
            height: _filmstripPortraitHeight,
            child: _buildFilmstrip(
              axis: Axis.horizontal,
              tileWidth: _filmstripPortraitTileWidth,
              tileHeight: _filmstripPortraitHeight,
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
    );
  }

  Widget _buildLandscapeLayout(BuildContext context) {
    // Keep the rail a proportion of the width so it stays a thumbnail strip on
    // a phone and doesn't balloon into a second stage on a tablet.
    final railWidth =
        (MediaQuery.of(context).size.width * 0.18).clamp(130.0, 190.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildStageArea(context, isLandscape: true)),
        if (_hasFilmstrip)
          SizedBox(
            width: railWidth,
            child: _buildFilmstrip(
              axis: Axis.vertical,
              tileWidth: railWidth,
              tileHeight: railWidth * 2 / 3,
            ),
          ),
        if (widget.room.localParticipant != null)
          RtcControls(
            widget.room,
            widget.room.localParticipant!,
            axis: Axis.vertical,
          ),
      ],
    );
  }

  /// The speaker / screen share / whiteboard surface plus everything that
  /// floats on top of it. Overlays are anchored to the stage (not the whole
  /// screen) so they never drift over the filmstrip or the controls rail.
  Widget _buildStageArea(BuildContext context, {required bool isLandscape}) {
    // The stage is the stack's only non-positioned child and StackFit.expand
    // makes it fill: a Stack sizes itself from its non-positioned children, so
    // if every child were positioned (or the only unpositioned one collapsed to
    // zero) the whole stage would collapse with it.
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildStage(),
        // Status pills (workshop / recording) share one centred block at the
        // top of the stage. Both top corners of the speaker tile are already
        // taken — hand raise / zoom-reset on the left, the quick-actions "⋮" on
        // the right — so the block is inset past the widest of them instead of
        // being pinned to a corner, which is what made the recording dot sit
        // under the "⋮" button. Wrap (not Row) means that when both pills are
        // showing on a narrow stage they stack vertically rather than growing
        // into the insets.
        Positioned(
          left: 0,
          right: 0,
          top: 10,
          child: Consumer<RtcViewmodel>(
            builder: (context, viewModel, _) {
              final pills = <Widget>[
                if (viewModel.isWebinarModeEnable)
                  _buildTopStatusIndicator(
                    label: 'Workshop',
                    indicatorColor: const Color(0xFF34C759),
                  ),
                if (viewModel.isRecording)
                  _buildTopStatusIndicator(
                    label: 'Recording',
                    indicatorColor: Colors.red,
                  ),
              ];
              if (pills.isEmpty) {
                return const SizedBox.shrink();
              }
              return IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 84),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: pills,
                  ),
                ),
              );
            },
          ),
        ),
        // Reactions float up the trailing edge of the stage. Landscape starts
        // them higher and keeps them shorter because there is far less height.
        // Display only: as a scrollable it would otherwise swallow every touch
        // in its strip, even when empty, and the whiteboard under it (e.g. the
        // export dialog's close button) couldn't be tapped there.
        Positioned(
          right: 0,
          top: isLandscape ? 8 : 50,
          bottom: isLandscape ? 8 : null,
          child: IgnorePointer(
            child: EmojiReactionWidget(
              viewModel: _livekitProviderKey.currentState?.viewModel,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStage() {
    if (_isWhiteBoardEnabled) {
      return Consumer<RtcViewmodel>(
        builder: (context, viewModel, _) => WhiteBoardWidget(
          key: const ValueKey('whiteboard'),
          controller: _webViewController,
          onClose: viewModel.canManageWhiteboard()
              ? () async {
                  if (await context.showCloseWhiteboardDialog() == true &&
                      viewModel.isWhiteboardOpen) {
                    viewModel.toggleWhiteboard();
                  }
                }
              : null,
          isClosing: viewModel.isWhiteboardActionInProgress,
        ),
      );
    }
    if (participantTracks.isEmpty) {
      return const SizedBox.shrink();
    }

    final speaker = ParticipantWidget.widgetFor(
      participantTracks.first,
      showStatsLayer: true,
      isSpeaker: true,
      key: ValueKey('speaker_${participantTracks.first.participant.identity}'),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        _speakerHasActiveVideo()
            ? GestureDetector(
                onDoubleTap: _resetZoom,
                child: InteractiveViewer(
                  transformationController: _zoomController,
                  minScale: 1.0,
                  maxScale: 4.0,
                  clipBehavior: Clip.hardEdge,
                  child: speaker,
                ),
              )
            : speaker,
        if (_speakerHasActiveVideo() && _zoomScale > 1.05)
          Positioned(
            top: 8,
            left: 8,
            child: GestureDetector(
              onTap: _resetZoom,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_out, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text('Reset',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFilmstrip({
    required Axis axis,
    required double tileWidth,
    required double tileHeight,
  }) {
    final isVertical = axis == Axis.vertical;
    return ListView.builder(
      scrollDirection: axis,
      padding: isVertical
          ? const EdgeInsets.symmetric(vertical: 4)
          : EdgeInsets.zero,
      itemCount: _filmstripCount,
      itemBuilder: (BuildContext context, int index) {
        final track = _filmstripTrackAt(index);
        return Padding(
          padding: isVertical
              ? const EdgeInsets.only(bottom: 4)
              : EdgeInsets.zero,
          child: SizedBox(
            width: tileWidth,
            height: tileHeight,
            child: ParticipantWidget.widgetFor(
              track,
              key: ValueKey(track.participant.identity),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _showExitConfirmationDialog(BuildContext context) {
    return confirmLeaveMeeting(context,
        useCallTerminology:
            _livekitProviderKey.currentState?.viewModel.useCallTerminology ??
                false);
  }

  Widget _buildTopStatusIndicator({
    required String label,
    required Color indicatorColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: indicatorColor.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: indicatorColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: indicatorColor.withValues(alpha: 0.7),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Surfaces [RoomPage.joinNotice], once the meeting UI has settled enough
  /// for the banner to be seen rather than swallowed by the join animation.
  void _showJoinNotice() {
    final notice = widget.joinNotice;
    if (notice == null || notice.isEmpty) return;
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        showSnackBar(message: notice, duration: const Duration(seconds: 6));
      }
    });
  }

  void showSnackBar({
    required String message,
    String? actionText,
    Function? actionCallBack,
    Duration? duration,
    VoidCallback? onDismiss,
  }) {
    _notificationKey.currentState?.show(
      message: message,
      actionText: actionText,
      actionCallback: actionCallBack != null ? () => actionCallBack() : null,
      duration: duration,
      onDismiss: onDismiss,
    );
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
      } else if (event is ShowWorkshopModeNotice) {
        // Joining a meeting that's already in Workshop mode: no actor to name,
        // and the controller drops it if nothing is actually restricted.
        _announceWorkshopChange(viewModel, null);
      } else if (event is ShowReaction) {
        showReaction(event.emoji, viewModel);
      } else if (event is UpdateView) {
        if (mounted) {
          setState(() {});
        }
      } else if (event is EndMeeting) {
        if (_inactivityAutoClosed) {
          _finishInactivityEnd(viewModel);
          return;
        }
        // Down first: with the prompt on top, the pop below would close it
        // instead of the meeting.
        _stopInactivityWatcher();
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

  /// Announces a Workshop-mode change made by somebody else.
  ///
  /// Everyone still in the room hears about it, but not in the same words:
  /// participants are told what's been taken away from them, while hosts and
  /// co-hosts — exempt from the restrictions — are told what changed for
  /// everyone else, so a co-host flipping the switch doesn't leave the host
  /// guessing. The person who flipped it doesn't receive their own data
  /// message; they got the summary from the Host controls screen already.
  ///
  /// The calling case has already applied the change to the viewmodel, so
  /// reading the three flags back off it gives the restrictions currently in
  /// force — which is exactly what the notice lists.
  void _announceWorkshopChange(RtcViewmodel? viewModel, String? actorName) {
    if (!mounted) return;
    if (viewModel == null) return;
    final isModerator = viewModel.isHost() || viewModel.isCoHost();
    _workshopNotice.report(
      context,
      micLocked: viewModel.isAudioModeEnable,
      cameraLocked: viewModel.isVideoModeEnable,
      participantListHidden: viewModel.isParticipantDrawerHidden,
      audience: isModerator
          ? WorkshopAudience.moderator
          : WorkshopAudience.participant,
      actorName: actorName,
    );
  }

  /// Tells a real second-device join apart from this device kicking itself
  /// during a reconnect (see [_lastReconnectAttemptAt]). The meeting has ended
  /// here either way; only the explanation differs.
  void _onDuplicateIdentity() {
    final lastAttempt = _lastReconnectAttemptAt;
    final sinceReconnect =
        lastAttempt == null ? null : DateTime.now().difference(lastAttempt);
    if (sinceReconnect == null || sinceReconnect > _selfKickWindow) {
      debugPrint('[Livekit] - DUPLICATE_IDENTITY: another device '
          '(last reconnect attempt: '
          '${sinceReconnect == null ? 'none' : '${sinceReconnect.inSeconds}s ago'})');
      _showDuplicateIdentityDialog();
      return;
    }
    debugPrint('[Livekit] - DUPLICATE_IDENTITY: connection drop '
        '(last reconnect attempt: ${sinceReconnect.inSeconds}s ago)');
    DaakiaVcLogger.logInfo(
      'DUPLICATE_IDENTITY during reconnect, treated as a connection drop',
      attributes: {
        'meetingId': widget.meetingDetails.meetingUid,
        'secondsSinceReconnectAttempt': sinceReconnect.inSeconds,
      },
    );
    _showDuplicateIdentityDialog(connectionDropped: true);
  }

  void _showDuplicateIdentityDialog({bool connectionDropped = false}) {
    void onLeave(BuildContext dialogCtx) {
      Navigator.of(dialogCtx).pop();
      closeMeetingProgrammatically(context);
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => connectionDropped
          ? DuplicateIdentityDialog.connectionDropped(
              onLeave: () => onLeave(dialogCtx))
          : DuplicateIdentityDialog(onLeave: () => onLeave(dialogCtx)),
    );
  }

  // When closing the meeting programmatically
  void closeMeetingProgrammatically(BuildContext context) {
    _isProgrammaticPop = true; // Set the flag
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  void _meetingEndLogic(RtcViewmodel? viewModel) {
    //TODO NEED TO UPDATE LOGIC
    if (viewModel?.meetingClosesAtScheduledEnd() == true) {
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

  /// Plays the recording chime for [soundKey]: from the cached file when it
  /// has been downloaded, otherwise streamed from the backend URL, retrying
  /// once on the fallback URL.
  ///
  /// Uses mediaPlayer rather than lowLatency. On Android, lowLatency (SoundPool)
  /// downloads the URL on a background thread that doesn't handle errors, so
  /// an offline device or a host that doesn't resolve crashes the whole app.
  /// mediaPlayer reports the failure back here instead.
  Future<void> playAudio(String soundKey) async {
    final cached = CdnSounds.cachedFile(soundKey);
    final sources = <Source>[
      if (cached != null) DeviceFileSource(cached),
      for (final url in {CdnSounds.url(soundKey), CdnSounds.fallbackUrl(soundKey)})
        UrlSource(url),
    ];
    for (final source in sources) {
      try {
        // A source that never loads can leave play() pending, hence the timeout.
        await player
            .play(source, mode: PlayerMode.mediaPlayer)
            .timeout(const Duration(seconds: 10));
        return;
      } catch (e) {
        // Only the chime is lost; the recording state change itself still lands.
        debugPrint("Recording chime failed to play from $source: $e");
      }
    }
  }

  //===============================[Inactive meeting prompt]===============================

  /// Runs the idle clock while this device is the elected watcher. Null when
  /// the feature is off for the meeting.
  InactiveMeetingWatcher? _inactivityWatcher;
  BuildContext? _inactivityDialogContext;

  /// Set when this device's countdown ran out and it is closing the meeting.
  bool _inactivityAutoClosed = false;

  /// When another device last announced it is ending the meeting for
  /// inactivity.
  DateTime? _inactivityNoticeAt;

  /// Guards [_finishInactivityEnd]: the end can be reached through both the
  /// end-meeting response and the ROOM_DELETED disconnect.
  bool _inactivityEndStarted = false;

  void _initInactivityWatcher(RtcViewmodel? viewModel) {
    if (viewModel == null || !viewModel.isInactivePromptEnabled()) return;
    _inactivityWatcher = InactiveMeetingWatcher(
      room: widget.room,
      timeout: viewModel.inactiveTimeout(),
      onShowPrompt: () => _showInactivityPrompt(viewModel),
      onHidePrompt: _closeInactivityPrompt,
    );
    _updateInactivityWatcher();
  }

  /// Re-runs the election and starts or stops the clock to match. Called on
  /// connect, reconnect, joins, leaves and role changes.
  void _updateInactivityWatcher() {
    final watcher = _inactivityWatcher;
    if (watcher == null || !mounted || _inactivityAutoClosed) return;
    final room = widget.room;
    if (room.connectionState == ConnectionState.connected &&
        InactiveMeetingRules.isWatcher(room)) {
      watcher.start();
    } else {
      // Whoever takes over starts a fresh clock of their own.
      watcher.stop();
    }
  }

  void _stopInactivityWatcher() {
    _inactivityWatcher?.stop();
    // Also covers a prompt left at 0:00 while the meeting is being closed.
    _closeInactivityPrompt();
  }

  bool _showInactivityPrompt(RtcViewmodel viewModel) {
    final watcher = _inactivityWatcher;
    // Never stacked on the meeting-end warning; the watcher asks again once
    // that card is gone.
    if (!mounted || watcher == null || _isEndingDialogOpen) return false;

    BuildContext? openedWith;
    showInactiveMeetingDialog(
      context,
      solo: watcher.solo,
      canEndForAll: () => InactiveMeetingRules.canEndForAll(widget.room),
      onStay: watcher.stay,
      onLeave: () => _leaveMeetingAfterPrompt(viewModel),
      onEnd: () => _endMeetingFromPrompt(viewModel),
      onCountdownZero: () => _onInactivityCountdownZero(viewModel),
      onOpened: (dialogContext) =>
          _inactivityDialogContext = openedWith = dialogContext,
    ).then((_) {
      // A newer prompt may already be up; only clear what this one set.
      if (_inactivityDialogContext != openedWith) return;
      _inactivityDialogContext = null;
      _inactivityWatcher?.promptClosed();
    });
    return true;
  }

  /// Pops the prompt's own route, even if something was pushed above it.
  void _closeInactivityPrompt() {
    final dialogContext = _inactivityDialogContext;
    if (dialogContext == null || !dialogContext.mounted) return;
    final route = ModalRoute.of(dialogContext);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(dialogContext).pop();
    } else {
      Navigator.of(dialogContext).removeRoute(route);
    }
  }

  /// Leave now: exactly what the Leave button does — this device only.
  void _leaveMeetingAfterPrompt(RtcViewmodel viewModel) {
    _stopInactivityWatcher();
    viewModel.isMeetingEnded = true;
    viewModel.sendEvent(EndMeeting(reason: "clientInitiated"));
  }

  /// End meeting, pressed by a host or co-host. Same API as the regular End
  /// button. On failure the prompt stays open with the reason so they can try
  /// again; on success the regular end flow closes everything.
  Future<String?> _endMeetingFromPrompt(RtcViewmodel viewModel) {
    final result = Completer<String?>();
    viewModel.endMeetingForAll(onFailed: (message) {
      if (!result.isCompleted) result.complete(message);
    });
    return result.future;
  }

  void _onInactivityCountdownZero(RtcViewmodel viewModel) {
    final room = widget.room;
    // Recording started, or someone came back, during the countdown.
    if (room.isRecording || !InactiveMeetingRules.isIdle(room)) {
      _inactivityWatcher?.stay();
      return;
    }

    _inactivityAutoClosed = true;
    // Head-count now, not whichever text the prompt was showing.
    final groupEnd = InactiveMeetingRules.humans(room).length > 1 &&
        InactiveMeetingRules.canEndForAll(room);
    if (!groupEnd) {
      // Solo, or a group watcher who can't end it: leave. The backend closes
      // an empty room; in a group the next watcher starts its own clock.
      viewModel.sendEvent(EndMeeting(reason: "clientInitiated"));
      return;
    }

    // Tell everyone first, so their ROOM_DELETED reads as an inactivity end.
    unawaited(viewModel.sendAction(
        ActionModel(action: MeetingActions.inactiveMeetingAutoEnd)));
    Timer(const Duration(milliseconds: Constant.inactiveEndNoticeLeadMs), () {
      if (!mounted) return;
      viewModel.endMeetingForAll(onFailed: (message) {
        if (!mounted) return;
        // Don't leave the host on a 0:00 prompt: leave, and let the meeting
        // carry on for the others until the next watcher tries.
        showSnackBar(message: message);
        viewModel.sendEvent(EndMeeting(reason: "clientInitiated"));
      });
    });
  }

  bool _isInactivityEnd(DisconnectReason? reason) {
    if (_inactivityAutoClosed) return true;
    final noticeAt = _inactivityNoticeAt;
    if (reason != DisconnectReason.roomDeleted || noticeAt == null) {
      return false;
    }
    final age = DateTime.now().difference(noticeAt);
    return !age.isNegative &&
        age <
            const Duration(milliseconds: Constant.inactiveEndNoticeValidityMs);
  }

  /// Closes the meeting behind the "ended due to inactivity" screen.
  void _finishInactivityEnd(RtcViewmodel? viewModel) {
    if (_inactivityEndStarted) return;
    _inactivityEndStarted = true;
    // Our own disconnect below must not show "You have left the meeting."
    _disconnectHandled = true;
    _stopInactivityWatcher();
    viewModel?.isMeetingEnded = true;
    clearMemory(viewModel);
    DatadogDisconnectLogger.logDisconnectEvent(
        meetingId: widget.meetingDetails.meetingUid,
        room: widget.room,
        reason: "INACTIVITY");
    unawaited(widget.room.disconnect());
    if (!mounted) return;
    showInactivityEndedDialog(context).then((_) {
      if (mounted) closeMeetingProgrammatically(context);
    });
  }

  //===============================[End of meeting warning]===============================

  /// Its own player, so a recording chime starting or stopping can't cut the
  /// warning short (and vice versa).
  AudioPlayer? _meetingEndWarningPlayer;

  /// The in-flight preparation, shared by everyone who wants the chime.
  ///
  /// Joining a meeting that is already inside its final minutes fires the
  /// warning on the scheduler's very first check — before the clip has
  /// finished loading. Routing every caller through this one future means a warning
  /// that arrives early waits for the same player instead of racing ahead and
  /// building a second one.
  Future<AudioPlayer?>? _meetingEndWarningPreparation;

  /// Whether the chime is still wanted. Cleared on dismiss, so a warning that
  /// is dismissed while the clip is still loading stays silent rather than
  /// starting up after the user waved it away.
  bool _meetingEndWarningWanted = false;

  /// Ends the looping chime when the warning window closes. See
  /// [_playMeetingEndWarningSound].
  Timer? _meetingEndWarningCutoff;
  bool _isEndingDialogOpen = false;
  BuildContext? _endingDialogContext;

  /// Tiers whose message and chime have already been delivered here.
  final Set<int> _warnedTiers = {};

  /// Tiers whose extend prompt this client has already been shown. Tracked
  /// apart from [_warnedTiers] because a co-host who inherits the leadership
  /// mid-window has not been prompted yet, even though the tier is old news.
  final Set<int> _promptedTiers = {};

  /// Whether the post-join re-read of the end time has come back. Until then
  /// the extend prompt is held, as on web, so it can't offer an extension that
  /// was used while this client sat on pre-join.
  bool _isMeetingEndTimeSynced = false;

  /// Starts, or joins, preparation of the chime. Runs at most once.
  ///
  /// Kicked off on join rather than when the warning fires, so that decoding
  /// the clip is already done by the time a warning wants it.
  ///
  /// The clip is a bundled asset, not a URL. It used to be fetched from blob
  /// storage on every join; on a late join that download raced the WebRTC
  /// connect for the network and the chime trailed its dialog by 3–7s.
  Future<AudioPlayer?> _prepareMeetingEndWarningSound() =>
      _meetingEndWarningPreparation ??= _createMeetingEndWarningPlayer();

  Future<AudioPlayer?> _createMeetingEndWarningPlayer() async {
    try {
      final warningPlayer = AudioPlayer()
        // Own cache, so pointing it at this package's assets doesn't change the
        // prefix of the app-wide AudioCache.instance a host app may rely on.
        ..audioCache = AudioCache(prefix: Constant.meetingEndWarningSoundDir);
      // Order matters. The Android backend is picked from the player mode, so
      // setting the mode after the source throws away whatever the previous
      // backend had prepared. lowLatency selects SoundPool, which decodes the
      // clip into memory here, at join time — otherwise the mp3 decoder is
      // allocated at the instant the warning fires and the chime lags the
      // dialog by a couple of seconds.
      await warningPlayer.setPlayerMode(PlayerMode.lowLatency);
      // The clip is three dings cut on exact period boundaries, so looping it
      // keeps ringing for as long as the warning is up. Loop mode also keeps
      // the clip loaded between warnings; the default ReleaseMode.release
      // would unload it and make the second warning pay the load cost again.
      await warningPlayer.setReleaseMode(ReleaseMode.loop);
      await warningPlayer.setSourceAsset(Constant.meetingEndWarningSound);
      if (!mounted) {
        await warningPlayer.dispose();
        return null;
      }
      _meetingEndWarningPlayer = warningPlayer;
      return warningPlayer;
    } catch (e) {
      // Temp directory unwritable, audio backend refusing the clip. The warning
      // message still shows; only the chime is lost, so this isn't worth
      // surfacing to the user.
      debugPrint("Could not prepare meeting-end warning sound: $e");
      return null;
    }
  }

  /// Plays the chime from the beginning, off the already-decoded clip.
  ///
  /// `stop()` rewinds to the start and `resume()` replays it. Deliberately not
  /// `play()`, which re-applies the mode and re-sets the source and so rebuilds
  /// the platform player — the very cost the preparation exists to avoid. And
  /// deliberately not `seek(0)`, which on a source that was set but never
  /// played hangs and throws `TimeoutException` out of `AudioPlayer.seek` 30s
  /// later, as an unhandled async error.
  Future<void> _playMeetingEndWarningSound() async {
    _meetingEndWarningWanted = true;
    try {
      final warningPlayer = await _prepareMeetingEndWarningSound();
      if (warningPlayer == null) return;
      // Preparation can still be loading on a late join. If the warning was
      // dismissed while we waited, honour that instead of starting a sound the
      // user has already cancelled.
      if (!mounted || !_meetingEndWarningWanted) return;
      // Dismissing the warning stops the loop, but the card stays up until
      // someone acts on it — so the loop is also capped rather than ringing
      // indefinitely at an unattended device.
      _meetingEndWarningCutoff?.cancel();
      _meetingEndWarningCutoff = Timer(
        const Duration(
            milliseconds: Constant.meetingEndWarningSoundDurationMs),
        () => unawaited(_stopMeetingEndWarningSound()),
      );
      await warningPlayer.stop();
      await warningPlayer.resume();
    } catch (e) {
      // A silent warning is a nuisance; an unhandled async error is a crash.
      debugPrint("Meeting-end warning sound failed to play: $e");
    }
  }

  Future<void> _stopMeetingEndWarningSound() async {
    _meetingEndWarningWanted = false;
    _meetingEndWarningCutoff?.cancel();
    _meetingEndWarningCutoff = null;
    try {
      await _meetingEndWarningPlayer?.stop();
    } catch (e) {
      debugPrint("Meeting-end warning sound failed to stop: $e");
    }
  }

  /// Delivers one warning tier, split the same three ways as the web client:
  ///
  ///  * the elected leader of an extendable meeting gets the extend dialog at
  ///    both tiers, which stands in for the notice;
  ///  * everyone else gets a notice — at the early tier only if they are a host
  ///    or co-host, at the final tier regardless. It is the same countdown card
  ///    without Extend when the meeting really closes at zero, or a
  ///    twelve-second message when it doesn't;
  ///  * hosts and co-hosts additionally hear the chime, at the final tier only,
  ///    and only while the setting is on.
  ///
  /// Called on every tick the tier's window is open, so the dedupe here is what
  /// keeps the message from re-appearing every ten seconds — while still
  /// letting a newly-elected leader be prompted partway through the window.
  void _handleMeetingEndingSoon(
      RtcViewmodel? viewModel, MeetingEndingSoon event) {
    if (!mounted || viewModel == null) return;

    final tier = event.minutesRemaining;
    final isExtendLeader =
        meetingManager.canExtendMeeting && viewModel.isMeetingExtendLeader();

    if (isExtendLeader) {
      // Not marked as prompted, so the next tick offers it once synced.
      if (!_isMeetingEndTimeSynced) return;
      if (!_promptedTiers.add(tier)) return;
      // The prompt stands in for the message and carries the chime with it.
      if (event.isFinalWarning &&
          _warnedTiers.add(tier) &&
          viewModel.shouldPlayMeetingEndSound()) {
        unawaited(_playMeetingEndWarningSound());
      }
      _showExtendMeetingDialog(viewModel);
      return;
    }

    // The early tier is a heads-up for moderators; participants wait for the
    // final one.
    if (!event.isFinalWarning && !viewModel.isHost() && !viewModel.isCoHost()) {
      return;
    }
    if (!_warnedTiers.add(tier)) return;

    if (event.isFinalWarning && viewModel.shouldPlayMeetingEndSound()) {
      unawaited(_playMeetingEndWarningSound());
    }
    // Only a meeting that really closes at zero gets the countdown card; one
    // that stays open keeps the message, as a countdown to nothing would tell
    // everyone something untrue.
    if (viewModel.meetingClosesAtScheduledEnd()) {
      _showMeetingEndingNotice();
      return;
    }
    // The chime is not tied to this message: the notice goes away on its own
    // timeout or whenever any later notice replaces it, which would cut the
    // sound short. It runs out on its own cutoff instead.
    showSnackBar(
      message: "Meeting will end in $tier minutes.",
      duration:
          const Duration(milliseconds: Constant.meetingEndWarningDurationMs),
    );
  }

  /// Moves the end time out and re-arms the warnings against it.
  ///
  /// The extend prompt does not come back — [MeetingManager.canExtendMeeting]
  /// is false from here on — but the new end time gets its own final warning.
  void _applyMeetingExtension() {
    meetingManager.extendMeetingBy10Minutes();
    _warnedTiers.clear();
    _promptedTiers.clear();
  }

  void _showExtendMeetingDialog(RtcViewmodel viewModel) {
    if (!mounted || _isEndingDialogOpen) return;
    _isEndingDialogOpen = true;

    showMeetingEndingDialog(
      context,
      // Read live, so a card left open keeps counting down to the real end.
      endTime: () => meetingManager.endDateTime,
      extendMinutes: Constant.meetingExtendTime,
      onOpened: (dialogContext) => _endingDialogContext = dialogContext,
      onExtend: () => _requestMeetingExtension(viewModel),
    ).then((_) {
      _isEndingDialogOpen = false;
      _endingDialogContext = null;
      // Dismissing is personal and stops only this client's sound; the meeting
      // still ends on schedule, and the next tier still fires.
      unawaited(_stopMeetingEndWarningSound());
      // The inactivity prompt held back for this card can show now.
      _inactivityWatcher?.check();
    });
  }

  /// The final warning for everyone who isn't being offered the extension: the
  /// same live countdown card, without the Extend button.
  void _showMeetingEndingNotice() {
    if (!mounted || _isEndingDialogOpen) return;
    _isEndingDialogOpen = true;

    showMeetingEndingDialog(
      context,
      endTime: () => meetingManager.endDateTime,
      onOpened: (dialogContext) => _endingDialogContext = dialogContext,
    ).then((_) {
      _isEndingDialogOpen = false;
      _endingDialogContext = null;
      // The card and the chime are one unit, as with the prompt.
      unawaited(_stopMeetingEndWarningSound());
      _inactivityWatcher?.check();
    });
  }

  /// Asks the backend for the extension on the dialog's behalf.
  ///
  /// Resolves to null once it is accepted, or to the backend's reason when it
  /// isn't, which the dialog shows in place so the host can retry. The local
  /// clock moves only once the backend agrees, so a rejected extend doesn't
  /// leave this client counting down to a different end than everyone else.
  Future<String?> _requestMeetingExtension(RtcViewmodel viewModel) {
    final result = Completer<String?>();
    viewModel.meetingTimeExtend(
      onExtended: () {
        if (mounted) {
          _applyMeetingExtension();
          showSnackBar(
              message:
                  "Meeting extended by ${Constant.meetingExtendTime} minutes");
        }
        if (!result.isCompleted) result.complete(null);
      },
      onFailed: (message) {
        if (!result.isCompleted) result.complete(message);
      },
    );
    return result.future;
  }

  /// Adopts an end-meeting-sound toggle broadcast by another client.
  ///
  /// Everyone used to read this once on join, which went stale the moment a
  /// host flipped it mid-meeting; the broadcast keeps every client honest.
  /// Only moderators may change it, so a message from a regular participant is
  /// dropped rather than trusted — otherwise anyone could silence the hosts.
  void _applyRemoteNotificationSoundSetting(
      RtcViewmodel? viewModel, RemoteActivityData remoteData) {
    if (viewModel == null) return;

    final sender = remoteData.identity;
    final senderMetadata = sender?.metadata;
    final isSenderHost = Utils.isHost(senderMetadata);
    final isSenderCoHost = Utils.isCoHost(senderMetadata);
    if (!isSenderHost && !isSenderCoHost) return;

    viewModel.isNotificationSoundEnabled = remoteData.value;

    // Who changed it is moderator business — participants have no toggle and
    // no sound, so the notice would mean nothing to them.
    if (!viewModel.isHost() && !viewModel.isCoHost()) return;

    final name = sender?.name.isNotEmpty == true ? sender!.name : "Someone";
    final role = isSenderHost ? "Host" : "Co-Host";
    final change = remoteData.value ? "enabled" : "disabled";
    showSnackBar(message: "$name ($role) $change the end meeting sound.");
  }

  /// Closes the prompt once somebody, anybody, has extended the meeting.
  void _dismissMeetingEndingDialog() {
    final dialogContext = _endingDialogContext;
    if (!_isEndingDialogOpen || dialogContext == null) return;
    if (!dialogContext.mounted) return;
    Navigator.of(dialogContext).pop();
  }

  var isCheckedWhileJoining = false;

  void checkRecordingPlayer(bool isRecording) {
    if (isRecording && !isCheckedWhileJoining) {
      unawaited(playAudio(CdnSounds.recordingStart));
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
    final isAndroid = lkPlatformIs(PlatformType.android);
    final isIOS = lkPlatformIs(PlatformType.iOS);
    if (!isAndroid && !isIOS) return;

    final title = widget.meetingDetails.meetingBasicDetails?.eventName ?? "Meeting";

    if (enable) {
      if (isAndroid) {
        final micEnabled = widget.room.localParticipant?.isMicrophoneEnabled() ?? false;
        await DaakiaMeetingService.start(
          title: title,
          isMuted: !micEnabled,
          showMuteButton: false,
        );
      } else {
        // iOS: activate AVAudioSession so the app survives background even
        // when the user's microphone is muted (no active capture track).
        await DaakiaMeetingService.start(title: title);
      }
    } else {
      await DaakiaMeetingService.stop();
    }
  }

  void clearMemory(RtcViewmodel? viewModel) {
    viewModel?.disposeScreenShare();
    viewModel?.unregisterCaption();
    // unawaited is intentional — dispose() is synchronous so we can't await here.
    // DaakiaMeetingService.stop() has its own try-catch and is safe to fire-and-forget.
    unawaited(handleAndroidNotification(enable: false));
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
