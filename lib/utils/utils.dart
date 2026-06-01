import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:daakia_vc_flutter_sdk/model/remote_activity_data.dart';
import 'package:daakia_vc_flutter_sdk/model/reply_message.dart';
import 'package:daakia_vc_flutter_sdk/model/saved_data.dart';
import 'package:daakia_vc_flutter_sdk/utils/constants.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:safe_device/safe_device.dart';

import '../model/transcription_model.dart';

FutureOr<void> Function()? onWindowShouldClose;

class Utils {
  Utils._privateConstructor();

  static final Utils _instance = Utils._privateConstructor();

  factory Utils() {
    return _instance;
  }

  static bool isMobileDevice() {
    if (kIsWeb) {
      return false;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return true;
    } else {
      return false;
    }
  }

  static void showSnackBar(BuildContext context,
      {required String message, String? actionText, Function? actionCallBack}) {
    if (!context.mounted) return;
    final snackBar = SnackBar(
      content: Text(message),
      action: actionText != null
          ? SnackBarAction(
              label: actionText,
              onPressed: () {
                actionCallBack?.call();
              },
            )
          : null,
    );

    // Find the ScaffoldMessenger in the widget tree
    // and use it to show a SnackBar.
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  static String getTimeZoneId() {
    return DateTime.now().timeZoneName;
  }

  static String formatTimestampToTime(int? timestamp) {
    if (timestamp == null) {
      return "N/A"; // Return "N/A" if the timestamp is null
    }
    DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    // Format the date to the desired format
    final formatter = DateFormat('hh:mm a'); // 12-hour format
    return formatter.format(date);
  }

  static String getInitials(String? fullName) {
    // Return "U" if the full name is null or empty
    if (fullName == null || fullName.trim().isEmpty) return "U";

    // Split the name into parts, ignoring extra spaces
    List<String> nameParts = fullName
        .trim()
        .split(RegExp(r'\s+')) // handles multiple spaces
        .where((part) => part.isNotEmpty)
        .toList();

    // Take only the first alphabet of the first two words
    String initials = nameParts
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    // Ensure it's restricted to 2 characters max
    return initials.length > 2 ? initials.substring(0, 2) : initials;
  }

  static Color generateUniqueColorFromInitials(String initials) {
    // Convert the initials to a hash code and use modulo to limit the range
    int hash = initials.hashCode.abs();
    double hue =
        (hash % 360).toDouble(); // Map hash to hue angle (0-360 degrees)
    double saturation = 0.7; // Set saturation (0-1)
    double brightness = 0.9; // Set brightness (0-1)

    // Convert HSB (Hue, Saturation, Brightness) to RGB
    return HSVColor.fromAHSV(1.0, hue, saturation, brightness).toColor();
  }

  static int calculateMinutesSince(DateTime? joinedAt) {
    if (joinedAt == null) return 0;
    final currentTime = DateTime.now();
    final difference = currentTime.difference(joinedAt);
    return difference.inMinutes;
  }

  static String getMetadataRole(String? metadata) {
    if (metadata == null) return '';

    try {
      final jsonObject = jsonDecode(metadata);
      return jsonObject['role_name'] ?? '';
    } catch (e) {
      // Handle parsing error, return a default value if needed
      return '';
    }
  }

  static String getMetadataAttendanceId(String? metadata) {
    if (metadata == null) return '';

    try {
      // Parse the JSON string
      final Map<String, dynamic> jsonData = jsonDecode(metadata);
      // Return the `meeting_attendance_id` if it exists, otherwise null
      return jsonData['meeting_attendance_id'].toString();
    } catch (e) {
      // Handle JSON parsing errors
      debugPrint('Error parsing JSON: $e');
      return "";
    }
  }

  static String? getMetadataSessionUid(String? metadata) {
    if (metadata == null || metadata.isEmpty) return null;

    try {
      final Map<String, dynamic> jsonData = jsonDecode(metadata);

      final sessionUid = jsonData['current_session_uid'];

      if (sessionUid == null) return null;

      return sessionUid.toString();
    } catch (e) {
      debugPrint('Error parsing JSON: $e');
      return null;
    }
  }

  static String getParticipantType(String? metadata) {
    String role = getMetadataRole(metadata);

    switch (role) {
      case 'moderator':
        return ' (Host)';
      case 'cohost':
        return ' (Co-Host)';
      default:
        return '';
    }
  }

  static bool isHost(String? metadata) {
    String role = getMetadataRole(metadata);
    return role == 'moderator';
  }

  static bool isCoHost(String? metadata) {
    String role = getMetadataRole(metadata);
    return role == 'cohost';
  }

  static Future<bool> isIosSimulator() async {
    var isRealDevice = await SafeDevice.isRealDevice;
    return isRealDevice;
  }

  static bool isValidEmail(String email) {
    String pattern =
        r'^[a-zA-Z0-9.a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
    RegExp regex = RegExp(pattern);
    return regex.hasMatch(email);
  }

  static Future<String> getAppName() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.appName;
  }

