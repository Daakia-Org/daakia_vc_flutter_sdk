library daakia_vc_flutter_sdk;

import 'package:daakia_vc_flutter_sdk/api/injection.dart';
import 'package:daakia_vc_flutter_sdk/presentation/screens/license_expired.dart';
import 'package:daakia_vc_flutter_sdk/presentation/screens/loading_screen.dart';
import 'package:daakia_vc_flutter_sdk/presentation/screens/prejoin_screen.dart';
import 'package:flutter/widgets.dart';

import 'model/daakia_meeting_configuration.dart';
import 'model/meeting_details_model.dart';
import 'utils/constants.dart';

/// Optional SDK-level configuration. Call [DaakiaSdk.initialize] once in your
/// app's startup (e.g. before [runApp]) to override default URLs.
///
/// ```dart
/// DaakiaSdk.initialize(
///   baseUrl: '<BASE_URL>',
///   whiteboardDomain: '<WHITEBOARD_URL>',
/// );
/// ```
///
/// Omitting a parameter keeps the production default.
class DaakiaSdk {
  DaakiaSdk._();

  static void initialize({
    String? baseUrl,
    String? whiteboardDomain,
  }) {
    if (baseUrl != null) {
      Constant.baseUrl = baseUrl;
    }
    if (whiteboardDomain != null) {
      Constant.whiteboardDomain = whiteboardDomain;
    }
  }
}

class DaakiaVideoConferenceWidget extends StatefulWidget {
  /// Creates a new instance of the [DaakiaVideoConferenceWidget].
  ///
  /// [secretKey] is the license key required for authenticating the meeting session.
  /// [meetingId] is the unique identifier for the meeting.
  /// [isHost] determines if the current participant is the meeting host.
  /// [configuration] provides optional advanced customizations.
  const DaakiaVideoConferenceWidget(
      {required this.meetingId,
      required this.secretKey,
      this.isHost = false,
      this.configuration,
      super.key});

  /// Unique identifier for the meeting session.
  final String meetingId;

  /// License key used to verify and authorize access to the meeting.
  ///
  /// This key is validated before allowing the user to join the session.
  /// Make sure the provided key is valid for the associated [meetingId].
  final String secretKey;

  /// Determines whether the user is a host.
  ///
  /// This can control special permissions in the meeting.
  final bool isHost;

  /// Optional advanced configuration for the meeting widget.
  ///
  /// This is a [BETA] feature intended for advanced customization and future extensibility.
  /// This field is optional and can be left `null` for default behavior.
  final DaakiaMeetingConfiguration? configuration;

  @override
  State<StatefulWidget> createState() {
    return _DaakiaVideoConferenceState();
  }
}

class _DaakiaVideoConferenceState extends State<DaakiaVideoConferenceWidget> {
  var _isLoading = false;
  var _verified = false;
  var _licenseMessage = "";
  MeetingDetailsModel? meetingDetails;

  @override
  void initState() {
    _verifyLicense();
    super.initState();
  }

  void _verifyLicense() {
    setState(() {
      _isLoading = true;
    });
    Map<String, dynamic> body = {
      "secret_key": widget.secretKey,
      "meeting_uid": widget.meetingId
    };
    networkRequestHandler(
        apiCall: () => apiClient.licenceVerify(body),
        onSuccess: (data) {
          _verified = data?.userVerified ?? false;
          if (_verified) {
            _getMeetingDetails();
            return;
          } else {
            _licenseMessage = "License key not verified!";
          }
          setState(() {
            _isLoading = false;
          });
        },
        onError: (message) {
          setState(() {
            _verified = false;
            _isLoading = false;
            _licenseMessage = message;
          });
        });
  }

  void _getMeetingDetails() {
    networkRequestHandler(
      apiCall: () =>
          apiClient.getMeetingDetails(widget.meetingId, widget.secretKey),
      onSuccess: (response) {
        meetingDetails = response;
        setState(() {
          _isLoading = false;
        });
      },
      onError: (message) {
        setState(() {
          _verified = false;
          _isLoading = false;
          _licenseMessage = message;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget screen = const LoadingScreen();
    if (_isLoading) {
      screen = const LoadingScreen();
    } else if (_verified) {
      screen = PreJoinScreen(
        meetingId: widget.meetingId,
        secretKey: widget.secretKey,
        isHost: widget.isHost,
        basicMeetingDetails: meetingDetails,
        configuration: widget.configuration,
      );
    } else {
      screen = LicenseExpiredScreen(_licenseMessage);
    }
    return screen;
  }
}
