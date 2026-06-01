import 'package:daakia_vc_flutter_sdk/model/feature_configuration.dart';

class Features {
  int? id;
  int? subscriptionId;
  int? isActive;
  String? audioVideoConference;
  String? meetDuration;
  String? cloudStorage;
  int? saveCloud;
  int? internationalPhone;
  int? hostMeetingMobile;
  int? conferenceChat;
  int? whiteboard;
  int? noiseCancellation;
  int? recordMeeting;
  int? poll;
  int? raiseHand;
  int? breakoutRoom;
  int? screenSharing;
  int? voiceTranscription;
  int? voiceTextTranslation;
  int? liveStream;
  int? shareYoutube;
  int? trackAttendance;
  int? muteParticipant;
  int? disableCamera;
  int? compatibility;
  int? mobileSupport;
  int? encryption;
  int? lobby;
  int? protectedMeeting;
  int? spamProtection;
  int? translation;
  int? videoTranslation;
  int? isBasic;
  int? screenSharePermission;
  int? conferenceChatAttachment;
  int? workshopEnabled;
  FeatureConfiguration? configurations;

  Features(
      {this.id,
      this.subscriptionId,
      this.isActive,
      this.audioVideoConference,
      this.meetDuration,
      this.cloudStorage,
      this.saveCloud,
      this.internationalPhone,
      this.hostMeetingMobile,
      this.conferenceChat,
      this.whiteboard,
      this.noiseCancellation,
      this.recordMeeting,
      this.poll,
      this.raiseHand,
      this.breakoutRoom,
      this.screenSharing,
      this.voiceTranscription,
      this.voiceTextTranslation,
      this.liveStream,
      this.shareYoutube,
      this.trackAttendance,
      this.muteParticipant,
      this.disableCamera,
      this.compatibility,
      this.mobileSupport,
      this.encryption,
      this.lobby,
      this.protectedMeeting,
      this.spamProtection,
      this.translation,
      this.videoTranslation,
      this.isBasic,
      this.configurations,
      this.screenSharePermission,
      this.conferenceChatAttachment,
      this.workshopEnabled,
      });

  Features.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    subscriptionId = json['subscription_id'];
    isActive = json['is_active'];
    audioVideoConference = json['audio_video_conference'];
    meetDuration = json['meet_duration'];
    cloudStorage = json['cloud_storage'];
    saveCloud = json['save_cloud'];
    internationalPhone = json['international_phone'];
    hostMeetingMobile = json['host_meeting_mobile'];
    conferenceChat = json['conference_chat'];
    whiteboard = json['whiteboard'];
    noiseCancellation = json['noise_cancellation'];
    recordMeeting = json['record_meeting'];
    poll = json['poll'];
    raiseHand = json['raise_hand'];
    breakoutRoom = json['breakout_room'];
    screenSharing = json['screen_sharing'];
    voiceTranscription = json['voice_transcription'];
    voiceTextTranslation = json['voice_text_translation'];
    liveStream = json['live_stream'];
    shareYoutube = json['share_youtube'];
    trackAttendance = json['track_attendance'];
    muteParticipant = json['mute_participant'];
    disableCamera = json['disable_camera'];
    compatibility = json['compatibility'];
    mobileSupport = json['mobile_support'];
    encryption = json['encryption'];
    lobby = json['lobby'];
    protectedMeeting = json['protected_meeting'];
    spamProtection = json['spam_protection'];
    translation = json['translation'];
    videoTranslation = json['video_translation'];
    isBasic = json['is_basic'];
    screenSharePermission = json['screen_share_permission'];
    conferenceChatAttachment = json['conference_chat_attachment'];
    workshopEnabled = json['workshop_enabled'];

    configurations = json['configurations'] != null
        ? FeatureConfiguration.fromJson(json['configurations'])
        : null;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['id'] = id;
    data['subscription_id'] = subscriptionId;
    data['is_active'] = isActive;
    data['audio_video_conference'] = audioVideoConference;
    data['meet_duration'] = meetDuration;
    data['cloud_storage'] = cloudStorage;
    data['save_cloud'] = saveCloud;
    data['international_phone'] = internationalPhone;
    data['host_meeting_mobile'] = hostMeetingMobile;
    data['conference_chat'] = conferenceChat;
    data['whiteboard'] = whiteboard;
    data['noise_cancellation'] = noiseCancellation;
    data['record_meeting'] = recordMeeting;
    data['poll'] = poll;
    data['raise_hand'] = raiseHand;
    data['breakout_room'] = breakoutRoom;
    data['screen_sharing'] = screenSharing;
    data['voice_transcription'] = voiceTranscription;
    data['voice_text_translation'] = voiceTextTranslation;
    data['live_stream'] = liveStream;
    data['share_youtube'] = shareYoutube;
    data['track_attendance'] = trackAttendance;
    data['mute_participant'] = muteParticipant;
    data['disable_camera'] = disableCamera;
    data['compatibility'] = compatibility;
    data['mobile_support'] = mobileSupport;
    data['encryption'] = encryption;
    data['lobby'] = lobby;
    data['protected_meeting'] = protectedMeeting;
    data['spam_protection'] = spamProtection;
    data['translation'] = translation;
    data['video_translation'] = videoTranslation;
    data['is_basic'] = isBasic;
    data['screen_share_permission'] = screenSharePermission;
    data['conference_chat_attachment'] = conferenceChatAttachment;
    data['workshop_enabled'] = workshopEnabled;

    if (configurations != null) {
      data['configurations'] = configurations!.toJson();
    }

    return data;
  }

  // Getter methods to check feature flags
  bool isChatAllowed() => conferenceChat == 1;

  bool isRecordingAllowed() => recordMeeting == 1;

  bool isRaiseHandAllowed() => raiseHand == 1;

  bool isScreenSharingAllowed() => screenSharing == 1;

  bool isLiveStreamingAllowed() => liveStream == 1;

  bool isMuteParticipantsAllowed() => muteParticipant == 1;

  bool isDisableCameraAllowed() => disableCamera == 1;

  bool isVoiceTranscriptionAllowed() => voiceTranscription == 1;

  bool isVoiceTextTranslationAllowed() => voiceTextTranslation == 1;

  bool isBasicPlan() => isBasic == 1;

  bool isScreenShareRequestAllowed() => screenSharePermission == 1;

  bool isConferenceChatAttachmentAllowed() => conferenceChatAttachment == 1;

  bool isAllowMultipleCoHost() => configurations?.allowMultipleCohost == 1;

  bool isReactionAllowed() => configurations?.enableReaction == 1;

  bool isPublicChatAllowed() => configurations?.enableChat == 1;

  bool isPrivateChatAllowed() => configurations?.enablePrivateChat == 1;

  bool isProfileEditByHostAllowed() => configurations?.allowProfileEditByHost == 1;

  bool isProfileEditBySelfAllowed() => configurations?.allowProfileEditBySelf == 1;

  bool isRecordingConsentAllowed() => configurations?.askRecordingRequest == "all";

  bool isWorkshopEnabled() => workshopEnabled == 1;

}