  static bool isUrl(String text) {
    final uri = Uri.tryParse(text.trim());
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  static final _urlRegex = RegExp(
    r'(https?:\/\/[^\s]+)',
    caseSensitive: false,
  );

  static List<String> extractLinks(String text) {
    return _urlRegex.allMatches(text).map((m) => m.group(0)!).toList();
  }

  static String extractTextWithoutLinks(String text) {
    return text.replaceAll(_urlRegex, '').trim();
  }

  // lookupMimeType works purely by extension but misses some JPEG variants.
  static String? resolveMimeType(String url) {
    final mime = lookupMimeType(url);
    if (mime != null) return mime;
    final ext = url.split('?').first.split('.').last.toLowerCase();
    const extraMappings = {'jfif': 'image/jpeg'};
    return extraMappings[ext];
  }

  static bool isFileLink(String url) {
    if (!isUrl(url)) return false;
    return resolveMimeType(url) != null;
  }

  static bool isLink(String message) {
    final linkRegExp = RegExp(
      r'((https?:\/\/)?([\w-]+\.)+[\w-]+(\/[\w- ./?%&=]*)?)',
      caseSensitive: false,
    );

    // Check if there's any match for the link
    final matches = linkRegExp.allMatches(message);
    if (matches.isEmpty) {
      return false; // No link found
    }

    // Check if the message contains only a link
    final onlyLink =
        matches.length == 1 && matches.first.group(0) == message.trim();
    return onlyLink
        ? true
        : true; // Contains a link (either only or mixed with other text)
  }

  static bool isOnlyLink(String message) {
    final linkRegExp = RegExp(
      r'((https?:\/\/)?([\w-]+\.)+[\w-]+(\/[\w\- ./?%&=()*]*)?)',
      caseSensitive: false,
    );

    // Check if the message is just a link
    final matches = linkRegExp.allMatches(message.trim());
    return matches.length == 1 && matches.first.group(0) == message.trim();
  }

  static String? extractFirstUrl(String message) {
    final urlRegExp = RegExp(
      r'((https?:\/\/)?([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})(\/[^\s]*)?)',
      caseSensitive: false,
      multiLine: true,
    );

    final match = urlRegExp.firstMatch(message);
    return match
        ?.group(0); // Returns the first match or null if no match is found
  }

  static String extractNonLinkText(String message) {
    final linkRegExp = RegExp(
      r'((https?:\/\/)?([\w-]+\.)+[\w-]+(\/[\w\- ./?%&=]*)?)',
      caseSensitive: false,
    );

    // Remove all link matches from the message
    final nonLinkText = message.replaceAll(linkRegExp, '').trim();

    return nonLinkText;
  }

  static Future<bool> validateFile(
      File? file, Function(String error) onError) async {
    if (file == null) {
      onError('File is null');
      return false;
    }

    final mimeType = lookupMimeType(file.path);
    final fileSize = await file.length();

    if (mimeType != null) {
      if (mimeType.startsWith('audio/')) {
        if (fileSize <= Constant.audioMaxSize * 1024 * 1024) {
          return true; // Valid audio file
        } else {
          onError("Audio file exceeds the size limit (${Constant.audioMaxSize} MB)");
        }
      }
      if (Constant.documentFileTypes()
          .any((type) => mimeType.startsWith(type))) {
        if (fileSize <= Constant.documentMaxSize * 1024 * 1024) {
          return true; // Valid text file
        } else {
          onError("Document file exceeds the size limit (${Constant.documentMaxSize} MB)");
        }
      } else if (mimeType.startsWith('image/')) {
        if (fileSize <= Constant.imageMaxSize * 1024 * 1024) {
          return true; // Valid image file
        } else {
          onError("Image file exceeds the size limit (${Constant.imageMaxSize} MB)");
        }
      } else if (mimeType.startsWith('video/')) {
        if (fileSize <= Constant.videoMaxSize * 1024 * 1024) {
          return true; // Valid video file
        } else {
          onError("Video file exceeds the size limit (${Constant.videoMaxSize} MB)");
        }
      } else {
        onError("Unsupported file type: $mimeType");
      }
    } else {
      onError('Failed to determine MIME type for "${file.path}"');
    }

    return false; // File is invalid
  }

  static String extractFileName(String url) {
    // Extract the file name from the URL
    final fileName = url.split('/').last;

    // Use a regular expression to find the part after "-file-"
    final match = RegExp(r'-file-(.+)$').firstMatch(fileName);

    // If a match is found, return the matched group; otherwise, return the original file name
    return match != null ? match.group(1)! : fileName;
  }

  static String decodeUnicode(String? input) {
    if (input == null) return "";
    return input.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (match) {
      final hexCode = match.group(1);
      return String.fromCharCode(int.parse(hexCode!, radix: 16));
    });
  }

