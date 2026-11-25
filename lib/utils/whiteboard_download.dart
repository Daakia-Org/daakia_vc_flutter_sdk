import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../service/daakia_vc_logger.dart';
import 'download_utils.dart';

/// Saves files the whiteboard page exports (PNG / SVG / .excalidraw).
///
/// A WebView can't save a page's download by itself: iOS navigates the whole
/// view to the blob: URL and Android drops it. [script] makes the page hand
/// the file to Flutter over the [channelName] JavaScript channel instead, and
/// [save] writes it to the device's Downloads folder.
class WhiteboardDownload {
  WhiteboardDownload._();

  static const String channelName = 'DaakiaWhiteboardDownload';

  /// Run after every page load. It is idempotent, so a reload or a second
  /// run on the same page doesn't double-wrap anything.
  ///
  /// - Removes `showSaveFilePicker`, so the page falls back to an
  ///   `<a download>` click (the picker throws inside a WebView).
  /// - Turns that click into a message carrying the file as base64.
  static const String script = '''
(function () {
  if (window.__daakiaDownloadBridge) return;
  window.__daakiaDownloadBridge = true;
  try { delete window.showSaveFilePicker; } catch (e) {}
  window.showSaveFilePicker = undefined;
  var originalClick = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    var href = this.href || '';
    if (!this.hasAttribute('download') ||
        !(href.indexOf('blob:') === 0 || href.indexOf('data:') === 0)) {
      return originalClick.apply(this, arguments);
    }
    var name = this.getAttribute('download') || 'whiteboard';
    fetch(href)
      .then(function (r) { return r.blob(); })
      .then(function (blob) {
        var reader = new FileReader();
        reader.onloadend = function () {
          var url = String(reader.result || '');
          $channelName.postMessage(JSON.stringify({
            name: name,
            mimeType: blob.type || 'application/octet-stream',
            data: url.substring(url.indexOf(',') + 1)
          }));
        };
        reader.readAsDataURL(blob);
      })
      .catch(function (e) {
        $channelName.postMessage(JSON.stringify({ error: String(e) }));
      });
  };
})();
''';

  /// Saves one message from [script]. Returns the saved file name, or null
  /// if the page reported an error or the save failed.
  static Future<String?> save(String message) async {
    try {
      final payload = jsonDecode(message) as Map<String, dynamic>;
      if (payload['error'] != null) {
        DaakiaVcLogger.logWarning(
            'Whiteboard export failed in page: ${payload['error']}',
            reportToSentry: false);
        return null;
      }
      final fileName = _safeName(payload['name'] as String? ?? 'whiteboard');
      final bytes = base64Decode(payload['data'] as String);
      final temp = File('${(await getTemporaryDirectory()).path}/$fileName');
      await temp.writeAsBytes(bytes, flush: true);
      final saved = await DownloadUtils.saveToDownloads(
        sourcePath: temp.path,
        fileName: fileName,
        mimeType: payload['mimeType'] as String? ?? 'application/octet-stream',
      );
      return saved ? fileName : null;
    } catch (e) {
      DaakiaVcLogger.logWarning('Whiteboard export save failed: $e',
          reportToSentry: false);
      return null;
    }
  }

  /// The page picks the name, so keep it to a plain file name.
  static String _safeName(String name) {
    final cleaned = name.split(RegExp(r'[\\/]')).last.trim();
    return cleaned.isEmpty ? 'whiteboard' : cleaned;
  }
}
