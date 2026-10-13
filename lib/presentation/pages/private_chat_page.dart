import 'dart:async';

import 'package:daakia_vc_flutter_sdk/presentation/widgets/attachment_picker_sheet.dart';
import 'package:daakia_vc_flutter_sdk/presentation/widgets/initials_circle.dart';
import 'package:flutter/material.dart';

import '../../events/rtc_events.dart';
import '../../utils/constants.dart';
import '../../utils/utils.dart';
import '../../viewmodel/rtc_viewmodel.dart';
import '../widgets/edit_preview_widget.dart';
import '../widgets/message_bubble.dart';
import '../widgets/pinned_message_widget.dart';
import '../widgets/reply_preview_widget.dart';

class PrivateChatPage extends StatefulWidget {
  const PrivateChatPage(
      {required this.viewModel, this.identity = "", this.name = "", super.key});

  final String identity;
  final String name;
  final RtcViewmodel viewModel;

  @override
  State<StatefulWidget> createState() {
    return PrivateChantState();
  }
}

class PrivateChantState extends State<PrivateChatPage>
    with AutomaticKeepAliveClientMixin {
  // Keep the tab alive so switching chats, which now closes the keyboard,
  // does not throw away a half-typed message.
  @override
  bool get wantKeepAlive => true;

  StreamSubscription? _privateChatSubscription;

  @override
  void dispose() {
    _privateChatSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.viewModel.isPrivateChatOpen = true;
      setState(() {
        if (widget.identity.isEmpty &&
            widget.viewModel.getPrivateMessage().isNotEmpty) {
          var privateMessages =
              widget.viewModel.getPrivateMessage().values.toList();
          var person = privateMessages[0];
          widget.viewModel.setPrivateChatIdentity(person.identity);
          widget.viewModel.setPrivateChatUserName(person.name);
          widget.viewModel.resetUnreadPrivateChatCount(person);
        } else {
          widget.viewModel.setPrivateChatIdentity(widget.identity);
          widget.viewModel.setPrivateChatUserName(widget.name);
          var person = widget.viewModel.getPrivateMessage()[widget.identity];
          if (person == null) return;
          widget.viewModel.resetUnreadPrivateChatCount(person);
        }
      });
    });
  }

  final TextEditingController messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  String? _highlightedMessageId;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    collectLobbyEvents(widget.viewModel, context);
    // Typing in landscape leaves ~150dp above the keyboard: trim padding so
    // the input and some messages stay visible.
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    // Read the keyboard from the view: the Chats scaffold this page sits in
    // strips it from the MediaQuery its body sees, so viewInsets is always 0.
    final isCompact = isLandscape && View.of(context).viewInsets.bottom > 0;
    return PopScope(
      onPopInvokedWithResult: (isPoped, dynamic) async {
        widget.viewModel.isPrivateChatOpen = false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        // Use a specific color for no_video_background
        body: Padding(
          padding: EdgeInsets.symmetric(vertical: isLandscape ? 4.0 : 20.0),
          child: Column(children: [
            Visibility(
                visible: (widget.viewModel.getPrivateMessage().isEmpty),
                child: const Center(
                  child: Text(
                    "No private chat available!",
                    style: TextStyle(
                      color: Colors.white, // Adjust text color
                      fontSize: 16.0, // Adjust font size
                    ),
                  ),
                )),
            Visibility(
              visible: (widget.viewModel.getPrivateMessage().isNotEmpty),
              // Landscape is too short to stack the person picker, the banner
              // and the conversation, so the picker moves to a side column
              // and the banner (the highlighted person says the same) goes.
              child: Expanded(
                child: isLandscape
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 160,
                            child: _buildPersonPicker(Axis.vertical),
                          ),
                          const VerticalDivider(
                              width: 1, color: Colors.white24),
                          Expanded(
                            child: Column(
                              children: _buildConversation(isCompact),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          SizedBox(
                            height: 80.0, // Set a fixed height for the ListView
                            child: _buildPersonPicker(Axis.horizontal),
                          ),
                          Text(
                            "ℹ️ You are in ${widget.viewModel.getPrivateChatUserName()}'s private chat window.",
                            // Using Unicode info symbol
                            style: const TextStyle(
                              color: Colors.white, // Adjust text color
                              fontSize: 16.0, // Adjust font size
                            ),
                          ),
                          ..._buildConversation(isCompact),
                        ],
                      ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// The people this user has a private chat with; tapping one opens it.
  Widget _buildPersonPicker(Axis axis) {
    final people = widget.viewModel.getPrivateMessage().values.toList();
    final isVertical = axis == Axis.vertical;
    return ListView.builder(
      itemCount: people.length,
      scrollDirection: axis,
      itemBuilder: (context, index) {
        final person = people[index];
        final isSelected =
            person.identity == widget.viewModel.getPrivateChatIdentity();
        return Padding(
          padding: isVertical
              ? const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0)
              : const EdgeInsets.symmetric(horizontal: 8.0),
          child: GestureDetector(
            onTap: () {
              setState(() {
                widget.viewModel.setPrivateChatIdentity(person.identity);
                widget.viewModel.setPrivateChatUserName(person.name);
                widget.viewModel.resetUnreadPrivateChatCount(person);
              });
            },
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  InitialsCircle(
                    initials: Utils.getInitials(person.name),
                    isSelected: isSelected,
                    unreadCount: person.unreadCount,
                  ),
                  Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: isSelected
                            ? Colors.deepPurpleAccent
                            : Colors.white),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The open conversation: pinned message, messages, reply/edit previews
  /// and the input.
  List<Widget> _buildConversation(bool isCompact) {
    return [
      // No room for the pinned bar above the keyboard in landscape.
      if (widget.viewModel.pinnedPrivateChat != null && !isCompact)
        PinnedMessageWidget(
          name:
              widget.viewModel.pinnedPrivateChat?.isSender == true
                  ? widget.viewModel.room.localParticipant?.name
                  : widget.viewModel.pinnedPrivateChat?.identity
                      ?.name,
          message:
              widget.viewModel.pinnedPrivateChat?.message ?? "",
          onPinPressed: () {
            widget.viewModel.pinnedPrivateChat = null;
          },
          onPinNavigatePressed: () {
            _scrollToMessageById(
                widget.viewModel.pinnedPrivateChat?.id);
          },
        ),
      Expanded(
        child: ListView.builder(
          controller: _scrollController,
          keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,
          reverse: true,
          itemCount: widget.viewModel
              .getPrivateChatForParticipant(
                  widget.viewModel.getPrivateChatIdentity())
              .length, // Placeholder item count
          itemBuilder: (context, index) {
            final reversedIndex = widget.viewModel
                    .getPrivateChatForParticipant(
                        widget.viewModel.getPrivateChatIdentity())
                    .length -
                1 -
                index;
            var message = widget.viewModel
                .getPrivateChatForParticipant(widget.viewModel
                    .getPrivateChatIdentity())[reversedIndex];
            return MessageBubble(
              chat: message,
              viewModel: widget.viewModel,
              isPrivateChat: true,
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
                  FocusScope.of(context).requestFocus(
                      FocusNode()); // clear old focus
                  FocusScope.of(context).requestFocus(
                      _messageFocusNode); // open keyboard
                });
              },
            );
          },
        ),
      ),
      if (widget.viewModel.privateReplyDraft != null)
        ReplyPreviewWidget(
          reply: widget.viewModel.privateReplyDraft!,
          onCancel: () {
            widget.viewModel.privateReplyDraft = null;
          },
        ),
      if (widget.viewModel.privateEditDraft != null)
        EditPreviewWidget(
          originalMessage:
              widget.viewModel.privateEditDraft!.message,
          onCancel: () {
            widget.viewModel.privateEditDraft = null;
            messageController.clear();
          },
        ),
      // Message Input Section
      Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 10.0, vertical: isCompact ? 4.0 : 10.0),
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
                        widget.viewModel.privateMessageProgress,
                    onUpload: (file, onDone) =>
                        widget.viewModel.uploadPrivateAttachment(
                      widget.viewModel.getPrivateChatIdentity(),
                      widget.viewModel.getPrivateChatUserName(),
                      file,
                      onDone,
                    ),
                  ),
                ),

              // Message input field
              Expanded(
                child: TextField(
                  controller: messageController,
                  focusNode: _messageFocusNode,
                  onTapOutside:
                      Utils.dismissKeyboardOnTapOutside,
                  maxLength: Constant.maxMessageCharLimit,
                  decoration: const InputDecoration(
                    hintText: "Type here...",
                    hintStyle: TextStyle(color: Colors.white),
                    border: InputBorder
                        .none, // Removes default borders
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
                  final messageText =
                      messageController.text.trim();
                  if (messageText.isEmpty) return;

                  if (widget.viewModel.privateEditDraft != null) {
                    // Edit existing private message
                    final identity =
                        widget.viewModel.getPrivateChatIdentity();
                    widget.viewModel.editPrivateMessage(
                        messageText, identity);
                    widget.viewModel.privateEditDraft = null;
                  } else {
                    // Send new message
                    widget.viewModel.sendPrivateMessage(
                      widget.viewModel.getPrivateChatIdentity(),
                      widget.viewModel.getPrivateChatUserName(),
                      messageText,
                    );
                  }

                  messageController.clear();
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    ];
  }

  void collectLobbyEvents(RtcViewmodel? viewModel, BuildContext context) {
    if (_privateChatSubscription != null) return;
    _privateChatSubscription = viewModel?.privateChatEvents.listen((event) {
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
    final messages = widget.viewModel.getPrivateChatForParticipant(
        widget.viewModel.getPrivateChatIdentity());
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
