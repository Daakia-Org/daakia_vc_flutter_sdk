import '../utils/json_parser.dart';

class ChatAttachmentConsentModel {
  bool chatAttachmentDownloadConsent = false;

  ChatAttachmentConsentModel({required this.chatAttachmentDownloadConsent});

  factory ChatAttachmentConsentModel.fromJson(Map<String, dynamic> json) {
    return ChatAttachmentConsentModel(
      chatAttachmentDownloadConsent: JsonParser.toBool(json['chat_attachment_download_consent']) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'chat_attachment_download_consent': chatAttachmentDownloadConsent,
  };
}