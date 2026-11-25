import '../utils/json_parser.dart';

class ScreenShareConsentModel {
  bool screenShareConsent = false;

  ScreenShareConsentModel({required this.screenShareConsent});

  factory ScreenShareConsentModel.fromJson(Map<String, dynamic> json) {
    return ScreenShareConsentModel(
      screenShareConsent: JsonParser.toBool(json['screen_share_consent']) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'screen_share_consent': screenShareConsent,
      };
}
