import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Internal Sentry service for SDK-level error and event tracking.
///
/// Uses a dedicated [SentryClient] so it never touches the host app's global
/// Sentry hub. Call [initialize] with a DSN obtained from the observability
/// credentials API before capturing events.
class DaakiaVcSentryService {
  static SentryClient? _client;
  static SentryOptions? _options;

  static bool get isInitialized => _client != null;

  static Future<void> initialize({required String dsn, String? release}) async {
    if (_client != null) return;
    try {
      _options = SentryOptions(dsn: dsn)
        ..release = release
        ..tracesSampleRate = 1.0;
      _client = SentryClient(_options!);
      _hookFlutterErrorHandlers();
    } catch (_) {}
  }

  /// Chains Sentry onto Flutter's existing error handlers without replacing them.
  /// Firebase Crashlytics (or any other handler) continues to work normally.
  static void _hookFlutterErrorHandlers() {
    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _client?.captureException(
        details.exception,
        stackTrace: details.stack,
      );
      previousFlutterError?.call(details);
    };

    final previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _client?.captureException(error, stackTrace: stack);
      return previousPlatformError?.call(error, stack) ?? false;
    };
  }

  static Future<Scope?> _buildScope(Map<String, Object?>? context) async {
    if (context == null || _options == null) return null;
    final scope = Scope(_options!);
    for (final entry in context.entries) {
      if (entry.value != null) {
        await scope.setTag(entry.key, entry.value.toString());
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
