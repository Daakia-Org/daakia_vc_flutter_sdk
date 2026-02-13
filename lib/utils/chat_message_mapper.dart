import '../model/remote_activity_data.dart';
import '../model/reply_message.dart';
import '../model/reaction_model.dart';

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
    return RemoteActivityData(
      id: json['id'] as String?,
      message: json['message'] as String?,
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
    );
  }
}
