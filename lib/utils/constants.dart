import 'dart:io';

class Constant {
  static const String sdkVersion = '4.5.1';

  static final String platform = getPlatform();

  static String baseUrl = "https://api.daakia.co.in/v2.0/";
  static String whiteboardDomain = "https://www.daakia.co.in/";

  static const String startRecordingUrl = "https://cdn.vc.daakia.co.in/sounds/recording_start.mp3";
  static const String stopRecordingUrl = "https://cdn.vc.daakia.co.in/sounds/recording_stop.mp3";

  static const String meetingUid = "MEETING_UID";
  static const String sessionUid = "SESSION_UID";
  static const String attendanceId = "ATTENDANCE_ID";
  static const String attendanceRole = "ATTENDANCE_ROLE";
  static const String hostToken = "HOST_TOKEN";
  static const String guestUserName = "GUEST_USER_NAME";

  static const String liveCaptionAgentId = "captions-agent";
  static const String liveCaptionAgentName = "Live Captions";
  static const String liveCaptionAgent = "lk.transcription";
  static const String captionAgentFinalTranscript = "final_transcript";
  static const String captionAgentInterimTranscript = "interim_transcript";

  static const int meetingExtendTime = 10;
  static const int meetingEndSoonTime = 10;

  static const int maxMessageSize = 16384; // 16 KB limit

  static const int maxMessageCharLimit = 512;

  static const int imageMaxSize = 15;
  static const int documentMaxSize = 15;
  static const int audioMaxSize = 15;
  static const int videoMaxSize = 15;


  static const int successResCheckValue = 1;

  static String getPlatform() {
    if (Platform.isAndroid) {
      return "android";
    } else if (Platform.isIOS) {
      return "ios";
    } else {
      return "unknown";
    }
  }

  static List<String>? allowedExtensions(){
    //TODO:: Need to add AMR Audio file in future
    return [
      // Allowed extensions for each media type
      'mp3', 'aac', 'mpeg', 'ogg', // Audio
      'txt', 'pdf', 'ppt', 'doc', 'xls', 'docx', 'pptx', 'xlsx', // Documents
      'jpg', 'jpeg', 'png', 'webp', // Images
      // 'mp4', '3gp', // Videos
    ];
  }

  static List<String> documentFileTypes() {
    return [
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document', // Word
      'application/vnd.openxmlformats-officedocument.presentationml.presentation', // PowerPoint
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', // Excel
      'application/vnd.ms-excel', // Older Excel format
      'application/msword', // Older Word format
      'application/vnd.ms-powerpoint', // Older PowerPoint format
      'application/pdf', // PDF
      'text/' // Text files
    ];
  }
}
