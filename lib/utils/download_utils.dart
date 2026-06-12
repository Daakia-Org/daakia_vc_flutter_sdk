import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadUtils {
  static const _channel = MethodChannel('io.daakia/meeting_service');

  /// Copies [sourcePath] into the platform downloads folder.
  ///
  /// Android: public Downloads directory. API < 29 requests
  /// WRITE_EXTERNAL_STORAGE first; API 29+ uses MediaStore (no permission).
  ///
  /// iOS: iCloud Drive Downloads on iOS 16+ when iCloud Drive is available,
  /// otherwise a "Downloads" subfolder in the app Documents directory
  /// (visible in Files > On My iPhone > [App Name] when the host app sets
  /// UIFileSharingEnabled = YES in its Info.plist).
  ///
  /// Returns true on success, false on permission denial or non-fatal error.
  static Future<bool> saveToDownloads({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    try {
      if (Platform.isAndroid) {
        final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
        if (sdkInt < 29) {
          final status = await Permission.storage.request();
          if (!status.isGranted) {
            debugPrint('[DownloadUtils] WRITE_EXTERNAL_STORAGE denied');
            return false;
          }
        }
      }

      debugPrint('[DownloadUtils] saveToDownloads: sourcePath=$sourcePath, fileName=$fileName, mimeType=$mimeType');
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
