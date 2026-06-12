import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadUtils {
  static const _channel = MethodChannel('io.daakia/meeting_service');

  /// Copies [sourcePath] into the public Downloads folder (Android only).
  /// On API < 29 this requests WRITE_EXTERNAL_STORAGE first; on API 29+
  /// it uses MediaStore.Downloads (no permission needed).
  /// Returns true on success, false if the permission was denied or a
  /// non-fatal error occurred.
  static Future<bool> saveToPublicDownloads({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) async {
    if (!Platform.isAndroid) return false;

    try {
      final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdkInt < 29) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          debugPrint('[DownloadUtils] WRITE_EXTERNAL_STORAGE denied');
          return false;
        }
      }

      debugPrint('[DownloadUtils] saveToPublicDownloads: sourcePath=$sourcePath, fileName=$fileName, mimeType=$mimeType');
      final result = await _channel.invokeMethod<String>('saveFileToDownloads', {
        'sourcePath': sourcePath,
        'fileName': fileName,
        'mimeType': mimeType,
      });
      debugPrint('[DownloadUtils] saved to: $result');
      return true;
    } catch (e) {
      debugPrint('[DownloadUtils] error: $e');
      return false;
    }
  }
}
