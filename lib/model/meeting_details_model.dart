import '../utils/json_parser.dart';

class MeetingDetailsModel {
  String? eventMode;
  String? eventType;
  String? eventName;
  String? startDate;
  String? endDate;
  int? duration;
  int? isStartNow;
  String? topic;
  String? timeZone;
  String? timezoneIdentifier;
  String? subject;
  String? chapter;
  String? subTopic;
  String? host;
  String? roomUid;
  int? conferenceStatusId;
  int? totalMembersCount;
  String? isPassword;
  ConferenceStatus? conferenceStatus;
  bool? isLobbyMode;
  bool? isStandardPassword;
  bool? isCommonPassword;
  TranscriptionDetail? transcriptionDetail;
  MeetingConfig? meetingConfig;
  String? currentSessionUid;
  int? meetingId;
  int? hostPinVerificationRequired;

  MeetingDetailsModel(
      {this.eventMode,
        this.eventType,
        this.eventName,
        this.startDate,
        this.endDate,
        this.duration,
        this.isStartNow,
        this.topic,
        this.timeZone,
        this.timezoneIdentifier,
        this.subject,
        this.chapter,
        this.subTopic,
        this.host,
        this.roomUid,
        this.conferenceStatusId,
        this.totalMembersCount,
        this.isPassword,
        this.conferenceStatus,
        this.isLobbyMode,
        this.isStandardPassword,
        this.isCommonPassword,
        this.transcriptionDetail,
        this.meetingConfig,
        this.currentSessionUid,
        this.meetingId,
        this.hostPinVerificationRequired,
      });

  MeetingDetailsModel.fromJson(Map<String, dynamic> json) {
    eventMode = json['event_mode'];
    eventType = json['event_type'];
    eventName = json['event_name'];
    startDate = json['start_date'];
    endDate = json['end_date'];
    duration = json['duration'];
    isStartNow = JsonParser.toFlagInt(json['is_start_now']);
    topic = json['topic'];
    timeZone = json['time_zone'];
    timezoneIdentifier = json['timezone_identifier'];
    subject = json['subject'];
    chapter = json['chapter'];
    subTopic = json['sub_topic'];
    host = json['host'];
    roomUid = json['room_uid'];
    conferenceStatusId = json['conference_status_id'];
    totalMembersCount = json['total_members_count'];
    isPassword = json['is_password']?.toString();
    conferenceStatus = json['conference_status'] != null
        ? ConferenceStatus.fromJson(json['conference_status'])
        : null;
    isLobbyMode = JsonParser.toBool(json['is_lobby_mode']);
    isStandardPassword = JsonParser.toBool(json['is_standard_password']);
    isCommonPassword = JsonParser.toBool(json['is_common_password']);
    // `?.` matters here: a plain `.toString()` turns a null session into the
    // literal string "null".
    currentSessionUid = json['current_session_uid']?.toString();
    transcriptionDetail = json['transcription_detail'] != null
        ? TranscriptionDetail.fromJson(json['transcription_detail'])
        : null;
    meetingConfig = json['meeting_config'] != null
        ? MeetingConfig.fromJson(json['meeting_config'])
        : null;
    meetingId = json['meeting_id'];
    hostPinVerificationRequired =
        JsonParser.toFlagInt(json['host_pin_verification_required']);
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['event_mode'] = eventMode;
    data['event_type'] = eventType;
    data['event_name'] = eventName;
    data['start_date'] = startDate;
    data['end_date'] = endDate;
    data['duration'] = duration;
    data['is_start_now'] = isStartNow;
    data['topic'] = topic;
    data['time_zone'] = timeZone;
    data['timezone_identifier'] = timezoneIdentifier;
    data['subject'] = subject;
    data['chapter'] = chapter;
    data['sub_topic'] = subTopic;
    data['host'] = host;
    data['room_uid'] = roomUid;
    data['conference_status_id'] = conferenceStatusId;
    data['total_members_count'] = totalMembersCount;
    data['is_password'] = isPassword;
    if (conferenceStatus != null) {
      data['conference_status'] = conferenceStatus!.toJson();
    }
    data['is_lobby_mode'] = isLobbyMode;
    data['is_standard_password'] = isStandardPassword;
    data['is_common_password'] = isCommonPassword;
    data['current_session_uid'] = currentSessionUid.toString();
    if (transcriptionDetail != null) {
      data['transcription_detail'] = transcriptionDetail!.toJson();
    }
    if (meetingConfig != null) {
      data['meeting_config'] = meetingConfig!.toJson();
    }
    data['meeting_id'] = meetingId;
    data['host_pin_verification_required'] = hostPinVerificationRequired;
    return data;
  }
}

class ConferenceStatus {
  String? title;

  ConferenceStatus({title});

  ConferenceStatus.fromJson(Map<String, dynamic> json) {
    title = json['title'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['title'] = title;
    return data;
  }
}

class TranscriptionDetail {
  bool? transcriptionEnable;
  String? transcriptionLangIso;
  String? transcriptionLangTitle;

  TranscriptionDetail({transcriptionEnable, transcriptionLangIso, transcriptionLangTitle});

  TranscriptionDetail.fromJson(Map<String, dynamic> json) {
    transcriptionEnable = JsonParser.toBool(json['transcription_enable']);
    transcriptionLangIso = json['transcription_lang_iso'];
    transcriptionLangTitle = json['transcription_lang_title'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['transcription_enable'] = transcriptionEnable;
    data['transcription_lang_iso'] = transcriptionLangIso;
    data['transcription_lang_title'] = transcriptionLangTitle;
    return data;
  }
}

class MeetingConfig {
  int? autoStartRecording;
  int? recordingForceStopped;
  int? autoMeetingEnd;
  String? autoMeetingEndSchedule;
  String? autoMeetingEndScheduleTimezoneFormated;
  int? isGuestMode;
  int? inactivePromptEnabled;
  int? inactiveTimeoutMinutes;

  MeetingConfig({autoStartRecording, recordingForceStopped, autoMeetingEnd, autoMeetingEndSchedule, autoMeetingEndScheduleTimezoneFormated, this.isGuestMode, this.inactivePromptEnabled, this.inactiveTimeoutMinutes});

  MeetingConfig.fromJson(Map<String, dynamic> json) {
    inactivePromptEnabled = JsonParser.toFlagInt(json['inactive_prompt_enabled']);
    inactiveTimeoutMinutes = JsonParser.toFlagInt(json['inactive_timeout_minutes']);
    autoStartRecording = JsonParser.toFlagInt(json['auto_start_recording']);
    recordingForceStopped = JsonParser.toFlagInt(json['recording_force_stopped']);
    autoMeetingEnd = JsonParser.toFlagInt(json['auto_meeting_end']);
    autoMeetingEndSchedule = json['auto_meeting_end_schedule'];
    autoMeetingEndScheduleTimezoneFormated = json['auto_meeting_end_schedule_timezone_formated'];
    isGuestMode = JsonParser.toFlagInt(json['is_guest_mode']);
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['auto_start_recording'] = autoStartRecording;
    data['recording_force_stopped'] = recordingForceStopped;
    data['auto_meeting_end'] = autoMeetingEnd;
    data['auto_meeting_end_schedule'] = autoMeetingEndSchedule;
    data['auto_meeting_end_schedule_timezone_formated'] = autoMeetingEndScheduleTimezoneFormated;
    data['is_guest_mode'] = isGuestMode;
    data['inactive_prompt_enabled'] = inactivePromptEnabled;
    data['inactive_timeout_minutes'] = inactiveTimeoutMinutes;
    return data;
  }
}