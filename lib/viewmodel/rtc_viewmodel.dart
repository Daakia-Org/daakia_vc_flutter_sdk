import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:daakia_vc_flutter_sdk/api/injection.dart';
import 'package:daakia_vc_flutter_sdk/events/rtc_events.dart';
import 'package:daakia_vc_flutter_sdk/model/consent_participant.dart';
import 'package:daakia_vc_flutter_sdk/model/edit_message.dart';
import 'package:daakia_vc_flutter_sdk/model/participant_attendance_data.dart';
import 'package:daakia_vc_flutter_sdk/model/reaction_model.dart';
import 'package:daakia_vc_flutter_sdk/model/remote_activity_data.dart';
import 'package:daakia_vc_flutter_sdk/model/reply_message.dart';
import 'package:daakia_vc_flutter_sdk/model/transcription_action_model.dart';
import 'package:daakia_vc_flutter_sdk/model/transcription_model.dart';
import 'package:daakia_vc_flutter_sdk/resources/json/language_json.dart';
import 'package:daakia_vc_flutter_sdk/utils/storage_helper.dart';
import 'package:daakia_vc_flutter_sdk/utils/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:uuid/uuid.dart';

import '../enum/chat_type_enum.dart';
import '../enum/attendance_role_enum.dart';
import '../model/action_model.dart';
import '../model/caption_data.dart';
import '../model/emoji_message.dart';
import '../model/language_model.dart';
import '../model/meeting_details.dart';
import '../model/private_chat_model.dart';
import '../model/raised_hand.dart';
import '../model/send_message_model.dart';
import '../rtc/widgets/participant_info.dart';
import '../utils/chat_message_mapper.dart';
import '../utils/consent_status_enum.dart';
import '../utils/constants.dart';
import '../utils/meeting_actions.dart';

class RtcViewmodel extends ChangeNotifier {
  final List<RemoteActivityData> _messageList = [];
  final List<RemoteActivityData> _lobbyRequestList = [];
  final Map<String, PrivateChatModel> _privateChat = {};
  late Room room;
  late MeetingDetails meetingDetails;

  final List<ParticipantTrack> _participantTracks = [];

  final Map<String, bool> _raisedHandMap = {};
  final List<RaisedHand> _raisedHandQueue = [];

  bool _isMyHandRaised = false;

  bool isChatOpen = false;
  int _unreadMessageCount = 0;

  bool isPrivateChatOpen = false;
  int _unreadMessageCountPrivateChat = 0;

  bool _isCoHost = false;

  bool _isRecording = false;

  bool _isMeetingEnded = false;

  // Getter
  bool get isMeetingEnded => _isMeetingEnded;

// Setter
  set isMeetingEnded(bool value) {
    _isMeetingEnded = value;
    notifyListeners();
  }

  void setCoHost(bool isCoHost) {
    _isCoHost = isCoHost;
    notifyListeners();
  }

  bool getCoHost() => _isCoHost;

  int getUnReadCount() {
    return _unreadMessageCount;
  }

  void increaseUnreadCount() {
    if (isChatOpen) return;
    _unreadMessageCount++;
    sendMainChatControllerEvent(UpdateView());
    notifyListeners();
  }

  void resetUnreadCount() {
    _unreadMessageCount = 0;
    sendMainChatControllerEvent(UpdateView());
    notifyListeners();
  }

  int getUnreadCountPrivateChat() {
    return _unreadMessageCountPrivateChat;
  }

  void increaseUnreadPrivateChatCount() {
    _unreadMessageCountPrivateChat++;
    sendMainChatControllerEvent(UpdateView());
    notifyListeners();
  }

  void resetUnreadPrivateChatCount(PrivateChatModel person) {
    if (_unreadMessageCountPrivateChat == 0) return;
    _unreadMessageCountPrivateChat -= person.unreadCount;
    person.unreadCount = 0;
    sendMainChatControllerEvent(UpdateView());
    notifyListeners();
  }

  RtcViewmodel(this.room, this.meetingDetails);

  List<RemoteActivityData> getMessageList() {
    return _messageList;
  }

  void addMessage(RemoteActivityData message) {
    _messageList.add(message);
    increaseUnreadCount();
    notifyListeners();
    sendPublicChatEvent(UpdateView());
  }

  void addAllMessage(List<RemoteActivityData> message) {
    _messageList.addAll(message);
    notifyListeners();
    sendPublicChatEvent(UpdateView());
  }

  void addPrivateMessage(RemoteActivityData message) {
    if (message.identity != null) {
      final identity = message.identity?.identity ?? "";
      final name = message.identity?.name ?? "Unknown";

      checkAndCreatePrivateChat(identity, name);
      _privateChat[identity]?.chats.add(message);

      final chatModel = _privateChat[identity];
      if (chatModel == null) return;

      // ✅ FIXED LOGIC
      // Increase unread if:
      // - Chat page is closed (normal case)
      // - OR Chat page is open but this particular chat is not selected
      if ((chatModel.identity != _privateChatIdentity) || !isPrivateChatOpen) {
        chatModel.unreadCount++;
        increaseUnreadPrivateChatCount();
      }
    } else {
      final identity = message.userIdentity ?? "Unknown";
      final name = message.userName ?? "Unknown";

      _privateChat.putIfAbsent(
        identity,
        () => PrivateChatModel(identity: identity, name: name, chats: []),
      );
      _privateChat[identity]?.chats.add(message);
    }

    notifyListeners();
    sendPrivateChatEvent(UpdateView());
  }

  void checkAndCreatePrivateChat(String? identity, String? name) {
    _privateChat.putIfAbsent(
        identity ?? "Unknown",
        () => PrivateChatModel(
            identity: identity ?? "Unknown",
            name: name ?? "Unknown",
            chats: []));
    notifyListeners();
    sendPrivateChatEvent(UpdateView());
  }

  Map<String, PrivateChatModel> getPrivateMessage() {
    return _privateChat;
  }

  List<RemoteActivityData> getPrivateChatForParticipant(String identity) {
    return _privateChat[identity]?.chats ?? [];
  }

  bool hasPrivateChat(String identity) {
    return _privateChat[identity]?.chats.isNotEmpty ?? false;
  }

  Future<void> sendPublicMessage(String userMessage) async {
    if (!Utils.isMessageSizeValid(userMessage)) {
      sendMessageToUI("Message is too long! Please shorten it and try again.");
      return;
    }
    // Create a message
    final message = SendMessageModel(
      action: MeetingActions.sendPublicMessage,
      id: const Uuid().v4(),
      // Generate a unique ID
      message: userMessage,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      // Current timestamp
      isReplied: _publicReplyDraft != null,
      replyMessage: _publicReplyDraft,
    );

    // Publish the data to the LiveKit room
    await room.localParticipant?.publishData(
      utf8.encode(jsonEncode(message)), // Convert to bytes,
      reliable: true,
    );

    // Update the message list
    addMessage(
      RemoteActivityData(
          identity: null,
          fromUserId: room.localParticipant?.identity,
          id: message.id,
          message: message.message,
          timestamp: message.timestamp,
          action: MeetingActions.sendPublicMessage,
          // Assuming no action is provided
          isSender: true,
          // isSender
          replyMessage: message.replyMessage),
    );
    publicReplyDraft = null;
  }

  Future<void> sendPrivateMessage(
      String? identity, String? name, String userMessage) async {
    if (!Utils.isMessageSizeValid(userMessage)) {
      sendMessageToUI("Message is too long! Please shorten it and try again.");
      return;
    }
    // Create a message
    final message = SendMessageModel(
      action: MeetingActions.sendPrivateMessage,
      id: const Uuid().v4(),
      // Generate a unique ID
      message: userMessage,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      // Current timestamp
      isReplied: privateReplyDraft != null,
      replyMessage: privateReplyDraft,
    );

    if (identity != null) {
      List<String> participantList = [identity];
      try {
        // Publish the data to the LiveKit room
        await room.localParticipant?.publishData(
          utf8.encode(jsonEncode(message)), // Convert to bytes,
          reliable: true,
          destinationIdentities: participantList,
        );

        // Update the message list
        addPrivateMessage(
          RemoteActivityData(
              identity: null,
              id: message.id,
              message: message.message,
              timestamp: message.timestamp,
              action: MeetingActions.sendPrivateMessage,
              // Assuming no action is provided
              isSender: true,
              // isSender
              userIdentity: identity,
              userName: name,
              replyMessage: message.replyMessage),
        );
        privateReplyDraft = null;
      } catch (e) {
        if (kDebugMode) {
          print('Error sending private action: $e');
        }
      }
    }
  }

  Future<void> sendPrivateAction(ActionModel action, String? identity) async {
    if (!MeetingActions.isValidAction(action.action)) {
      sendMessageToUI("Action not allowed.");
      return;
    }

    if (identity != null) {
      List<String> participantList = [identity];
      try {
        String jsonData = jsonEncode(action.toJson());
        await room.localParticipant?.publishData(
          utf8.encode(jsonData),
          reliable: true,
          destinationIdentities: participantList,
        );
      } catch (e) {
        if (kDebugMode) {
          print('Error sending private action: $e');
        }
      }
    }
  }

  Future<void> sendAction(ActionModel action) async {
    if (!MeetingActions.isValidAction(action.action)) {
      sendMessageToUI("Action not allowed.");
      return;
    }

    try {
      String jsonData = jsonEncode(action.toJson());
      await room.localParticipant?.publishData(
        utf8.encode(jsonData),
        reliable: true,
      );
      setHandRaisedForLocal(action);
    } catch (e) {
      if (kDebugMode) {
        print('Error sending action: $e');
      }
    }
  }

