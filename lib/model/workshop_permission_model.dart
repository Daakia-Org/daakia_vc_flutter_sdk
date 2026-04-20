class WorkshopPermissionModel {
  bool? isUpdated;
  bool? videoPermission;
  bool? audioPermission;

  WorkshopPermissionModel({this.isUpdated, this.videoPermission, this.audioPermission});

  factory WorkshopPermissionModel.fromJson(Map<String, dynamic> json) {
    return WorkshopPermissionModel(
      isUpdated: json['updated'] as bool?,
      videoPermission: json['is_video_enabled'] as bool?,
      audioPermission: json['is_mic_enabled'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (isUpdated != null) 'updated': isUpdated,
    if (videoPermission != null) 'is_video_enabled': videoPermission,
    if (audioPermission != null) 'is_mic_enabled': audioPermission,
  };
}