  @Deprecated(
      'No longer in use. Replaced by getFormattedTranscriptToSave which handles both '
          'caption and translated caption in a unified format. Kept for reference in case '
          'separate original transcript formatting is needed again in the future.'
  )
  static String getTranscriptFormattedToSave(
      List<TranscriptionModel> transcriptions) {
    StringBuffer contentBuffer = StringBuffer();
    for (var entry in transcriptions) {
      if (entry.isFinal) {
        contentBuffer.writeln('${entry.name} ${entry.timestamp}');
        contentBuffer.writeln(entry.transcription);
        contentBuffer.writeln();
        contentBuffer.writeln();
      }
    }
    return contentBuffer.toString();
  }
  @Deprecated(
      'No longer in use. Replaced by getFormattedTranscriptToSave which handles both '
          'caption and translated caption in a unified format. Kept for reference in case '
          'separate translated transcript formatting is needed again in the future.'
  )
  static String getTranslatedTranscriptFormattedToSave(
      List<TranscriptionModel> transcriptions) {
    StringBuffer contentBuffer = StringBuffer();
    for (var entry in transcriptions) {
      if (entry.isFinal) {
        final String textToUse = (entry.translatedTranscription != null &&
                entry.translatedTranscription!.trim().isNotEmpty)
            ? (entry.translatedTranscription ?? "")
            : entry.transcription;

        contentBuffer.writeln('${entry.name} ${entry.timestamp}');
        contentBuffer.writeln(textToUse);
        contentBuffer.writeln();
        contentBuffer.writeln();
      }
    }
    return contentBuffer.toString();
  }

  static String getFormattedTranscriptToSave(
      List<TranscriptionModel> transcriptions) {
    final StringBuffer contentBuffer = StringBuffer();

    for (var entry in transcriptions) {
      if (!entry.isFinal) continue;

      final String caption = entry.transcription.trim();

      final String translatedCaption =
      (entry.translatedTranscription != null &&
          entry.translatedTranscription!.trim().isNotEmpty)
          ? entry.translatedTranscription!.trim()
          : caption;

      contentBuffer.writeln('${entry.name} ${entry.timestamp}');
      contentBuffer.writeln('Caption:');
      contentBuffer.writeln(caption);
      contentBuffer.writeln('Translated Caption:');
      contentBuffer.writeln(translatedCaption);
      contentBuffer.writeln(); // spacing between entries
    }

    return contentBuffer.toString();
  }

  static Future<SavedData> saveDataToFile(String data, String fileName) async {
    try {
      // Request storage permission for Android only
      // if (Platform.isAndroid) {
      //   var status = await Permission.storage.request();
      //   if (!status.isGranted) {
      //     debugPrint('Permission denied.');
      //     return false;
      //   }
      // }
      //TODO:: need to check this permission block for Android 34
      // Get the directory for the Downloads folder (Android) or Documents folder (iOS)
      String downloadsPath = "";
      if (Platform.isAndroid) {
        final PackageInfo packageInfo = await PackageInfo.fromPlatform();
        downloadsPath =
            '/storage/emulated/0/Download/${packageInfo.appName}/transcriptions';
      } else if (Platform.isIOS) {
        final Directory directory = await getApplicationDocumentsDirectory();
        downloadsPath = '${directory.path}/transcriptions';
      }

      // Ensure the directory exists
      Directory downloadsFolder = Directory(downloadsPath);
      if (!await downloadsFolder.exists()) {
        await downloadsFolder.create(recursive: true);
      }

      // Create the file path
      String filePath = '$downloadsPath/$fileName.txt';
      File file = File(filePath);

      // Write the formatted content to the file
      await file.writeAsString(data);
      debugPrint('File saved at $filePath');
      return SavedData(isSuccess: true, filePath: filePath);
    } catch (e) {
      debugPrint('Error saving file: $e');
      return SavedData(isSuccess: false);
    }
  }

