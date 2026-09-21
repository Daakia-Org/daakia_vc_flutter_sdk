class HostControlsData {
  final bool annotationAllowed;
  final bool audioPermission;
  final bool autoMeetingEnd;
  final bool chatAttachmentDownloadEnabled;
  final bool notificationSoundEnabled;
  final bool participantDrawer;
  final bool screenSharePermissionGranted;
  final bool videoPermission;
  final bool whiteboardCollaborationEnabled;
  final bool isRecordingActive;

  const HostControlsData({
    required this.annotationAllowed,
    required this.audioPermission,
    required this.autoMeetingEnd,
    required this.chatAttachmentDownloadEnabled,
    required this.notificationSoundEnabled,
    required this.participantDrawer,
    required this.screenSharePermissionGranted,
    required this.videoPermission,
    required this.whiteboardCollaborationEnabled,
    required this.isRecordingActive,
  });

  factory HostControlsData.fromJson(Map<String, dynamic> json) {
    bool parseBool(String key, {bool fallback = false}) {
      final v = json[key];
      if (v is bool) return v;
      if (v is int) return v == 1;
      return fallback;
    }

    return HostControlsData(
      annotationAllowed: parseBool('annotation_allowed'),
      audioPermission: parseBool('audio_permission'),
      autoMeetingEnd: parseBool('auto_meeting_end'),
      chatAttachmentDownloadEnabled: parseBool('chat_attachment_download_enabled'),
      // Defaults on: a backend that predates this field shouldn't silently
      // leave hosts without the end-of-meeting warning sound.
      notificationSoundEnabled: parseBool('notification_sound_enabled', fallback: true),
      participantDrawer: parseBool('participant_drawer'),
      screenSharePermissionGranted: parseBool('screen_share_permission_granted', fallback: true),
      videoPermission: parseBool('video_permission'),
      whiteboardCollaborationEnabled: parseBool('whiteboard_collaboration_enabled'),
      isRecordingActive: parseBool('is_recording_active'),
    );
  }
}
