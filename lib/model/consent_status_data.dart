import '../utils/json_parser.dart';

class ConsentStatusData {
  bool? canStartRecording = false;

  ConsentStatusData({this.canStartRecording});

  ConsentStatusData.fromJson(Map<String, dynamic> json) {
    canStartRecording = JsonParser.toBool(json['can_start_recording']);
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['can_start_recording'] = canStartRecording;
    return data;
  }
}