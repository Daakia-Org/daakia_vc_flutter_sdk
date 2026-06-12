import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DaakiaPiP {
  static const String _channelName = 'daakia_pip_channel';
  static const MethodChannel _methodChannel = MethodChannel(_channelName);

  /// Create PiP view on iOS
  /// [name] - participant name
  /// [avatar] - optional avatar URL
  static void createPipVideoCall({
    required String name,
    String? avatar,
  }) {
    if (!Platform.isIOS) return;

    _methodChannel.invokeMethod("createPiP", {
      "name": name,
      "avatar": avatar ?? "",
    }).catchError((e) => debugPrint('[DaakiaPiP] createPiP error: $e'));
  }

  /// Dispose PiP view
  static void disposePiP() async {
    if (!Platform.isIOS) return;

    try {
      await _methodChannel.invokeMethod("disposePiP");
    } catch (e) {
      debugPrint('[DaakiaPiP] disposePiP error: $e');
    }
  }
}