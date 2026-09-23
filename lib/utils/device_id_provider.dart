import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

import 'storage_helper.dart';

/// Identifies the device this SDK runs on, so the backend can tell whether a
/// session already in the meeting belongs to this device (a stale one the
/// server hasn't dropped yet) or to a genuinely different device.
///
/// The value has to stay the same for a device across app restarts *and
/// reinstalls*, so it comes from the platform rather than from app storage:
/// `ANDROID_ID` on Android (per device, app signing key and user; survives a
/// reinstall, changes on factory reset) and `identifierForVendor` on iOS.
///
/// What is sent is a SHA-256 of that value, never the raw platform id: it ends
/// up in the join metadata, which LiveKit gives to every participant in the
/// room. Hashing keeps it useful for comparison while making it useless as a
/// device fingerprint elsewhere.
///
/// If the platform returns nothing (an emulator with no ANDROID_ID, a
/// simulator, a platform we don't cover), it falls back to the random
/// per-install id in [StorageHelper.getOrCreateDeviceId], which stays stable
/// until the app is reinstalled.
class DeviceIdProvider {
  DeviceIdProvider._();

  static const MethodChannel _channel =
      MethodChannel('io.daakia/meeting_service');

  static String? _cached;
  static Future<String>? _inFlight;

  /// The id for this device. Computed once per process; concurrent callers
  /// share the same lookup, so two joins can't race to different values.
  static Future<String> get() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _inFlight ??= _resolveAndCache();
  }

  static Future<String> _resolveAndCache() async {
    try {
      final id = await _resolve();
      _cached = id;
      return id;
    } finally {
      _inFlight = null;
    }
  }

  static Future<String> _resolve() async {
    final platformId = await _platformId();
    if (platformId != null && platformId.trim().isNotEmpty) {
      return sha256.convert(utf8.encode(platformId.trim())).toString();
    }
    return StorageHelper().getOrCreateDeviceId();
  }

  static Future<String?> _platformId() async {
    try {
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<String>('getDeviceId');
      }
      if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        return info.identifierForVendor;
      }
    } catch (_) {
      // Fall through to the stored id.
    }
    return null;
  }
}
