import '../model/remote_activity_data.dart';
import '../model/reply_message.dart';
import '../model/reaction_model.dart';
import 'json_parser.dart';

class ChatMessageMapper {
  ChatMessageMapper._(); // 🔒 no instance

  /// ------------------------------------------------------------
  /// RemoteActivityData -> API Payload
  /// ------------------------------------------------------------
  static List<Map<String, dynamic>> toApiList(
      List<RemoteActivityData> messages,
      ) {
    return messages.map(toApiJson).toList();
  }

  static Map<String, dynamic> toApiJson(RemoteActivityData msg) {
    return {
      "id": msg.id,
      "message": msg.message,
      "timestamp": msg.timestamp,
      "from": _resolveFrom(msg),
      "isReplied": msg.replyMessage != null,
      "replyMessage": msg.replyMessage?.toJson(),
      "reactions": msg.reactions?.map((e) => e.toJson()).toList() ?? [],
      // Web's keys for these flags. We don't keep the edit time, so the send
      // time stands in; only its presence marks the message as edited.
      if (msg.isEdited) "editTimestamp": msg.timestamp,
      if (msg.isDeleted) "deleted": true,
    };
  }

  static String? _resolveFrom(RemoteActivityData msg) {
    if (msg.identity?.identity.isNotEmpty == true) {
      return msg.identity?.identity;
    }
    if (msg.fromUserId?.isNotEmpty == true) {
      return msg.fromUserId;
    }
    return null;
  }

  /// ------------------------------------------------------------
  /// API Payload -> RemoteActivityData
  /// ------------------------------------------------------------
  static List<RemoteActivityData> fromApiList(
      List<dynamic> json,
      ) {
    return json
        .map((e) => fromApiJson(e as Map<String, dynamic>))
        .toList();
  }

  static RemoteActivityData fromApiJson(
      Map<String, dynamic> json,
      ) {
    // Web marks an edit with `editTimestamp` and a delete with `deleted`, and
    // keeps the original text of a deleted message, so it must not be shown.
    final isDeleted = JsonParser.toBool(json['deleted'] ?? json['isDeleted']) ?? false;
    final isEdited = json['editTimestamp'] != null ||
        (JsonParser.toBool(json['isEdited']) ?? false);
    return RemoteActivityData(
      id: json['id'] as String?,
      message: isDeleted ? "[Message deleted]" : json['message'] as String?,
      timestamp: json['timestamp'] as int?,
      fromUserId: json['from'] as String?,
      participantIdentity: json['from'] as String?,
      replyMessage: json['replyMessage'] != null
          ? ReplyMessage.fromJson(
        json['replyMessage'] as Map<String, dynamic>,
      )
          : null,
      reactions: (json['reactions'] as List<dynamic>?)
          ?.map(
            (e) => Reaction.fromJson(e as Map<String, dynamic>),
      )
          .toList(),
      isEdited: isEdited,
      isDeleted: isDeleted,
    );
  }
}
