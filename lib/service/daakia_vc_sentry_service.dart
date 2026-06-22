import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../model/observability_config.dart';
import '../utils/constants.dart';

/// Internal Sentry service for SDK-level error and event tracking.
///
/// Uses a dedicated [SentryClient] so it never touches the host app's global
/// Sentry hub. Call [initialize] with a DSN obtained from the observability
/// credentials API before capturing events.
class DaakiaVcSentryService {
  static SentryClient? _client;
  static SentryOptions? _options;

  static String? _appName;
  static String? _appVersion;
  static String? _appIdentifier;
  static String? _deviceModel;
  static String? _osVersion;

  static bool get isInitialized => _client != null;

  static Future<void> initializeFromConfig(SentryObsConfig config) async {
    await initialize(dsn: config.dsn);
  }

  static Future<void> initialize({required String dsn}) async {
    if (_client != null) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _appName = info.appName;
      _appVersion = info.version;
      _appIdentifier = info.packageName;

      final deviceInfo = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = await deviceInfo.androidInfo;
        _deviceModel = '${android.manufacturer} ${android.model}';
        _osVersion = 'Android ${android.version.release}';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = await deviceInfo.iosInfo;
        _deviceModel = ios.model;
        _osVersion = 'iOS ${ios.systemVersion}';
      }

      _options = SentryOptions(dsn: dsn)
        ..release = '${Constant.sdkName}@${Constant.sdkVersion}'
        ..tracesSampleRate = 1.0;
      _client = SentryClient(_options!);
      _hookFlutterErrorHandlers();
    } catch (_) {}
  }

  /// Chains Sentry onto Flutter's existing error handlers without replacing them.
  /// Only errors that originate inside the SDK are captured; host app errors
  /// are passed through untouched. Firebase Crashlytics (or any other handler)
  /// continues to work normally.
  static void _hookFlutterErrorHandlers() {
    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (_isFromSdk(details.stack)) {
        _captureWithScope(details.exception, details.stack);
      }
      previousFlutterError?.call(details);
    };

    final previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      if (_isFromSdk(stack)) {
        _captureWithScope(error, stack);
      }
      return previousPlatformError?.call(error, stack) ?? false;
    };
  }

  static Future<void> _captureWithScope(dynamic exception, StackTrace? stack) async {
    final scope = await _buildScope(null);
    await _client?.captureException(exception, stackTrace: stack, scope: scope);
  }

  static bool _isFromSdk(StackTrace? stack) {
    return stack.toString().contains('package:daakia_vc_flutter_sdk');
  }

  static Future<Scope?> _buildScope(Map<String, Object?>? context) async {
    if (_options == null) return null;
    final scope = Scope(_options!);

    if (_appName != null) await scope.setTag('app_name', _appName!);
    if (_appVersion != null) await scope.setTag('app_version', _appVersion!);
    if (_appIdentifier != null) await scope.setTag('app_identifier', _appIdentifier!);
    if (_deviceModel != null) await scope.setTag('device_model', _deviceModel!);
    if (_osVersion != null) await scope.setTag('os_version', _osVersion!);
    await scope.setTag('platform', Constant.platform);

    if (context != null) {
      for (final entry in context.entries) {
        if (entry.value != null) {
          await scope.setTag(entry.key, entry.value.toString());
        }
      }
    }
    return scope;
  }

  static Future<void> captureException(
    dynamic throwable, {
    dynamic stackTrace,
    Map<String, Object?>? context,
  }) async {
    if (_client == null) return;
    try {
      await _client!.captureException(
        throwable,
        stackTrace: stackTrace,
        scope: await _buildScope(context),
      );
    } catch (_) {}
  }

  static Future<void> captureMessage(
    String message, {
    SentryLevel level = SentryLevel.info,
    Map<String, Object?>? context,
  }) async {
    if (_client == null) return;
    try {
      await _client!.captureMessage(
        message,
        level: level,
        scope: await _buildScope(context),
      );
    } catch (_) {}
  }
}
