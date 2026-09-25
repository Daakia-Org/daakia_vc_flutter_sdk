import 'dart:async';
import 'dart:io';

import 'package:daakia_vc_flutter_sdk/model/features.dart';
import 'package:daakia_vc_flutter_sdk/model/meeting_details.dart';
import 'package:daakia_vc_flutter_sdk/model/meeting_details_model.dart';
import 'package:daakia_vc_flutter_sdk/model/rtc_data.dart';
import 'package:daakia_vc_flutter_sdk/enum/attendance_role_enum.dart';
import 'package:daakia_vc_flutter_sdk/rtc/meeting_manager.dart';
import 'package:daakia_vc_flutter_sdk/utils/device_id_provider.dart';
import 'package:daakia_vc_flutter_sdk/utils/storage_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:loading_btn/loading_btn.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../api/injection.dart';
import '../../model/daakia_meeting_configuration.dart';
import '../../model/meeting_status_model.dart';
import '../../presentation/bottom_sheets/duplicate_identity_bottomsheet.dart';
import '../../presentation/dialog/host_verification_dialog.dart';
import '../../presentation/dialog/join_failure_dialog.dart';
import '../../presentation/dialog/media_permission_dialog.dart';
import '../../resources/colors/color.dart';
import '../../rtc/room.dart';
import '../../service/daakia_vc_logger.dart';
import '../../utils/join_failure.dart';
import '../../utils/meeting_end_time.dart';
import '../../utils/name_input_formatter.dart';
import '../../utils/utils.dart';

@protected
class PreJoinScreen extends StatefulWidget {
  const PreJoinScreen(
      {required this.meetingId,
      required this.secretKey,
      this.isHost = false,
      required this.basicMeetingDetails,
      this.configuration,
      super.key});

  final String meetingId;
  final String secretKey;
  final bool isHost;
  final MeetingDetailsModel? basicMeetingDetails;

  /// Optional advanced configuration
  final DaakiaMeetingConfiguration? configuration;

  @override
  State<StatefulWidget> createState() {
    return _PreJoinState();
  }
}

class _PreJoinState extends State<PreJoinScreen> {
  bool isHostVerified = false;
  String hostToken = "";

  late MeetingDetails meetingDetails;

  var name = "";
  var password = "";
  String? _participantEmail;
  bool _joinAsGuest = false;
  String _guestEmail = "";

  var _obscurePassword = true;

  static const _defaultAlertMessage =
      'Check your camera and mic before you join.';

  var alertMessage = _defaultAlertMessage;
  var isRejected = false;

  var isLoading = false;
  var isNeedToCancelApiCall = false;
  var _enableAudio = false;
  var _enableVideo = false;

  var _isCoHostVerified = false;

  TextEditingController? _nameController;
  // Rotation swaps the portrait/landscape trees and remounts the fields, so
  // they need controllers to keep what was typed in sync with [password] /
  // [_guestEmail].
  final _passwordController = TextEditingController();
  final _guestEmailController = TextEditingController();
  bool _isNameEditable = true;
  bool _autoJoinStarted = false;
  String _skipJoinErrorMessage = "";
  bool _initialMediaStateResolved = false;

  // Meeting-level mic/camera locks (webinar/workshop mode). Fetched before the
  // user can join so a participant can't walk in publishing media the host has
  // switched off; room.dart re-checks and enforces after the connect.
  bool _isMicDisabledByHost = false;
  bool _isCameraDisabledByHost = false;

  //============== RTC ===============
  StreamSubscription? _subscription;
  List<MediaDevice> _audioInputs = [];
  List<MediaDevice> _videoInputs = [];
  LocalVideoTrack? _videoTrack;
  MediaDevice? _selectedVideoDevice;
  MediaDevice? _selectedAudioDevice;
  final VideoParameters _selectedVideoParameters =
      VideoParametersPresets.h720_169;

  LocalAudioTrack? _audioTrack;

  Features? features;

  late final MeetingManager meetingManager;

