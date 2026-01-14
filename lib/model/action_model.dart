import 'package:daakia_vc_flutter_sdk/model/reaction_model.dart';
import 'package:daakia_vc_flutter_sdk/model/transcription_action_model.dart';

import 'consent_participant.dart';

class ActionModel {
  final String? action;
  final String? identity;
  final String? message;
  final String? token;
  final bool? value;
  final TranscriptionActionModel? liveCaptionsData;
  final String? consent;
  final List<ConsentParticipant>? participants;
  final Map<String, dynamic>? user;
  final int? timeStamp;
  final int? timestamp; //specially for edit message
  final String? dispatchId;
  final String? id;
  final String? mode;
  final String? messageId;
  final Reaction? reaction;
  final bool? removeReaction;
  final String? requestBy;
  final String? requestByName;
  final bool? isScreenShareAllowed;
  final List<Map<String, dynamic>>? messages;

  // ✅ ADD NEW FIELD

  ActionModel({
    this.action,
    this.identity,
    this.message,
    this.token,
    this.value,
    this.liveCaptionsData,
    this.consent,
    this.participants,
    this.user,
    this.timeStamp,
    this.timestamp,
    this.dispatchId,
    this.id,
    this.mode,
    this.messageId,
    this.reaction,
    this.removeReaction,
    this.requestBy,
    this.requestByName,
    this.isScreenShareAllowed,
    this.messages,
    // ✅ ADD NEW FIELD
  });

  // Converts ActionModel to JSON
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'action': action,
    };
    if (message != null) {
      data['message'] = message;
    }
    if (token != null) {
      data['token'] = token;
    }
    if (value != null) {
      data['value'] = value;
    }
    if (identity != null) {
      data['identity'] = identity;
    }
    if (liveCaptionsData != null) {
      data['liveCaptionsData'] = liveCaptionsData;
    }
    if (consent != null) {
      data['consent'] = consent;
    }
    if (participants != null) {
      data['participants'] = participants!.map((p) => p.toJson()).toList();
    }
    if (user != null) {
      data['user'] = user;
    }
    if (timeStamp != null) {
      data['timeStamp'] = timeStamp;
    }
    if (timestamp != null) {
      data['timestamp'] = timestamp;
    }
    if (dispatchId != null) {
      data['dispatchId'] = dispatchId;
    }
    if (id != null) {
      data['id'] = id;
    }
    if (mode != null) {
      data['mode'] = mode;
    }
    if (messageId != null) {
      data['messageId'] = messageId;
    }
    if (reaction != null) {
      data['reaction'] = reaction;
    }
    if (removeReaction != null) {
      data['removeReaction'] = removeReaction;
    }
    if (requestBy != null) {
      data['request_by'] = requestBy;
    }
    if (requestByName != null) {
      data['request_by_name'] = requestByName;
    }
    if (isScreenShareAllowed != null) {
      data['is_screen_share_allowed'] = isScreenShareAllowed;
    }
    if (messages != null) {
      data['messages'] = messages;
    }
    // ✅ ADD NEW FIELD
    return data;
  }

  // Creates an ActionModel from JSON
  factory ActionModel.fromJson(Map<String, dynamic> json) {
    return ActionModel(
      action: json['action'] as String?,
      identity: json['identity'] as String?,
      message: json['message'] as String? ?? "",
      token: json['token'] as String? ?? "",
      value: json['value'] as bool? ?? true,
      liveCaptionsData: json['liveCaptionsData'] as TranscriptionActionModel?,
      consent: json['consent'] as String?,
      participants: (json['participants'] as List<dynamic>?)
          ?.map((e) => ConsentParticipant.fromJson(e as Map<String, dynamic>))
          .toList(),
      user: json['user'] as Map<String, dynamic>?,
      timeStamp: json['timeStamp'] as int?,
      timestamp: json['timestamp'] as int?,
      dispatchId: json['dispatchId'] as String? ?? "",
      id: json['id'] as String? ?? "",
      mode: json['mode'] as String? ?? "",
      messageId: json['messageId'] as String?,
      reaction: json['reaction'] != null
          ? Reaction.fromJson(json['reaction'] as Map<String, dynamic>)
          : null,
      removeReaction: json['removeReaction'] as bool? ?? false,
      requestBy: json['request_by'] as String? ?? "",
      requestByName: json['request_by_name'] as String? ?? "",
      isScreenShareAllowed: json['is_screen_share_allowed'] as bool? ?? false,
      messages: json['messages'] as List<Map<String, dynamic>>?,
      // ✅ ADD NEW FIELD
    );
  }
}
