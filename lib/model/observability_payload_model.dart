class ObservabilityPayloadModel {
  final String? payload;

  ObservabilityPayloadModel({this.payload});

  ObservabilityPayloadModel.fromJson(Map<String, dynamic> json)
      : payload = json['payload'] as String?;

  Map<String, dynamic> toJson() => {'payload': payload};
}
