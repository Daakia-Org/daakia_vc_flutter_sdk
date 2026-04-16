import 'package:daakia_vc_flutter_sdk/model/subscription_feature.dart';

/// @nodoc
class VCConfig {
  final String? hostToken;
  final bool? isCoHost;
  final SubscriptionFeature? subscriptionFeature;

  const VCConfig({this.hostToken, this.isCoHost, this.subscriptionFeature});
}
