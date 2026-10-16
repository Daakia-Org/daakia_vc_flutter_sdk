import '../utils/json_parser.dart';

class ParticipantDrawerConsentModel {
  bool isAllowed;

  ParticipantDrawerConsentModel({required this.isAllowed});

  factory ParticipantDrawerConsentModel.fromJson(Map<String, dynamic> json) {
    return ParticipantDrawerConsentModel(
      isAllowed: JsonParser.toBool(json['is_allowed']) ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'is_allowed': isAllowed,
  };
}
