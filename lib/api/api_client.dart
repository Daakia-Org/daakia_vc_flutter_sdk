import 'dart:io';

import 'package:daakia_vc_flutter_sdk/model/chat_attachment_consent_model.dart';
import 'package:daakia_vc_flutter_sdk/model/consent_status_data.dart';
import 'package:daakia_vc_flutter_sdk/model/egress_data.dart';
import 'package:daakia_vc_flutter_sdk/model/feature_data.dart';
import 'package:daakia_vc_flutter_sdk/model/licence_verify_model.dart';
import 'package:daakia_vc_flutter_sdk/model/participant_attendance_data.dart';
import 'package:daakia_vc_flutter_sdk/model/screen_share_consent_model.dart';
import 'package:daakia_vc_flutter_sdk/model/session_details_data.dart';
import 'package:daakia_vc_flutter_sdk/model/translation_data.dart';
import 'package:daakia_vc_flutter_sdk/model/webinar_permission_model.dart';
import 'package:daakia_vc_flutter_sdk/model/participant_drawer_consent_model.dart';
import 'package:daakia_vc_flutter_sdk/model/workshop_permission_model.dart';
import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../model/agent_dispatch_data.dart';
import '../model/base_list_response.dart';
import '../model/base_response.dart';
import '../model/event_password_protected_data.dart';
import '../model/host_token_model.dart';
import '../model/meeting_details_model.dart';
import '../model/recording_dispatch_data.dart';
import '../model/remote_participant_consent_model.dart';
import '../model/rtc_data.dart';
import '../model/upload_data.dart';
import '../model/white_board_data.dart';

part 'api_client.g.dart';

@RestApi()
abstract class RestClient {
  factory RestClient(Dio dio, {String? baseUrl}) = _RestClient;

  //-------------------[PRE-JOIN]-------------------

  @POST("rtc/meeting/join")
  Future<BaseResponse<RtcData>> getMeetingJoinDetail(
    @Header("Authorization") String token,
    @Body() Map<String, dynamic> body,
  );

  @POST("meeting/verifyHost")
  Future<BaseResponse<HostTokenModel>> verifyHostToken(
    @Body() Map<String, dynamic> body,
  );

  @GET("saas/host/token")
  Future<BaseResponse<HostTokenModel>> getHostToken(
    @Query("meeting_uid") String meetingUid,
  );

  @GET("saas/meeting/features")
  Future<BaseResponse<FeatureData>> getFeatures(
      @Query("meeting_uid") String meetingUid);

  @POST("rtc/meeting/verify/commonPassword")
  Future<BaseResponse<EventPasswordProtectedData>> verifyCommonMeetingPassword(
    @Body() Map<String, dynamic> body,
  );

  @POST("meeting/verify/password")
  Future<BaseResponse<EventPasswordProtectedData>> verifyMeetingPassword(
    @Body() Map<String, dynamic> body,
  );

  @POST("rtc/meeting/addParticipant/toLobby")
  Future<BaseResponse<RtcData>> addParticipantToLobby(
    @Body() Map<String, dynamic> body,
  );

  @POST("saas/sdk/verify/key")
  Future<BaseResponse<LicenceVerifyModel>> licenceVerify(
    @Body() Map<String, dynamic> body,
  );

  @GET("saas/sdk/meeting/basic/detail")
  Future<BaseResponse<MeetingDetailsModel>> getMeetingDetails(
      @Query("meeting_uid") String meetingUid, @Header("secret") String secret);

  //-------------------[RTC]-------------------

