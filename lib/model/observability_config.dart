import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';

class DatadogObsConfig {
  final String clientToken;
  final String applicationId;
  final String env;
  final DatadogSite site;

  const DatadogObsConfig({
    required this.clientToken,
    required this.applicationId,
    required this.env,
    this.site = DatadogSite.us3,
  });

  factory DatadogObsConfig.fromJson(Map<String, dynamic> json) {
    return DatadogObsConfig(
      clientToken: json['client_token'] as String,
      applicationId: json['application_id'] as String,
      env: json['env'] as String,
      site: _parseSite(json['site'] as String? ?? 'us3'),
    );
  }

  static DatadogSite _parseSite(String site) {
    switch (site) {
      case 'us1': return DatadogSite.us1;
      case 'us3': return DatadogSite.us3;
      case 'us5': return DatadogSite.us5;
      case 'eu1': return DatadogSite.eu1;
      case 'ap1': return DatadogSite.ap1;
      default:    return DatadogSite.us3;
    }
  }
}

class SentryObsConfig {
  final String dsn;

  const SentryObsConfig({required this.dsn});

  factory SentryObsConfig.fromJson(Map<String, dynamic> json) =>
      SentryObsConfig(dsn: json['dsn'] as String);
}

class ObservabilityConfigModel {
  final DatadogObsConfig? datadog;
  final SentryObsConfig? sentry;

  const ObservabilityConfigModel({this.datadog, this.sentry});

  factory ObservabilityConfigModel.fromJson(Map<String, dynamic> json) {
    return ObservabilityConfigModel(
      datadog: json['datadog'] != null
          ? DatadogObsConfig.fromJson(json['datadog'] as Map<String, dynamic>)
          : null,
      sentry: json['sentry'] != null
          ? SentryObsConfig.fromJson(json['sentry'] as Map<String, dynamic>)
          : null,
    );
  }
}
