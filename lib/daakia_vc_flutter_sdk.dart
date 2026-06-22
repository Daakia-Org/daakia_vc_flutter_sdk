library daakia_vc_flutter_sdk;

import 'dart:convert';

import 'package:daakia_vc_flutter_sdk/api/injection.dart';
import 'package:daakia_vc_flutter_sdk/presentation/screens/license_expired.dart';
import 'package:daakia_vc_flutter_sdk/presentation/screens/loading_screen.dart';
import 'package:daakia_vc_flutter_sdk/presentation/screens/prejoin_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'model/daakia_meeting_configuration.dart';
import 'model/meeting_details_model.dart';
import 'model/observability_config.dart';
import 'model/observability_payload_model.dart';
import 'service/daakia_vc_datadog_service.dart';
import 'service/daakia_vc_sentry_service.dart';
import 'utils/constants.dart';
import 'utils/sdk_crypto.dart';

/// SDK-level configuration. Call [DaakiaSdk.initialize] once in your app's
/// startup (e.g. in [main] before [runApp]).
///
/// **New flow — recommended:**
/// ```dart
/// DaakiaSdk.initialize(
///   secret: '<YOUR_SECRET_KEY>',
///   baseUrl: '<BASE_URL>',         // optional, defaults to production
///   whiteboardDomain: '<WB_URL>',  // optional
/// );
/// ```
///
/// Once the secret is set here, omit [secretKey] from [DaakiaVideoConferenceWidget].
/// Omitting any parameter keeps the current default.
class DaakiaSdk {
  DaakiaSdk._();

  static String? _secret;

  static void initialize({
    String? secret,
    String? baseUrl,
    String? whiteboardDomain,
  }) {
    if (secret != null) _secret = secret;
    if (baseUrl != null) Constant.baseUrl = baseUrl;
    if (whiteboardDomain != null) Constant.whiteboardDomain = whiteboardDomain;
  }
}

class DaakiaVideoConferenceWidget extends StatefulWidget {
  /// Creates a new instance of the [DaakiaVideoConferenceWidget].
  ///
  /// **Recommended:** Set the secret key once at app startup via
  /// [DaakiaSdk.initialize] and omit [secretKey] here:
  /// ```dart
  /// // main.dart
  /// DaakiaSdk.initialize(secret: '<YOUR_SECRET_KEY>');
  ///
  /// // meeting screen
  /// DaakiaVideoConferenceWidget(meetingId: id, isHost: true)
  /// ```
  ///
  /// Passing [secretKey] directly still works but is deprecated — move it to
  /// [DaakiaSdk.initialize] to avoid repeating it on every widget instantiation.
  const DaakiaVideoConferenceWidget({
    required this.meetingId,
    this.secretKey,
    this.isHost = false,
    this.configuration,
    super.key,
  });

  /// Unique identifier for the meeting session.
  final String meetingId;

  /// License key used to verify and authorize access to the meeting.
  ///
  /// Deprecated: pass the secret key via [DaakiaSdk.initialize] at app startup
  /// and remove this parameter from the widget. It will be removed in a future
  /// major version.
  final String? secretKey;

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
  late final String? _secret;

  @override
  void initState() {
    super.initState();
    _secret = widget.secretKey ?? DaakiaSdk._secret;
    if (widget.secretKey != null) {
      debugPrint(
        '[DaakiaSDK] secretKey passed directly to DaakiaVideoConferenceWidget is deprecated. '
        'Move it to DaakiaSdk.initialize(secret: yourKey) in main() and remove it from the widget.',
      );
    }
    _verifyLicense();
  }

  void _verifyLicense() {
    if (_secret == null || _secret.isEmpty) {
      setState(() {
        _isLoading = false;
        _licenseMessage =
            'DaakiaSdk secret key is not configured. '
            'Call DaakiaSdk.initialize(secret: \'<your_key>\') in main() '
            'before launching DaakiaVideoConferenceWidget.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
    });
    networkRequestHandler(
        apiCall: () => apiClient.licenceVerify({
              "secret_key": _secret,
              "meeting_uid": widget.meetingId,
            }),
        onSuccess: (data) {
          _verified = data?.userVerified ?? false;
          if (_verified) {
            _getMeetingDetails();
            _initObservability();
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

  Future<void> _initObservability() async {
    if (DaakiaVcDatadogService.isInitialized && DaakiaVcSentryService.isInitialized) return;
    try {
      PackageInfo? pkgInfo;
      try { pkgInfo = await PackageInfo.fromPlatform(); } catch (_) {}

      final body = <String, dynamic>{
        'sdk_name': Constant.sdkName,
        'sdk_version': Constant.sdkVersion,
        if (pkgInfo != null) ...{
          'app_name': pkgInfo.appName,
          'app_version': pkgInfo.version,
          'app_identifier': pkgInfo.packageName,
        },
      };

      await networkRequestHandler<ObservabilityPayloadModel>(
        apiCall: () => apiClient.getObservabilityCredentials(_secret!, body),
        onSuccess: (data) async {
          final payload = data?.payload;
          if (payload == null) return;
          final json = SdkCrypto.decryptPayload(payload, _secret!);
          if (json == null) return;
          final config = ObservabilityConfigModel.fromJson(
            jsonDecode(json) as Map<String, dynamic>,
          );
          if (config.datadog != null) {
            await DaakiaVcDatadogService.initializeFromConfig(config.datadog!);
          }
          if (config.sentry != null) {
            await DaakiaVcSentryService.initializeFromConfig(config.sentry!);
          }
        },
      );
    } catch (_) {}
  }

  void _getMeetingDetails() {
    networkRequestHandler(
      apiCall: () =>
          apiClient.getMeetingDetails(widget.meetingId, _secret!),
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
        secretKey: _secret!,
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