  @override
  void initState() {
    _subscription =
        Hardware.instance.onDeviceChange.stream.listen(_loadDevices);
    unawaited(_initializeMediaState());
    setUserName();
    // Schedule verifyCoHost after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await verifyCoHost();
      if (!mounted) return;
      // Prejoin only asks isMeetingEnded(); the warning schedule belongs to the
      // meeting screen, so no scheduler is started here.
      meetingManager = MeetingManager(
          endDate: getMeetingEndDate(), endMeetingCallBack: (event) {});
      // Awaited: skip-prejoin joins straight away, and joining with the mic on
      // is exactly what the host controls are supposed to prevent.
      await _fetchHostMediaRestrictions();
      if (!mounted) return;
      unawaited(_startAutoJoinIfRequired());
    });
    super.initState();
  }

  bool get _shouldSkipPreJoin => widget.configuration?.skipPreJoinPage == true;
  bool get _shouldEnableAudioByDefault =>
      widget.configuration?.enableMicrophoneByDefault == true;
  bool get _shouldEnableVideoByDefault =>
      widget.configuration?.enableCameraByDefault == true;
  bool get _isConfiguredCoHost =>
      widget.configuration?.vcConfig?.isCoHost == true;
  bool get _shouldBypassParticipantChecks =>
      _isCoHostVerified || _isConfiguredCoHost;

  // Host and co-host are never subject to the participant mic/camera locks.
  bool get _isPrivilegedUser => widget.isHost || _shouldBypassParticipantChecks;

  // Guest join is only offered when the meeting is password-protected and the
  // backend has enabled it for this meeting via meeting_config.is_guest_mode.
  bool get _isGuestModeAvailable =>
      widget.basicMeetingDetails?.meetingConfig?.isGuestMode == 1 &&
      (widget.basicMeetingDetails?.isStandardPassword == true ||
          widget.basicMeetingDetails?.isCommonPassword == true);

  Future<void> _initializeMediaState() async {
    try {
      final devices = await Hardware.instance.enumerateDevices();
      if (!mounted) return;
      _loadDevices(devices, updateState: false);
      await _applyConfiguredMediaDefaults();
    } finally {
      _initialMediaStateResolved = true;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _applyConfiguredMediaDefaults() async {
    final canEnableAudio = _shouldEnableAudioByDefault &&
        await _hasPermission(Permission.microphone);
    final canEnableVideo =
        _shouldEnableVideoByDefault && await _hasPermission(Permission.camera);

    _enableAudio = canEnableAudio &&
        _selectedAudioDevice != null &&
        !_isMicDisabledByHost;
    _enableVideo = canEnableVideo &&
        _selectedVideoDevice != null &&
        !_isCameraDisabledByHost;

    if (_enableAudio) {
      try {
        await _changeLocalAudioTrack();
      } catch (_) {
        _enableAudio = false;
        _audioTrack = null;
      }
    }

    if (_enableVideo) {
      try {
        await _changeLocalVideoTrack();
      } catch (_) {
        _enableVideo = false;
        _videoTrack = null;
      }
    }
  }

  /// Reads the meeting's host-control state so the prejoin toggles match what
  /// the participant will actually be allowed to do in the meeting.
  ///
  /// `x-self-identity` is a LiveKit participant identity, which doesn't exist
  /// yet at this point — the host-control states are meeting-level, so an empty
  /// identity is enough to read them. Any failure leaves the toggles untouched
  /// rather than locking the user out of their own mic; the room enforces the
  /// same states again right after joining.
  Future<void> _fetchHostMediaRestrictions() async {
    if (_isPrivilegedUser) return;

    await networkRequestHandler(
      apiCall: () => apiClient.getHostControls("", widget.meetingId),
      onSuccess: (data) {
        if (data == null) return;
        _isMicDisabledByHost = data.audioPermission;
        _isCameraDisabledByHost = data.videoPermission;
      },
      onError: (_) {},
    );

    await _applyHostMediaRestrictions();
  }

  Future<void> _applyHostMediaRestrictions() async {
    if (_isMicDisabledByHost && _enableAudio) {
      await _setEnableAudio(false);
    }
    if (!mounted) return;
    if (_isCameraDisabledByHost && _enableVideo) {
      await _setEnableVideo(false);
    }
    if (mounted) setState(() {});
  }

  bool get _isDefaultAlertSuppressed =>
      alertMessage == _defaultAlertMessage &&
      _hostMediaRestrictionMessage != null;

  /// Explains the locked toggles, so a participant doesn't read a greyed-out
  /// mic as a broken device.
  String? get _hostMediaRestrictionMessage {
    if (_isMicDisabledByHost && _isCameraDisabledByHost) {
      return "The host has disabled the microphone and camera for participants. "
          "You can still join and ask the host to unlock them.";
    }
    if (_isMicDisabledByHost) {
      return "The host has disabled the microphone for participants.";
    }
    if (_isCameraDisabledByHost) {
      return "The host has disabled the camera for participants.";
    }
    return null;
  }

  Future<bool> _hasPermission(Permission permission) async {
    final status = await permission.status;
    return status.isGranted || status.isLimited;
  }

  Future<void> _startAutoJoinIfRequired() async {
    if (!_shouldSkipPreJoin || _autoJoinStarted || !mounted) {
      return;
    }

    _autoJoinStarted = true;
    _skipJoinErrorMessage = "";
    isNeedToCancelApiCall = false;

    if (!_initialMediaStateResolved) {
      await _initializeMediaState();
      if (!mounted) return;
    }

    if (name.trim().isEmpty) {
      final resolvedName = await getUserName();
      if (!mounted) return;
      name = resolvedName.trim().isNotEmpty ? resolvedName : "Guest";
      _nameController?.text = name;
    }

    final validationError = _getSkipPreJoinValidationError();
    if (validationError != null) {
      _skipJoinErrorMessage = validationError;
      isLoading = false;
      if (mounted) {
        setState(() {});
      }
      return;
    }

    isLoading = true;
    if (mounted) {
      setState(() {});
    }

    _checkDuplicateJoinAndProceed(_autoStopLoading, () {
      if (widget.isHost && !isHostVerified) {
        final token = widget.configuration?.vcConfig?.hostToken;
        if (token != null && token.isNotEmpty) {
          hostToken = token;
          isHostVerified = true;
          getFeaturesAndJoinMeeting(_autoStopLoading);
          return;
        }
        _getHostToken(_autoStopLoading);
        return;
      }
      checkMeetingType(_autoStopLoading);
    });
  }

  String? _getSkipPreJoinValidationError() {
    if (_shouldBypassParticipantChecks) {
      return null;
    }
    if (widget.isHost &&
        widget.basicMeetingDetails?.hostPinVerificationRequired == 1 &&
        (widget.configuration?.vcConfig?.hostToken?.isEmpty ?? true)) {
      return "Host verification is required. Please provide host token in configuration or disable skipPreJoinPage.";
    }
    if (!widget.isHost &&
        widget.basicMeetingDetails?.isStandardPassword == true) {
      return "This meeting requires password verification. Disable skipPreJoinPage for this meeting type.";
    }
    if (!widget.isHost &&
        widget.basicMeetingDetails?.isCommonPassword == true) {
      return "This meeting requires a password. Disable skipPreJoinPage for this meeting type.";
    }
    return null;
  }

  void _autoStopLoading() {
    isLoading = false;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void setUserName() async {
    final initialName = await getUserName();
    setState(() {
      name = initialName;
      _nameController = TextEditingController(text: initialName);

      _isNameEditable = initialName.isEmpty ||
          (widget.configuration?.participantNameConfig?.isEditable ?? false);
    });
  }

  Future<String> getUserName() async {
    final inputName = widget.configuration?.participantNameConfig?.name;
    final guestName = await StorageHelper().getGuestUserName();

    // Helper to check null or empty
    String? validName(String? value) =>
        (value != null && value.trim().isNotEmpty) ? value : null;

    final resolvedName = validName(inputName) ?? validName(guestName) ?? "";

    return resolvedName;
  }

  /// See `RtcViewmodel.getMeetingEndDate`. The extension must be included:
  /// reading only `end_date`, which the extend API never moves, told anyone
  /// rejoining an extended meeting that it had already ended.
  String? getMeetingEndDate() {
    return MeetingEndTime.from(widget.basicMeetingDetails)
        .end
        ?.toIso8601String();
  }

  void _loadDevices(List<MediaDevice> devices,
      {bool updateState = true}) async {
    _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
    _videoInputs = devices.where((d) => d.kind == 'videoinput').toList();

    if (_audioInputs.isNotEmpty && _selectedAudioDevice == null) {
      _selectedAudioDevice = _audioInputs.first;
    }

    if (_videoInputs.isNotEmpty && _selectedVideoDevice == null) {
      // Try to find a front camera, otherwise default to the first available
      _selectedVideoDevice = _videoInputs.firstWhere(
        (device) => device.label.toLowerCase().contains('front'),
        orElse: () => _videoInputs.first,
      );
    }

    if (updateState && mounted) {
      setState(() {});
    }
  }

  Future<void> _setEnableAudio(bool value) async {
    _enableAudio = value && !_isMicDisabledByHost;
    if (_enableAudio) {
      await _changeLocalAudioTrack();
    } else {
      await _audioTrack?.stop();
      _audioTrack = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _changeLocalAudioTrack() async {
    if (_audioTrack != null) {
      await _audioTrack!.stop();
      _audioTrack = null;
    }

    if (_enableAudio && _selectedAudioDevice != null) {
      _audioTrack = await LocalAudioTrack.create(AudioCaptureOptions(
        deviceId: _selectedAudioDevice!.deviceId,
        stopAudioCaptureOnMute: false,
      ));
      await _audioTrack!.start();
    }
  }

  Future<void> _setEnableVideo(bool value) async {
    _enableVideo = value && !_isCameraDisabledByHost;
    if (_enableVideo) {
      await _changeLocalVideoTrack();
    } else {
      await _videoTrack?.stop();
      _videoTrack = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _changeLocalVideoTrack() async {
    if (_videoTrack != null) {
      await _videoTrack!.stop();
      _videoTrack = null;
    }

    if (_enableVideo && _selectedVideoDevice != null) {
      _videoTrack =
          await LocalVideoTrack.createCameraTrack(CameraCaptureOptions(
        deviceId: _selectedVideoDevice!.deviceId,
        params: _selectedVideoParameters,
      ));
      await _videoTrack!.start();
    }
  }

  String lobbyRequestId = "";
  bool isUserCanJoin = false;

  void joinMeeting(Function stopLoading, {bool isParticipant = false}) async {
    if (isNeedToCancelApiCall) {
      stopLoading.call();
      return;
    }

    isLoading = true;

    final configuredToken = widget.configuration?.vcConfig?.hostToken;
    if (hostToken.isEmpty &&
        configuredToken != null &&
        configuredToken.isNotEmpty) {
      hostToken = configuredToken;
    }

    Map<String, dynamic> body = {
      "meeting_uid": widget.meetingId,
      "preferred_video_server_id": "ap1",
      "display_name": name.trim()
    };
    if (isParticipant) {
      body["lobby_request_id"] = lobbyRequestId;
    }
    // Always include client_platform; merge with any caller-supplied metadata.
    final Map<String, dynamic> customMetadata =
        Map<String, dynamic>.from(widget.configuration?.metadata ?? {});
    customMetadata["client_platform"] = Utils.getClientPlatform();
    // Identifies the device, so the backend can tell this device's own
    // leftover session apart from a real second device (the duplicate-device
    // checks). Hashed, never the raw platform id: this metadata becomes the
    // LiveKit participant metadata, which every participant in the room can
    // read. A host app that already has its own device id can pass it in
    // metadata and keep it.
    customMetadata["device_id"] = await _resolveDeviceId();
    if (_joinAsGuest && _isGuestModeAvailable) {
      body["email"] = _participantEmail;
      body["is_guest"] = true;
      customMetadata["identifier"] = _participantEmail;
      customMetadata["participant_email"] = _participantEmail;
      customMetadata["participant_type"] = "guest";
    }
    body["custom_metadata"] = customMetadata;
    final cacheData = StorageHelper();
    var tokenFromCache = false;
    if (await cacheData.getMeetingUid() == widget.meetingId) {
      if (await cacheData.getSessionUid() ==
          widget.basicMeetingDetails?.currentSessionUid) {
        if (await cacheData.getAttendanceId() != "") {
          body["meeting_attendance_uid"] = await cacheData.getAttendanceId();
          if (hostToken.isEmpty) {
            final cachedToken = await cacheData.getHostToken() ?? "";
            if (cachedToken.isNotEmpty) {
              hostToken = cachedToken;
              tokenFromCache = true;
            }
          }
        }
      }
    }

    // Never forward a cached token to the join API — its role claim may be stale
    // (e.g. saved when cohost but user was later demoted). Send meeting_attendance_uid
    // instead and let the server determine the current role. The token is kept in
    // hostToken for in-session API calls that do require it.
    final token = tokenFromCache ? "" : hostToken;

    networkRequestHandlerWithMessage(
      apiCall: () => apiClient.getMeetingJoinDetail(token, body),
      onSuccess: (response) {
        if (response?.data == null) {
          if (mounted) {
            Utils.showSnackBar(context, message: "Something went wrong!");
          }
          return;
        }

        var it = response!.data!;
        alertMessage = response.message ?? "";

        if (!widget.isHost) {
          if (it.isRejected == true) {
            _handleRejection(stopLoading);
            return;
          }

          if (_isInvalidMeetingDetails(it)) {
            setState(() => alertMessage = response.message ?? "");
            if (it.meetingStarted == true ||
                widget.basicMeetingDetails?.isLobbyMode == true) {
              return;
            }
            meetingNotStarted(stopLoading);
            return;
          }

          final canJoinAsCoHost = it.roleName == AttendanceRole.cohost.name;
          if (it.participantCanJoin == true || canJoinAsCoHost) {
            _handleJoin(it, stopLoading);
          }
        } else {
          if (_isInvalidMeetingDetails(it)) {
            setState(() => alertMessage = response.message ?? "");
            meetingNotStarted(stopLoading);
            return;
          }
          _handleJoin(it, stopLoading);
        }
      },
      onError: (message) {
        if (_shouldSkipPreJoin) {
          _skipJoinErrorMessage = message;
        }
        setState(() {
          isLoading = false;
          isNeedToCancelApiCall = true;
          stopLoading.call();
        });
        unawaited(_showJoinApiError(message,
            stopLoading: stopLoading, isParticipant: isParticipant));
      },
    );
  }

  /// Reports a failure from the join API.
  ///
  /// Backend messages are already written for participants, so they are shown
  /// as-is — but a transport failure never reaches the backend, and the message
  /// the API layer synthesises for it ("Can't reach the server…") can't tell the
  /// user *why*. Probing here upgrades that one case to the full explanation,
  /// which is the difference between "no internet" and the Wi-Fi that is
  /// connected but has no internet access.
  Future<void> _showJoinApiError(
    String message, {
    required Function stopLoading,
    required bool isParticipant,
  }) async {
    if (!mounted) return;
    final failure = await JoinFailure.forNetwork(technicalDetail: message);
    if (!mounted) return;

    if (failure == null) {
      Utils.showSnackBar(context, message: message);
      return;
    }

    DaakiaVcLogger.logWarning(
      'Meeting join API failed with no usable connection',
      attributes: {
        'meeting_uid': widget.meetingId,
        'network_status': failure.diagnosis.status.name,
        'network_transport': failure.diagnosis.transport,
        'api_message': message,
      },
      reportToSentry: false,
    );

    if (_shouldSkipPreJoin) {
      setState(() => _skipJoinErrorMessage =
          '${failure.title}\n\n${failure.summary}');
      return;
    }

    final retry = await showJoinFailureDialog(context, failure);
    if (!retry || !mounted) return;

    // The failing call set this to cancel the attempt; clear it so the retry
    // isn't short-circuited by its own predecessor.
    isNeedToCancelApiCall = false;
    setState(() => isLoading = true);
    joinMeeting(stopLoading, isParticipant: isParticipant);
  }

  bool _isInvalidMeetingDetails(RtcData it) {
    return it.accessToken?.isEmpty != false ||
        it.livekitServerURL?.isEmpty != false;
  }

  void _handleJoin(RtcData it, Function stopLoading) {
    widget.basicMeetingDetails?.currentSessionUid = it.currentSessionUid;
    isNeedToCancelApiCall = true;
    _join(context, stopLoading,
        livekitUrl: it.livekitServerURL ?? "",
        livekitToken: it.accessToken ?? "");
  }

  void _handleRejection(Function stopLoading) {
    isRejected = true;
    lobbyRequestId = "";
    if (_shouldSkipPreJoin) {
      _skipJoinErrorMessage = alertMessage;
    }
    stopLoading.call();
    if (mounted) {
      setState(() => Utils.showSnackBar(context, message: alertMessage));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> meetingNotStarted(Function stopLoading) async {
    await Future.delayed(const Duration(seconds: 10));
    joinMeeting(stopLoading);
  }

  void _getHostToken(Function stopLoading) {
    isLoading = true;
    networkRequestHandler(
        apiCall: () => apiClient.getHostToken(widget.meetingId),
        onSuccess: (data) {
          isHostVerified = true;
          hostToken = data?.token ?? "";
          isNeedToCancelApiCall = data?.token == "";
          // Only now do we have a real token to identify this SaaS host with,
          // so run the duplicate-device check here rather than before fetch.
          _checkDuplicateJoinAndProceed(
              stopLoading, () => getFeaturesAndJoinMeeting(stopLoading));
        },
        onError: (message) {
          if (_shouldSkipPreJoin) {
            _skipJoinErrorMessage = message;
          }
          if (mounted) {
            Utils.showSnackBar(context, message: message);
          }
          setState(() {
            isLoading = false;
            isNeedToCancelApiCall = true;
            stopLoading.call();
          });
        });
  }

  /// [onResult] gets null on success or the error message on failure; when
  /// given, the error is left to the caller to show instead of a snackbar.
  void verifyHost(String email, String pin, Function stopLoading,
      {void Function(String? error)? onResult}) async {
    isLoading = true;

    Map<String, dynamic> body = {
      "email": email,
      "pin": pin,
      "meeting_id": widget.meetingId
    };

    networkRequestHandlerWithMessage(
        apiCall: () => apiClient.verifyHostToken(body),
        onSuccess: (response) {
          onResult?.call(null);
          if (mounted) {
            Utils.showSnackBar(context, message: response?.message ?? "");
          }
          isHostVerified = true;
          hostToken = response?.data?.token ?? "";
          isNeedToCancelApiCall = response?.data?.token == "";
          // Only now do we have a real token to identify this SaaS host with,
          // so run the duplicate-device check here rather than before fetch.
          _checkDuplicateJoinAndProceed(
              stopLoading, () => getFeaturesAndJoinMeeting(stopLoading));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).pop();
            }
          });
        },
        onError: (message) {
          if (_shouldSkipPreJoin) {
            _skipJoinErrorMessage = message;
          }
          if (onResult != null) {
            onResult(message);
          } else if (mounted) {
            Utils.showSnackBar(context, message: message);
          }
          setState(() {
            isLoading = false;
            isNeedToCancelApiCall = true;
            stopLoading.call();
          });
        });
  }

  void addParticipantToLobby(Function stopLoading) {
    if (isNeedToCancelApiCall) {
      stopLoading.call();
      return;
    }
    Map<String, dynamic> body = {
      "meeting_uid": widget.meetingId,
      "display_name": name.trim(),
    };
    if (_participantEmail != null && _participantEmail!.isNotEmpty) {
      body["email"] = _participantEmail;
    }
    if (_joinAsGuest && _isGuestModeAvailable) {
      body["is_guest"] = true;
    }

    networkRequestHandler(
        apiCall: () => apiClient.addParticipantToLobby(body),
        onSuccess: (data) {
          lobbyRequestId = data?.requestId ?? "";
          startAddingParticipantsPool(stopLoading);
        },
        onError: (message) {
          if (_shouldSkipPreJoin) {
            _skipJoinErrorMessage = message;
          }
          if (mounted) {
            Utils.showSnackBar(context, message: message);
          }
          stopLoading();
        });
  }

  Timer? _participantTimer;

  void startAddingParticipantsPool(Function stopLoading) {
    int iterations = 0;

    _participantTimer?.cancel(); // Cancel any previous timer if exists

    // Set up a timer to repeat every 10 seconds
    _participantTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (isNeedToCancelApiCall) {
        stopLoading.call();
        timer.cancel();
        return;
      }
      if (isUserCanJoin || isRejected || iterations >= 50) {
        // Stop the timer if the user can join, has been rejected, or after 2 minutes
        // stopLoading();
        timer.cancel();
        return;
      }

      // Call the function to add a participant to the lobby
      getFeaturesAndJoinMeeting(stopLoading,
          isLobby: true, isParticipant: true);

      iterations++; // Track the number of iterations
    });
  }

  void _showVerificationDialog(BuildContext context, Function stopLoading) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (_) => HostVerificationDialog(
        onVerify: (email, pin) {
          final result = Completer<String?>();
          verifyHost(email, pin, stopLoading, onResult: result.complete);
          return result.future;
        },
        onCancel: () {
          isNeedToCancelApiCall = true;
          stopLoading.call();
        },
      ),
    );
  }

  /// LiveKit's default gives each leg of the connect a single 10s window,
  /// which is tight for a phone moving between cells or on congested Wi-Fi.
  static const _connectTimeout = Duration(seconds: 12);

  /// The media-free retry gets longer still: it is the last attempt before the
  /// user is told they can't join at all.
  static const _fallbackConnectTimeout = Duration(seconds: 15);

  static const _weakConnectionNotice =
      'Your connection was weak, so you joined with your microphone and camera '
      'off. You can turn them on any time.';

  void _join(BuildContext context, Function stopLoading,
      {required String livekitUrl, required String livekitToken}) async {
    isLoading = true;

    setState(() {});

    // Remember what the user actually asked for. A failed attempt takes the
    // live tracks down with it (see [_discardLocalMedia]), so anything we
    // rebuild afterwards has to come from their intent, not from the track
    // objects — those are corpses by then.
    final wantedAudio = _enableAudio;
    final wantedVideo = _enableVideo;

    Object? lastError;

    // Two passes. The first publishes whatever the user set up on this screen.
    // If it was the media path that failed, the second drops the local mic and
    // camera: with nothing to publish there is no publisher peer connection to
    // negotiate and far less to force through a constrained network, which is
    // often enough to get in. Being in the meeting muted beats not getting in.
    for (var attempt = 0; attempt < 2; attempt++) {
      final withoutMedia = attempt == 1;
      final room = _buildRoom();
      // Create a Listener before connecting
      final listener = room.createListener();

      try {
        await room.prepareConnection(livekitUrl, livekitToken);

        // Try to connect to the room
        // This will throw an Exception if it fails for any reason.
        await room.connect(
          livekitUrl,
          livekitToken,
          connectOptions: _connectOptions(
              withoutMedia ? _fallbackConnectTimeout : _connectTimeout),
          fastConnectOptions: withoutMedia
              ? null
              : FastConnectOptions(
                  microphone: TrackOption(track: _audioTrack),
                  camera: TrackOption(track: _videoTrack),
                ),
        );
      } catch (error) {
        if (kDebugMode) {
          print('Could not connect $error');
        }
        lastError = error;
        await _disposeRoom(room, listener);
        await _discardLocalMedia();

        final shouldFallBack = !withoutMedia &&
            _isMediaPathFailure(error) &&
            (wantedAudio || wantedVideo) &&
            mounted;

        // Not a defect on its own — an attempt we are about to retry, and the
        // final outcome is logged separately. It's here so a Datadog dashboard
        // can show how often first attempts fail in the field, which is the
        // only way to tell a one-off from a systemic ICE/TURN problem.
        DaakiaVcLogger.logWarning(
          'Meeting join attempt failed',
          attributes: {
            'meeting_uid': widget.meetingId,
            'attempt': attempt + 1,
            'without_media': withoutMedia,
            'will_retry_without_media': shouldFallBack,
            'error_type': error.runtimeType.toString(),
            'error': error.toString(),
          },
          reportToSentry: false,
        );

        if (!shouldFallBack) break;

        if (mounted) {
          Utils.showSnackBar(this.context,
              message: 'Connection is weak — trying again with your camera '
                  'and microphone off…');
        }
        continue;
      }

      if (withoutMedia) {
        // A degraded join, not a failure — worth a dashboard line so a rise in
        // "joined muted" is visible before users start reporting it.
        DaakiaVcLogger.logWarning(
          'Joined meeting without local media after a media-path failure',
          attributes: {
            'meeting_uid': widget.meetingId,
            'wanted_audio': wantedAudio,
            'wanted_video': wantedVideo,
          },
          reportToSentry: false,
        );
      }

      await _enterMeeting(room, listener,
          livekitToken: livekitToken, joinedWithoutMedia: withoutMedia);
      if (mounted) {
        setState(() {
          stopLoading();
          isLoading = false;
        });
      }
      return;
    }

    // Note we are still "loading" here on purpose. On the pre-join page the
    // retry lives inside the failure dialog, so leaving the join button in its
    // loading state behind the dialog means Try Again reuses that spinner
    // instead of running a join under a button that looks idle.
    // [_reportJoinFailure] owns stopping it on every path that ends the attempt.
    await _reportJoinFailure(
      lastError,
      livekitUrl: livekitUrl,
      livekitToken: livekitToken,
      wantedAudio: wantedAudio,
      wantedVideo: wantedVideo,
      stopLoading: stopLoading,
    );
  }

  void _stopJoinLoading(Function stopLoading) {
    isLoading = false;
    stopLoading();
    if (mounted) setState(() {});
  }

  Room _buildRoom() {
    var cameraEncoding = const VideoEncoding(
      maxBitrate: 5 * 1000 * 1000,
      maxFramerate: 30,
    );

    var screenEncoding = const VideoEncoding(
      maxBitrate: 3 * 1000 * 1000,
      maxFramerate: 15,
    );

    // E2EEOptions? e2eeOptions;
    // if (args.e2ee && args.e2eeKey != null) {
    //   final keyProvider = await BaseKeyProvider.create();
    //   e2eeOptions = E2EEOptions(keyProvider: keyProvider);
    //   await keyProvider.setKey(args.e2eeKey!);
    // }

    return Room(
      roomOptions: RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioPublishOptions: const AudioPublishOptions(
          name: 'custom_audio_track_name',
        ),
        defaultAudioCaptureOptions: const AudioCaptureOptions(
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          stopAudioCaptureOnMute: false,
        ),
        defaultCameraCaptureOptions: const CameraCaptureOptions(
            maxFrameRate: 30,
            params: VideoParameters(
              dimensions: VideoDimensions(1280, 720),
            )),
        defaultScreenShareCaptureOptions: const ScreenShareCaptureOptions(
            useiOSBroadcastExtension: true,
            params: VideoParameters(
              dimensions: VideoDimensionsPresets.h1080_169,
            )),
        defaultVideoPublishOptions: VideoPublishOptions(
          simulcast: false,
          videoEncoding: cameraEncoding,
          screenShareEncoding: screenEncoding,
        ),
      ),
    );
  }

  /// [Timeouts] has no copyWith, so carry LiveKit's own defaults across and
  /// override only the window we care about.
  ConnectOptions _connectOptions(Duration timeout) {
    const defaults = Timeouts.defaultTimeouts;
    return ConnectOptions(
      timeouts: Timeouts(
        connection: timeout,
        debounce: defaults.debounce,
        publish: defaults.publish,
        subscribe: defaults.subscribe,
        peerConnection: defaults.peerConnection,
        iceRestart: defaults.iceRestart,
      ),
    );
  }

  /// True when signalling worked but media didn't — the only case a media-free
  /// retry can rescue. A signalling failure (rejected token, server
  /// unreachable) would fail exactly the same way the second time.
  bool _isMediaPathFailure(Object error) =>
      error is MediaConnectException || error is NegotiationError;

  Future<void> _enterMeeting(
    Room room,
    EventsListener<RoomEvent> listener, {
    required String livekitToken,
    required bool joinedWithoutMedia,
  }) async {
    //NOTE:: Storing guest name in cache
    StorageHelper().setGuestUserName(name.trim());

    meetingDetails = MeetingDetails(
        meetingUid: widget.meetingId,
        authorizationToken: hostToken,
        livekitToken: livekitToken,
        features: features,
        meetingBasicDetails: widget.basicMeetingDetails,
        // Guests must never trigger notifyParticipantJoinedStatus: that call
        // marks a pre-registered participant email as joined, so forwarding
        // a guest-entered email would let a guest impersonate/mark a real
        // invited participant as joined just by typing their address.
        participantEmail: _joinAsGuest ? null : _participantEmail);

    if (!mounted) {
      // Nobody is going to take ownership of this room, so don't leak it.
      await _disposeRoom(room, listener);
      return;
    }

    final navigator = Navigator.of(context);
    await navigator.push<void>(
      MaterialPageRoute(
          builder: (_) => RoomPage(room, listener, meetingDetails,
              fastConnection: true,
              sdkConfiguration: widget.configuration,
              joinNotice: joinedWithoutMedia ? _weakConnectionNotice : null)),
    );
    if (mounted && navigator.canPop()) {
      navigator.pop();
    }
  }

  /// A [Room] that never connected still owns a signal client, listeners and
  /// native peer connections. Without this every failed attempt leaked one.
  Future<void> _disposeRoom(
      Room room, EventsListener<RoomEvent> listener) async {
    try {
      await listener.dispose();
    } catch (_) {}
    try {
      await room.dispose();
    } catch (_) {}
  }

  /// Drops the preview tracks after a failed connect.
  ///
  /// A failed connect can take them down with it: once fast-connect has
  /// published them, the room's cleanup unpublishes everything, and
  /// `stopLocalTrackOnUnpublish` (LiveKit's default) stops the very
  /// [LocalAudioTrack] / [LocalVideoTrack] this screen created and still holds.
  /// Handing those to the next [Room] would join the user with a dead mic and a
  /// black preview — and they'd still carry a transceiver bound to the discarded
  /// peer connection. Whether or not the publish got that far is a race, so
  /// always let them go here and rebuild from intent instead.
  Future<void> _discardLocalMedia() async {
    try {
      await _audioTrack?.stop();
    } catch (_) {}
    try {
      await _videoTrack?.stop();
    } catch (_) {}
    _audioTrack = null;
    _videoTrack = null;
    _enableAudio = false;
    _enableVideo = false;
    if (mounted) setState(() {});
  }

  /// Rebuilds the preview the user had before a failed attempt, so they aren't
  /// left staring at a dead camera while deciding whether to retry.
  Future<void> _restoreLocalMedia(bool wantAudio, bool wantVideo) async {
    if (wantAudio && !_isMicDisabledByHost) {
      try {
        await _setEnableAudio(true);
      } catch (_) {}
    }
    if (!mounted) return;
    if (wantVideo && !_isCameraDisabledByHost) {
      try {
        await _setEnableVideo(true);
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  /// Translates whatever LiveKit threw into something a participant can act on
  /// and offers them the retry.
  Future<void> _reportJoinFailure(
    Object? error, {
    required String livekitUrl,
    required String livekitToken,
    required bool wantedAudio,
    required bool wantedVideo,
    required Function stopLoading,
  }) async {
    if (error == null || !mounted) {
      _stopJoinLoading(stopLoading);
      return;
    }

    // Diagnosing probes the network, so the join button stays in its loading
    // state until we actually have something to say.
    final failure = await JoinFailure.diagnose(error, livekitUrl: livekitUrl);

    // The one that matters: the user did not get in. The network diagnosis
    // rides along because the exception alone can't tell a blocked office
    // Wi-Fi from a phone that had already lost signal.
    DaakiaVcLogger.logError(
      'Meeting join failed: ${failure.title}',
      error: error,
      attributes: {
        'meeting_uid': widget.meetingId,
        'error_type': error.runtimeType.toString(),
        'error': error.toString(),
        'network_status': failure.diagnosis.status.name,
        'network_transport': failure.diagnosis.transport,
        'network_latency_ms': failure.diagnosis.latency?.inMilliseconds,
      },
    );

    if (!mounted) return;

    await _restoreLocalMedia(wantedAudio, wantedVideo);
    if (!mounted) return;

    // The skip-prejoin screen has no UI of its own behind a dialog — it renders
    // the message inline, with its own Retry button, and only once the loader
    // has stopped.
    if (_shouldSkipPreJoin) {
      _skipJoinErrorMessage = '${failure.title}\n\n${failure.summary}';
      _stopJoinLoading(stopLoading);
      return;
    }

    final retry = await showJoinFailureDialog(context, failure);
    if (!mounted) return;

    if (!retry) {
      _stopJoinLoading(stopLoading);
      return;
    }

    isNeedToCancelApiCall = false;
    _join(context, stopLoading,
        livekitUrl: livekitUrl, livekitToken: livekitToken);
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldSkipPreJoin) {
      return _buildSkipPreJoinLoader();
    }

    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    // A landscape phone with the keyboard up has ~150dp left; the app bar
    // alone would take a third of it, so drop it while typing to keep the
    // field and the Join button on screen together.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: isLandscape && keyboardOpen ? null : _buildAppBar(),
      body: SafeArea(
        top: isLandscape && keyboardOpen,
        child: isLandscape ? _buildLandscapeBody() : _buildPortraitBody(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final details = widget.basicMeetingDetails;
    final title = details?.eventName?.trim();
    final host = details?.host?.trim();
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 0,
      shape: const Border(bottom: BorderSide(color: Colors.black12)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            (title == null || title.isEmpty) ? 'Join meeting' : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (host != null && host.isNotEmpty)
            Text(
              'Hosted by $host',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black54, fontSize: 12.5),
            ),
        ],
      ),
    );
  }

  Widget _buildPortraitBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => SizedBox(
                  height: (constraints.maxWidth * 0.75).clamp(220.0, 380.0),
                  child: _buildPreview(),
                ),
              ),
              ..._buildStatusBanners(),
              const SizedBox(height: 32),
              _buildJoinForm(),
            ],
          ),
        ),
      ),
    );
  }

  /// Preview on the left, form on the right, so the Join button is on screen
  /// without scrolling, which a stacked layout can't manage in ~360dp height.
  Widget _buildLandscapeBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 11,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildPreview()),
                // With the keyboard up there's no room for both: the banner
                // squeezes the preview until its placeholder overflows.
                if (MediaQuery.viewInsetsOf(context).bottom == 0)
                  ..._buildStatusBanners(),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 9,
            child: Center(
              child: SingleChildScrollView(child: _buildJoinForm()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final showVideo = _videoTrack != null && _enableVideo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: emptyVideoColor,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showVideo)
              VideoTrackRenderer(
                _videoTrack!,
                renderMode: VideoRenderMode.auto,
                fit: VideoViewFit.cover,
              )
            else
              _buildCameraOffPlaceholder(),
            // Scrim so the name and buttons stay readable over bright video.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 28, 12, 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name.trim().isEmpty ? 'You' : name.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _MediaToggleButton(
                      isOn: _enableAudio,
                      onIcon: Icons.mic_rounded,
                      offIcon: Icons.mic_off_rounded,
                      lockedByHost: _isMicDisabledByHost,
                      tooltip: _isMicDisabledByHost
                          ? 'Microphone disabled by host'
                          : (_enableAudio
                                ? 'Turn off microphone'
                                : 'Turn on microphone'),
                      onPressed: _toggleAudio,
                    ),
                    const SizedBox(width: 12),
                    _MediaToggleButton(
                      isOn: _enableVideo,
                      onIcon: Icons.videocam_rounded,
                      offIcon: Icons.videocam_off_rounded,
                      lockedByHost: _isCameraDisabledByHost,
                      tooltip: _isCameraDisabledByHost
                          ? 'Camera disabled by host'
                          : (_enableVideo
                                ? 'Turn off camera'
                                : 'Turn on camera'),
                      onPressed: _toggleVideo,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The same `user_avatar` the meeting tiles read back out of participant
  /// metadata (see [Utils.extractUserAvatar]); the host app supplies it via
  /// [DaakiaMeetingConfiguration.metadata].
  String? get _userAvatarUrl {
    final value = widget.configuration?.metadata?['user_avatar'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  Widget _buildCameraOffPlaceholder() {
    final trimmed = name.trim();
    final avatarUrl = _userAvatarUrl;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Shrinks with the preview (e.g. landscape with the keyboard up).
        final avatar = (constraints.maxHeight * 0.34).clamp(40.0, 96.0);
        final showCaption = constraints.maxHeight > 150;
        final Widget fallback = trimmed.isEmpty
            ? Icon(
                Icons.person_rounded,
                color: Colors.white,
                size: avatar * 0.55,
              )
            : Text(
                Utils.getInitials(trimmed),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: avatar * 0.36,
                  fontWeight: FontWeight.w600,
                ),
              );
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: avatar,
              height: avatar,
              alignment: Alignment.center,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                color: themeColor,
                shape: BoxShape.circle,
              ),
              child: avatarUrl == null
                  ? fallback
                  : Image.network(
                      avatarUrl,
                      width: avatar,
                      height: avatar,
                      fit: BoxFit.cover,
                      // Initials until the image arrives, and for good if it
                      // fails, so the circle is never blank.
                      frameBuilder: (_, child, frame, wasSync) =>
                          wasSync || frame != null ? child : fallback,
                      errorBuilder: (_, _, _) => fallback,
                    ),
            ),
            if (showCaption) ...[
              const SizedBox(height: 12),
              Text(
                _isCameraDisabledByHost
                    ? 'Camera is disabled by the host'
                    : 'Camera is off',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
            // Keep the avatar clear of the bottom control row.
            SizedBox(height: showCaption ? 40 : 28),
          ],
        );
      },
    );
  }

  Future<void> _toggleVideo() async {
    if (!Platform.isIOS) {
      final granted = await checkAndRequestPermissions(
        context,
        checkForAudio: false,
      );
      if (!granted) return;
    }
    setState(() {
      _enableVideo = !_enableVideo;
      _setEnableVideo(_enableVideo);
    });
  }

  Future<void> _toggleAudio() async {
    if (!Platform.isIOS) {
      final granted = await checkAndRequestPermissions(
        context,
        checkForCamera: false,
      );
      if (!granted) return;
    }
    setState(() {
      _enableAudio = !_enableAudio;
      _setEnableAudio(_enableAudio);
    });
  }

  List<Widget> _buildStatusBanners() {
    return [
      if (_hostMediaRestrictionMessage != null) ...[
        const SizedBox(height: 16),
        _StatusBanner(
          icon: Icons.lock_outline_rounded,
          message: _hostMediaRestrictionMessage!,
        ),
      ],
      // "Check your camera and mic" is pointless advice when the host is the
      // one holding them off, so it's hidden until the API sends a real message.
      if (!_isDefaultAlertSuppressed && alertMessage.trim().isNotEmpty) ...[
        const SizedBox(height: 16),
        _StatusBanner(
          icon: Icons.info_outline_rounded,
          message: alertMessage,
          // Server messages (meeting not started, waiting in the lobby, …)
          // need the user's attention; the default hint doesn't.
          emphasized: alertMessage != _defaultAlertMessage,
        ),
      ],
    ];
  }

  Widget _buildJoinForm() {
    final details = widget.basicMeetingDetails;
    final showPassword =
        !widget.isHost &&
        !_shouldBypassParticipantChecks &&
        !_joinAsGuest &&
        (details?.isCommonPassword == true ||
            details?.isStandardPassword == true);
    final showGuestEmail =
        !widget.isHost &&
        !_shouldBypassParticipantChecks &&
        _joinAsGuest &&
        _isGuestModeAvailable;
    final showGuestToggle =
        !widget.isHost &&
        !_shouldBypassParticipantChecks &&
        _isGuestModeAvailable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Ready to join?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.black87,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (widget.isHost) ...[
          const SizedBox(height: 8),
          const Text(
            "You're joining as the host",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 14),
          ),
        ],
        const SizedBox(height: 24),
        TextFormField(
          controller: _nameController ?? TextEditingController(),
          onTapOutside: Utils.dismissKeyboardOnTapOutside,
          decoration: _fieldDecoration(
            label: 'Your name',
            icon: Icons.person_outline_rounded,
          ),
          style: const TextStyle(color: Colors.black87),
          enabled: _isNameEditable,
          textCapitalization: TextCapitalization.words,
          textInputAction: showPassword || showGuestEmail
              ? TextInputAction.next
              : TextInputAction.done,
          inputFormatters: [
            NameInputFormatter(),
            // Block digits
            FilteringTextInputFormatter.deny(RegExp(r'[0-9]')),
            // Block noisy punctuation (but allow . ' -)
            FilteringTextInputFormatter.deny(
              RegExp(r'[_\[\]{}<>@#$%^&*+=~`|\\/"^]'),
            ),
            LengthLimitingTextInputFormatter(50),
          ],
          onChanged: (value) => setState(() => name = value),
        ),
        if (showPassword) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            onTapOutside: Utils.dismissKeyboardOnTapOutside,
            decoration: _fieldDecoration(
              label: 'Meeting password',
              icon: Icons.lock_outline_rounded,
              suffix: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
            style: const TextStyle(color: Colors.black87),
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onChanged: (String? value) {
              setState(() {
                password = value ?? "";
              });
            },
          ),
        ],
        if (showGuestEmail) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _guestEmailController,
            onTapOutside: Utils.dismissKeyboardOnTapOutside,
            decoration: _fieldDecoration(
              label: 'Email',
              icon: Icons.mail_outline_rounded,
            ),
            style: const TextStyle(color: Colors.black87),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onChanged: (String? value) {
              setState(() {
                _guestEmail = (value ?? "").trim();
              });
            },
          ),
        ],
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) => LoadingBtn(
            height: 52,
            borderRadius: 12,
            animate: true,
            color: themeColor,
            width: constraints.maxWidth,
            loader: Container(
              padding: const EdgeInsets.all(12),
              width: 44,
              height: 44,
              child: const CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            child: const Text(
              "Join meeting",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: (startLoading, stopLoading, btnState) async {
              if (btnState == ButtonState.idle) {
                if (name.trim().isEmpty) {
                  Utils.showSnackBar(
                    context,
                    message: "Please enter your name",
                  );
                  return;
                }
                if (!widget.isHost &&
                    !_shouldBypassParticipantChecks &&
                    !await shouldAddAttendanceId()) {
                  var event = widget.basicMeetingDetails;
                  if (_joinAsGuest && _isGuestModeAvailable) {
                    if (!Utils.isValidEmail(_guestEmail)) {
                      if (!context.mounted) return;
                      Utils.showSnackBar(
                        context,
                        message: "Please enter a valid email",
                      );
                      return;
                    }
                  } else {
                    if (event?.isStandardPassword == true) {
                      if (!checkValidity()) {
                        return;
                      }
                    }
                    if (event?.isCommonPassword == true) {
                      if (password.isEmpty) {
                        if (!context.mounted) return;
                        Utils.showSnackBar(
                          context,
                          message: "Please enter your password",
                        );
                        return;
                      }
                    }
                  }
                }
                // Check and request permissions
                startLoading();
                if (isLoading) {
                  return;
                } else {
                  isNeedToCancelApiCall = false;
                  _checkDuplicateJoinAndProceed(stopLoading, () {
                    if (widget.isHost && !isHostVerified) {
                      if (!context.mounted) return;
                      final token = widget.configuration?.vcConfig?.hostToken;

                      if (token != null && token.isNotEmpty) {
                        hostToken = token;
                        isHostVerified = true;
                        isNeedToCancelApiCall = false;
                        getFeaturesAndJoinMeeting(stopLoading);
                        return;
                      }
                      if (widget
                              .basicMeetingDetails
                              ?.hostPinVerificationRequired ==
                          1) {
                        _showVerificationDialog(context, stopLoading);
                      } else {
                        _getHostToken(stopLoading);
                      }
                    } else {
                      checkMeetingType(stopLoading);
                    }
                  });
                }
              }
            },
          ),
        ),
        if (showGuestToggle) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _toggleGuestMode,
              icon: Icon(
                _joinAsGuest
                    ? Icons.lock_outline_rounded
                    : Icons.person_outline_rounded,
                size: 18,
                color: themeColor,
              ),
              label: Text(
                _joinAsGuest
                    ? "Have a password? Join with password"
                    : "Join as guest instead",
                style: const TextStyle(
                  color: themeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF6F6F9),
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffix,
      labelStyle: const TextStyle(color: Colors.black54),
      floatingLabelStyle: const TextStyle(color: themeColor),
      border: border(Colors.black12),
      enabledBorder: border(Colors.black12),
      disabledBorder: border(Colors.black12),
      focusedBorder: border(themeColor, 1.5),
    );
  }

  void _toggleGuestMode() {
    // Abort any in-flight lobby polling from a previous attempt so switching
    // modes mid-flight doesn't leave a stale lobby_request_id around.
    _participantTimer?.cancel();
    setState(() {
      _joinAsGuest = !_joinAsGuest;
      lobbyRequestId = "";
      if (_joinAsGuest) {
        password = "";
        _passwordController.clear();
      } else {
        _guestEmail = "";
        _guestEmailController.clear();
        _participantEmail = null;
      }
    });
  }

  Widget _buildSkipPreJoinLoader() {
    final hasError = _skipJoinErrorMessage.trim().isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading) ...[
                  const CircularProgressIndicator(color: themeColor),
                  const SizedBox(height: 16),
                  const Text(
                    "Joining call...",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
                if (!isLoading && hasError) ...[
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.wifi_tethering_error_rounded,
                        color: themeColor, size: 32),
                  ),
                  const SizedBox(height: 16),
                  // The message can run to a few lines of guidance, and this
                  // screen is all there is when the pre-join page is skipped —
                  // let it scroll rather than clip on a short viewport.
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        _skipJoinErrorMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.black87, fontSize: 14, height: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          _autoJoinStarted = false;
                          unawaited(_startAutoJoinIfRequired());
                        },
                        child: const Text("Retry"),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: () {
                          if (mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                        child: const Text("Back"),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void deactivate() {
    _subscription?.cancel();
    super.deactivate();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _participantTimer?.cancel();
    _nameController?.dispose();
    _passwordController.dispose();
    _guestEmailController.dispose();
    // Leaving this screen without joining must release the camera and mic —
    // otherwise the device's in-use indicator stays lit after the user backs
    // out, which reads as the SDK spying on them. On the join path these were
    // handed to the Room, which has already stopped them by now.
    final audioTrack = _audioTrack;
    final videoTrack = _videoTrack;
    _audioTrack = null;
    _videoTrack = null;
    unawaited(() async {
      try {
        await audioTrack?.stop();
      } catch (_) {}
      try {
        await videoTrack?.stop();
      } catch (_) {}
    }());
    super.dispose();
  }

  void _checkDuplicateJoinAndProceed(
      Function stopLoading, VoidCallback onProceed) {
    final token = widget.configuration?.vcConfig?.hostToken ?? hostToken;
    if (token.isEmpty) {
      // No authenticated identity yet (SaaS guest, or host token not fetched
      // yet) — meetingStatus requires an Authorization token, so calling it
      // now would always 401. Skip it and proceed; the host case is retried
      // with a real token once one is fetched (see _getHostToken/verifyHost).
      onProceed();
      return;
    }
    networkRequestHandler(
      apiCall: () => apiClient.getMeetingStatus(token, widget.meetingId),
      onSuccess: (data) async {
        if (data?.inMeeting != true) {
          onProceed();
          return;
        }
        // A session carrying this device's own id is this device's leftover
        // one (e.g. after a crash or a dropped connection) that the server
        // hasn't cleared yet, not a second device, so don't ask. Joining again
        // replaces it. Sessions without a device_id (older SDKs, web) still
        // count as another device.
        final deviceId = await _resolveDeviceId();
        final otherDevices = (data?.meetings ?? const <ActiveMeetingItem>[])
            .where((m) => m.deviceId != deviceId)
            .toList();
        if (!mounted) return;
        if (data?.meetings?.isNotEmpty == true && otherDevices.isEmpty) {
          onProceed();
          return;
        }
        _showDuplicateDeviceSheet(stopLoading, onProceed,
            otherPlatform:
                otherDevices.isNotEmpty ? otherDevices.first.platform : null);
      },
      onError: (_) => onProceed(),
    );
  }

  /// The device id sent as `device_id` in the join metadata, and compared
  /// against meetingStatus: the host app's own one from configuration
  /// metadata when it passes one, otherwise [DeviceIdProvider]'s.
  Future<String> _resolveDeviceId() async {
    final configured = widget.configuration?.metadata?["device_id"];
    if (configured != null && "$configured".trim().isNotEmpty) {
      return "$configured";
    }
    return DeviceIdProvider.get();
  }

  void _showDuplicateDeviceSheet(Function stopLoading, VoidCallback onProceed,
      {String? otherPlatform}) {
    if (!mounted) return;
    Utils.showAdaptiveSheet<void>(
      context,
      isDismissible: false,
      enableDrag: false,
      // Taller than a landscape phone even with the cap lifted.
      scrollable: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DuplicateIdentityBottomSheet(
        otherPlatform: otherPlatform,
        onLeave: () {
          Navigator.of(context).pop();
          isLoading = false;
          isNeedToCancelApiCall = true;
          stopLoading();
          if (mounted) setState(() {});
        },
        onSwitch: () {
          Navigator.of(context).pop();
          onProceed();
        },
      ),
    );
  }

  void getFeaturesAndJoinMeeting(Function stopLoading,
      {bool isLobby = false, bool isParticipant = false}) {
    if (isNeedToCancelApiCall) {
      stopLoading.call();
      return;
    }
    isLoading = true;

    networkRequestHandler(
        apiCall: () => apiClient.getFeatures(widget.meetingId),
        onSuccess: (data) {
          features = getFeature(data?.features);
          if (meetingManager.isMeetingEnded() &&
              widget.basicMeetingDetails?.meetingConfig?.autoMeetingEnd == 1 &&
              mounted) {
            // Prevents joining if the meeting has already ended and the user has Auto-Meeting-End enabled.
            setState(() {
              isLoading = false;
              isNeedToCancelApiCall = true;
              stopLoading.call();
            });
            if (!mounted) return;

            Utils.showSnackBar(
              context,
              message: "The meeting has already ended!",
            );

            if (widget.configuration?.skipPreJoinPage == true) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted && Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              });
            }
            return;
          }
          if (meetingManager.isMeetingEnded() &&
              features?.isBasicPlan() == true &&
              mounted) {
            // Prevents joining if the meeting has already ended and the user is on a basic plan.
            setState(() {
              isLoading = false;
              isNeedToCancelApiCall = true;
              stopLoading.call();
            });
            if (!mounted) return;

            Utils.showSnackBar(
              context,
              message: "The meeting has already ended!",
            );

            if (widget.configuration?.skipPreJoinPage == true) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted && Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              });
            }
            return;
          }
          if (isLobby) {
            joinMeeting(stopLoading, isParticipant: true);
          } else {
            joinMeeting(stopLoading);
          }
        },
        onError: (message) {
          if (_shouldSkipPreJoin) {
            _skipJoinErrorMessage = message;
          }
          setState(() {
            isLoading = false;
            isNeedToCancelApiCall = true;
            stopLoading.call();
          });
          if (mounted) {
            Utils.showSnackBar(context, message: message);
          }
        });
  }

  Future<bool> checkAndRequestPermissions(BuildContext context,
      {bool checkForCamera = true, bool checkForAudio = true}) async {
    if (checkForAudio &&
        !await _ensureMediaPermission(context, MediaPermission.microphone)) {
      return false;
    }
    if (checkForCamera) {
      if (!context.mounted) return false;
      if (!await _ensureMediaPermission(context, MediaPermission.camera)) {
        return false;
      }
    }
    return true;
  }

  /// Asks for [media] if needed; if it's refused, explains why it's needed and
  /// offers to ask again or, once the system has stopped asking, to open
  /// Settings. Resolves to whether the permission is granted in the end.
  Future<bool> _ensureMediaPermission(
      BuildContext context, MediaPermission media) async {
    var status = await media.permission.status;
    // Permanently denied reports isDenied == false, so check it explicitly:
    // otherwise the toggle would switch on without the permission.
    if (!status.isPermanentlyDenied && !status.isGranted && !status.isLimited) {
      status = await media.permission.request();
    }
    if (status.isGranted || status.isLimited) return true;
    if (!context.mounted) return false;
    return showMediaPermissionDialog(context, media,
        permanentlyDenied: status.isPermanentlyDenied);
  }

  Future<void> checkMeetingType(Function stopLoading) async {
    var event = widget.basicMeetingDetails;
    final shouldReuseAttendance =
        _shouldBypassParticipantChecks || await shouldAddAttendanceId();
    if (shouldReuseAttendance) {
      // Configured or cached co-host bypasses participant checks.
      getFeaturesAndJoinMeeting(stopLoading);
      return;
    }
    if (widget.isHost) {
      getFeaturesAndJoinMeeting(stopLoading);
    } else if (_joinAsGuest && _isGuestModeAvailable) {
      if (!Utils.isValidEmail(_guestEmail)) {
        if (mounted) {
          Utils.showSnackBar(context, message: "Please enter a valid email");
        }
        stopLoading();
        return;
      }
      if (isNeedToCancelApiCall) {
        stopLoading();
        return;
      }
      _participantEmail = _guestEmail;
      // Same as the standard lobby flow: register the guest via addToLobby
      // to get a server-issued lobby_request_id, then poll join with it
      // until the host accepts/rejects.
      addParticipantToLobby(stopLoading);
    } else if (event?.isStandardPassword == true) {
      if (checkValidity()) {
        verifyPasswordProtectedMeeting(stopLoading);
      } else {
        stopLoading();
      }
    } else if (event?.isCommonPassword == true) {
      if (password.isEmpty) {
        if (mounted) {
          Utils.showSnackBar(context, message: "Please enter your password");
        }
        stopLoading();
        return;
      }
      verifyCommonPasswordProtectedMeeting(stopLoading);
    } else {
      if (event?.isLobbyMode == true && !shouldReuseAttendance) {
        addParticipantToLobby(stopLoading);
        // startAddingParticipantsPool(stopLoading);
      } else {
        getFeaturesAndJoinMeeting(stopLoading);
      }
    }
  }

  Future<bool> shouldAddAttendanceId() async {
    final cacheData = StorageHelper();
    final cachedMeetingUid = await cacheData.getMeetingUid();
    final cachedSessionUid = await cacheData.getSessionUid();
    final cachedAttendanceId = await cacheData.getAttendanceId();
    final cachedAttendanceRole = await cacheData.getAttendanceRole();
    final shouldReuse = cachedMeetingUid == widget.meetingId &&
        cachedSessionUid == widget.basicMeetingDetails?.currentSessionUid &&
        cachedAttendanceId != "" &&
        cachedAttendanceRole == AttendanceRole.cohost;
    return shouldReuse;
  }

  Future<void> verifyCoHost() async {
    _isCoHostVerified = await shouldAddAttendanceId();
  }

  bool checkValidity() {
    if (password.isEmpty) {
      Utils.showSnackBar(context, message: "Please enter your password");
      return false;
    }
    return true;
  }

  void verifyCommonPasswordProtectedMeeting(Function stopLoading) {
    Map<String, dynamic> body = {
      "password": password,
      "meeting_uid": widget.meetingId
    };

    networkRequestHandlerWithMessage(
      apiCall: () => apiClient.verifyCommonMeetingPassword(body),
      onSuccess: (response) {
        if (response?.data?.passwordVerified == true) {
          passwordVerified(stopLoading);
        } else {
          passwordNotVerified(stopLoading,
              message: response?.message ?? "Not verified");
        }
      },
      onError: (message) {
        passwordNotVerified(stopLoading, message: message);
      },
    );
  }

  void verifyPasswordProtectedMeeting(Function stopLoading) {
    networkRequestHandlerWithMessage(
      apiCall: () => apiClient.verifyMeetingPassword({
        "password": password,
        "meeting_uid": widget.meetingId
      }),
      onSuccess: (response) {
        if (response?.data?.passwordVerified == true) {
          _participantEmail = response?.data?.participantEmail;
          passwordVerified(stopLoading);
        } else {
          passwordNotVerified(stopLoading,
              message: response?.message ?? "Not verified");
        }
      },
      onError: (errorMessage) {
        passwordNotVerified(stopLoading, message: errorMessage);
      },
    );
  }

  void passwordNotVerified(Function stopLoading,
      {String message = "Something went wrong!"}) {
    if (_shouldSkipPreJoin) {
      _skipJoinErrorMessage = message;
    }
    stopLoading();
    if (_shouldSkipPreJoin && mounted) {
      setState(() {});
    }
    Utils.showSnackBar(context, message: message);
  }

  Future<void> passwordVerified(Function stopLoading) async {
    if (widget.basicMeetingDetails?.isLobbyMode == true &&
        !_shouldBypassParticipantChecks &&
        !await shouldAddAttendanceId()) {
      // startAddingParticipantsPool(stopLoading);
      addParticipantToLobby(stopLoading);
    } else {
      getFeaturesAndJoinMeeting(stopLoading);
    }
  }

  Features? getFeature(Features? features) {
    final configFeature = widget.configuration?.vcConfig?.subscriptionFeature;
    if (configFeature?.subscriptionId != null &&
        configFeature?.features != null) {
      return configFeature?.features;
    }
    return features;
  }
}

