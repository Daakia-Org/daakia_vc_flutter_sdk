# Broadcast Extension Quick Setup

Follow these steps to set up the Broadcast Extension for screen sharing on iOS.

---

## Step 1: Add Broadcast Extension
1. Open your iOS project in Xcode.
2. Go to **File > New > Target** and select **Broadcast Upload Extension without UI**.  
   *(Ensure "Include UI Extension" is unchecked.)*

---

## Step 2: Configure App Groups
1. Add **App Groups** to both your main app and the broadcast extension.  
   **Important**: Ensure the app group identifier follows this format: `group.yourappbundle`.  
   Both the app and extension must share the **same App Group**.

### Adding App Groups
- **For your broadcast extension**:
    1. Go to your extension's target in the project.
    2. Navigate to the **Signing & Capabilities** tab.
    3. Click the **+** button in the top-left and select **App Groups**.
- **For your main app**:
    1. Repeat the above steps for the app’s target.

---

## Step 3: Set Up the Sample Handler
1. Copy the following files into your extension from [BroadcastExtension Directory](BroadcastExtension)
   :
    - `SampleHandler.swift`
    - `SampleUploader.swift`
    - `SocketConnection.swift`
    - `DarwinNotificationCenter.swift`
    - `Atomic.swift`
2. Overwrite the auto-generated `SampleHandler.swift` if prompted.
3. In `SampleHandler.swift`, update `appGroupIdentifier` to match your App Group identifier.

---

## Step 4: Update `Info.plist`
1. Open the `Info.plist` file for your broadcast extension.
2. Add the following keys and values:
   ```
   <key>RTCAppGroupIdentifier</key>
   <string>yourgroupid</string> <!-- Replace with your App Group identifier -->
   <key>RTCScreenSharingExtension</key>
   <string>yourbundleid.BroadcastExtension</string> <!-- Replace with your Broadcast Extension bundle ID -->
    ```
---

## Step 5: Configure `AppDelegate.swift`

1. Open `AppDelegate` in your main app.
2. Add the following code. It uses the UIScene life cycle, which apps built with the iOS 27 SDK (Xcode 27)
   must adopt: add the scene manifest to your `Info.plist` as shown in the
   [Migration Guide](../../doc/MigrationGuide.md#building-with-the-ios-27-sdk-xcode-27-uiscene-life-cycle).
   With UIScene there is no window or root view controller at launch, so plugins and the ReplayKit channel
   are registered once Flutter's engine exists.

    ```swift
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

       func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
           GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

           // Setting up ReplayKit communication
           replayKitChannel = FlutterMethodChannel(name: "daakia_vc/replaykit-channel",
                                                   binaryMessenger: engineBridge.applicationRegistrar.messenger())

           // Handle Flutter method calls
           replayKitChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
               self?.handleReplayKitFromFlutter(result: result, call: call)
           }
       }

       func handleReplayKitFromFlutter(result: FlutterResult, call: FlutterMethodCall) {
           switch call.method {
           case "startReplayKit":
               self.hasEmittedFirstSample = false
               if let group = UserDefaults(suiteName: "group.com.daakia.example") {
                   group.set(false, forKey: "closeReplayKitFromNative")
                   group.set(false, forKey: "closeReplayKitFromFlutter")
                   self.observeReplayKitStateChanged()
               }
               result(true)
           case "closeReplayKit":
               if let group = UserDefaults(suiteName: "group.com.daakia.example") {
                   group.set(true, forKey: "closeReplayKitFromFlutter")
                   result(true)
               }
           default:
               result(FlutterMethodNotImplemented)
           }
       }

       func observeReplayKitStateChanged() {
           if observeTimer != nil { return }

           let group = UserDefaults(suiteName: "group.com.daakia.example")
           observeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
               guard let self = self, let group = group else { return }

               let closeReplayKitFromNative = group.bool(forKey: "closeReplayKitFromNative")
               let hasSampleBroadcast = group.bool(forKey: "hasSampleBroadcast")

               if closeReplayKitFromNative {
                   self.hasEmittedFirstSample = false
                   self.replayKitChannel.invokeMethod("closeReplayKitFromNative", arguments: true)
               } else if hasSampleBroadcast, !self.hasEmittedFirstSample {
                   self.hasEmittedFirstSample = true
                   self.replayKitChannel.invokeMethod("hasSampleBroadcast", arguments: true)
               }
           }
       }
   }
    ```

3. Replace all instances of group.com.daakia.example with your actual App Group identifier.
4. Do not modify the channel names.

> **App without the UIScene life cycle** (built with an SDK older than iOS 27 and no scene manifest in
> `Info.plist`): `didInitializeImplicitFlutterEngine` is not called. Register in
> `didFinishLaunchingWithOptions` instead, and drop `FlutterImplicitEngineDelegate`:
>
> ```swift
> guard let controller = window?.rootViewController as? FlutterViewController else {
>     return super.application(application, didFinishLaunchingWithOptions: launchOptions)
> }
> replayKitChannel = FlutterMethodChannel(name: "daakia_vc/replaykit-channel",
>                                         binaryMessenger: controller.binaryMessenger)
> replayKitChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
>     self?.handleReplayKitFromFlutter(result: result, call: call)
> }
> GeneratedPluginRegistrant.register(with: self)
> return super.application(application, didFinishLaunchingWithOptions: launchOptions)
> ```

### Special Note:
> ⚠️ **This screen share will not work on the iOS Simulator. To test its functionality, you must use a real device.**