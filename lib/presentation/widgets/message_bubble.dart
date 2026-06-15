import 'package:daakia_vc_flutter_sdk/enum/chat_type_enum.dart';
import 'package:daakia_vc_flutter_sdk/model/edit_message.dart';
import 'package:daakia_vc_flutter_sdk/model/remote_activity_data.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/reaction_bar_widget.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/reply_message_widget.dart';
import 'package:daakia_vc_flutter_sdk/viewmodel/rtc_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/utils.dart';
import '../bottom_sheets/message_action_sheet.dart';
import '../bottom_sheets/reaction_details_sheet.dart';
import 'file_preview.dart';

class MessageBubble extends StatefulWidget {
  final RemoteActivityData chat;
  final RtcViewmodel viewModel;
  final bool isPrivateChat;
  final bool isHighlighted;
  final VoidCallback? onNavigate;
  final VoidCallback? onEdit;

  const MessageBubble({
    super.key,
    required this.chat,
    required this.viewModel,
    this.isPrivateChat = false,
    this.isHighlighted = false,
    this.onNavigate,
    this.onEdit,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  @override
  Widget build(BuildContext context) {
    final participant = widget.chat.identity;
    final String userName = participant == null ? widget.viewModel.getParticipantNameByIdentity(widget.chat.fromUserId) : participant.name;
    final String message = widget.chat.message ?? "";
    final String time = Utils.formatTimestampToTime(widget.chat.timestamp);
    final bool isSender = (widget.chat.isSender || widget.chat.fromUserId == widget.viewModel.room.localParticipant?.identity);
    final bool isEdited = widget.chat.isEdited;
    final links = Utils.extractLinks(message);
    final text = Utils.extractTextWithoutLinks(message);
    return Align(
      alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
        child: Column(
          crossAxisAlignment:
              isSender ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Display username for the receiver only
            if (!isSender)
              Text(
                userName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (!isSender) const SizedBox(height: 5.0),

            // Message Card
            GestureDetector(
              onLongPress: () => !widget.chat.isDeleted
                  ? showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      builder: (_) => MessageActionSheet(
                        isMine: isSender,
                        isPinned: Utils.isPinned(
                            widget.chat,
                            widget.isPrivateChat
                                ? widget.viewModel.pinnedPrivateChat
                                : widget.viewModel.pinnedPublicChat),
                        isFile: Utils.isFileLink(widget.chat.message ?? ""),
                        onReply: () {
                          final replyDraft = Utils.getReplyDraft(
                            widget.chat,
                            name: isSender
                                ? widget.viewModel.room.localParticipant?.name
                                : null,
                          );

                          if (widget.isPrivateChat) {
                            widget.viewModel.privateReplyDraft = replyDraft;
                          } else {
                            widget.viewModel.publicReplyDraft = replyDraft;
                          }
                        },
                        onCopy: () {
                          Clipboard.setData(
                            ClipboardData(text: widget.chat.message ?? ""),
                          ).then((_) {
                            widget.viewModel.sendMessageToUI("Copied");
                          });
                        },
                        onEdit: () {
                          final chat = widget.chat;
                          if (widget.isPrivateChat) {
                            widget.viewModel.privateEditDraft = EditMessage(
                                id: chat.id ?? "", message: chat.message ?? "");
                          } else {
                            widget.viewModel.publicEditDraft = EditMessage(
                                id: chat.id ?? "", message: chat.message ?? "");
                          }
                          widget.onEdit?.call();
                        },
                        onDelete: () {
                          final chatType = widget.isPrivateChat
                              ? ChatType.private.name
                              : ChatType.public.name;
                          widget.viewModel.deleteMessage(chatType,
                              widget.chat.id, widget.chat.userIdentity);
                          widget.viewModel
                              .sendDeleteMessageAction(chatType, widget.chat);
                        },
                        onPin: () {
                          if (Utils.isPinned(
                              widget.chat,
                              widget.isPrivateChat
                                  ? widget.viewModel.pinnedPrivateChat
                                  : widget.viewModel.pinnedPublicChat)) {
                            !widget.isPrivateChat
                                ? widget.viewModel.pinnedPublicChat = null
                                : widget.viewModel.pinnedPrivateChat = null;
                          } else {
                            !widget.isPrivateChat
                                ? widget.viewModel.pinnedPublicChat =
                                    widget.chat
                                : widget.viewModel.pinnedPrivateChat =
                                    widget.chat;
                          }
                        },
                        onReact: (emoji) {
                          final chatType = widget.isPrivateChat
                              ? ChatType.private.name
                              : ChatType.public.name;
                          widget.viewModel
                              .addReaction(chatType, emoji, widget.chat);
                        },
                      ),
                    )
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  color: widget.isHighlighted
                      ? Colors.greenAccent
                          .withValues(alpha: 0.3) // 👈 highlight color
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Card(
                  color: isSender
                      ? const Color(0xFF2196F3)
                      : const Color(0xFF303030),
                  // Different colors for sender and receiver
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: 200, minWidth: 100),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10.0, vertical: 5.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ✅ Reply message shown inside the bubble
                          if (widget.chat.replyMessage != null &&
                              !widget.chat.isDeleted)
                            GestureDetector(
                              onTap: widget.onNavigate,
                              child: ReplyMessageWidget(
                                reply: widget.chat.replyMessage!,
                                isSender: isSender,
                              ),
                            ),

                          /// 🔗 Show preview for each link
                          ...links.map(
                            (url) => Center(
                              child: Card(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                color: Colors.transparent,
                                child: FilePreviewWidget(
                                  fileUrl: url,
                                  isChatAttachmentDownloadEnable: widget.viewModel.isChatAttachmentDownloadEnable,
                                  isSender: isSender,
                                  saveAttachmentToDownloads: widget.viewModel.saveAttachmentToDownloads,
                                ),
                              ),
                            ),
                          ),

                          /// 📝 Show remaining text
                          if (text.isNotEmpty)
                            Text(
                              text,
                              style: const TextStyle(color: Colors.white),
                            ),

                          const SizedBox(height: 5.0),

                          // Sent Time
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              isEdited ? "Edited  $time" : time,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if ((widget.chat.reactions ?? []).isNotEmpty &&
                !widget.chat.isDeleted)
              ReactionBarWidget(
                reactions: widget.chat.reactions!,
                onTapReaction: (emojiCode, list) {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: const Color(0xFF1E1E1E),
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    builder: (_) => ReactionDetailsSheet(
                      emojiCode: emojiCode,
                      reactions: list,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
