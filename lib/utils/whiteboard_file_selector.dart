import 'package:file_picker/file_picker.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../service/daakia_vc_logger.dart';

/// Answers the whiteboard page's file pickers on Android.
///
/// Android's WebView does nothing with a page's file request (`<input
/// type="file">` or `showOpenFilePicker`) unless the app opens a picker for
/// it, so the board's Insert image (and Open) silently did nothing there. iOS
/// shows its own picker and doesn't need this.
class WhiteboardFileSelector {
  WhiteboardFileSelector._();

  /// Makes cancelling the picker look like a cancel to the page.
  ///
  /// The WebView can only hand the page a list of files, so a cancel arrives
  /// as an empty selection, which the board reports as "Unsupported file
  /// type". A browser instead rejects `showOpenFilePicker` with AbortError
  /// (which the board ignores), or, on WebViews without that API, sends the
  /// file input a `cancel` event rather than an empty `change`.
  static const String cancelScript = r"""
(function () {
  if (window.__daakiaFileCancelPatched) return;
  window.__daakiaFileCancelPatched = true;
  if (window.showOpenFilePicker) {
    var open = window.showOpenFilePicker;
    window.showOpenFilePicker = function () {
      return open.apply(this, arguments).then(function (handles) {
        if (!handles || handles.length === 0) {
          throw new DOMException('The user aborted a request.', 'AbortError');
        }
        return handles;
      });
    };
  }
  function hook(input) {
    if (input.type !== 'file' || input.__daakiaCancelHooked) return;
    input.__daakiaCancelHooked = true;
    input.addEventListener('change', function (e) {
      if (input.files && input.files.length === 0) {
        e.stopImmediatePropagation();
        input.dispatchEvent(new Event('cancel'));
      }
    }, true);
  }
  ['click', 'showPicker'].forEach(function (name) {
    var original = HTMLInputElement.prototype[name];
    if (!original) return;
    HTMLInputElement.prototype[name] = function () {
      hook(this);
      return original.apply(this, arguments);
    };
  });
})();
""";

  /// Returns `file://` URIs of the picked files, or an empty list when the
  /// user cancels — the page treats that as no selection.
  static Future<List<String>> pick(FileSelectorParams params) async {
    try {
      final type = _wantsImagesOnly(params.acceptTypes)
          ? FileType.image
          : FileType.any;
      final files = params.mode == FileSelectorMode.openMultiple
          ? await FilePicker.pickFiles(type: type)
          : [?await FilePicker.pickFile(type: type)];
      return [
        for (final file in files)
          if (file.path != null) Uri.file(file.path!).toString(),
      ];
    } catch (e) {
      DaakiaVcLogger.logWarning('Whiteboard file picker failed: $e',
          reportToSentry: false);
      return const [];
    }
  }

  /// The image tool asks for image extensions (or `image/*` types); the
  /// board's Open asks for its own scene files, which need the full picker.
  static bool _wantsImagesOnly(List<String> acceptTypes) {
    final types = acceptTypes
        .expand((t) => t.split(','))
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toList();
    if (types.isEmpty) return false;
    // The board's image tool lists extensions, not MIME types.
    const imageExtensions = {
      '.png', '.jpg', '.jpeg', '.jpe', '.jfif', '.pjp', '.pjpeg', '.gif',
      '.webp', '.svg', '.svgz', '.bmp', '.ico', '.avif', '.heic', '.heif',
      '.tif', '.tiff',
    };
    return types
        .every((t) => t.startsWith('image/') || imageExtensions.contains(t));
  }
}