  static Future<void> openMediaFile(
      String filePath, BuildContext context) async {
    try {
      final result = await OpenFile.open(filePath);
      if (kDebugMode) {
        print("OpenFile result: ${result.type}, message: ${result.message}");
      }
    } catch (e) {
      if (context.mounted) {
        Utils.showSnackBar(context, message: "Error opening file: $e");
      }
    }
  }

  static bool isMessageSizeValid(String message) {
    final encodedMessage = utf8.encode(jsonEncode(message));
    return encodedMessage.length <= Constant.maxMessageSize;
  }

  static String generateWhiteboardUrl({
    required String meetingId,
    required String livekitToken,
  }) {
    return '${Constant.whiteboardDomain}whiteboard/$meetingId?token=$livekitToken';
  }

  static void hideKeyboard(BuildContext context) {
    FocusScope.of(context).unfocus();
  }

  static String? extractUserAvatar(String? metadata) {
    if (metadata == null || metadata.trim().isEmpty) return null;

    try {
      final Map<String, dynamic> decoded = jsonDecode(metadata);

      // Navigate through the nested keys safely
      if (decoded.containsKey('custom_metadata') &&
          decoded['custom_metadata'] is Map &&
          decoded['custom_metadata']['user_avatar'] is String) {
        final String avatarUrl = decoded['custom_metadata']['user_avatar'];
        return avatarUrl.isNotEmpty ? avatarUrl : null;
      }
    } catch (e) {
      // Invalid JSON — just return null
      return null;
    }

    return null;
  }

  /// Returns the current platform identifier.
  ///
  /// Possible values: `"android"`, `"ios"`, `"macos"`, `"windows"`, `"linux"`, `"web"`.
  /// Web clients (browser) should pass `"web"` or `"mobile_web"` manually via custom metadata.
  static String getClientPlatform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static String? extractClientPlatform(String? metadata) {
    if (metadata == null || metadata.trim().isEmpty) return null;

    try {
      final Map<String, dynamic> decoded = jsonDecode(metadata);
      if (decoded['custom_metadata'] is Map) {
        final platform = decoded['custom_metadata']['client_platform'];
        if (platform is String && platform.isNotEmpty) return platform;
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  static String extractMessage(String prefix, dynamic data, String fallback) {
    if (data is Map<String, dynamic> && data['message'] != null) {
      return "$prefix ${data['message']}";
    }
    return "$prefix $fallback";
  }

  static Future<int> getAndroidVersion() async {
    DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
    final androidInfo = await deviceInfoPlugin.androidInfo;
    return androidInfo.version.sdkInt;
  }

  static bool isPinned(RemoteActivityData? chat, RemoteActivityData? pinnedPublicChat) {
    if (chat == null || pinnedPublicChat == null) return false;
    if (chat.id == pinnedPublicChat.id) return true;
    return false;
  }

  static ReplyMessage? getReplyDraft(RemoteActivityData chat, {String? name}) {
    return ReplyMessage(name: name ?? (chat.identity?.name ?? ""), message: chat.message ?? "", id: chat.id ?? "", identity: chat.userIdentity ?? "");
  }

  static bool isMicEnabled(Map<String, dynamic>? attributes) {
    final value = attributes?['is_mic_enabled'];
    return _toBool(value);
  }

  static bool isVideoEnabled(Map<String, dynamic>? attributes) {
    final value = attributes?['is_video_enabled'];
    return _toBool(value);
  }

  static bool isAnnotationAllowed(Map<String, dynamic>? attributes) {
    final value = attributes?['annotation_allowed'];
    return _toBool(value);
  }

  static bool isMobilePlatform(String? metadata) {
    final platform = extractClientPlatform(metadata);
    if (platform == null) return false;
    return platform == 'android' || platform == 'ios' || platform == 'mobile_web';
  }

  static bool _toBool(dynamic value) {
    if (value == null) return false;

    if (value is bool) return value;

    if (value is String) {
      switch (value.toLowerCase()) {
        case 'true':
        case '1':
        case 'yes':
          return true;
        default:
          return false;
      }
    }

    if (value is num) {
      return value != 0;
    }

    return false;
  }

}
