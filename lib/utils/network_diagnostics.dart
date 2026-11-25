import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import 'constants.dart';

/// What the device's internet actually looks like right now.
enum NetworkStatus {
  /// No transport at all — airplane mode, or Wi-Fi and mobile data both off.
  offline,

  /// Joined to a network, but nothing answers on the other side: a captive
  /// portal nobody has signed into, a router with a dead uplink, a cell with no
  /// backhaul. This is the case users misread as "the app is broken".
  noInternetAccess,

  /// Reachable, but slow enough that a call will struggle to set itself up.
  poor,

  /// Reachable and responsive.
  online,
}

/// The outcome of [NetworkDiagnostics.run] — facts only. The user-facing
/// wording lives in `JoinFailure`, which pairs this with what actually failed.
class NetworkDiagnosis {
  const NetworkDiagnosis({
    required this.status,
    required this.transport,
    this.latency,
  });

  final NetworkStatus status;

  /// How to name the connection in a sentence: "Wi-Fi", "mobile data", …
  final String transport;

  /// Round trip to [NetworkDiagnostics.run]'s probe target, when one completed.
  final Duration? latency;

  bool get isUsable =>
      status == NetworkStatus.online || status == NetworkStatus.poor;
}

/// Tells apart "no internet", "connected but no internet access" and "slow".
///
/// `connectivity_plus` alone can't do this: it reports the *transport*, so it
/// says "Wi-Fi" just as confidently for a working network as for a hotel router
/// waiting on a sign-in page. Only an actual round trip separates the two, so
/// this pairs the transport check with a real request.
class NetworkDiagnostics {
  NetworkDiagnostics._();

  /// A round trip slower than this means media will struggle even if it does
  /// eventually connect, so it's worth telling the user before they wait again.
  static const _poorLatencyThreshold = Duration(milliseconds: 1500);

  static const _probeTimeout = Duration(seconds: 5);

  /// Diagnoses the current connection, probing [probeUrl] when given (the
  /// LiveKit server URL is the most honest target — it's the host that has to
  /// work) and falling back to the Daakia API host.
  ///
  /// Never throws: an inconclusive check reports [NetworkStatus.online] rather
  /// than inventing a network problem to blame.
  static Future<NetworkDiagnosis> run({String? probeUrl}) async {
    final transport = await _describeTransport();

    if (transport == null) {
      return const NetworkDiagnosis(
        status: NetworkStatus.offline,
        transport: 'a network',
      );
    }

    final probe = await _probe(probeUrl);

    if (!probe.reachable) {
      return NetworkDiagnosis(
        status: NetworkStatus.noInternetAccess,
        transport: transport,
      );
    }

    final latency = probe.latency;
    return NetworkDiagnosis(
      status: latency != null && latency > _poorLatencyThreshold
          ? NetworkStatus.poor
          : NetworkStatus.online,
      transport: transport,
      latency: latency,
    );
  }

  /// Returns null when the device has no transport at all.
  static Future<String?> _describeTransport() async {
    final List<ConnectivityResult> results;
    try {
      results = await Connectivity().checkConnectivity();
    } catch (_) {
      // Can't tell — assume there is a transport and let the probe decide.
      return 'your network';
    }

    if (results.contains(ConnectivityResult.wifi)) return 'Wi-Fi';
    if (results.contains(ConnectivityResult.mobile)) return 'mobile data';
    if (results.contains(ConnectivityResult.ethernet)) return 'this network';
    if (results.isEmpty ||
        results.every((r) => r == ConnectivityResult.none)) {
      return null;
    }
    return 'your network';
  }

  /// Probes the meeting server, then the API host, and reports the latency of
  /// whichever answered.
  ///
  /// Two hosts, not one, because a single unanswered probe is not proof the
  /// device is offline — the server could be down, its DNS broken, or the URL
  /// malformed. Telling a user with perfectly good internet to go fix their
  /// Wi-Fi sends them chasing the wrong thing, and hides an outage from us.
  static Future<({bool reachable, Duration? latency})> _probe(
      String? probeUrl) async {
    final target = _toHttpUrl(probeUrl);
    final targets = <String>{
      ?target,
      Constant.baseUrl,
    };

    // Concurrently, not one after the other: a dead network makes every probe
    // burn the full timeout, and stacking them would double the wait the user
    // sits through *after* the join attempts have already timed out.
    final results = await Future.wait(targets.map(_timedReach));

    final reached = results.where((r) => r.reachable).toList();
    if (reached.isEmpty) return (reachable: false, latency: null);

    // Report the best round trip we saw — one slow host shouldn't make a
    // healthy connection look "poor".
    reached.sort((a, b) => a.latency!.compareTo(b.latency!));
    return reached.first;
  }

  static Future<({bool reachable, Duration? latency})> _timedReach(
      String url) async {
    final stopwatch = Stopwatch()..start();
    final reachable = await _canReach(url);
    stopwatch.stop();
    return (
      reachable: reachable,
      latency: reachable ? stopwatch.elapsed : null,
    );
  }

  static Future<bool> _canReach(String url) async {
    final host = Uri.tryParse(url)?.host;

    final dio = Dio(BaseOptions(
      connectTimeout: _probeTimeout,
      sendTimeout: _probeTimeout,
      receiveTimeout: _probeTimeout,
      // Any answer at all proves the network carries traffic to that host — a
      // 404 or a 401 is as good a signal as a 200, so don't let Dio throw on it.
      validateStatus: (_) => true,
      followRedirects: false,
    ));

    try {
      final response = await dio.head(url);
      final status = response.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        final location = response.headers.value('location');
        final redirectHost =
            location == null ? null : Uri.tryParse(location)?.host;
        // Being bounced to a different host is the classic captive-portal
        // handshake: the network answered, but with its own sign-in page
        // instead of our server. That is "no internet access", not "online".
        if (redirectHost != null &&
            redirectHost.isNotEmpty &&
            redirectHost != host) {
          return false;
        }
      }
      return true;
    } catch (_) {
      // DNS failure, TLS failure, timeout, connection refused — no usable path
      // to the host, whatever the transport claims.
      return false;
    } finally {
      dio.close(force: true);
    }
  }

  /// LiveKit hands out `ws://` / `wss://` URLs; an HTTP probe needs the
  /// http(s) form of the same host.
  static String? _toHttpUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return null;

    final scheme = switch (uri.scheme) {
      'wss' => 'https',
      'ws' => 'http',
      'http' || 'https' => uri.scheme,
      _ => 'https',
    };
    return uri.replace(scheme: scheme, path: '', query: '', fragment: '').toString();
  }
}