  void addParticipant(List<ParticipantTrack> participants) {
    // Clear the existing list
    _participantTracks.clear();

    // Create a map to store unique participants by identity
    final Map<String, ParticipantTrack> uniqueParticipants = {};

    for (var participantTrack in participants) {
      final identity = participantTrack.participant.identity;

      if (participantTrack.type == ParticipantTrackType.kScreenShare) {
        // If it's a screen share, update or add the entry
        uniqueParticipants[identity] = ParticipantTrack(
          participant: participantTrack.participant,
          type: ParticipantTrackType.kScreenShare,
        );
      } else {
        // If it's a user media track, add it only if no screen share exists for the participant
        uniqueParticipants.putIfAbsent(identity, () => participantTrack);
      }
    }

    // Sort participants to ensure local participant comes first
    ParticipantTrack? localParticipant =
        uniqueParticipants.values.firstWhereOrNull(
      (participantTrack) =>
          participantTrack.participant.identity ==
          room.localParticipant?.identity,
    );

    // Add local participant first if it exists
    if (localParticipant != null) {
      _participantTracks.add(localParticipant);
    }

    // Add the remaining participants excluding the local participant
    _participantTracks.addAll(
      uniqueParticipants.values.where(
        (participantTrack) =>
            participantTrack.participant.identity !=
            room.localParticipant?.identity,
      ),
    );

    updateIdentityToNameMap();
    requestForTranscriptionState();
    // Notify listeners of the update
    notifyListeners();
  }

  List<ParticipantTrack> getParticipantList() {
    return _participantTracks;
  }

  void addParticipantInLobby(RemoteActivityData participant) {
    _lobbyRequestList.add(participant);
  }

  List<RemoteActivityData> getLobbyRequestList() {
    return _lobbyRequestList;
  }

  //===========================RTC Controls====================

  bool _isAudioPermissionEnable = true;
  bool _isVideoPermissionEnable = true;

  LocalParticipant get participant => room.localParticipant!;

  String get selfIdentity => room.localParticipant?.identity ?? "";

  void disableAudio() async {
    await participant.setMicrophoneEnabled(false);
    notifyListeners();
  }

  Future<void> enableAudio() async {
    await participant.setMicrophoneEnabled(true);
    notifyListeners();
  }

  void disableVideo() async {
    await participant.setCameraEnabled(false);
    notifyListeners();
  }

  void enableVideo() async {
    await participant.setCameraEnabled(true);
    notifyListeners();
  }

  double getMicAlpha() {
    if (isHost() || isCoHost()) return 1.0;
    return isAudioPermissionEnable ? 1.0 : 0.5;
  }

  double getCameraAlpha() {
    if (isHost() || isCoHost()) return 1.0;
    return isVideoPermissionEnable ? 1.0 : 0.5;
  }

  bool isVisibleForHost(String role, String targetRole) {
    return role == "moderator";
  }

  bool isVisibleForCoHost(String role, String targetRole) {
    return role == "cohost" && targetRole != "moderator";
  }

  void removeFromCall(String identity) {
    Map<String, dynamic> body = {
      "participant_id": identity,
      "meeting_uid": meetingDetails.meetingUid
    };
    networkRequestHandler(
      apiCall: () =>
          apiClient.removeParticipant(meetingDetails.authorizationToken, selfIdentity, body),
      onSuccess: (_) => sendMessageToUI("Participant Removed"),
      onError: (message) => sendMessageToUI(message),
    );
  }

  int _coHostCount = 0;

  // Getter
  int get coHostCount => _coHostCount;

// Setter
  set coHostCount(int value) {
    _coHostCount = value;
    notifyListeners();
  }

  void makeCoHost(String identity, bool isCoHost) {
    Map<String, dynamic> body = {
      "participant_identity": identity,
      "meeting_uid": meetingDetails.meetingUid,
      "is_co_host": isCoHost
    };
    networkRequestHandler(
      apiCall: () =>
          apiClient.makeCoHost(meetingDetails.authorizationToken, selfIdentity, body),
      onSuccess: (_) => {
        sendPrivateAction(
            ActionModel(
                action: !isCoHost
                    ? MeetingActions.removeCoHost
                    : MeetingActions.makeCoHost,
                token: !isCoHost ? "" : meetingDetails.authorizationToken,
                user: {"name": room.localParticipant?.name}),
            identity),
        if (!meetingDetails.features!.isAllowMultipleCoHost())
          {
            if (isCoHost) {coHostCount++} else {coHostCount--}
          }
      },
      onError: (message) => sendMessageToUI(message),
    );
  }

  void setRecording(bool isRecording) {
    _isRecording = isRecording;
    notifyListeners();
  }

  bool get isRecording => _isRecording;

  bool _isRecordingActionInProgress = false;

  bool get isRecordingActionInProgress => _isRecordingActionInProgress;

  set isRecordingActionInProgress(bool value) {
    if (_isRecordingActionInProgress == value) return; // avoid redundant rebuilds
    _isRecordingActionInProgress = value;

    if (!value) cancelResetRecordingAction();

    notifyListeners();
  }

  bool isRecordingStartByMe = false;

  String? dispatchId;
  bool _stopRecordingRetried = false;

  void startRecording({bool isNeedToShowError = true}) {
    Map<String, dynamic> body = {
      "meeting_uid": meetingDetails.meetingUid,
    };
    networkRequestHandler(
      apiCall: () =>
          apiClient.startRecording(meetingDetails.authorizationToken, selfIdentity, body),
      onSuccess: (data) {
        isRecordingStartByMe = true;
        dispatchId = data?.dispatchId.id;
        resetRecordingActionInProgressAfterDelay(10);
        sendMessageToUI("Recording is starting...");
        sendAction(ActionModel(
          action: MeetingActions.startRecording,
          dispatchId: dispatchId,
        ));
      },
      onError: (message) {
        isRecordingActionInProgress = false;
        if (isNeedToShowError) {
          sendMessageToUI(message);
        }
      },
    );
  }

  void stopRecording({bool isNeedToShowError = true}) {
    if (dispatchId == null) {
      // No dispatchId available, fetch it first
      getRecordingDispatchedId(
        isNeedToShowError: isNeedToShowError,
        onComplete: () {
          if (dispatchId != null) {
            _attemptStopRecording(isNeedToShowError: isNeedToShowError);
          } else {
            isRecordingActionInProgress = false;
            if (isNeedToShowError) {
              sendMessageToUI(
                  "Unable to stop recording: dispatch ID not found.");
            }
          }
        },
      );
    } else {
      _attemptStopRecording(isNeedToShowError: isNeedToShowError);
    }
  }

  void _attemptStopRecording({bool isNeedToShowError = true}) {
    Map<String, dynamic> body = {
      "meeting_uid": meetingDetails.meetingUid,
      "dispatch_id": dispatchId,
    };

    networkRequestHandler(
      apiCall: () =>
          apiClient.stopRecording(meetingDetails.authorizationToken, selfIdentity, body),
      onSuccess: (_) {
        _stopRecordingRetried = false;
        isRecordingStartByMe = false;
        dispatchId = null;
        resetRecordingActionInProgressAfterDelay();
        sendMessageToUI("Recording is stopping...");
        sendAction(ActionModel(action: MeetingActions.stopRecording));

        try {
          meetingDetails
              .meetingBasicDetails?.meetingConfig?.recordingForceStopped = 1;
        } catch (_) {}
      },
      onError: (message) {
        // Fail-safe retry logic (only once)
        if (!_stopRecordingRetried) {
          _stopRecordingRetried = true;
          if (isNeedToShowError) {
            sendMessageToUI("Retrying to stop recording...");
          }
          getRecordingDispatchedId(
            isNeedToShowError: false,
            onComplete: () {
              if (dispatchId != null) {
                _attemptStopRecording(isNeedToShowError: isNeedToShowError);
              } else {
                isRecordingActionInProgress = false;
                sendMessageToUI(
                    "Unable to stop recording: dispatch ID not found.");
              }
            },
          );
        } else {
          isRecordingActionInProgress = false;
          _stopRecordingRetried = false;
          if (isNeedToShowError) {
            sendMessageToUI(message);
          }
        }
      },
    );
  }

  void getRecordingDispatchedId({
    bool isNeedToShowError = true,
    VoidCallback? onComplete,
  }) {
    networkRequestHandler(
      apiCall: () => apiClient.getRecordingDispatchedId(
        meetingDetails.authorizationToken,
        selfIdentity,
        meetingDetails.meetingUid,
      ),
      onSuccess: (data) {
        dispatchId = data?.dispatchId;
        onComplete?.call();
      },
      onError: (message) {
        if (isNeedToShowError) {
          sendMessageToUI(message);
        }
        onComplete?.call();
      },
    );
  }

  Timer? _resetTimer;

  void resetRecordingActionInProgressAfterDelay([int seconds = 30]) {
    // Cancel any existing timer if one is active
    _resetTimer?.cancel();

    isRecordingActionInProgress = true;

    _resetTimer = Timer(Duration(seconds: seconds), () {
      isRecordingActionInProgress = false;
      _resetTimer = null; // optional: clean up
    });
  }

  void cancelResetRecordingAction() {
    _resetTimer?.cancel();
    _resetTimer = null;
  }

  bool isHost() {
    return Utils.isHost(room.localParticipant?.metadata);
  }

  bool isCoHost() {
    return Utils.isCoHost(room.localParticipant?.metadata);
  }

  bool isHandRaised(String identity) {
    var isHandRaised = _raisedHandMap[identity] ?? false;
    return isHandRaised;
  }

