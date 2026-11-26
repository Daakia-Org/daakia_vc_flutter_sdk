import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../model/remote_activity_data.dart';
import '../service/daakia_vc_logger.dart';
import '../viewmodel/rtc_viewmodel.dart';
import 'download_utils.dart';

/// One chat message as written to the file.
class ChatExportEntry {
  final int? timestamp;
  final String sender;
  final bool isEdited;

  /// The quoted message, already shortened, when this one is a reply.
  final ({String sender, String text})? reply;

  /// Set when the message is an uploaded file. [url] is null when the host
  /// does not allow attachment downloads.
  final ({String fileName, String? url})? attachment;

  /// The message text, or an attachment's caption.
  final String text;

  const ChatExportEntry({
    required this.timestamp,
    required this.sender,
    this.isEdited = false,
    this.reply,
    this.attachment,
    this.text = '',
  });
}

class ChatExportConversation {
  final String withName;
  final List<ChatExportEntry> messages;

  const ChatExportConversation(this.withName, this.messages);
}

/// The meeting chat as written to the downloaded file: the public chat and
/// the user's own private conversations, in the same layout as the web app's
/// chat download.
class ChatExport {
  final String meetingTitle;
  final DateTime downloadedAt;
  final List<ChatExportEntry> publicMessages;
  final List<ChatExportConversation> privateConversations;

  const ChatExport({
    required this.meetingTitle,
    required this.downloadedAt,
    required this.publicMessages,
    this.privateConversations = const [],
  });

  static const _quoteMaxLength = 100;
  static const _deletedText = 'Message deleted';
  static const _indent = '    ';
  static final _attachmentExtension = RegExp(
    r'\.(pdf|doc|docx|xls|xlsx|csv|ppt|pptx|txt|odt|ods|jpe?g|png|gif|svg|webp|tiff?|bmp|ico|heic|heif|jfif|pjpeg|pjp|avif)$',
    caseSensitive: false,
  );

  /// Builds the export from what the chat screens hold right now.
  factory ChatExport.fromViewModel(RtcViewmodel viewModel, {DateTime? now}) {
    final local = viewModel.room.localParticipant;
    final basic = viewModel.meetingDetails.meetingBasicDetails;
    final ctx = _Context(
      localIdentity: local?.identity,
      localName: local?.name,
      nameOf: viewModel.getParticipantNameOrNull,
      includeAttachmentLinks: viewModel.isChatAttachmentDownloadEnable,
    );

    final conversations = <ChatExportConversation>[];
    if (viewModel.meetingDetails.features?.isPrivateChatAllowed() == true) {
      for (final chat in viewModel.getPrivateMessage().values) {
        final messages = _entries(chat.chats, ctx, fallbackName: chat.name);
        if (messages.isEmpty) continue;
        final withName = viewModel.getParticipantNameOrNull(chat.identity) ??
            (chat.name.isNotEmpty ? chat.name : chat.identity);
        conversations.add(ChatExportConversation(withName, messages));
      }
    }

    return ChatExport(
      meetingTitle: meetingTitleOf(
          basic?.eventName, basic?.subject, basic?.topic),
      downloadedAt: now ?? DateTime.now(),
      publicMessages: _entries(viewModel.getMessageList(), ctx),
      privateConversations: conversations,
    );
  }

  bool get hasMessages =>
      publicMessages.isNotEmpty || privateConversations.isNotEmpty;

