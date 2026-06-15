import 'dart:collection';
import 'dart:io';

import 'package:daakia_vc_flutter_sdk/presentation/screens/web_preview.dart';
import 'package:daakia_vc_flutter_sdk/utils/download_utils.dart';
import 'package:daakia_vc_flutter_sdk/utils/utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' show PreviewData;
import 'package:flutter_link_previewer/flutter_link_previewer.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

class FilePreviewWidget extends StatefulWidget {
  final String fileUrl;
  final bool isChatAttachmentDownloadEnable;
  final bool isSender;
  final bool saveAttachmentToDownloads;

  const FilePreviewWidget({
    super.key,
    required this.fileUrl,
    required this.isChatAttachmentDownloadEnable,
    this.isSender = false,
    this.saveAttachmentToDownloads = false,
  });

  @override
  State<FilePreviewWidget> createState() => _FilePreviewWidgetState();
}

class _FilePreviewWidgetState extends State<FilePreviewWidget> {
  final HashMap<String, PreviewData?> metadata =
      HashMap<String, PreviewData?>();
  double? _progress; // State variable to track download progress

  @override
  void initState() {
    metadata[widget.fileUrl] = null;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final mimeType = Utils.resolveMimeType(widget.fileUrl);
    final fileExtension = widget.fileUrl.split('.').last;

    TextStyle getTextStyle(Color textColor) {
      var style = TextStyle(
        color: textColor,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.375,
      );
      return style;
    }

    Widget buildPreview() {
      if (mimeType != null) {
        if (mimeType.startsWith('image/')) {
          return Image.network(
            widget.fileUrl,
            width: 50,
            height: 50,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return child; // Image is fully loaded
              }
              return Container(
                width: 50,
                height: 50,
                color: Colors.grey[800], // Background color for placeholder
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.0,
                    color: Colors.white,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.broken_image, size: 25, color: Colors.white),
          );
        } else if (mimeType.startsWith('video/')) {
          return const Icon(Icons.video_library,
              size: 25, color: Colors.purple);
        } else if (mimeType.startsWith('audio/')) {
          return const Icon(Icons.audiotrack, size: 25, color: Colors.orange);
        } else if (mimeType.startsWith('application/pdf')) {
          return const Icon(Icons.picture_as_pdf, size: 25, color: Colors.red);
        } else if (mimeType.startsWith('application/vnd') ||
            fileExtension.contains('ppt')) {
          return const Icon(Icons.slideshow, size: 25, color: Colors.orange);
        } else if (mimeType.startsWith('application/msword') ||
            mimeType.startsWith(
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document')) {
          return const Icon(Icons.description, size: 25, color: Colors.blue);
        } else if (mimeType
            .startsWith('application/vnd.android.package-archive')) {
          return const Icon(Icons.android, size: 25, color: Colors.green);
        } else if (mimeType.startsWith('application/')) {
          return const Icon(Icons.insert_drive_file,
              size: 25, color: Colors.white);
        } else {
          return const Icon(Icons.question_mark_rounded,
              size: 25, color: Colors.white);
        }
      }

      return LinkPreview(
        linkStyle: getTextStyle(Colors.lightBlueAccent),
        textStyle: getTextStyle(Colors.white),
        metadataTitleStyle: getTextStyle(CupertinoColors.white),
        metadataTextStyle: getTextStyle(CupertinoColors.white),
        enableAnimation: true,
        onPreviewDataFetched: (data) {
          setState(() {
            metadata[widget.fileUrl] = data;
          });
        },
        previewData: metadata[widget.fileUrl],
        text: widget.fileUrl,
        width: MediaQuery.of(context).size.width,
      );
    }

    return GestureDetector(
      onTap: () async {
        if (mimeType == null) {
          if (!isValidUri(widget.fileUrl)) {
            Utils.showSnackBar(context, message: "Invalid URL");
            return;
          }
          await Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => WebPreview(url: widget.fileUrl)),
          );
        } else {
          final fileName = Uri.decodeFull(widget.fileUrl.split('/').last);
          final filePath = await _resolveFilePath(fileName);

          if (File(filePath).existsSync()) {
            try {
              final result = await OpenFile.open(filePath);
              if (kDebugMode) {
                print(
                    "OpenFile result: ${result.type}, message: ${result.message}");
              }
            } catch (e) {
              if (context.mounted) {
                Utils.showSnackBar(context, message: "Error opening file: $e");
              }
            }
          } else {
            if(!widget.isChatAttachmentDownloadEnable) return;
            setState(() => _progress = 0.0);

            await _downloadFile(widget.fileUrl, filePath);

            setState(() => _progress = null);

            if (widget.saveAttachmentToDownloads && !widget.isSender) {
              await DownloadUtils.saveToDownloads(
                sourcePath: filePath,
                fileName: fileName,
                mimeType: mimeType,
              );
            }

            try {
              final result = await OpenFile.open(filePath);
              if (kDebugMode) {
                print(
                    "OpenFile result: ${result.type}, message: ${result.message}");
              }
            } catch (e) {
              if (context.mounted) {
                Utils.showSnackBar(context, message: "Error opening file: $e");
              }
            }
          }
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (mimeType != null)
                FittedBox(
                  child: buildPreview(),
                ),
              if (mimeType == null)
                Flexible(
                  flex: 2, // Adjust flex value to control the width ratio
                  child: buildPreview(),
                ),
              const SizedBox(width: 10),
              if (mimeType != null)
                Expanded(
                  child: Text(
                    Utils.extractFileName(widget.fileUrl), // File name from URL
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis, // Truncate if too long
                    maxLines: 2,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_progress != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                // Make the corners rounded
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 5,
                  color: CupertinoColors.systemGreen,
                  backgroundColor: Colors.grey,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<String> _resolveFilePath(String fileName) async {
    final tempDir = await getTemporaryDirectory();
    return '${tempDir.path}/$fileName';
  }

  Future<void> _downloadFile(String url, String filePath) async {
    await Dio().download(
      url,
      filePath,
      onReceiveProgress: (received, total) {
        if (total != -1) {
          setState(() {
            _progress = received / total;
          });
        }
      },
    );
  }

  bool isValidUri(String uri) {
    try {
      final parsedUri = Uri.parse(uri);
      return parsedUri.hasScheme && parsedUri.isAbsolute;
    } catch (e) {
      return false;
    }
  }
}
