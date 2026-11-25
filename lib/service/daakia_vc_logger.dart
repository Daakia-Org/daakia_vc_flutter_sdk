import 'package:sentry_flutter/sentry_flutter.dart';

import '../model/observability_config.dart';
import 'daakia_vc_datadog_service.dart';
import 'daakia_vc_sentry_service.dart';

/// Unified observability entry point.
///
/// Both services are independent — initialize either or both; an uninitialized
/// service is silently skipped without affecting the other.
///
/// ## Routing policy
///
/// Datadog is the firehose: every log level reaches it, including routine
/// lifecycle telemetry (API responses, disconnects, reconnect attempts).
///
/// Sentry is for actionable faults only — crashes, uncaught exceptions and
/// response-parsing failures. Anything expected during a healthy meeting must
/// not reach it, or real issues drown in noise. Concretely:
///
/// - [logDebug] / [logInfo] never reach Sentry.
/// - [logWarning] / [logError] reach Sentry by default; pass
///   `reportToSentry: false` for events that are logged at those levels for
///   Datadog dashboards but are not defects (e.g. reconnect attempts).
/// - [captureException] is Sentry-only.
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
      await DaakiaVcSentryService.initialize(dsn: sentry.dsn);
    }
  }

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  static void logDebug(String message, {Map<String, Object?>? attributes}) {
    DaakiaVcDatadogService.logDebug(message, attributes: attributes);
  }

  /// Datadog only — informational events are never Sentry issues.
  static void logInfo(String message, {Map<String, Object?>? attributes}) {
    DaakiaVcDatadogService.logInfo(message, attributes: attributes);
  }

  static void logWarning(
    String message, {
    Map<String, Object?>? attributes,
    bool reportToSentry = true,
  }) {
    DaakiaVcDatadogService.logWarning(message, attributes: attributes);
    if (!reportToSentry) return;
    DaakiaVcSentryService.captureMessage(
      message,
      level: SentryLevel.warning,
      context: attributes,
    );
  }

  /// Logs an error message to Datadog; Sentry receives it as an exception
  /// (with stack trace) if [error] is provided, or as an error message if not.
  ///
  /// Set [reportToSentry] to false for events that belong at error level in
  /// Datadog but are not defects — they would otherwise bury real issues.
  static void logError(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    Map<String, Object?>? attributes,
    bool reportToSentry = true,
  }) {
    DaakiaVcDatadogService.logError(message, null, null, attributes);
    if (!reportToSentry) return;
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
