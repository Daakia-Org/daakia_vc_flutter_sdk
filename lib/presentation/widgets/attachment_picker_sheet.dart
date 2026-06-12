import 'dart:io';

import 'package:daakia_vc_flutter_sdk/presentation/widgets/compact_file_preview.dart';
import 'package:daakia_vc_flutter_sdk/utils/constants.dart';
import 'package:daakia_vc_flutter_sdk/utils/utils.dart';
import 'package:daakia_vc_flutter_sdk/viewmodel/rtc_viewmodel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../events/rtc_events.dart';

typedef AttachmentUploadCallback = void Function(
    File file, VoidCallback onDone);

class AttachmentPickerSheet {
  static void show({
    required BuildContext context,
    required RtcViewmodel viewModel,
    required double uploadProgress,
    required AttachmentUploadCallback onUpload,
  }) {
    Utils.hideKeyboard(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white38,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.attach_file, color: Colors.white),
              title: const Text("Attach File",
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickFile(context, viewModel, uploadProgress, onUpload);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text("Take Photo",
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                _takePhoto(context, viewModel, uploadProgress, onUpload);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static Future<void> _pickFile(
    BuildContext context,
    RtcViewmodel viewModel,
    double uploadProgress,
    AttachmentUploadCallback onUpload,
  ) async {
    try {
      viewModel.sendMainChatControllerEvent(ShowLoading());
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: Constant.allowedExtensions(),
      );
      viewModel.sendMainChatControllerEvent(StopLoading());
      if (result != null) {
        File? file = result.files.single.path != null
            ? File(result.files.single.path!)
            : null;
        final isValid = await Utils.validateFile(file, (error) {
          viewModel.sendMessageToUI(error);
        });
        if (!isValid) return;
        if (file != null) {
          if (!context.mounted) return;
          _showPreviewSheet(context, file, viewModel, uploadProgress, onUpload);
        } else {
          viewModel.sendMessageToUI("File not found!");
        }
      } else {
        viewModel.sendMessageToUI("File not selected!");
      }
    } catch (e) {
      viewModel.sendMessageToUI(e.runtimeType.toString());
    } finally {
      viewModel.sendMainChatControllerEvent(StopLoading());
    }
  }

  static Future<void> _takePhoto(
    BuildContext context,
    RtcViewmodel viewModel,
    double uploadProgress,
    AttachmentUploadCallback onUpload,
  ) async {
    final wasEnabled = await viewModel.pauseCameraForHandoff();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Camera paused for photo capture"),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.black87,
        ),
      );
    }

    try {
      final XFile? photo =
          await ImagePicker().pickImage(source: ImageSource.camera);
      await viewModel.resumeCameraAfterHandoff(wasEnabled);

      if (photo == null) return;

      final file = File(photo.path);
      final isValid = await Utils.validateFile(file, (error) {
        viewModel.sendMessageToUI(error);
      });
      if (!isValid) return;
      if (!context.mounted) return;
      _showPreviewSheet(context, file, viewModel, uploadProgress, onUpload);
    } catch (e) {
      await viewModel.resumeCameraAfterHandoff(wasEnabled);
      viewModel.sendMessageToUI(e.runtimeType.toString());
    }
  }

  static void _showPreviewSheet(
    BuildContext context,
    File file,
    RtcViewmodel viewModel,
    double uploadProgress,
    AttachmentUploadCallback onUpload,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      builder: (previewContext) => Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Selected File",
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            LocalFilePreview(
                file: file, progress: uploadProgress, viewModel: viewModel),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: IconButton(
                    onPressed: () => Navigator.pop(previewContext),
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    tooltip: "Delete",
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: IconButton(
                    onPressed: () =>
                        onUpload(file, () => Navigator.pop(previewContext)),
                    icon: const Icon(Icons.upload, color: Colors.green),
                    tooltip: "Upload",
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
