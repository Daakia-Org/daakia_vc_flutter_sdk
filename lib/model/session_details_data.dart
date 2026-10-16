import '../utils/json_parser.dart';

class SessionDetailsData {
  int? id;
  int? recordingConsentActive;

  SessionDetailsData({this.id, this.recordingConsentActive});

  SessionDetailsData.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    recordingConsentActive = JsonParser.toFlagInt(json['recording_consent_active']);
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['recording_consent_active'] = recordingConsentActive;
    return data;
  }
}
