import 'package:livekit_client/livekit_client.dart';

import 'network_diagnostics.dart';

/// A join failure translated out of LiveKit's vocabulary and into the user's.
///
/// The raw exceptions are accurate but unusable by anyone who isn't a WebRTC
/// engineer — "[MediaConnectException] Timed out waiting for PeerConnection to
/// connect, please check your network for ice connectivity" reads as a crash to
/// a participant who just wanted to join a call, so they report it as our bug.
/// Every user-facing surface should show one of these instead, and keep
/// [technicalDetail] for logs and for testers who need the real string.
class JoinFailure {
  const JoinFailure({
    required this.title,
    required this.message,
    required this.tips,
    required this.technicalDetail,
    required this.diagnosis,
    this.canRetry = true,
  });

  /// Short headline, e.g. "You're offline".
  final String title;

  /// One or two plain sentences saying what happened and whose side it's on.
  final String message;

  /// Concrete things the user can actually do, most likely to work first.
  final List<String> tips;

  /// The original exception text — for logs and bug reports, never the headline.
  final String technicalDetail;

  /// What the network looked like when this failed. Not shown to the user;
  /// it's what makes a field report actionable — "ICE timed out" alone can't
  /// tell a blocked office Wi-Fi from a phone that had already lost signal.
  final NetworkDiagnosis diagnosis;

  /// False when retrying can't possibly help (an invalid or expired token).
  final bool canRetry;

  /// Flattened form, for surfaces that only have room for a single string.
  String get summary =>
      tips.isEmpty ? message : '$message\n\n${tips.map((t) => '• $t').join('\n')}';

  /// Diagnoses the connection on its own, for callers holding a failure that
  /// isn't a LiveKit exception — an API call that couldn't reach the backend,
  /// say. Returns null when the network is fine and the caller's own message is
  /// the better one to show.
  static Future<JoinFailure?> forNetwork({
    required String technicalDetail,
  }) async {
    return _fromNetwork(await NetworkDiagnostics.run(), technicalDetail);
  }

  /// The two failures that are about the device's connection rather than about
  /// anything the meeting did. Null when the connection isn't the story.
  static JoinFailure? _fromNetwork(NetworkDiagnosis diagnosis, String detail) {
    switch (diagnosis.status) {
      case NetworkStatus.offline:
        return JoinFailure(
          title: "You're offline",
          message: "Your device isn't connected to the internet, so we couldn't "
              "reach the meeting.",
          tips: const [
            'Turn on Wi-Fi or mobile data',
            'Check that Airplane mode is off',
          ],
          technicalDetail: detail,
          diagnosis: diagnosis,
        );

      case NetworkStatus.noInternetAccess:
        return JoinFailure(
          title: 'No internet access',
          message: "Your device is connected to ${diagnosis.transport}, but that "
              "connection can't reach the internet right now.",
          tips: const [
            'If you are on public, hotel or office Wi-Fi, open your browser — it '
                'may be waiting for you to sign in',
            'Switch to mobile data, or move to a different network',
          ],
          technicalDetail: detail,
          diagnosis: diagnosis,
        );

      case NetworkStatus.poor:
      case NetworkStatus.online:
        return null;
    }
  }

  /// Builds the message for [error], checking the device's actual connectivity
  /// first so we can tell "you have no internet" from "your internet is fine
  /// but this network blocks video calls" — two failures that look identical to
  /// the caller but need completely different advice.
  static Future<JoinFailure> diagnose(
    Object error, {
    String? livekitUrl,
  }) async {
    final detail = error.toString();
    final diagnosis = await NetworkDiagnostics.run(probeUrl: livekitUrl);

    // A dead connection explains every one of these exceptions, so it wins
    // over whatever LiveKit happened to throw first.
    final networkFailure = _fromNetwork(diagnosis, detail);
    if (networkFailure != null) return networkFailure;

    // The internet works. Now the exception tells us which leg of the join
    // broke, and each leg needs different advice.
    if (error is ConnectException &&
        error.reason == ConnectionErrorReason.NotAllowed) {
      return JoinFailure(
        title: "Couldn't join this meeting",
        message: 'This meeting link is no longer valid, or the meeting has '
            'already been closed.',
        tips: const [
          'Ask the host to share the meeting link again',
        ],
        technicalDetail: detail,
        diagnosis: diagnosis,
        canRetry: false,
      );
    }

    if (error is MediaConnectException || error is NegotiationError) {
      // Signalling worked, media didn't: the network carries ordinary web
      // traffic but not the call itself. Restrictive Wi-Fi is by far the most
      // common cause, and switching networks is the fix that actually works.
      return JoinFailure(
        title: 'Weak or restricted connection',
        message: diagnosis.status == NetworkStatus.poor
            ? "Your ${diagnosis.transport} connection is too slow at the moment "
                "to set up the call."
            : "Your internet is working, but we couldn't set up the call's "
                "audio and video connection.",
        tips: const [
          'Try mobile data instead of Wi-Fi, or the other way round',
          'Office, hotel and public Wi-Fi often block video calls — a different '
              'network usually works',
          'If you are on a VPN, turn it off and try again',
        ],
        technicalDetail: detail,
        diagnosis: diagnosis,
      );
    }

    if (error is TrackCreateException) {
      return JoinFailure(
        title: 'Camera or microphone unavailable',
        message: "We couldn't start your camera or microphone, so the call "
            "could not begin.",
        tips: const [
          'Close any other app that may be using the camera',
          "Check the app's camera and microphone permissions in Settings",
        ],
        technicalDetail: detail,
        diagnosis: diagnosis,
      );
    }

    // Everything that reaches here — a signalling timeout, a dropped web
    // socket, a server error — comes down to the same thing from the user's
    // side: the internet works, but the meeting server did not complete the
    // handshake. LiveKit's own WebSocketException isn't exported, so it lands
    // here too rather than being matched by name.
    return JoinFailure(
      title: "Couldn't reach the meeting",
      message: 'We could not connect to the meeting server. This is usually a '
          'temporary network problem.',
      tips: const [
        'Check your connection and try again',
        'If you are on a VPN or office network, try mobile data',
      ],
      technicalDetail: detail,
      diagnosis: diagnosis,
    );
  }
}
