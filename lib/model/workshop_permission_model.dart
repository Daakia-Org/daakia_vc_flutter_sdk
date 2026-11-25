import '../utils/json_parser.dart';

class WorkshopPermissionModel {
  bool? isUpdated;
  bool? videoPermission;
  bool? audioPermission;

  WorkshopPermissionModel({this.isUpdated, this.videoPermission, this.audioPermission});

  factory WorkshopPermissionModel.fromJson(Map<String, dynamic> json) {
    return WorkshopPermissionModel(
      isUpdated: JsonParser.toBool(json['updated']),
      videoPermission: JsonParser.toBool(json['is_video_enabled']),
      audioPermission: JsonParser.toBool(json['is_mic_enabled']),
    );
  }

  Map<String, dynamic> toJson() => {
    if (isUpdated != null) 'updated': isUpdated,
    if (videoPermission != null) 'is_video_enabled': videoPermission,
    if (audioPermission != null) 'is_mic_enabled': audioPermission,
  };
}