  int? getRaisePosition(String identity) {
    final index = _raisedHandQueue.indexWhere((e) => e.identity == identity);

    if (index == -1) return null;

    return index + 1; // 1-based index like Teams
  }

  void setHandRaised(RemoteActivityData remoteData) {
    final id = remoteData.identity?.identity ?? "";

    if (remoteData.action == "raise_hand") {
      // prevent duplicate
      if (!_raisedHandMap.containsKey(id) || _raisedHandMap[id] == false) {
        _raisedHandMap[id] = true;

        _raisedHandQueue.add(
          RaisedHand(
            identity: id,
            timeStamp: remoteData.timeStamp ?? DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    } else {
      _raisedHandMap[id] = false;
      _raisedHandQueue.removeWhere((e) => e.identity == id);
    }

    notifyListeners();
  }

  void clearRaiseHandMemory(String? identity) {
    if (identity == null) return;
    _raisedHandMap[identity] = false;
    _raisedHandQueue.removeWhere((e) => e.identity == identity);
  }


  void stopHandRaisedForAll() {
    _raisedHandMap.clear();
    _raisedHandQueue.clear();
    _isMyHandRaised = false;
    notifyListeners();
  }

  void setMyHandRaised(bool isHandRaised) {
    _isMyHandRaised = isHandRaised;
    notifyListeners();
  }

  bool get isMyHandRaised => _isMyHandRaised;

  List<RaisedHand> get raisedHandQueue => List.unmodifiable(_raisedHandQueue);

  void syncRaiseHand(List<RaisedHand>? serverList) {
    if (serverList == null) return;
    // clear existing state
    _raisedHandMap.clear();
    _raisedHandQueue.clear();

    // sort to ensure correct order (safety)
    serverList.sort((a, b) => a.timeStamp.compareTo(b.timeStamp));

    for (final item in serverList) {
      _raisedHandMap[item.identity] = true;
      _raisedHandQueue.add(item);
    }

    // update my hand state
    final localId = room.localParticipant?.identity ?? "";
    _isMyHandRaised = _raisedHandMap[localId] ?? false;

    notifyListeners();
  }

  void requestRaiseHand() {
    if (room.remoteParticipants.values.isEmpty) return;
    final participant = room.remoteParticipants.values.first;
    sendPrivateAction(
      ActionModel(action: MeetingActions.requestRaisedHands, userIdentity: room.localParticipant?.identity),
      participant.identity,
    );
  }

  void responseRaiseHand(RemoteActivityData action) {
    final identity = action.userIdentity;
    if(identity == null) return;
    if (_raisedHandQueue.isEmpty) return;
    sendPrivateAction(ActionModel(
      action: MeetingActions.responseRaisedHands,
      raisedHands: _raisedHandQueue,
    ), identity);
  }


  void setHandRaisedForLocal(ActionModel action) {
    final id = room.localParticipant?.identity ?? "";

    if (action.action == MeetingActions.raiseHand) {
      if (!(_raisedHandMap[id] ?? false)) {
        _raisedHandMap[id] = true;

        _raisedHandQueue.add(
          RaisedHand(
            identity: id,
            timeStamp: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }

      _isMyHandRaised = true;
    } else {
      _raisedHandMap[id] = false;
      _raisedHandQueue.removeWhere((e) => e.identity == id);
      _isMyHandRaised = false;
    }

    notifyListeners();
  }

  set isAudioPermissionEnable(bool isAudioPermissionEnable) {
    _isAudioPermissionEnable = isAudioPermissionEnable;
    notifyListeners();
  }

  set isVideoPermissionEnable(bool isVideoPermissionEnable) {
    _isVideoPermissionEnable = isVideoPermissionEnable;
    notifyListeners();
  }

  bool get isAudioPermissionEnable => _isAudioPermissionEnable;

  bool get isVideoPermissionEnable => _isVideoPermissionEnable;

  bool _isWebinarModeEnable = false;
  bool _isAudioModeEnable = false;
  bool _isVideoModeEnable = false;

// Getter and Setter for _isWebinarModeEnable
  bool get isWebinarModeEnable => _isWebinarModeEnable;

  set isWebinarModeEnable(bool value) {
    _isWebinarModeEnable = value;
    _isAudioModeEnable = value;
    _isVideoModeEnable = value;
    notifyListeners();
  }

// Getter and Setter for _isAudioModeEnable
  bool get isAudioModeEnable => _isAudioModeEnable;

  set isAudioModeEnable(bool value) {
    _isAudioModeEnable = value;
    _isWebinarModeEnable = (_isAudioModeEnable && _isVideoModeEnable);
    notifyListeners();
  }

// Getter and Setter for _isVideoModeEnable
  bool get isVideoModeEnable => _isVideoModeEnable;

  set isVideoModeEnable(bool value) {
    _isVideoModeEnable = value;
    _isWebinarModeEnable = (_isAudioModeEnable && _isVideoModeEnable);
    notifyListeners();
  }

  void acceptParticipant(
      {required RemoteActivityData? request,
      required bool accept,
      bool acceptAll = false}) {
    if (request == null) return;
    Map<String, dynamic> body = {
      "meeting_uid": meetingDetails.meetingUid,
    };
    if (!acceptAll) {
      body["request_id"] = request.requestId;
      body["is_admit"] = accept;
    } else {
      body["is_admit_all"] = acceptAll;
    }
    networkRequestHandler(
        apiCall: () => apiClient.acceptParticipantInLobby(selfIdentity, body),
        onSuccess: (_) {},
        onError: (message) => sendMessageToUI(message));
  }

  final Map<String, int> requestTimestamps = {};
  final Set<String> _previousLobbyRequestList = {};
  Timer? _timer;

  List<RemoteActivityData> get lobbyRequestList =>
      List.unmodifiable(_lobbyRequestList);

  void checkAndAddUserToLobbyList(RemoteActivityData remoteData) {
    final requestId = remoteData.requestId ?? "";

    if (!_previousLobbyRequestList.contains(requestId)) {
      _lobbyRequestList.add(remoteData);
      _previousLobbyRequestList.add(requestId);
      requestTimestamps[requestId] = DateTime.now().millisecondsSinceEpoch;
      notifyListeners();
    } else {
      // Update the timestamp for the existing request
      requestTimestamps[requestId] = DateTime.now().millisecondsSinceEpoch;
    }
  }

  void startLobbyCheck() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      final currentTime = DateTime.now().millisecondsSinceEpoch;

      // Remove entries older than 12 seconds without `removeWhere`
      List<String> toRemove = [];
      requestTimestamps.forEach((requestId, timestamp) {
        if (currentTime - timestamp > 12000) {
          toRemove.add(requestId);
        }
      });

      for (final requestId in toRemove) {
        requestTimestamps.remove(requestId);
        _previousLobbyRequestList.remove(requestId);
        _lobbyRequestList.removeWhere((data) => data.requestId == requestId);
      }

      startReactionCheck();

      if (toRemove.isNotEmpty) {
        notifyListeners();
      }
    });
  }

  void stopLobbyCheck() {
    _timer?.cancel();
  }

  final _roomEventController = StreamController<RTCEvents>();

  // Stream to expose the events
  Stream<RTCEvents> get roomEvents => _roomEventController.stream;

  final _publicChatEventController = StreamController<RTCEvents>.broadcast();
  final _privateChatEventController = StreamController<RTCEvents>.broadcast();

  final _uploadAttachmentController = StreamController<RTCEvents>.broadcast();

  final _mainChatController = StreamController<RTCEvents>.broadcast();

  // Expose streams
  Stream<RTCEvents> get publicChatEvents => _publicChatEventController.stream;

  Stream<RTCEvents> get privateChatEvents => _privateChatEventController.stream;

  Stream<RTCEvents> get uploadAttachmentController =>
      _uploadAttachmentController.stream;

  Stream<RTCEvents> get mainChatController => _mainChatController.stream;

  // Send events
  void sendPublicChatEvent(RTCEvents event) {
    if (_publicChatEventController.isClosed) return;
    _publicChatEventController.sink.add(event);
  }

  void sendPrivateChatEvent(RTCEvents event) {
    if (_privateChatEventController.isClosed) return;
    _privateChatEventController.sink.add(event);
  }

  void sendUploadAttachmentEvent(RTCEvents event) {
    if (_uploadAttachmentController.isClosed) return;
    _uploadAttachmentController.sink.add(event);
  }

  void sendMainChatControllerEvent(RTCEvents event) {
    if (_mainChatController.isClosed) return;
    _mainChatController.sink.add(event);
  }

  // Cancel chat event streams
  void cancelPublicChatEvents() {
    _publicChatEventController.close();
  }

  void cancelPrivateChatEvents() {
    _privateChatEventController.close();
  }

  void cancelUploadAttachmentEvent() {
    _uploadAttachmentController.close();
  }

  void cancelMainChatControllerEvent() {
    _mainChatController.close();
  }

  void cancelRoomEvents() {
    _roomEventController.close();
  }

  // Function to emit events
  void sendEvent(RTCEvents event) {
    _roomEventController.sink.add(event);
  }

  // Function to show a snackbar message
  void sendMessageToUI(String? message) {
    sendEvent(ShowSnackBar(message ?? ""));
  }

  final List<EmojiMessage> _emojiQueue = [];

  void addEmoji(EmojiMessage emoji) {
    _emojiQueue.add(emoji);
    if (emojiQueue.length > 6) {
      emojiQueue.removeAt(0);
    }
    notifyListeners(); // Notify listeners to update the UI
  }

  void removeEmojiAt(int position) {
    _emojiQueue.removeAt(position);
    notifyListeners();
  }

  List<EmojiMessage> get emojiQueue => _emojiQueue;

  void startReactionCheck() {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    // Remove emojis older than 3 seconds
    _emojiQueue.removeWhere(
      (emoji) => currentTime - int.parse(emoji.timestamp) > 3000,
    );
    notifyListeners();
    sendEvent(UpdateView());
  }

  var _privateChatIdentity = "";

  void setPrivateChatIdentity(String identity) {
    _privateChatIdentity = identity;
    notifyListeners();
    sendPrivateChatEvent(UpdateView());
  }

  String getPrivateChatIdentity() {
    return _privateChatIdentity;
  }

  var _privateChatUserName = "";

  void setPrivateChatUserName(String name) {
    _privateChatUserName = name;
    notifyListeners();
    sendPrivateChatEvent(UpdateView());
  }

  String getPrivateChatUserName() {
    return _privateChatUserName;
  }

  BuildContext? context;

  void uploadAttachment(File file, Function? onUploadSuccess) {
    networkRequestHandler(
        apiCall: () =>
            apiClient.uploadFile(file, onSendProgress: (sent, total) {
              publicMessageProgress = sent / total;
              sendUploadAttachmentEvent(ShowProgress(publicMessageProgress));
            }),
        onSuccess: (data) {
          if (onUploadSuccess != null) {
            onUploadSuccess();
          }
          resetProgress();
          sendPublicMessage(data?.url ?? "");
        });
  }

  void uploadPrivateAttachment(
      String identity, String name, File file, Function? onUploadSuccess) {
    networkRequestHandler(
        apiCall: () =>
            apiClient.uploadFile(file, onSendProgress: (sent, total) {
              privateMessageProgress = sent / total;
              sendUploadAttachmentEvent(ShowProgress(privateMessageProgress));
            }),
        onSuccess: (data) {
          if (onUploadSuccess != null) {
            onUploadSuccess();
          }
          resetProgress();
          sendPrivateMessage(identity, name, data?.url ?? "");
        });
  }

  double _publicMessageProgress = -1;
  double _privateMessageProgress = -1;

  // Getter for public message upload progress
  double get publicMessageProgress => _publicMessageProgress;

  // Setter for public message upload progress
  set publicMessageProgress(double progress) {
    _publicMessageProgress = progress;
    notifyListeners(); // Notify UI updates
  }

  // Getter for private message upload progress
  double get privateMessageProgress => _privateMessageProgress;

  // Setter for private message upload progress
  set privateMessageProgress(double progress) {
    _privateMessageProgress = progress;
    notifyListeners(); // Notify UI updates
  }

  // Reset progress for both messages
  void resetProgress() {
    _publicMessageProgress = -1;
    _privateMessageProgress = -1;
    notifyListeners();
  }

  //================Transcription=============

  TranscriptionModel? particalTranscription;
  List<TranscriptionModel> _transcriptionList = [];

  // Getter
  List<TranscriptionModel> get transcriptionList => _transcriptionList;

  // Setter
  set transcriptionList(List<TranscriptionModel> value) {
    _transcriptionList = value;
    notifyListeners();
  }

  void addTranscription(TranscriptionModel value) {
    _transcriptionList.add(value);
    notifyListeners();
  }

  bool _isTranscriptionLanguageSelected = false;

  set isTranscriptionLanguageSelected(bool isSelected) {
    _isTranscriptionLanguageSelected = isSelected;
    notifyListeners();
  }

  bool get isTranscriptionLanguageSelected => _isTranscriptionLanguageSelected;

  List<LanguageModel> _languages = [];

  // Getter
  List<LanguageModel> get languages => _languages;

  // Setter
  set languages(List<LanguageModel> value) {
    _languages = value;
    notifyListeners();
  }

  Future<List<LanguageModel>> fetchLanguages() async {
    // 1. Load the JSON string from the assets folder
    const String response = languageJsonString;

    // 2. Check for loading errors (optional, but good practice)
    if (response.isEmpty) {
      throw Exception('Error loading JSON file');
    }

    // 3. Decode the JSON string into a Dart object
    final data = await json.decode(response) as List<
        dynamic>; // Cast to List<dynamic> to avoid potential type errors

    // 4. Convert each JSON object to a LanguageModel instance
    return data.map((item) => LanguageModel.fromJson(item)).toList();
  }

  void setTranscriptionLanguage(
      LanguageModel selectedLanguage, Function transcriptionEnabled) {
    Map<String, dynamic> body = {
      "meeting_uid": meetingDetails.meetingUid,
      "transcription_enable": true,
      "transcription_lang_iso": selectedLanguage.code,
      "transcription_lang_title": selectedLanguage.code
    };
    networkRequestHandler(
        apiCall: () => apiClient.setTranscriptionLanguage(
            meetingDetails.authorizationToken, selfIdentity, body),
        onSuccess: (data) {
          isTranscriptionLanguageSelected = true;
          var transcriptionData = TranscriptionActionModel(
              showIcon: true,
              isLanguageSelected: true,
              langCode: selectedLanguage.code,
              sourceLang: selectedLanguage.code);
          saveTranscriptionLanguage(transcriptionData);
          sendAction(ActionModel(
              action: MeetingActions.showLiveCaption,
              liveCaptionsData: transcriptionData));
          transcriptionEnabled.call();
        },
        onError: (message) => sendMessageToUI(message));
  }

  void startTranscription() {
    Map<String, dynamic> body = {
      "meeting_uid": meetingDetails.meetingUid,
    };
    networkRequestHandler(apiCall: () => apiClient.startTranscription(selfIdentity, body));
  }

  TranscriptionActionModel? _transcriptionLanguageData;

  TranscriptionActionModel? get transcriptionLanguageData =>
      _transcriptionLanguageData;

  // Setter method to set the value of _transcriptionLanguageData
  set transcriptionLanguageData(TranscriptionActionModel? value) {
    if (value != null) {
      value.sourceLang ??= value.langCode;
    }
    _transcriptionLanguageData = value;
    notifyListeners();
  }

  void saveTranscriptionLanguage(TranscriptionActionModel? liveCaptionsData) {
    if (liveCaptionsData == null) return;
    isTranscriptionLanguageSelected =
        liveCaptionsData.isLanguageSelected ?? false;
    transcriptionLanguageData = liveCaptionsData;
  }

  @Deprecated(
    'Use handleCaptionTranscription instead. '
        'This method is scheduled for removal and should not be used.',
  )
  void collectTranscriptionData(RemoteActivityData remoteData) {
    // Check if the incoming data is a final transcription
    if (remoteData.finalTranscription?.isNotEmpty == true) {
      // If there's an existing partial transcription, finalize it
      if (particalTranscription != null) {
        particalTranscription = particalTranscription!.copyWith(
            name: getParticipantNameByIdentity(remoteData.participantIdentity),
            transcription: Utils.decodeUnicode(remoteData.finalTranscription),
            isFinal: true,
            sourceLang: transcriptionLanguageData?.sourceLang,
            targetLang: translationLanguage?.code ??
                transcriptionLanguageData?.sourceLang);

        // Replace the existing transcription in the list with the finalized one
        _updateTranscriptionInList(particalTranscription!);

        // Trigger translation if source and target languages differ
        if (particalTranscription?.sourceLang !=
            particalTranscription?.targetLang) {
          translateText(particalTranscription!);
        }
      } else {
        // Create and add a new finalized transcription
        final newTranscription = TranscriptionModel(
          id: const Uuid().v4(),
          name: getParticipantNameByIdentity(remoteData.participantIdentity),
          transcription: Utils.decodeUnicode(remoteData.finalTranscription),
          timestamp: Utils.formatTimestampToTime(
              DateTime.now().millisecondsSinceEpoch),
          isFinal: true,
          sourceLang: transcriptionLanguageData?.sourceLang ?? "",
          targetLang: translationLanguage?.code ??
              (transcriptionLanguageData?.sourceLang ?? ""),
        );
        addTranscription(newTranscription);

        // Trigger translation if source and target languages differ
        if (newTranscription.sourceLang != newTranscription.targetLang) {
          translateText(newTranscription);
        }
      }

      // Reset the partial transcription
      particalTranscription = null;
    } else if (remoteData.partialTranscription?.isNotEmpty == true) {
      // Handle partial transcription updates
      if (particalTranscription != null) {
        // Update the existing partial transcription
        particalTranscription = particalTranscription!.copyWith(
            name: getParticipantNameByIdentity(remoteData.participantIdentity),
            transcription: remoteData.partialTranscription ?? "",
            isFinal: false,
            sourceLang: transcriptionLanguageData?.sourceLang,
            targetLang: translationLanguage?.code ??
                transcriptionLanguageData?.sourceLang);

        // Update the transcription in the list
        _updateTranscriptionInList(particalTranscription!);
      } else {
        // Create and add a new partial transcription
        particalTranscription = TranscriptionModel(
          id: const Uuid().v4(),
          name: getParticipantNameByIdentity(remoteData.participantIdentity),
          transcription: remoteData.partialTranscription ?? "",
          timestamp: Utils.formatTimestampToTime(
              DateTime.now().millisecondsSinceEpoch),
          isFinal: false,
          sourceLang: transcriptionLanguageData?.sourceLang ?? "",
          targetLang: translationLanguage?.code ??
              (transcriptionLanguageData?.sourceLang ?? ""),
        );
        addTranscription(particalTranscription!);
      }
    }
  }

  void _updateTranscriptionInList(TranscriptionModel updatedModel) {
    final index = _transcriptionList.indexWhere((t) => t.id == updatedModel.id);
    if (index != -1) {
      _transcriptionList[index] = updatedModel;
    } else {
      _transcriptionList
          .add(updatedModel); // Add if it doesn't exist (fallback)
    }
    notifyListeners();
  }

  final Map<String, String> _identityToNameMap = {};

  void updateIdentityToNameMap() {
    _identityToNameMap.clear();
    for (final track in _participantTracks) {
      final identity = track.participant.identity;
      final name = track.participant.name;
      _identityToNameMap[identity] = name;
    }
  }

  String getParticipantNameByIdentity(String? identity) {
    if (identity == null) return "Unknown";
    return _identityToNameMap[identity] ?? "Unknown";
  }

  var _isRequestedForTranscription = false;

  void requestForTranscriptionState() {
    if (_isRequestedForTranscription) return;
    _isRequestedForTranscription = true;
    if (meetingDetails.meetingBasicDetails?.transcriptionDetail != null) {
      if (meetingDetails
              .meetingBasicDetails?.transcriptionDetail?.transcriptionEnable ==
          true) {
        var data = meetingDetails.meetingBasicDetails?.transcriptionDetail;
        isTranscriptionLanguageSelected = true;
        transcriptionLanguageData = TranscriptionActionModel(
            showIcon: data?.transcriptionEnable,
            isLanguageSelected: data?.transcriptionEnable,
            langCode: data?.transcriptionLangIso,
            sourceLang: data?.transcriptionLangIso);
        return;
      }
    }
    // Skip the first participant (alias "you") and check the others
    for (int i = 1; i < _participantTracks.length; i++) {
      var participantTrack = _participantTracks[i];
      var participant = participantTrack.participant;
      if (!Utils.isHost(participant.metadata) &&
          !Utils.isCoHost(participant.metadata)) {
        // Send the action with the participant's ID (assuming `identity` is the ID)
        sendPrivateAction(
          ActionModel(action: MeetingActions.requestLiveCaptionDrawerState),
          participant.identity, // Using participant's identity (ID)
        );
        break; // Exit after sending the action to the first valid participant
      }
    }
  }

  void checkTranscriptionStateAndReturn(RemoteActivityData remoteData) {
    if (_transcriptionLanguageData != null) {
      if (_transcriptionLanguageData?.isLanguageSelected == true) {
        sendPrivateAction(
            ActionModel(
                action: MeetingActions.showLiveCaption,
                liveCaptionsData: TranscriptionActionModel(
                    showIcon: true,
                    isLanguageSelected: true,
                    langCode: _transcriptionLanguageData?.langCode,
                    sourceLang: _transcriptionLanguageData?.sourceLang)),
            remoteData.participantIdentity);
      }
    }
  }

  LanguageModel? _translationLanguage;

  LanguageModel? get translationLanguage => _translationLanguage;

  set translationLanguage(LanguageModel? language) {
    _translationLanguage = language;
    notifyListeners();
  }

  void translateText(TranscriptionModel transcriptionData,
      {Function? callBack}) {
    Map<String, dynamic> body = {
      "meeting_uid": meetingDetails.meetingUid,
      "source_language": transcriptionData.sourceLang,
      "target_language": translationLanguage?.code,
      "text": transcriptionData.transcription,
    };
    networkRequestHandler(
        apiCall: () => apiClient.translateText(selfIdentity, body),
        onSuccess: (data) {
          _updateTranscriptionInList(transcriptionData.copyWith(
            translatedTranscription: data?.translatedText,
            targetLang: translationLanguage?.code,
          ));
          callBack?.call();
        },
        onError: (message) {
          callBack?.call();
          sendMessageToUI(message);
        });
  }

  void endMeetingForAll() {
    Map<String, dynamic> body = {
      "meeting_uid": meetingDetails.meetingUid,
    };
    networkRequestHandler(
      apiCall: () => apiClient.endMeeting(selfIdentity, body),
      onSuccess: (_) => sendEvent(EndMeeting(reason: "roomDeleted")),
      onError: (message) => sendMessageToUI(message),
    );
  }

  void updateParticipantName({String? participant, required String newName}) {
    if (participant == null) return;
    Map<String, dynamic> body = {
      "meeting_uid": meetingDetails.meetingUid,
      "participant_identity": participant,
      "new_name": newName,
    };
    networkRequestHandler(
        apiCall: () => apiClient.updateParticipantName(selfIdentity, body),
        onError: (message) => sendMessageToUI(message));
  }

  void configAutoRecording() {
    if (isHost()) {
      if (meetingDetails.meetingBasicDetails?.meetingConfig != null) {
        var meetingConfig = meetingDetails.meetingBasicDetails?.meetingConfig!;
        if (meetingConfig?.recordingForceStopped != 1 &&
            meetingConfig?.autoStartRecording == 1) {
          if (!isRecording) {
            startRecording(isNeedToShowError: false);
          }
        }
      }
    }
  }

  void meetingTimeExtend() {
    Map<String, dynamic> body = {
      "meeting_uid": meetingDetails.meetingUid,
      "is_extend_time": true,
    };
    networkRequestHandler(
        apiCall: () => apiClient.meetingTimeExtend(
            meetingDetails.authorizationToken, selfIdentity, body),
        onSuccess: (_) => sendAction(
            ActionModel(action: MeetingActions.extendMeetingEndTime)));
  }

  bool isAutoMeetingEndEnable() {
    if (isHost() &&
        meetingDetails.meetingBasicDetails?.meetingConfig?.autoMeetingEnd ==
            1) {
      return true;
    }
    return false;
  }

  String? getMeetingEndDate() {
    return meetingDetails
            .meetingBasicDetails?.meetingConfig?.autoMeetingEndSchedule ??
        meetingDetails.meetingBasicDetails?.endDate;
  }

  void getWhiteboardData() {
    networkListRequestHandler(
        apiCall: () => apiClient.getWhiteBoardData(
            selfIdentity,
            meetingDetails.meetingBasicDetails?.meetingId.toString() ?? ""),
        onSuccess: (data) {
          final whiteboard = data!.first;
          sendEvent(WhiteboardStatus(status: whiteboard.status == 'open'));
        });
  }

  List<ParticipantAttendanceData> _pendingParticipantList = [];

  // Getter
  List<ParticipantAttendanceData> get pendingParticipantList =>
      _pendingParticipantList;

  // Setter
  set pendingParticipantList(List<ParticipantAttendanceData> newList) {
    _pendingParticipantList = newList;
    notifyListeners();
  }

  Timer? _attendanceDebounceTimer;

  void getAttendanceListForParticipant() {
    if (!isHost() && !isCoHost()) {
      return;
    }
    // Cancel any existing timer
    _attendanceDebounceTimer?.cancel();

    // Start a new debounce timer
    _attendanceDebounceTimer = Timer(const Duration(seconds: 1), () {
      networkListRequestHandler(
          apiCall: () => apiClient
              .getAttendanceListForParticipant(selfIdentity, meetingDetails.meetingUid),
          onSuccess: (data) {
            collectInactiveParticipant(data);
          });
    });
  }

  void collectInactiveParticipant(List<ParticipantAttendanceData>? data) {
    List<ParticipantAttendanceData> tempList = [];
    if (data != null) {
      for (var participant in data) {
        if (participant.participantStatus?.toLowerCase() != 'joined') {
          tempList.add(participant);
        }
      }
    }
    pendingParticipantList = tempList;
  }

  //Recording Consent Flow

  List<ConsentParticipant> _participantListForConsent = [];

  List<ConsentParticipant> get participantListForConsent =>
      _participantListForConsent;

  set participantListForConsent(List<ConsentParticipant> list) {
    _participantListForConsent = list;
    notifyListeners();
  }

  void updateRecordingConsentStatus(bool status,
      {bool needToUpdateLocally = false}) {
    var metadata = room.localParticipant?.metadata;
    Map<String, dynamic> body = {
      "meeting_uid": meetingDetails.meetingUid,
      "session_id": getSessionId(),
      "is_accepted": status,
      "attendance_id": Utils.getMetadataAttendanceId(metadata),
    };

    networkRequestHandler(
        apiCall: () => apiClient.updateRecordingConsent(selfIdentity, body),
        onSuccess: (data) {
          if (data?.canStartRecording == true) {
            startRecording();
          }
          if (needToUpdateLocally) {
            locallyUpdateRecordingConsentStatus(status);
          }
          sendAction(ActionModel(
              action: MeetingActions.recordingConsentStatus,
              consent: status ? "accept" : "reject"));
        },
        onError: (message) {
          sendMessageToUI(message);
        });
  }

  void startRecordingConsentFlow() {
    if (isRecording) {
      stopRecording();
    } else {
      checkSessionStatus();
    }
  }

  var sessionId = "";

  String? getSessionId() {
    if (sessionId.isNotEmpty) {
      return sessionId;
    }

    final metadataSessionId =
        Utils.getMetadataSessionUid(room.localParticipant?.metadata);
    if (metadataSessionId != null && metadataSessionId != "null" && metadataSessionId.isNotEmpty) {
      return metadataSessionId;
    }

    return meetingDetails.meetingBasicDetails?.currentSessionUid;
  }

  Future<void> fetchAndStoreSessionUid() async {
    networkRequestHandler(
      apiCall: () => apiClient.getSessionDetails(selfIdentity, meetingDetails.meetingUid),
      onSuccess: (data) async {
        if (data?.id != null) {
          final sessionUid = data!.id.toString();
          StorageHelper().setSessionUid(sessionUid);
        }
      },
    );
  }

  void checkSessionStatus({bool asUser = false, Function? callBack}) {
    networkRequestHandler(
        apiCall: () => apiClient.getSessionDetails(selfIdentity, meetingDetails.meetingUid),
        onSuccess: (data) {
          if (data != null) {
            sessionId = data.id.toString();
            StorageHelper().setSessionUid(sessionId);
          }

          if (data?.recordingConsentActive == 1) {
            if (asUser) {
              // Fetch consent list before checking consent
              getParticipantConsentList(onLoaded: () {
                if (!hasAlreadyAcceptedConsent()) {
                  callBack?.call(); // Show dialog if not yet accepted
                }
              });
            } else {
              getParticipantConsentList();
            }
          } else {
            if (!asUser) {
              startRecordingConsent();
            }
          }
        },
        onError: (message) {
          sendMessageToUI(message);
        });
  }

  void startRecordingConsent() {
    var metadata = room.localParticipant?.metadata;
    Map<String, dynamic> body = {
      "meeting_uid": meetingDetails.meetingUid,
      "session_id": getSessionId(),
      "meeting_consent_start": true,
      "attendance_id": Utils.getMetadataAttendanceId(metadata),
    };
    networkRequestHandler(
        apiCall: () => apiClient.startRecordingConsent(selfIdentity, body),
        onSuccess: (_) {
          sendAction(ActionModel(
              action: MeetingActions.recordingConsentModal, value: true));
          getParticipantConsentList();
        },
        onError: (message) {
          sendMessageToUI(message);
        });
  }

  void getParticipantConsentList({VoidCallback? onLoaded}) {
    networkListRequestHandler(
        apiCall: () => apiClient.getParticipantConsentList(
            selfIdentity,
            meetingDetails.meetingUid, getSessionId() ?? ""),
        onSuccess: (data) {
          if (data != null) {
            final localList = ConsentParticipant.fromRemoteList(data);
            participantListForConsent = localList;

            if (onLoaded != null) {
              onLoaded.call(); // <-- Trigger callback after loading list
              return;
            }
            sendAction(ActionModel(
              action: MeetingActions.startedRecordingConsent,
              participants: localList,
            ));
          }
        });
  }

  void verifyRecordingConsent(RemoteActivityData remoteData) {
    if (!isHost() && !isCoHost()) return;

    if (participantListForConsent.isEmpty) {
      getParticipantConsentList();
      return;
    }

    int index = participantListForConsent.indexWhere(
      (participant) =>
          participant.participantId == remoteData.identity?.identity,
    );

    if (index != -1) {
      final existing = participantListForConsent[index];
      participantListForConsent[index] = ConsentParticipant(
        participantId: existing.participantId,
        participantName: existing.participantName,
        participantAvatar: existing.participantAvatar,
        consent: remoteData.consent,
      );
    }
    notifyListeners();
  }

  bool hasAlreadyAcceptedConsent() {
    final participant = room.localParticipant;
    final localId = participant?.identity;
    final existing = participantListForConsent.firstWhere(
      (p) => p.participantId == localId,
      orElse: () => ConsentParticipant(
        participantId: localId ?? '',
        participantName: participant?.name,
        participantAvatar: Utils.getInitials(participant?.name),
        consent: null,
      ),
    );

    return parseConsentStatus(existing.consent) == ConsentStatus.accept;
  }

  void resendRecordingConsent(String? identity) {
    sendPrivateAction(
        ActionModel(action: MeetingActions.recordingConsentModal, value: true),
        identity);
  }

  void addParticipantToConsentList(RemoteParticipant participant) {
    if ((!isHost() && !isCoHost()) &&
        !meetingDetails.features!.isRecordingConsentAllowed()) {
      return;
    }

    final participantId = participant.identity;

    // Check for duplicates
    final alreadyExists = participantListForConsent.any(
      (p) => p.participantId == participantId,
    );

    if (alreadyExists) return;

    // Add new participant to the list
    final newConsentParticipant =
        ConsentParticipant.fromRemoteParticipant(participant);

    participantListForConsent.add(newConsentParticipant);
    notifyListeners();
  }

  void removeParticipantFromConsentList(String participantId) {
    participantListForConsent.removeWhere(
      (participant) => participant.participantId == participantId,
    );
    notifyListeners();
  }

  void locallyUpdateRecordingConsentStatus(bool status) {
    final localId = room.localParticipant?.identity;

    final index = participantListForConsent.indexWhere(
      (p) => p.participantId == localId,
    );
    if (index != -1) {
      participantListForConsent[index] =
          participantListForConsent[index].copyWith(
        consent: status ? "accept" : "reject",
      );
      notifyListeners();
    }
  }

  Future<void> disposeScreenShare() async {
    if (room.localParticipant?.isScreenShareEnabled() == true) {
      final participant = room.localParticipant;
      await participant?.setScreenShareEnabled(false);
      if (lkPlatformIs(PlatformType.android)) {
        // Android specific
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

  String? _pinnedParticipantId;

  String? get pinnedParticipantId => _pinnedParticipantId;

  set pinnedParticipantId(String? value) {
    _pinnedParticipantId = value;
    notifyListeners();
  }

  //===============================[Pin Chat]===============================
  RemoteActivityData? _pinnedPublicChat;

  set pinnedPublicChat(RemoteActivityData? chat) {
    _pinnedPublicChat = chat;
    notifyListeners();
  }

  RemoteActivityData? get pinnedPublicChat => _pinnedPublicChat;

  set pinnedPrivateChat(RemoteActivityData? chat) {
    getPrivateMessage()[getPrivateChatIdentity()]?.pinnedChat = chat;
    notifyListeners();
  }

  RemoteActivityData? get pinnedPrivateChat =>
      getPrivateMessage()[getPrivateChatIdentity()]?.pinnedChat;

  void deleteMessage(String mode, String? id, String? identity) {
    final chatType = ChatTypeExtension.fromString(mode);
    switch (chatType) {
      case ChatType.public:
        _deletePublicMessage(id);
        break;

      case ChatType.private:
        _deletePrivateMessage(id, identity);
        break;
    }
  }

  void _deletePublicMessage(String? id) {
    if (id == null) return;

    final index = _messageList.indexWhere((message) => message.id == id);
    if (index != -1) {
      _messageList[index] = _messageList[index].copyWith(
        message: "[Message deleted]",
        isDeleted: true,
      );
      notifyListeners();
    }
  }

  void _deletePrivateMessage(String? id, String? identity) {
    if (id == null || identity == null) return;
    final privateChats = _privateChat[identity]?.chats;
    if (privateChats == null) return;
    final index = privateChats.indexWhere((message) => message.id == id);
    if (index != -1) {
      privateChats[index] = privateChats[index].copyWith(
        message: "[Message deleted]",
        isDeleted: true,
      );
      notifyListeners();
    }
  }

  void sendDeleteMessageAction(String mode, RemoteActivityData chat) {
    final chatType = ChatTypeExtension.fromString(mode);
    switch (chatType) {
      case ChatType.public:
        sendAction(ActionModel(
            action: MeetingActions.deleteMessage, id: chat.id, mode: mode));
        break;

      case ChatType.private:
        sendPrivateAction(
            ActionModel(
                action: MeetingActions.deleteMessage, id: chat.id, mode: mode),
            chat.userIdentity);
        break;
    }
  }

  //===============================[Reply Chat]===============================
  ReplyMessage? _publicReplyDraft;

  ReplyMessage? get publicReplyDraft => _publicReplyDraft;

  set publicReplyDraft(ReplyMessage? value) {
    _publicReplyDraft = value;
    notifyListeners();
  }

  set privateReplyDraft(ReplyMessage? replyChat) {
    getPrivateMessage()[getPrivateChatIdentity()]?.replyMessage = replyChat;
    notifyListeners();
  }

  ReplyMessage? get privateReplyDraft =>
      getPrivateMessage()[getPrivateChatIdentity()]?.replyMessage;

  //===============================[Reply Chat]===============================
  void editMessage(String mode, String? id, String? identity, String? message) {
    final chatType = ChatTypeExtension.fromString(mode);
    switch (chatType) {
      case ChatType.public:
        _editPublicMessage(id, message);
        break;

      case ChatType.private:
        _editPrivateMessage(id, identity, message);
        break;
    }
  }

  void _editPublicMessage(String? id, String? message) {
    if (id == null) return;

    final index = _messageList.indexWhere((message) => message.id == id);
    if (index != -1) {
      _messageList[index] = _messageList[index].copyWith(
        message: message,
        isEdited: true,
      );
      notifyListeners();
    }
  }

  void _editPrivateMessage(String? id, String? identity, String? message) {
    if (id == null || identity == null) return;
    final privateChats = _privateChat[identity]?.chats;
    if (privateChats == null) return;
    final index = privateChats.indexWhere((message) => message.id == id);
    if (index != -1) {
      privateChats[index] = privateChats[index].copyWith(
        message: message,
        isEdited: true,
      );
      notifyListeners();
    }
  }

  EditMessage? _publicEditDraft;

  EditMessage? get publicEditDraft => _publicEditDraft;

  set publicEditDraft(EditMessage? value) {
    _publicEditDraft = value;
    notifyListeners();
  }

  set privateEditDraft(EditMessage? editMessage) {
    getPrivateMessage()[getPrivateChatIdentity()]?.editMessage = editMessage;
    notifyListeners();
  }

  EditMessage? get privateEditDraft =>
      getPrivateMessage()[getPrivateChatIdentity()]?.editMessage;

  void editPublicMessage(String updatedMessage) {
    sendAction(ActionModel(
        action: MeetingActions.editMessage,
        id: _publicEditDraft?.id,
        message: updatedMessage,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        mode: ChatType.public.name));

    editMessage(ChatType.public.name, _publicEditDraft?.id,
        room.localParticipant?.identity, updatedMessage);
  }

  void editPrivateMessage(String updatedMessage, String identity) {
    final draft = privateEditDraft;
    if (draft == null) return;

    sendPrivateAction(
      ActionModel(
        action: MeetingActions.editMessage,
        id: draft.id,
        message: updatedMessage,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        mode: ChatType.private.name,
      ),
      identity,
    );

    editMessage(ChatType.private.name, draft.id, identity, updatedMessage);
  }

  //===============================[Chat Reaction]===============================
  void handleReaction(RemoteActivityData remoteData) {
    final chatType = ChatTypeExtension.fromString(remoteData.mode ?? "");
    final id = remoteData.messageId;
    final reaction = remoteData.reaction;
    final isRemoveReaction = remoteData.removeReaction;
    final senderIdentity = remoteData.identity?.identity; // who sent event

    switch (chatType) {
      case ChatType.public:
        _publicReaction(id, reaction, isRemoveReaction);
        break;

      case ChatType.private:
        _privateReaction(id, senderIdentity, reaction, isRemoveReaction);
        break;
    }
  }

  void _publicReaction(
    String? id,
    Reaction? reaction,
    bool isRemoveReaction,
  ) {
    if (id == null || reaction == null) return;

    final index = _messageList.indexWhere((message) => message.id == id);
    if (index == -1) return;

    final message = _messageList[index];

    // Copy existing reactions or use empty list if null
    final reactions = List<Reaction>.from(message.reactions ?? []);

    // Reactor = user who actually reacted (from reaction model)
    final reactorId = reaction.reactor;
    if (reactorId == null) return;

    // Check if this user already reacted
    final existingIndex = reactions.indexWhere((r) => r.reactor == reactorId);

    if (isRemoveReaction) {
      // 🔹 Remove reaction if user already reacted
      if (existingIndex != -1) {
        reactions.removeAt(existingIndex);
      }
    } else {
      if (existingIndex != -1) {
        // 🔹 Replace old reaction (update emoji)
        reactions[existingIndex] = reaction;
      } else {
        // 🔹 Add new reaction
        reactions.add(reaction);
      }
    }

    // Update message in list
    _messageList[index] = message.copyWith(reactions: reactions);

    notifyListeners();
  }

  void _privateReaction(
    String? id,
    String? identity,
    Reaction? reaction,
    bool isRemoveReaction,
  ) {
    if (id == null || identity == null || reaction == null) return;
    final privateChats = _privateChat[identity]?.chats;
    if (privateChats == null) return;

    final index = privateChats.indexWhere((message) => message.id == id);
    if (index == -1) return;

    final message = privateChats[index];

    // Copy existing reactions or use empty list if null
    final reactions = List<Reaction>.from(message.reactions ?? []);

    // Reactor = user who actually reacted (from reaction model)
    final reactorId = reaction.reactor;
    if (reactorId == null) return;

    // Check if this user already reacted
    final existingIndex = reactions.indexWhere((r) => r.reactor == reactorId);

    if (isRemoveReaction) {
      // 🔹 Remove reaction if user already reacted
      if (existingIndex != -1) {
        reactions.removeAt(existingIndex);
      }
    } else {
      if (existingIndex != -1) {
        // 🔹 Replace old reaction (update emoji)
        reactions[existingIndex] = reaction;
      } else {
        // 🔹 Add new reaction
        reactions.add(reaction);
      }
    }

    if (index != -1) {
      privateChats[index] = privateChats[index].copyWith(
        reactions: reactions
      );
      notifyListeners();
    }
  }

  bool shouldUpdateReaction(
      List<Reaction> reactions,
      String identity,
      String newEmoji,
      ) {
    if (identity == "" || newEmoji == "") return true;
    final existing = reactions.firstWhere(
          (r) => r.reactor == identity,
      orElse: () => Reaction(),
    );

    if (existing.reactor == null) {
      // User hasn't reacted yet → adding
      return true;
    }

    if (existing.emoji == newEmoji) {
      // Same emoji → removing
      return false;
    }

    // Different emoji → updating
    return true;
  }

  void addReaction(String chatType, String emoji, RemoteActivityData chat) {
    final mode = ChatTypeExtension.fromString(chatType);
    final localIdentity = room.localParticipant?.identity;
    final id = chat.id;
    final reaction = Reaction(
      emoji: emoji,
      reactor: localIdentity,
      name: room.localParticipant?.name,
    );

    final reactions = chat.reactions ?? [];
    final isRemoveReaction =
    !shouldUpdateReaction(reactions, localIdentity ?? "", emoji);

    // 🧠 Determine correct chat identity
    String? targetIdentity = chat.identity?.identity ?? _privateChatIdentity;

    final action = ActionModel(
      action: MeetingActions.addReaction,
      mode: chatType,
      messageId: id,
      reaction: reaction,
      removeReaction: isRemoveReaction,
    );

    switch (mode) {
      case ChatType.public:
        sendAction(action);
        _publicReaction(id, reaction, isRemoveReaction);
        break;

      case ChatType.private:
        sendPrivateAction(action, targetIdentity);
        _privateReaction(id, targetIdentity, reaction, isRemoveReaction);
        break;
    }
  }


  //===============================[ScreenShare Permission]===============================
  bool _isScreenShareEnable = true;

  bool get isScreenShareEnable => _isScreenShareEnable;

  set isScreenShareEnable(bool value) {
    _isScreenShareEnable = value;
    notifyListeners();
  }

  void getScreenShareConsent() {
    networkRequestHandler(
        apiCall: ()=> apiClient.getScreenShareConsent(selfIdentity, meetingDetails.meetingUid),
        onSuccess: (data) {
          isScreenShareEnable = data?.screenShareConsent == true;
        },
        onError: (message) {
          sendMessageToUI(message);
          isScreenShareEnable = false;
        }
    );
  }

  void updateScreenShareConsent(bool value) {
    Map<String, dynamic> body = {
      "meeting_id": meetingDetails.meetingUid,
      "permission_granted": value,
    };

    networkRequestHandler(
      apiCall: ()=> apiClient.updateScreenShareConsent(meetingDetails.authorizationToken, selfIdentity, body),
      onSuccess: (data) {
        isScreenShareEnable = data?.screenShareConsent == true;
        sendAction(ActionModel(action: MeetingActions.allowScreenShareForAll, value: _isScreenShareEnable));
      },
      onError: (message) {
        sendMessageToUI(message);
        isScreenShareEnable = !isScreenShareEnable;
      }
    );
  }

  bool isScreenShareRequestAccepted = false;

  bool isScreenSharePermissionNeeded() {
    var localParticipant = room.localParticipant;
    if (Utils.isHost(localParticipant?.metadata) || Utils.isCoHost(localParticipant?.metadata)) return false;
    if (!_isScreenShareEnable) {
      if (isScreenShareRequestAccepted) return false;
      if(adminList.isEmpty) return true;
      sendPrivateAction(ActionModel(action: MeetingActions.requestScreenSharePermission, requestBy: localParticipant?.identity, requestByName: localParticipant?.name), adminList[0]?.identity);
      return true;
    }
    return false;
  }

  List<RemoteParticipant?> adminList = [];

  void updateAdminList(RemoteParticipant participant) {
    if (Utils.isHost(participant.metadata)) {
      // Always keep host at 0 index
      adminList.insert(0, participant);
    } else if (Utils.isCoHost(participant.metadata)) {
      // Add co-host normally
      adminList.add(participant);
    }
  }

  String? getAdminType() {
    if(adminList.isEmpty) return null;
    final metadata = adminList[0]?.metadata;
    if (Utils.isHost(metadata)) return "Host";
    if (Utils.isCoHost(metadata)) return "Co-Host";
    return null;
  }

  List<RemoteActivityData> _screenShareRequestList = [];

  List<RemoteActivityData> get screenShareRequestList =>
      _screenShareRequestList;

  set screenShareRequestList(List<RemoteActivityData> value) {
    _screenShareRequestList = value;
    notifyListeners();
  }


  void addScreenShareRequest(RemoteActivityData data) {
    // Check if the participant is already in the list
    final exists = _screenShareRequestList.any(
          (item) => item.identity == data.identity,
    );

    if (!exists) {
      _screenShareRequestList.add(data);
      notifyListeners();
    }
  }

  void removeScreenShareRequest(RemoteActivityData data) {
    _screenShareRequestList.removeWhere(
          (item) => item.identity == data.identity,
    );
    notifyListeners();
  }

  void clearScreenShareRequest(String identity) {
    _screenShareRequestList.removeWhere(
          (item) => item.identity?.identity == identity,
    );
    notifyListeners();
  }

  bool _isScreenShareDialogOpen = false;

  bool get isScreenShareDialogOpen => _isScreenShareDialogOpen;
  set isScreenShareDialogOpen(bool value) {
    _isScreenShareDialogOpen = value;
    notifyListeners();
  }

  int get screenShareRequestCount {
    final metadata = room.localParticipant?.metadata;
    if (!Utils.isHost(metadata) && !Utils.isCoHost(metadata)) return 0;
    if (_isScreenShareEnable) return 0;
    return screenShareRequestList.length;
  }

  void handleScreenShareRequest(bool allow, RemoteActivityData request) {
    sendPrivateAction(ActionModel(action: MeetingActions.requestScreenSharePermissionResponse, isScreenShareAllowed: allow), request.identity?.identity ?? "");
  }

  //===============================[Chat Attachment Permission]===============================
  bool _isChatAttachmentDownloadEnable = true;

  bool get isChatAttachmentDownloadEnable => _isChatAttachmentDownloadEnable;

  set isChatAttachmentDownloadEnable(bool value) {
    _isChatAttachmentDownloadEnable = value;
    notifyListeners();
  }

  void getChatAttachmentConsent() {
    networkRequestHandler(
        apiCall: ()=> apiClient.getChatAttachmentConsent(selfIdentity, meetingDetails.meetingUid),
        onSuccess: (data) {
          isChatAttachmentDownloadEnable = data?.chatAttachmentDownloadConsent == true;
        },
        onError: (message) {
          sendMessageToUI(message);
          isChatAttachmentDownloadEnable = false;
        }
    );
  }

  void updateChatAttachmentConsent(bool value) {
    Map<String, dynamic> body = {
      "meeting_id": meetingDetails.meetingUid,
      "permission_granted": value,
    };

    networkRequestHandler(
        apiCall: ()=> apiClient.updateChatAttachmentConsent(meetingDetails.authorizationToken, selfIdentity, body),
        onSuccess: (data) {
          isChatAttachmentDownloadEnable = data?.chatAttachmentDownloadConsent == true;
          sendAction(ActionModel(action: MeetingActions.canDownloadChatAttachment, value: _isChatAttachmentDownloadEnable));
        },
        onError: (message) {
          sendMessageToUI(message);
          isChatAttachmentDownloadEnable = !isChatAttachmentDownloadEnable;
        }
    );
  }

  //===============================[Webinar Control]===============================

  void getAudioPermission() {
    networkRequestHandler(
        apiCall: ()=> apiClient.getAudioPermission(selfIdentity, meetingDetails.meetingUid),
        onSuccess: (data) {
          isAudioModeEnable = (data?.audioPermission == true);
          isAudioPermissionEnable = !(data?.audioPermission == true);
        },
        onError: (message) {
          sendMessageToUI(message);
          isAudioModeEnable = false;
          isAudioPermissionEnable = false;
        }
    );
  }

  void updateAudioPermission(bool value) {
    Map<String, dynamic> body = {
      "meeting_id": meetingDetails.meetingUid,
      "permission_granted": value,
    };
    networkRequestHandler(
        apiCall: ()=> apiClient.updateAudioPermission(meetingDetails.authorizationToken, selfIdentity, body),
        onSuccess: (data) {
          isAudioModeEnable = (data?.audioPermission == true);
          isAudioPermissionEnable = !(data?.audioPermission == true);
          sendAction(ActionModel(action: MeetingActions.forceMuteAll, value: _isAudioModeEnable));
        },
        onError: (message) {
          sendMessageToUI(message);
          isAudioModeEnable = !isAudioModeEnable;
          isAudioPermissionEnable = !isAudioPermissionEnable;
        }
    );
  }

  void getVideoPermission() {
    networkRequestHandler(
        apiCall: ()=> apiClient.getVideoPermission(selfIdentity, meetingDetails.meetingUid),
        onSuccess: (data) {
          isVideoModeEnable = (data?.videoPermission == true);
          isVideoPermissionEnable = !(data?.videoPermission == true);
        },
        onError: (message) {
          sendMessageToUI(message);
          isVideoModeEnable = false;
          isVideoPermissionEnable = false;
        }
    );
  }

  void updateVideoPermission(bool value) {
    Map<String, dynamic> body = {
      "meeting_id": meetingDetails.meetingUid,
      "permission_granted": value,
    };
    networkRequestHandler(
        apiCall: ()=> apiClient.updateVideoPermission(meetingDetails.authorizationToken, selfIdentity, body),
        onSuccess: (data) {
          isVideoModeEnable = (data?.videoPermission == true);
          isVideoPermissionEnable = !(data?.videoPermission == true);
          sendAction(ActionModel(action: MeetingActions.forceVideoOffAll, value: _isVideoModeEnable));
        },
        onError: (message) {
          sendMessageToUI(message);
          isVideoModeEnable = !isVideoModeEnable;
          isVideoPermissionEnable = !isVideoPermissionEnable;
        }
    );
  }

  //===============================[Live Caption]===============================

  void handleCaptionTranscription(CaptionData data) {
    final name = getParticipantNameByIdentity(data.participantIdentity);

    final isFinal = data.speechEventType == Constant.captionAgentFinalTranscript;
    final isPartial = data.speechEventType == Constant.captionAgentInterimTranscript;

    if (isFinal) {
      if (particalTranscription != null) {
        // Finalize previous partial
        particalTranscription = particalTranscription!.copyWith(
          name: name,
          transcription: data.text,
          isFinal: true,
          sourceLang: transcriptionLanguageData?.sourceLang ?? data.language,
          targetLang: translationLanguage?.code ??
              transcriptionLanguageData?.sourceLang ??
              data.language,
        );

        _updateTranscriptionInList(particalTranscription!);

        if (particalTranscription!.sourceLang !=
            particalTranscription!.targetLang) {
          translateText(particalTranscription!);
        }
      } else {
        final newTranscription = TranscriptionModel(
          id: const Uuid().v4(),
          name: name,
          transcription: data.text,
          timestamp: Utils.formatTimestampToTime(
              DateTime.now().millisecondsSinceEpoch),
          isFinal: true,
          sourceLang: transcriptionLanguageData?.sourceLang ?? data.language,
          targetLang: translationLanguage?.code ??
              transcriptionLanguageData?.sourceLang ??
              data.language,
        );

        addTranscription(newTranscription);

        if (newTranscription.sourceLang != newTranscription.targetLang) {
          translateText(newTranscription);
        }
      }

      particalTranscription = null;
    }

    // -------------------- PARTIAL ---------------------
    else if (isPartial) {
      if (particalTranscription != null) {
        // Update existing partial
        particalTranscription = particalTranscription!.copyWith(
          name: name,
          transcription: data.text,
          isFinal: false,
          sourceLang: transcriptionLanguageData?.sourceLang ?? data.language,
          targetLang: translationLanguage?.code ??
              transcriptionLanguageData?.sourceLang ??
              data.language,
        );

        _updateTranscriptionInList(particalTranscription!);
      } else {
        // Create new partial
        particalTranscription = TranscriptionModel(
          id: const Uuid().v4(),
          name: name,
          transcription: data.text,
          timestamp: Utils.formatTimestampToTime(
              DateTime.now().millisecondsSinceEpoch),
          isFinal: false,
          sourceLang: transcriptionLanguageData?.sourceLang ?? data.language,
          targetLang: translationLanguage?.code ??
              transcriptionLanguageData?.sourceLang ??
              data.language,
        );

        addTranscription(particalTranscription!);
      }
    }
  }

  void registerCaption() {
    room.registerTextStreamHandler(Constant.liveCaptionAgent, (TextStreamReader reader, String participantIdentity) async {
        final raw = await reader.readAll();
        try {
          final jsonData = jsonDecode(raw);
          final caption = CaptionData.fromJson(jsonData);

          handleCaptionTranscription(caption);
        } catch (e) {
          debugPrint("[ERROR] Failed to parse caption: $e");
        }
      },
    );
  }

  void unregisterCaption() {
    room.unregisterTextStreamHandler(Constant.liveCaptionAgent);
  }

  void storeMeetingDetails() {
    final storageHelper = StorageHelper();
    final metadata = room.localParticipant?.metadata;
    final sessionUid = Utils.getMetadataSessionUid(metadata);
    final isCoHost = Utils.isCoHost(metadata);
    storageHelper
        .setMeetingUid(meetingDetails.meetingUid);
    if (sessionUid != null) {
      storageHelper.setSessionUid(sessionUid);
    }
    storageHelper.setAttendanceId(Utils.getMetadataAttendanceId(room.localParticipant?.metadata));
    storageHelper.setAttendanceRole(
        isCoHost ? AttendanceRole.cohost : AttendanceRole.participant);
  }

  void requestChatHistory() {
    if (room.remoteParticipants.values.isEmpty) return;
    final participant = room.remoteParticipants.values.first;
    sendPrivateAction(
      ActionModel(action: MeetingActions.requestPublicChat, userIdentity: room.localParticipant?.identity),
      participant.identity,
    );
  }

  void sendPublicChatHistory(String? identity) {
    if (identity == null) return;
    final payload = ChatMessageMapper.toApiList(getMessageList());
    sendPrivateAction(
      ActionModel(action: MeetingActions.responsePublicChat, messages: payload, userIdentity: room.localParticipant?.identity),
      identity,
    );
  }

  void restorePublicChat(RemoteActivityData remoteData) {
    final messages = ChatMessageMapper.fromApiList(remoteData.messages ?? []);
    addAllMessage(messages);
  }


  void sendPrivateChatHistory(String? identity) {
    if (identity == null) return;
    if (!hasPrivateChat(identity)) return;
    final payload = ChatMessageMapper.toApiList(getPrivateMessage()[identity]?.chats ?? []);
    sendPrivateAction(
      ActionModel(action: MeetingActions.sendPrivateChat, userIdentity: room.localParticipant?.identity, messages: payload),
      identity,
    );
  }

  void restorePrivateChat(RemoteActivityData remoteData) {
    final messages = ChatMessageMapper.fromApiList(remoteData.messages ?? []);
    final identity = remoteData.userIdentity;
    final name = getParticipantNameByIdentity(identity);
    _privateChat.putIfAbsent(
        identity ?? "Unknown",
            () => PrivateChatModel(
            identity: identity ?? "Unknown",
            name: name,
            chats: messages));
    notifyListeners();
    sendPrivateChatEvent(UpdateView());
  }

  void lowerHand(String? identity) {
    if (identity == null) return;
    if (room.localParticipant?.identity == identity) {
      setMyHandRaised(false);
      sendAction(ActionModel(action: MeetingActions.stopRaiseHand));
    } else {
      sendPrivateAction(ActionModel(action: MeetingActions.lowerHand), identity);
    }
  }

}
