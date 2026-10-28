import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api/injection.dart';
import '../model/cdn_assets_model.dart';

/// Meeting sound URLs. The backend serves them from
/// `v2.0/configuration/cdn-assets` so they can move without an SDK release;
/// until that answers, or if it fails, the hard-coded fallbacks are used.
///
/// Once the URLs are known the files are downloaded into the app's cache
/// folder, so a chime plays from disk instead of the network.
class CdnSounds {
  CdnSounds._();

  static const String recordingStart = "recording_start";
  static const String recordingStop = "recording_stop";

  static const Map<String, String> _fallbacks = {
    recordingStart: "https://cdn.daakia.co.in/sounds/recording_start.mp3",
    recordingStop: "https://cdn.daakia.co.in/sounds/recording_stop.mp3",
  };

  static final Map<String, String> _resolved = {};
  static Future<void>? _loading;

  /// URL → downloaded file path.
  static final Map<String, String> _cachedFiles = {};
  static final Map<String, Future<void>> _downloads = {};

  // Plain Dio: no base URL, auth or API logging for CDN files.
  static final Dio _downloader = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  ));

  /// Fetches the URLs once per app run, then caches the files. Safe to call
  /// repeatedly; a failed fetch or download is retried on the next call.
  static Future<void> load() async {
    await (_loading ??= _fetch());
    // Cache whatever URLs are in use now, backend or fallback.
    await Future.wait(_fallbacks.keys.map((key) => _cache(url(key))));
  }

  static Future<void> _fetch() async {
    var loaded = false;
    try {
      await networkRequestHandler<CdnAssetsModel>(
        apiCall: () =>
            apiClient.getCdnAssets().timeout(const Duration(seconds: 10)),
        onSuccess: (data) {
          // Only known keys with absolute https URLs, like web.
          data?.sounds.forEach((key, value) {
            final uri = Uri.tryParse(value);
            if (_fallbacks.containsKey(key) &&
                uri != null &&
                uri.scheme == "https" &&
                uri.host.isNotEmpty) {
              _resolved[key] = value;
            }
          });
          loaded = true;
        },
        onError: (message) => debugPrint("CDN sounds not loaded: $message"),
      );
    } catch (e) {
      debugPrint("CDN sounds not loaded: $e");
    }
    if (!loaded) _loading = null;
  }

  /// The backend URL for [key] if it has arrived, else the fallback.
  static String url(String key) => _resolved[key] ?? fallbackUrl(key);

  static String fallbackUrl(String key) => _fallbacks[key]!;

  /// Local copy of the current URL for [key], or null until it is downloaded.
  static String? cachedFile(String key) => _cachedFiles[url(key)];

  /// Downloads [link] once. The file is named after the URL, so a new URL
  /// from the backend gets a fresh download and an unchanged one is reused
  /// across app runs.
  static Future<void> _cache(String link) {
    if (_cachedFiles.containsKey(link)) return Future.value();
    return _downloads[link] ??= _download(link);
  }

  static Future<void> _download(String link) async {
    File? part;
    try {
      final dir = Directory('${(await getApplicationCacheDirectory()).path}/daakia_sounds');
      final name = md5.convert(utf8.encode(link)).toString();
      final file = File('${dir.path}/$name.mp3');
      if (await file.exists() && await file.length() > 0) {
        _cachedFiles[link] = file.path;
        return;
      }
      await dir.create(recursive: true);
      part = File('${file.path}.part');
      final response = await _downloader.download(link, part.path);
      final type = response.headers.value(Headers.contentTypeHeader) ?? "";
      // Don't keep an error page that came back as 200.
      if (!type.startsWith("audio/") || await part.length() == 0) {
        throw Exception("Not an audio file ($type)");
      }
      await part.rename(file.path);
      _cachedFiles[link] = file.path;
    } catch (e) {
      debugPrint("Sound not cached from $link: $e");
      try {
        if (part != null && await part.exists()) await part.delete();
      } catch (_) {}
    } finally {
      // Let a failed download be tried again by the next load().
      _downloads.remove(link);
    }
  }
}