/// Round mic/camera toggle on the pre-join preview: translucent when on, red
/// when off (so "off" reads at a glance), dimmed with a lock when the host
/// has disabled it.
class _MediaToggleButton extends StatelessWidget {
  const _MediaToggleButton({
    required this.isOn,
    required this.onIcon,
    required this.offIcon,
    required this.lockedByHost,
    required this.tooltip,
    required this.onPressed,
  });

  final bool isOn;
  final IconData onIcon;
  final IconData offIcon;
  final bool lockedByHost;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    if (lockedByHost) {
      background = Colors.white.withValues(alpha: 0.12);
      foreground = Colors.white38;
    } else if (isOn) {
      background = Colors.white.withValues(alpha: 0.22);
      foreground = Colors.white;
    } else {
      background = const Color(0xFFE5484D);
      foreground = Colors.white;
    }

    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: background,
            shape: CircleBorder(
              side: isOn && !lockedByHost
                  ? const BorderSide(color: Colors.white38)
                  : BorderSide.none,
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              // Null rather than a snackbar: the banner below the preview
              // already says why it's locked.
              onTap: lockedByHost ? null : onPressed,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  isOn ? onIcon : offIcon,
                  color: foreground,
                  size: 24,
                ),
              ),
            ),
          ),
          if (lockedByHost)
            const Positioned(
              right: -2,
              bottom: -2,
              child: CircleAvatar(
                radius: 9,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.lock_rounded,
                  size: 11,
                  color: Colors.black54,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A one-line-or-more notice under the pre-join preview.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.message,
    this.emphasized = false,
  });

  final IconData icon;
  final String message;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final color = emphasized ? themeColor : Colors.black54;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: emphasized
            ? themeColor.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      // Icon rides inline with the text so a wrapped message stays centred
      // as one block instead of leaving the icon stranded top-left.
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(icon, size: 18, color: color),
              ),
            ),
            TextSpan(text: message),
          ],
        ),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: emphasized ? themeColor : Colors.black87,
          fontSize: 13.5,
          height: 1.35,
          fontWeight: emphasized ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
    );
  }
}
