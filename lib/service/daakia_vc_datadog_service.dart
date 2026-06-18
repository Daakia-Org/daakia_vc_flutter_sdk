import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';

class DaakiaVcDatadogService {
  static DatadogLogger? _logger;

  static bool get isInitialized => _logger != null;

  static Future<void> initialize({
    required String clientToken,
    required String env,
    required String serviceName,
    required String applicationId,
    required String? version,
    DatadogSite site = DatadogSite.us3,
    bool enableCrashReporting = true,
  }) async {
    if (_logger != null) return;
    final configuration = DatadogConfiguration(
      clientToken: clientToken,
      env: env,
      site: site,
      service: serviceName,
      version: version,
      nativeCrashReportEnabled: enableCrashReporting,
      loggingConfiguration: DatadogLoggingConfiguration(),
      rumConfiguration: DatadogRumConfiguration(
        applicationId: applicationId,
        sessionSamplingRate: 100,
        trackAnonymousUser: true,
      ),
    );

    await DatadogSdk.runApp(configuration, TrackingConsent.granted, () async {});

    _logger = DatadogSdk.instance.logs?.createLogger(
      DatadogLoggerConfiguration(remoteLogThreshold: LogLevel.info),
    );
  }

  // --- Logging Methods ---
  static void logDebug(String message, {Map<String, Object?>? attributes}) {
    _logger?.debug(message, attributes: attributes ?? {});
  }

  static void logInfo(String message, {Map<String, Object?>? attributes}) {
    _logger?.info(message, attributes: attributes ?? {});
  }

  static void logWarning(String message, {Map<String, Object?>? attributes}) {
    _logger?.warn(message, attributes: attributes ?? {});
  }

  static void logError(
      String message, [
        Object? error,
        StackTrace? stackTrace,
        Map<String, Object?>? attributes,
      ]) {
    _logger?.error(
      message,
      errorMessage: error?.toString(),
      errorStackTrace: stackTrace,
      attributes: attributes ?? {},
    );
  }
}