  /// The meeting's name: its event name, then subject or topic (set only for
  /// a personal room or a class).
  static String meetingTitleOf(String? eventName, String? subject,
      String? topic) {
    for (final value in [eventName, subject, topic]) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  /// `meeting_chat_<title>.txt`, keeping letters of any language.
  String get fileName {
    final safeTitle = meetingTitle
        .trim()
        .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}_-]+', unicode: true), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return 'meeting_chat_${safeTitle.isEmpty ? 'meeting' : safeTitle}.txt';
  }

  String toText() {
    final lines = <String>[
      meetingTitle.isEmpty ? 'Meeting Chat' : 'Meeting Chat: $meetingTitle',
      'Downloaded: ${DateFormat('dd-MM-yyyy, hh:mm a').format(downloadedAt)}',
      '',
      ..._heading('ALL CHATS'),
      ...(publicMessages.isEmpty
          ? ['No messages.']
          : _conversationLines(publicMessages)),
    ];
    if (privateConversations.isNotEmpty) {
      lines.addAll(['', ..._heading('PRIVATE MESSAGES')]);
      for (var i = 0; i < privateConversations.length; i++) {
        if (i > 0) lines.add('');
        final conversation = privateConversations[i];
        lines
          ..add('With ${conversation.withName}')
          ..addAll(_conversationLines(conversation.messages));
      }
    }
    return '${lines.join('\n')}\n';
  }

  /// Writes the chat to Downloads. Returns a local copy of the file to open,
  /// or null if it could not be saved.
  Future<String?> save() async {
    try {
      final file = File('${(await getTemporaryDirectory()).path}/$fileName');
      await file.writeAsString(toText(), flush: true);
      final saved = await DownloadUtils.saveToDownloads(
        sourcePath: file.path,
        fileName: fileName,
        mimeType: 'text/plain',
      );
      return saved ? file.path : null;
    } catch (e) {
      DaakiaVcLogger.logWarning('Chat download failed: $e',
          reportToSentry: false);
      return null;
    }
  }

  /// File name and caption of an uploaded attachment message (`<url>` or
  /// `<url> <caption>`), or null for any other message.
  static ({String url, String fileName, String caption})? attachmentOf(
      String? message) {
    if (message == null || !message.startsWith('https://')) return null;
    final firstSpace = message.indexOf(' ');
    final url = firstSpace == -1 ? message : message.substring(0, firstSpace);
    final path = url.split('?').first;
    if (!_attachmentExtension.hasMatch(path)) return null;
    final caption =
        firstSpace == -1 ? '' : message.substring(firstSpace + 1).trim();
    // Uploaded files are stored as `.../<id>-file-<original name>`.
    var fileName =
        path.contains('-file-') ? path.split('-file-').last : path.split('/').last;
    try {
      fileName = Uri.decodeComponent(fileName);
    } catch (_) {
      // Keep the raw name when it is not valid URI encoding.
    }
    return (
      url: url,
      fileName: fileName.isEmpty ? 'attachment' : fileName,
      caption: caption,
    );
  }

  static List<ChatExportEntry> _entries(
      List<RemoteActivityData> messages, _Context ctx,
      {String? fallbackName}) {
    final deletedIds = {
      for (final m in messages)
        if (m.isDeleted && m.id != null) m.id!,
    };
    return [
      for (final m in messages)
        if (!m.isDeleted) _entry(m, ctx, deletedIds, fallbackName),
    ];
  }

  static ChatExportEntry _entry(RemoteActivityData m, _Context ctx,
      Set<String> deletedIds, String? fallbackName) {
    final attachment = attachmentOf(m.message);
    final reply = m.replyMessage;
    return ChatExportEntry(
      timestamp: m.timestamp,
      sender: _senderOf(m, ctx, fallbackName),
      isEdited: m.isEdited,
      reply: reply == null || reply.id.isEmpty && reply.message.isEmpty
          ? null
          : _replyOf(reply.identity, reply.name, reply.message, reply.id, ctx,
              deletedIds),
      attachment: attachment == null
          ? null
          : (
              fileName: attachment.fileName,
              url: ctx.includeAttachmentLinks ? attachment.url : null,
            ),
      text: attachment != null ? attachment.caption : (m.message ?? ''),
    );
  }

  static String _localLabel(String? localName) =>
      localName?.isNotEmpty == true ? '$localName (You)' : 'You';

  /// Same order as the chat screen: the live participant name, the name
  /// saved on the message, then the identity.
  static String _senderOf(
      RemoteActivityData m, _Context ctx, String? fallbackName) {
    final identity = m.identity?.identity ?? m.fromUserId ?? m.userIdentity;
    if (m.isSender ||
        (identity != null && identity == ctx.localIdentity)) {
      return _localLabel(ctx.localName);
    }
    for (final name in [
      ctx.nameOf(identity),
      m.identity?.name,
      m.userName,
      fallbackName,
      identity,
    ]) {
      if (name != null && name.isNotEmpty) return name;
    }
    return 'Unknown';
  }

  static ({String sender, String text}) _replyOf(String identity, String name,
      String message, String id, _Context ctx, Set<String> deletedIds) {
    final sender = identity.isNotEmpty && identity == ctx.localIdentity
        ? _localLabel(ctx.localName)
        : name.isNotEmpty
            ? name
            : ctx.nameOf(identity) ?? 'Agent';
    if (id.isNotEmpty && deletedIds.contains(id)) {
      return (sender: sender, text: _deletedText);
    }
    final attachment = attachmentOf(message);
    final text = attachment == null
        ? message
        : '[File] ${attachment.fileName}'
            '${attachment.caption.isNotEmpty ? ' ${attachment.caption}' : ''}';
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return (
      sender: sender,
      text: oneLine.length > _quoteMaxLength
          ? '${oneLine.substring(0, _quoteMaxLength)}…'
          : oneLine,
    );
  }

  static List<String> _heading(String text) => [text, '-' * text.length];

  static String _date(int? timestamp) => timestamp == null
      ? ''
      : DateFormat('dd MMM yyyy')
          .format(DateTime.fromMillisecondsSinceEpoch(timestamp));

  static String _time(int? timestamp) => timestamp == null
      ? '--:--'
      : DateFormat('hh:mm a')
          .format(DateTime.fromMillisecondsSinceEpoch(timestamp));

  /// A conversation's lines, with a date line whenever the day changes.
  static List<String> _conversationLines(List<ChatExportEntry> messages) {
    final lines = <String>[];
    String? currentDate;
    for (final entry in messages) {
      final date = _date(entry.timestamp);
      if (date != currentDate) {
        if (currentDate != null) lines.add('');
        if (date.isNotEmpty) lines.add(date);
        currentDate = date;
      }
      lines.add('[${_time(entry.timestamp)}] ${entry.sender}'
          '${entry.isEdited ? ' (edited)' : ''}');
      final reply = entry.reply;
      if (reply != null) lines.add('$_indent> ${reply.sender}: ${reply.text}');
      final attachment = entry.attachment;
      if (attachment != null) {
        lines.add(attachment.url != null
            ? '$_indent[File] ${attachment.fileName} (${attachment.url})'
            : '$_indent[File] ${attachment.fileName}');
      }
      if (entry.text.isNotEmpty) {
        for (final line in entry.text.split(RegExp(r'\r?\n'))) {
          lines.add('$_indent$line');
        }
      }
    }
    return lines;
  }
}

class _Context {
  final String? localIdentity;
  final String? localName;
  final String? Function(String? identity) nameOf;
  final bool includeAttachmentLinks;

  const _Context({
    required this.localIdentity,
    required this.localName,
    required this.nameOf,
    required this.includeAttachmentLinks,
  });
}
