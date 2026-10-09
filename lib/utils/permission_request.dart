import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

// permission_handler runs one request at a time on Android: a second request
// started while one is pending throws "A request for permissions is already
// running". The SDK asks from several places (notifications on joining,
// mic/camera taps, downloads), so every request goes through this queue and
// waits its turn.
Future<void> _pending = Future.value();

extension SerialPermissionRequest on Permission {
  /// [request], but queued behind any request the SDK already has open.
  Future<PermissionStatus> requestSerially() {
    final result = _pending.then((_) => _requestSafely(this));
    _pending = result.then((_) {}, onError: (_) {});
    return result;
  }
}

Future<PermissionStatus> _requestSafely(Permission permission) async {
  try {
    return await permission.request();
  } on PlatformException {
    // The host app has its own request open. Report the current status
    // instead of throwing; the user can tap again once it is answered.
    return permission.status;
  }
}
