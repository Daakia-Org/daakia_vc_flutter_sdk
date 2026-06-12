import Flutter
import UIKit
import AVFoundation

public class DaakiaVcFlutterSdkPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private var isInterrupted = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let ch = FlutterMethodChannel(
            name: "io.daakia/meeting_service",
            binaryMessenger: registrar.messenger()
        )
        let instance = DaakiaVcFlutterSdkPlugin()
        instance.channel = ch
        registrar.addMethodCallDelegate(instance, channel: ch)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startMeetingService":
            activateAudioSession()
            registerInterruptionObserver()
            result(nil)
        case "stopMeetingService":
            // Let LiveKit / WebRTC manage teardown — we don't force-deactivate here
            // because WebRTC's internal ref-counting will handle it on disconnect.
            unregisterInterruptionObserver()
            result(nil)
        case "updateMuteState":
            // iOS keeps the audio session alive regardless of mute state — no-op.
            result(nil)
        case "saveFileToDownloads":
            // iOS saves directly to the app Documents directory in Dart — no native step needed.
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // Activates the audio session. Returns true on success, false if still interrupted.
    // When force=false (the default), skips reconfiguration if LiveKit has already
    // set the session to .playAndRecord — reconfiguring mid-capture disrupts the
    // WebRTC audio pipeline and causes the mic to go silent despite appearing unmuted.
    // Set force=true only when recovering from a phone-call interruption, where the
    // session must be explicitly reclaimed.
    @discardableResult
    private func activateAudioSession(force: Bool = false) -> Bool {
        let session = AVAudioSession.sharedInstance()
        if !force && session.category == .playAndRecord {
            return true
        }
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .videoChat,
                options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
            )
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }

    private func registerInterruptionObserver() {
        let session = AVAudioSession.sharedInstance()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: session
        )
        // iOS 16+ often skips AVAudioSessionInterruptionTypeEnded after phone calls.
        // didBecomeActive covers the case where the app was backgrounded during the call.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        // Dynamic Island calls: app stays in foreground the whole time, so
        // didBecomeActive never fires. Route change is the only reliable signal
        // that the call released the audio session.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: session
        )
    }

    private func unregisterInterruptionObserver() {
        let session = AVAudioSession.sharedInstance()
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: session)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: session)
        isInterrupted = false
    }

    // Called by iOS when a phone call (or other audio interruption) begins or ends.
    // On `.ended` we reactivate AVAudioSession and tell Flutter so it can restart
    // the LiveKit microphone track — without this, WebRTC never resumes capturing
    // even though the track is still "enabled" from LiveKit's perspective.
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        if type == .began {
            isInterrupted = true
            channel?.invokeMethod("audioInterruptionBegan", arguments: nil)
            return
        }

        // .ended path — not reliable on iOS 16+ for phone calls; handleAppDidBecomeActive
        // and handleRouteChange are the primary recovery paths.
        guard type == .ended else { return }

        var shouldResume = true
        if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
            shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                .contains(.shouldResume)
        }
        guard shouldResume else { return }

        recoverAudioSession()
    }

    // Fires when the user returns from a backgrounded phone call.
    @objc private func handleAppDidBecomeActive() {
        guard isInterrupted else { return }
        recoverAudioSession()
    }

    // Fires when the audio route changes — the only reliable signal when a Dynamic
    // Island call ends while the app stays in the foreground.
    @objc private func handleRouteChange(_ notification: Notification) {
        guard isInterrupted else { return }
        guard notification.userInfo?[AVAudioSessionRouteChangeReasonKey] is UInt else { return }
        recoverAudioSession()
    }

    private func recoverAudioSession() {
        guard isInterrupted else { return }
        // Do NOT clear isInterrupted yet — only clear it if activation succeeds.
        // This prevents the mic button from unlocking while the call is still active.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, self.isInterrupted else { return }
            if self.activateAudioSession(force: true) {
                // Session is ours again — call has truly ended.
                self.isInterrupted = false
                self.channel?.invokeMethod("audioInterruptionEnded", arguments: nil)
            }
            // If activation failed the call is still active; isInterrupted stays true
            // and the next route change / didBecomeActive will retry.
        }
    }
}
