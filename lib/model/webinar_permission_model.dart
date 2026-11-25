import '../utils/json_parser.dart';

class WebinarPermissionModel {
  bool? videoPermission;
  bool? audioPermission;

  WebinarPermissionModel({this.videoPermission, this.audioPermission});

  factory WebinarPermissionModel.fromJson(Map<String, dynamic> json) {
    return WebinarPermissionModel(
      videoPermission: JsonParser.toBool(json['video_permission']),
      audioPermission: JsonParser.toBool(json['audio_permission']),
    );
  }

  Map<String, dynamic> toJson() => {
    if (videoPermission != null) 'video_permission': videoPermission,
    if (audioPermission != null) 'audio_permission': audioPermission,
  };
}