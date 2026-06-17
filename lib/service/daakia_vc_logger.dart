import 'package:sentry_flutter/sentry_flutter.dart';

import 'daakia_vc_datadog_service.dart';
import 'daakia_vc_sentry_service.dart';

/// Unified observability entry point.
///
/// Routes log calls to Datadog and Sentry independently — each service is
/// called only if it has been initialized; an uninitialized service is silently
/// skipped without affecting the other.
class DaakiaVcLogger {
  DaakiaVcLogger._();

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

  /// Logs an error to both services.
  ///
  /// If [error] is provided, Sentry receives it as an exception (with a full
  /// stack trace). Otherwise Sentry receives a message at error level.
  static void logError(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    Map<String, Object?>? attributes,
  }) {
    DaakiaVcDatadogService.logError(message, error, stackTrace, attributes);
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

  /// Captures a raw exception in both services without a log-style message.
  static void captureException(
    dynamic throwable, {
    dynamic stackTrace,
    Map<String, Object?>? context,
  }) {
    DaakiaVcDatadogService.logError(
      throwable.toString(),
      throwable,
      stackTrace is StackTrace ? stackTrace : null,
      context,
    );
    DaakiaVcSentryService.captureException(
      throwable,
      stackTrace: stackTrace,
      context: context,
    );
  }
}
