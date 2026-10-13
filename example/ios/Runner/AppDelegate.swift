import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    var replayKitChannel: FlutterMethodChannel! = nil
    var observeTimer: Timer! = nil
    var hasEmittedFirstSample = false

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // With the UIScene life cycle (required from the iOS 27 SDK) there is no
    // window or root view controller at launch, so plugins and the ReplayKit
    // channel are wired up once Flutter's engine exists.
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

        // Creating the method channel for ReplayKit communication
        replayKitChannel = FlutterMethodChannel(name: "daakia_vc/replaykit-channel",
                                                binaryMessenger: engineBridge.applicationRegistrar.messenger())

        // Setting method call handler for handling Flutter calls
        replayKitChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            self?.handleReplayKitFromFlutter(result: result, call: call)
        }
    }
        
        
    func handleReplayKitFromFlutter(result: FlutterResult, call: FlutterMethodCall) {
        switch call.method {
        case "startReplayKit":
            self.hasEmittedFirstSample = false
            if let group = UserDefaults(suiteName: "group.com.daakia.example") {
                // Resetting flags when starting ReplayKit
                group.set(false, forKey: "closeReplayKitFromNative")
                group.set(false, forKey: "closeReplayKitFromFlutter")
                self.observeReplayKitStateChanged()
            }
            result(true)
        case "closeReplayKit":
            if let group = UserDefaults(suiteName: "group.com.daakia.example") {
                // Setting flag to close ReplayKit from Flutter side
                group.set(true, forKey: "closeReplayKitFromFlutter")
                result(true)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    
    // Method to observe ReplayKit state changes
    func observeReplayKitStateChanged() {
        if self.observeTimer != nil {
            return // Timer is already active, no need to start another one
        }
        
        let group = UserDefaults(suiteName: "group.com.daakia.example")
        self.observeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self = self, let group = group else { return }
            
            // Checking whether to close ReplayKit from native or if a sample was broadcast
            let closeReplayKitFromNative = group.bool(forKey: "closeReplayKitFromNative")
            let hasSampleBroadcast = group.bool(forKey: "hasSampleBroadcast")
            
            if closeReplayKitFromNative {
                // If the broadcast should be closed natively
                self.hasEmittedFirstSample = false
                self.replayKitChannel.invokeMethod("closeReplayKitFromNative", arguments: true)
            } else if hasSampleBroadcast, !self.hasEmittedFirstSample {
                // If a sample was broadcast for the first time
                self.hasEmittedFirstSample = true
                self.replayKitChannel.invokeMethod("hasSampleBroadcast", arguments: true)
            }
        }
    }
        
}