  @POST("rtc/meeting/delete")
  Future<BaseResponse> endMeeting(
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @POST("rtc/meeting/remove/participant")
  Future<BaseResponse> removeParticipant(
    @Header("Authorization") String token,
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @POST("rtc/meeting/create/cohost")
  Future<BaseResponse> makeCoHost(
    @Header("Authorization") String token,
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @POST("rtc/meeting/recording/start")
  Future<BaseResponse<EgressData>> startRecording(
    @Header("Authorization") String token,
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @POST("rtc/meeting/recording/stop")
  Future<BaseResponse> stopRecording(
    @Header("Authorization") String token,
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @Deprecated("No longer needed the dispatch id")
  @GET("rtc/recording/dispatchId")
  Future<BaseResponse<RecordingDispatchData>> getRecordingDispatchedId(
      @Header("Authorization") String token,
      @Header("x-self-identity") String selfIdentity,
      @Query("meeting_id") String meetingUid);

  @PUT("rtc/meeting/update/participantLobbyStatus")
  Future<BaseResponse<RtcData>> acceptParticipantInLobby(
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @POST("rtc/meeting/chat/uploadAttachment")
  @MultiPart()
  Future<BaseResponse<UploadData>> uploadFile(@Part() File file,
      {@SendProgress() ProgressCallback? onSendProgress});

  @Deprecated("This API is no longer supported.")
  @POST("rtc/meeting/update/transcriptionLanguage")
  Future<BaseResponse> setTranscriptionLanguage(
    @Header("Authorization") String token,
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @PUT("rtc/meeting/update/participantLanguage")
  Future<BaseResponse> updateTranscriptionLanguage(
    @Header("Authorization") String token,
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @Deprecated("This API is no longer supported. Please use dispatchAgent instead.")
  @POST("rtc/meeting/transcription/start")
  Future<BaseResponse> startTranscription(
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @POST("rtc/meeting/dispatch/agent")
  Future<BaseResponse<AgentDispatchData>> dispatchAgent(
    @Header("Authorization") String token,
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @POST("rtc/meeting/text/translation")
  Future<BaseResponse<TranslationData>> translateText(
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @POST("rtc/meeting/transcription/stop")
  Future<BaseResponse> stopTranscription(
    @Header("Authorization") String token,
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @POST("rtc/meeting/updateParticipant/name")
  Future<BaseResponse> updateParticipantName(
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @POST("rtc/meeting/time/extend")
  Future<BaseResponse> meetingTimeExtend(
    @Header("Authorization") String token,
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @GET("rtc/meeting/whiteboard/get")
  Future<BaseListResponse<WhiteboardData>> getWhiteBoardData(
    @Header("x-self-identity") String selfIdentity,
    @Query("meeting_id") String meetingId,
  );

  @GET("rtc/meeting/invitee/participantsList")
  Future<BaseListResponse<ParticipantAttendanceData>>
      getAttendanceListForParticipant(
    @Header("x-self-identity") String selfIdentity,
    @Query("meeting_uid") String meetingId,
  );

  @PUT("rtc/meeting/updateRecording/consentStatus")
  Future<BaseResponse<ConsentStatusData>> updateRecordingConsent(
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @GET("rtc/meeting/session/detail")
  Future<BaseResponse<SessionDetailsData>> getSessionDetails(
    @Header("x-self-identity") String selfIdentity,
    @Query("meeting_uid") String meetingId,
  );

  @POST("rtc/meeting/startRecording/consent")
  Future<BaseResponse> startRecordingConsent(
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @GET("rtc/meeting/participant/consentList")
  Future<BaseListResponse<RemoteParticipantConsent>> getParticipantConsentList(
    @Header("x-self-identity") String selfIdentity,
    @Query("meeting_uid") String meetingId,
    @Query("session_id") String sessionId,
  );

  @GET("rtc/screenShareConsent")
  Future<BaseResponse<ScreenShareConsentModel>> getScreenShareConsent(
    @Header("x-self-identity") String selfIdentity,
    @Query("meeting_id") String meetingId,
  );

  @PUT("rtc/screenShareConsent")
  Future<BaseResponse<ScreenShareConsentModel>> updateScreenShareConsent(
    @Header("Authorization") String token,
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @GET("rtc/chatAttachmentDownloadConsent")
  Future<BaseResponse<ChatAttachmentConsentModel>> getChatAttachmentConsent(
    @Header("x-self-identity") String selfIdentity,
    @Query("meeting_id") String meetingId,
  );

  @PUT("rtc/chatAttachmentDownloadConsent")
  Future<BaseResponse<ChatAttachmentConsentModel>> updateChatAttachmentConsent(
    @Header("Authorization") String token,
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @GET("rtc/audioPermission")
  Future<BaseResponse<WebinarPermissionModel>> getAudioPermission(
    @Header("x-self-identity") String selfIdentity,
    @Query("meeting_id") String meetingId,
  );

  @PUT("rtc/audioPermission")
  Future<BaseResponse<WebinarPermissionModel>> updateAudioPermission(
    @Header("Authorization") String token,
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @GET("rtc/videoPermission")
  Future<BaseResponse<WebinarPermissionModel>> getVideoPermission(
    @Header("x-self-identity") String selfIdentity,
    @Query("meeting_id") String meetingId,
  );

  @PUT("rtc/videoPermission")
  Future<BaseResponse<WebinarPermissionModel>> updateVideoPermission(
    @Header("Authorization") String token,
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @PUT("rtc/meeting/update/participantMicPermission")
  Future<BaseResponse<WorkshopPermissionModel>> updateWorkshopMicPermission(
    @Header("Authorization") String token,
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @PUT("rtc/meeting/update/participantVideoPermission")
  Future<BaseResponse<WorkshopPermissionModel>> updateWorkshopVideoPermission(
    @Header("Authorization") String token,
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );

  @GET("rtc/meeting/get/participantDrawer")
  Future<BaseResponse<ParticipantDrawerConsentModel>> getParticipantDrawerConsent(
    @Header("x-self-identity") String selfIdentity,
    @Query("meeting_uid") String meetingUid,
  );

  @PUT("rtc/meeting/allow/participantDrawer")
  Future<BaseResponse<ParticipantDrawerConsentModel>> updateParticipantDrawerConsent(
    @Header("Authorization") String token,
    @Header("x-self-identity") String selfIdentity,
    @Body() Map<String, dynamic> body,
  );
}
