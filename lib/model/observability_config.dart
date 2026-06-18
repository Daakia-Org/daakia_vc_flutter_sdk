import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';

class DatadogObsConfig {
  final String clientToken;
  final String env;
  final String serviceName;
  final String applicationId;
  final String? version;
  final DatadogSite site;

  const DatadogObsConfig({
    required this.clientToken,
    required this.env,
    required this.serviceName,
    required this.applicationId,
    this.version,
    this.site = DatadogSite.us3,
  });
}

class SentryObsConfig {
  final String dsn;

  const SentryObsConfig({required this.dsn});
}
