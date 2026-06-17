import 'package:sentry_flutter/sentry_flutter.dart';

import '../model/observability_config.dart';
import 'daakia_vc_datadog_service.dart';
import 'daakia_vc_sentry_service.dart';

/// Unified observability entry point.
///
/// Both services are independent — initialize either or both; an uninitialized
/// service is silently skipped without affecting the other.
class DaakiaVcLogger {
  DaakiaVcLogger._();

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initializes whichever services have credentials supplied.
  /// Pass null for a service to skip it entirely.
  static Future<void> initialize({
    DatadogObsConfig? datadog,
    SentryObsConfig? sentry,
  }) async {
    if (datadog != null) {
      await DaakiaVcDatadogService.initialize(
        clientToken: datadog.clientToken,
        env: datadog.env,
        serviceName: datadog.serviceName,
        applicationId: datadog.applicationId,
        version: datadog.version,
        site: datadog.site,
        enableCrashReporting: false,
      );
    }
    if (sentry != null) {
      await DaakiaVcSentryService.initialize(
        dsn: sentry.dsn,
        release: sentry.release,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  static void logDebug(String message, {Map<String, Object?>? attributes}) {
    DaakiaVcDatadogService.logDebug(message, attributes: attributes);
  }

  static void logInfo(String message, {Map<String, Object?>? attributes}) {
    DaakiaVcDatadogService.logInfo(message, attributes: attributes);
    DaakiaVcSentryService.captureMessage(
      message,
      level: SentryLevel.info,
      context: attributes,
    );
  }

  static void logWarning(String message, {Map<String, Object?>? attributes}) {
    DaakiaVcDatadogService.logWarning(message, attributes: attributes);
    DaakiaVcSentryService.captureMessage(
      message,
      level: SentryLevel.warning,
      context: attributes,
    );
  }

  /// Logs an error message to Datadog; Sentry receives it as an exception
  /// (with stack trace) if [error] is provided, or as an error message if not.
  static void logError(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    Map<String, Object?>? attributes,
  }) {
    DaakiaVcDatadogService.logError(message, null, null, attributes);
    if (error != null) {
      DaakiaVcSentryService.captureException(
        error,
        stackTrace: stackTrace,
        context: attributes,
      );
    } else {
      DaakiaVcSentryService.captureMessage(
        message,
        level: SentryLevel.error,
        context: attributes,
      );
    }
  }

  /// Captures a raw exception with stack trace — Sentry only.
  /// Datadog is not involved; crash/exception capture is Sentry's domain.
  static void captureException(
    dynamic throwable, {
    dynamic stackTrace,
    Map<String, Object?>? context,
  }) {
    DaakiaVcSentryService.captureException(
      throwable,
      stackTrace: stackTrace,
      context: context,
    );
  }
}
