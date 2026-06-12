import 'package:daakia_vc_flutter_sdk/presentation/widgets/attachment_picker_sheet.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/message_bubble.dart';
import 'package:daakia_vc_flutter_sdk/utils/utils.dart';
import 'package:flutter/material.dart';

import '../../events/rtc_events.dart';
import '../../utils/constants.dart';
import '../../viewmodel/rtc_viewmodel.dart';
import '../widgets/edit_preview_widget.dart';
import '../widgets/pinned_message_widget.dart';
import '../widgets/reply_preview_widget.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({required this.viewModel, super.key});

  final RtcViewmodel viewModel;

  @override
  State<StatefulWidget> createState() {
    return _ChatState();
  }
}

class _ChatState extends State<ChatPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.viewModel.isChatOpen = true;
      widget.viewModel.resetUnreadCount();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  final TextEditingController messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  String? _highlightedMessageId;

  @override
  Widget build(BuildContext context) {
    collectLobbyEvents(widget.viewModel, context);
    return PopScope(
      onPopInvokedWithResult: (isPoped, dynamic) async {
        widget.viewModel.isChatOpen = false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        // Use a specific color for no_video_background
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: Column(
            children: [
              if (widget.viewModel.pinnedPublicChat != null)
                PinnedMessageWidget(
                  name: widget.viewModel.pinnedPublicChat?.isSender == true
                      ? widget.viewModel.room.localParticipant?.name
                      : widget.viewModel.pinnedPublicChat?.identity?.name,
                  message: widget.viewModel.pinnedPublicChat?.message ?? "",
                  onPinPressed: () {
                    widget.viewModel.pinnedPublicChat = null;
                  },
                  onPinNavigatePressed: () {
                    _scrollToMessageById(widget.viewModel.pinnedPublicChat?.id);
                  },
                ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: widget.viewModel.getMessageList().length,
                  itemBuilder: (context, index) {
                    final reversedIndex =
                        widget.viewModel.getMessageList().length - 1 - index;
                    var message =
                        widget.viewModel.getMessageList()[reversedIndex];
                    return MessageBubble(
                      chat: message,
                      viewModel: widget.viewModel,
                      isHighlighted: _highlightedMessageId == message.id,
                      onNavigate: () {
                        _scrollToMessageById(message.replyMessage?.id);
                      },
                      onEdit: () {
                        final text = message.message ?? "";
                        messageController.text = text;

                        // Wait a frame so the text field updates before selecting
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          messageController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: text.length,
                          );
                          FocusScope.of(context)
                              .requestFocus(FocusNode()); // clear old focus
                          FocusScope.of(context)
                              .requestFocus(_messageFocusNode); // open keyboard
                        });
                      },
                    );
                  },
                ),
              ),
              if (widget.viewModel.publicReplyDraft != null)
                ReplyPreviewWidget(
                  reply: widget.viewModel.publicReplyDraft!,
                  onCancel: () {
                    widget.viewModel.publicReplyDraft = null;
                  },
                ),
              if (widget.viewModel.publicEditDraft != null)
                EditPreviewWidget(
                  originalMessage: widget.viewModel.publicEditDraft!.message,
                  onCancel: () {
                    widget.viewModel.publicEditDraft = null;
                    messageController.clear();
                  },
                ),

              // Message Input Section
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10.0, vertical: 10.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10.0, vertical: 5.0),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    // Adjust the background color as needed
                    borderRadius: BorderRadius.circular(30.0),
                    // Rounded corners
                    border: Border.all(
                        color: Colors.white
                            .withValues(alpha: 0.3)), // Optional border
                  ),
                  child: Row(
                    children: [
                      if (widget.viewModel.meetingDetails.features
                              ?.isConferenceChatAttachmentAllowed() ==
                          true)
                        IconButton(
                          icon: const Icon(Icons.attach_file),
                          color: Colors.white,
                          onPressed: () => AttachmentPickerSheet.show(
                            context: context,
                            viewModel: widget.viewModel,
                            uploadProgress:
                                widget.viewModel.publicMessageProgress,
                            onUpload: (file, onDone) =>
                                widget.viewModel.uploadAttachment(file, onDone),
                          ),
                        ),

                      // Message input field
                      Expanded(
                        child: TextField(
                          controller: messageController,
                          focusNode: _messageFocusNode,
                          maxLength: Constant.maxMessageCharLimit,
                          decoration: const InputDecoration(
                            hintText: "Type here...",
                            hintStyle: TextStyle(color: Colors.white),
                            border: InputBorder.none, // Removes default borders
                            counterText: "",
                          ),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),

                      // Send button
                      IconButton(
                        icon: const Icon(Icons.send),
                        color: Colors.white,
                        onPressed: () {
                          Utils.hideKeyboard(context);
                          if (messageController.text.trim().isEmpty) return;

                          if (widget.viewModel.publicEditDraft != null) {
                            // Edit existing message
                            widget.viewModel.editPublicMessage(
                                messageController.text.trim());
                            widget.viewModel.publicEditDraft = null;
                          } else {
                            // Normal send
                            widget.viewModel.sendPublicMessage(
                                messageController.text.trim());
                          }

                          messageController.clear();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  bool isEventAdded = false;

  void collectLobbyEvents(RtcViewmodel? viewModel, BuildContext context) {
    if (isEventAdded) return;
    isEventAdded = true;
    viewModel?.publicChatEvents.listen((event) {
      if (event is UpdateView) {
        if (mounted) {
          setState(() {});
        }
      }
    });
  }

  /// Scrolls to a specific message by its [messageId] and highlights it temporarily.
  /// Can be used for pinned messages, reply navigation, or any message jump.
  void _scrollToMessageById(String? messageId) {
    if (messageId == null) return;
    final messages = widget.viewModel.getMessageList();
    final index = messages.indexWhere((msg) => msg.id == messageId);

    if (index != -1) {
      final reversedIndex = messages.length - 1 - index;

      setState(() {
        _highlightedMessageId = messageId;
      });

      _scrollController.animateTo(
        reversedIndex * 100.0, // Approximate height per item
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );

      // Remove highlight after a short delay
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _highlightedMessageId = null;
          });
        }
      });
    }
  }
}
