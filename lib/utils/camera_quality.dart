import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:livekit_client/livekit_client.dart';

import '../service/daakia_vc_logger.dart';

/// How this device captures and sends its camera.
///
/// The camera goes out in several quality levels (simulcast): viewers get a
/// small copy for small tiles and the full one only when it fills the screen,
/// and someone on a weak network drops to a lower level instead of freezing.
///
/// Phones with little memory capture at 540p/24 fps instead of 720p/30 fps:
/// encoding three levels from a 720p camera is what makes them run hot, drop
/// frames and get killed in the background.
class CameraQuality {
  const CameraQuality._({
    required this.tier,
    required this.capture,
    required this.maxFrameRate,
  });

  /// `standard` or `low`; logged so field reports can be split by tier.
  final String tier;

  /// Capture size and the top quality level's bitrate/frame rate.
  final VideoParameters capture;

  final double maxFrameRate;

  static const standard = CameraQuality._(
    tier: 'standard',
    capture: VideoParametersPresets.h720_169, // 1.7 Mbps, 30 fps
    maxFrameRate: 30,
  );

  static const low = CameraQuality._(
    tier: 'low',
    capture: VideoParameters(
      dimensions: VideoDimensionsPresets.h540_169,
      encoding: VideoEncoding(maxBitrate: 800 * 1000, maxFramerate: 24),
    ),
    maxFrameRate: 24,
  );

  /// Android reports total RAM a little under the marketed size (a "4 GB"
  /// phone shows ~3.6 GB), so this puts 3 GB phones and below in [low].
  static const int _lowRamThresholdMb = 3500;

  static CameraQuality? _resolved;
  static Future<CameraQuality>? _pending;

  /// The quality for this device, resolved once per app run. [standard] until
  /// [resolve] has finished.
  static CameraQuality get current => _resolved ?? standard;

  static Future<CameraQuality> resolve() {
    final resolved = _resolved;
    if (resolved != null) return Future.value(resolved);
    return _pending ??= _detect().then((quality) {
      _resolved = quality;
      DaakiaVcLogger.logInfo(
        'Camera quality selected',
        attributes: {'camera_quality_tier': quality.tier},
      );
      return quality;
    });
  }

  static Future<CameraQuality> _detect() async {
    if (!Platform.isAndroid) return standard;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final ramMb = info.physicalRamSize;
      final isLow = info.isLowRamDevice ||
          (ramMb > 0 && ramMb < _lowRamThresholdMb);
      return isLow ? low : standard;
    } catch (_) {
      return standard;
    }
  }

  CameraCaptureOptions captureOptions({String? deviceId}) =>
      CameraCaptureOptions(
        deviceId: deviceId,
        maxFrameRate: maxFrameRate,
        params: capture,
      );

  /// Simulcast on, top level from [capture]; LiveKit adds the 180p and 360p
  /// levels below it.
  VideoPublishOptions publishOptions({
    required VideoEncoding screenShareEncoding,
  }) =>
      VideoPublishOptions(
        simulcast: true,
        videoEncoding: capture.encoding,
        videoSimulcastLayers: [
          VideoParametersPresets.h180_169,
          VideoParametersPresets.h360_169,
        ],
        screenShareEncoding: screenShareEncoding,
      );
}
