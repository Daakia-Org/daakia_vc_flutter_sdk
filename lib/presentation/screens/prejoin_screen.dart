import 'dart:async';
import 'dart:io';

import 'package:daakia_vc_flutter_sdk/model/features.dart';
import 'package:daakia_vc_flutter_sdk/model/meeting_details.dart';
import 'package:daakia_vc_flutter_sdk/model/meeting_details_model.dart';
import 'package:daakia_vc_flutter_sdk/model/rtc_data.dart';
import 'package:daakia_vc_flutter_sdk/rtc/meeting_manager.dart';
import 'package:daakia_vc_flutter_sdk/utils/rtc_ext.dart';
import 'package:daakia_vc_flutter_sdk/utils/storage_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:loading_btn/loading_btn.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../api/injection.dart';
import '../../model/daakia_meeting_configuration.dart';
import '../../resources/colors/color.dart';
import '../../rtc/room.dart';
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
  var email = "";
  var password = "";

  var _obscurePassword = true;

  var alertMessage = 'Please check your audio/video settings';
  var isRejected = false;

  var isLoading = false;
  var isNeedToCancelApiCall = false;
  var _enableAudio = false;
  var _enableVideo = false;

  var _isCoHostVerified = false;

  TextEditingController? _nameController;
  bool _isNameEditable = true;
  bool _autoJoinStarted = false;
  String _skipJoinErrorMessage = "";
  bool _initialMediaStateResolved = false;

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
      meetingManager = MeetingManager(
          endDate: getMeetingEndDate(),
          endMeetingCallBack: (event) {},
          context: context);
      unawaited(_startAutoJoinIfRequired());
    });
    super.initState();
  }

  bool get _shouldSkipPreJoin => widget.configuration?.skipPreJoinPage == true;
  bool get _shouldEnableAudioByDefault =>
      widget.configuration?.enableMicrophoneByDefault == true;
  bool get _shouldEnableVideoByDefault =>
      widget.configuration?.enableCameraByDefault == true;

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

    _enableAudio = canEnableAudio && _selectedAudioDevice != null;
    _enableVideo = canEnableVideo && _selectedVideoDevice != null;

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
  }

  String? _getSkipPreJoinValidationError() {
    if (_isCoHostVerified) {
      return null;
    }
    if (widget.isHost &&
        widget.basicMeetingDetails?.hostPinVerificationRequired == 1 &&
        (widget.configuration?.vcConfig?.hostToken?.isEmpty ?? true)) {
      return "Host verification is required. Please provide host token in configuration or disable skipPreJoinPage.";
    }
    if (!widget.isHost &&
        widget.basicMeetingDetails?.isStandardPassword == true) {
      return "This meeting requires email/password verification. Disable skipPreJoinPage for this meeting type.";
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

  String? getMeetingEndDate() {
    return widget.basicMeetingDetails?.meetingConfig?.autoMeetingEndSchedule ??
        widget.basicMeetingDetails?.endDate;
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
    _enableAudio = value;
    if (_enableAudio) {
      await _changeLocalAudioTrack();
    } else {
      await _audioTrack?.stop();
      _audioTrack = null;
    }
    setState(() {});
  }

  Future<void> _changeLocalAudioTrack() async {
    if (_audioTrack != null) {
      await _audioTrack!.stop();
      _audioTrack = null;
    }

    if (_enableAudio && _selectedAudioDevice != null) {
      _audioTrack = await LocalAudioTrack.create(AudioCaptureOptions(
        deviceId: _selectedAudioDevice!.deviceId,
      ));
      await _audioTrack!.start();
    }
  }

  Future<void> _setEnableVideo(bool value) async {
    _enableVideo = value;
    if (_enableVideo) {
      await _changeLocalVideoTrack();
    } else {
      await _videoTrack?.stop();
      _videoTrack = null;
    }
    setState(() {});
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

    var token = hostToken;
    Map<String, dynamic> body = {
      "meeting_uid": widget.meetingId,
      "preferred_video_server_id": "ap1",
      "display_name": name.trim()
    };
    if (isParticipant) {
      body["lobby_request_id"] = lobbyRequestId;
    }
    // Add custom_metadata only if metadata is provided
    if (widget.configuration?.metadata != null) {
      body["custom_metadata"] = widget.configuration?.metadata;
    }
    final cacheData = StorageHelper();
    if (await cacheData.getMeetingUid() == widget.meetingId) {
      if (await cacheData.getSessionUid() ==
          widget.basicMeetingDetails?.currentSessionUid) {
        if (await cacheData.getAttendanceId() != "") {
          body["meeting_attendance_uid"] = await cacheData.getAttendanceId();
          if (hostToken.isEmpty) {
            hostToken = await cacheData.getHostToken() ?? "";
          }
        }
      }
    }

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

          if (it.participantCanJoin == true) {
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
        if (mounted) Utils.showSnackBar(context, message: message);
      },
    );
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
          getFeaturesAndJoinMeeting(stopLoading);
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

  void verifyHost(String email, String pin, Function stopLoading) async {
    isLoading = true;

    Map<String, dynamic> body = {
      "email": email,
      "pin": pin,
      "meeting_id": widget.meetingId
    };

    networkRequestHandlerWithMessage(
        apiCall: () => apiClient.verifyHostToken(body),
        onSuccess: (response) {
          if (mounted) {
            Utils.showSnackBar(context, message: response?.message ?? "");
          }
          isHostVerified = true;
          hostToken = response?.data?.token ?? "";
          isNeedToCancelApiCall = response?.data?.token == "";
          getFeaturesAndJoinMeeting(stopLoading);
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

  void addParticipantToLobby(Function stopLoading) {
    if (isNeedToCancelApiCall) {
      stopLoading.call();
      return;
    }
    Map<String, dynamic> body = {
      "meeting_uid": widget.meetingId,
      "display_name": name.trim(),
    };

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
    final emailController = TextEditingController();
    final pinController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Verify Email and PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'Enter your email',
                ),
                keyboardType: TextInputType.emailAddress, // Email input only
                textInputAction: TextInputAction.next, // Move to next field
              ),
              TextField(
                controller: pinController,
                decoration: const InputDecoration(
                  labelText: 'PIN',
                  hintText: 'Enter your PIN',
                ),
                keyboardType: TextInputType.number,
                obscureText: true, // Hide the PIN input
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Close the dialog
                isNeedToCancelApiCall = true;
                stopLoading.call();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                });
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                String email = emailController.text;
                String pin = pinController.text;
                if (!Utils.isValidEmail(email)) {
                  Utils.showSnackBar(context,
                      message: "Please enter your valid email");
                  return;
                }
                if (pin.isEmpty) {
                  Utils.showSnackBar(context, message: "Please enter your pin");
                  return;
                }
                verifyHost(email, pin, stopLoading);

                // Close the dialog
                // Navigator.of(context).pop();
              },
              child: const Text('Verify'),
            ),
          ],
        );
      },
    );
  }

  void _join(BuildContext context, Function stopLoading,
      {required String livekitUrl, required String livekitToken}) async {
    isLoading = true;

    setState(() {});

    // var args = widget.args;

    try {
      //create new room
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

      final room = Room(
        roomOptions: RoomOptions(
          adaptiveStream: false,
          dynacast: false,
          defaultAudioPublishOptions: const AudioPublishOptions(
            name: 'custom_audio_track_name',
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
      // Create a Listener before connecting
      final listener = room.createListener();

      await room.prepareConnection(livekitUrl, livekitToken);

      // Try to connect to the room
      // This will throw an Exception if it fails for any reason.
      await room.connect(
        livekitUrl,
        livekitToken,
        fastConnectOptions: FastConnectOptions(
          microphone: TrackOption(track: _audioTrack),
          camera: TrackOption(track: _videoTrack),
        ),
      );

      //NOTE:: Storing guest name in cache
      StorageHelper().setGuestUserName(name.trim());

      meetingDetails = MeetingDetails(
          meetingUid: widget.meetingId,
          authorizationToken: hostToken,
          livekitToken: livekitToken,
          features: features,
          meetingBasicDetails: widget.basicMeetingDetails);
      if (mounted) {
        final navigator = Navigator.of(this.context);
        await navigator.push<void>(
          MaterialPageRoute(
              builder: (_) => RoomPage(room, listener, meetingDetails)),
        );
        if (mounted && navigator.canPop()) {
          navigator.pop();
        }
      }
    } catch (error) {
      if (kDebugMode) {
        print('Could not connect $error');
      }
      if (_shouldSkipPreJoin) {
        _skipJoinErrorMessage = error.toString();
      }
      if (context.mounted) {
        await context.showErrorDialog(error);
      }
    } finally {
      setState(() {
        stopLoading();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldSkipPreJoin) {
      return _buildSkipPreJoinLoader();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Prejoin Page",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: themeColor,
        elevation: 3,
        shadowColor: Colors.grey,
        iconTheme: const IconThemeData(
          color:
              Colors.white, // Set the color you want for the back button here
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Card(
                    color: emptyVideoColor,
                    elevation: 5,
                    clipBehavior: Clip.antiAliasWithSaveLayer,
                    child: SizedBox(
                      width: double.maxFinite,
                      height: Utils.isMobileDevice() ? 250 : 350,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _videoTrack != null && _enableVideo
                              ? Visibility(
                                  visible: _enableVideo,
                                  child: VideoTrackRenderer(
                                    renderMode: VideoRenderMode.auto,
                                    _videoTrack!,
                                  ),
                                )
                              : Visibility(
                                  visible: !_enableVideo,
                                  child: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.videocam_off,
                                        size: 55,
                                        color: Colors.white,
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Your Camera is turned off',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 15,
                                            color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              color: transparentMaskColor,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                        _enableVideo
                                            ? Icons.videocam
                                            : Icons.videocam_off,
                                        color: Colors.white),
                                    iconSize: 30,
                                    onPressed: () async {
                                      if (!Platform.isIOS) {
                                        bool permissionsGranted =
                                            await checkAndRequestPermissions(
                                                context,
                                                checkForAudio: false);
                                        if (!permissionsGranted) return;
                                      }
                                      setState(() {
                                        _enableVideo = !_enableVideo;
                                        _setEnableVideo(_enableVideo);
                                      });
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(
                                        _enableAudio
                                            ? Icons.mic
                                            : Icons.mic_off,
                                        color: Colors.white),
                                    iconSize: 30,
                                    onPressed: () async {
                                      if (!Platform.isIOS) {
                                        bool permissionsGranted =
                                            await checkAndRequestPermissions(
                                                context,
                                                checkForCamera: false);
                                        if (!permissionsGranted) return;
                                      }
                                      setState(() {
                                        _enableAudio = !_enableAudio;
                                        _setEnableAudio(_enableAudio);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                  Center(
                    child: Text(
                      alertMessage,
                      textAlign:
                          TextAlign.center, // Equivalent to gravity="center"
                      style: const TextStyle(
                        color: Colors
                            .black, // Equivalent to textColor="@color/black"
                        fontSize: 15, // Equivalent to textSize="15sp"
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    // Equivalent to marginHorizontal="20dp" and marginTop="10dp"
                    child: TextFormField(
                      controller: _nameController ?? TextEditingController(),
                      decoration: const InputDecoration(
                        labelText: 'Name*',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(color: Colors.black),
                      enabled: _isNameEditable,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [
                        NameInputFormatter(),
                        // Block digits
                        FilteringTextInputFormatter.deny(RegExp(r'[0-9]')),
                        // Block noisy punctuation (but allow . ' -)
                        FilteringTextInputFormatter.deny(
                            RegExp(r'[_\[\]{}<>@#$%^&*+=~`|\\/"^]')),
                        LengthLimitingTextInputFormatter(50),
                      ],
                      onChanged: (value) => setState(() => name = value),
                    ),
                  ),
                  Visibility(
                    visible: !widget.isHost &&
                        !_isCoHostVerified &&
                        (widget.basicMeetingDetails?.isStandardPassword ==
                            true),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      // Equivalent to marginHorizontal="20dp" and marginTop="10dp"
                      child: TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Email*', // Equivalent to hint="Name*"
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(
                          color: Colors
                              .black, // Equivalent to textColor="@color/black"
                        ),
                        enabled: true, // Equivalent to android:enabled="false"
                        onChanged: (String? value) {
                          setState(() {
                            email = value ?? "";
                          });
                        },
                      ),
                    ),
                  ),
                  Visibility(
                    visible: !widget.isHost &&
                        !_isCoHostVerified &&
                        (widget.basicMeetingDetails?.isCommonPassword == true ||
                            widget.basicMeetingDetails?.isStandardPassword ==
                                true),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      child: TextFormField(
                        decoration: InputDecoration(
                          labelText: 'Password*',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              !_obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        style: const TextStyle(
                          color: Colors.black,
                        ),
                        enabled: true,
                        obscureText: _obscurePassword,
                        onChanged: (String? value) {
                          setState(() {
                            password = value ?? "";
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  LoadingBtn(
                    height: 50,
                    borderRadius: 8,
                    animate: true,
                    color: themeColor,
                    width: MediaQuery.of(context).size.width * 0.45,
                    loader: Container(
                      padding: const EdgeInsets.all(10),
                      width: 40,
                      height: 40,
                      child: const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    child: const Text(
                      "Join Meeting",
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: (startLoading, stopLoading, btnState) async {
                      if (btnState == ButtonState.idle) {
                        if (name.trim().isEmpty) {
                          Utils.showSnackBar(context,
                              message: "Please enter your name");
                          return;
                        }
                        if (!widget.isHost && !await shouldAddAttendanceId()) {
                          var event = widget.basicMeetingDetails;
                          if (event?.isStandardPassword == true) {
                            if (!checkValidity()) {
                              return;
                            }
                          }
                          if (event?.isCommonPassword == true) {
                            if (password.isEmpty) {
                              if (!context.mounted) return;
                              Utils.showSnackBar(context,
                                  message: "Please enter your password");
                              return;
                            }
                          }
                        }
                        // Check and request permissions
                        startLoading();
                        if (isLoading) {
                          return;
                        } else {
                          isNeedToCancelApiCall = false;
                          if (widget.isHost && !isHostVerified) {
                            if (!context.mounted) return;
                            final token =
                                widget.configuration?.vcConfig?.hostToken;

                            if (token != null && token.isNotEmpty) {
                              hostToken = token;
                              isHostVerified = true;
                              isNeedToCancelApiCall = false;
                              getFeaturesAndJoinMeeting(stopLoading);
                              return;
                            }
                            if (widget.basicMeetingDetails
                                    ?.hostPinVerificationRequired ==
                                1) {
                              _showVerificationDialog(context, stopLoading);
                            } else {
                              _getHostToken(stopLoading);
                            }
                          } else {
                            checkMeetingType(stopLoading);
                          }
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
                  Text(
                    _skipJoinErrorMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
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
    super.dispose();
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
    // Check and request microphone permission
    if (checkForAudio) {
      if (await Permission.microphone.isDenied) {
        // Request permission
        PermissionStatus micStatus = await Permission.microphone.request();
        if (micStatus.isDenied) {
          if (context.mounted) {
            _showPermissionDialog(context, "Microphone");
            return false;
          }
        } else if (micStatus.isPermanentlyDenied) {
          if (context.mounted) {
            _showSettingsDialog(context, "Microphone");
            return false;
          }
        }
      }
    }

    if (checkForCamera) {
      // Check and request camera permission
      if (await Permission.camera.isDenied) {
        // Request permission
        PermissionStatus cameraStatus = await Permission.camera.request();
        if (cameraStatus.isDenied) {
          if (context.mounted) {
            _showPermissionDialog(context, "Camera");
            return false;
          }
        } else if (cameraStatus.isPermanentlyDenied) {
          if (context.mounted) {
            _showSettingsDialog(context, "Camera");
            return false;
          }
        }
      }
    }

    // Return true if both permissions are granted
    return true;
  }

// Show dialog if permission is temporarily denied
  void _showPermissionDialog(BuildContext context, String permissionType) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("$permissionType Permission Required"),
          content: Text(
              "Please allow $permissionType permission to join the meeting."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

// Show dialog with a link to app settings if permission is permanently denied
  void _showSettingsDialog(BuildContext context, String permissionType) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("$permissionType Permission Required"),
          content: Text(
              "$permissionType permission is permanently denied. Please enable it from the app settings."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                openAppSettings(); // Open the app settings
                Navigator.of(context).pop();
              },
              child: const Text("Settings"),
            ),
          ],
        );
      },
    );
  }

  Future<void> checkMeetingType(Function stopLoading) async {
    var event = widget.basicMeetingDetails;
    final shouldReuseAttendance = await shouldAddAttendanceId();
    if (shouldReuseAttendance) {
      // If shouldAddAttendanceId is true, bypass other checks
      getFeaturesAndJoinMeeting(stopLoading);
      return;
    }
    if (widget.isHost) {
      getFeaturesAndJoinMeeting(stopLoading);
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
        cachedAttendanceRole == "cohost";
    return shouldReuse;
  }

  Future<void> verifyCoHost() async {
    _isCoHostVerified = await shouldAddAttendanceId();
  }

  bool checkValidity() {
    var isValid = false;
    if (email.isNotEmpty) {
      if (Utils.isValidEmail(email)) {
        isValid = true;
      } else {
        Utils.showSnackBar(context, message: "Invalid email");
        return false;
      }
    } else {
      Utils.showSnackBar(context, message: "Please enter your email");
      return false;
    }
    if (password.isEmpty) {
      Utils.showSnackBar(context, message: "Please enter your password");
      return false;
    } else {
      isValid = true;
    }
    return isValid;
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
        "email": email,
        "password": password,
        "meeting_uid": widget.meetingId
      }),
      onSuccess: (response) {
        if (response?.data?.passwordVerified == true) {
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
