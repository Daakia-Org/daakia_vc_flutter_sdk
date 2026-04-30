import Flutter
import UIKit
import AVFoundation

public class DaakiaVcFlutterSdkPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "io.daakia/meeting_service",
            binaryMessenger: registrar.messenger()
        )
        let instance = DaakiaVcFlutterSdkPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startMeetingService":
            activateAudioSession()
            result(nil)
        case "stopMeetingService":
            // Let LiveKit / WebRTC manage teardown — we don't force-deactivate here
            // because WebRTC's internal ref-counting will handle it on disconnect.
            result(nil)
        case "updateMuteState":
            // iOS keeps the audio session alive regardless of mute state — no-op.
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // Activates AVAudioSession with the same category/mode that WebRTC/LiveKit uses
    // (.playAndRecord / .videoChat). Calling this when the meeting starts ensures
    // iOS keeps the app alive in the background under the `audio` UIBackgroundMode
    // even when the user's microphone is muted, because the session is active for
    // audio playback of remote participants.
    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .videoChat,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setActive(true)
        } catch {
            print("DaakiaMeetingService: audio session activation failed — \(error)")
        }
    }
}
