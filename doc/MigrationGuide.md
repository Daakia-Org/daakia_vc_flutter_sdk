# Migration Guide

## Upgrading to v4.6.0

v4.6.0 updates the SDK's internal dependencies to their latest versions. The SDK's public Dart API does
not change, but the build requirements do.

### 1. Toolchain

| | v4.5.x | v4.6.0 |
|---|---|---|
| Flutter | 3.22+ | **3.41.6+** |
| Dart SDK | ^3.8.0 | **^3.11.0** |
| Android `minSdk` | 21 | **24** |
| Android `compileSdk` | Flutter default | **37** |
| iOS deployment target | 14.0 | 14.0 (unchanged) |

Your app's own `environment: sdk` constraint in `pubspec.yaml` (for example `^3.8.0`) can stay as it is.
What has to be upgraded is the **Flutter installation** that builds the app: Flutter 3.41.6 or newer, which
includes Dart 3.11. Check it with `flutter --version`.

After upgrading, run:

```bash
flutter clean && flutter pub get
```

The video engine includes a prebuilt native library that is downloaded from github.com the first time the
app is built, then reused from the build cache. Build machines (including CI) need internet access to
github.com for that first build.

### 2. Android

Raise `minSdk` and `compileSdk` in `android/app/build.gradle` (or `build.gradle.kts`):

```groovy
android {
    compileSdk = 37
    defaultConfig {
        minSdk = 24
    }
}
```

- **`minSdk` 24** — with a lower `minSdk` the manifest merge fails.
- **`compileSdk` 37** — with a lower `compileSdk` the build still succeeds but prints a warning asking for
  Android SDK 37. Install the SDK 37 platform from Android Studio's SDK Manager if you don't have it. Your
  `targetSdk` does not have to change.

#### Android build tools

The SDK's plugins are now built with newer Kotlin and Android Gradle Plugin versions. With older ones in
your app, the Android build can fail (for example with Kotlin metadata or AGP version errors). These
versions are known to work:

| Tool | Version | Where |
|---|---|---|
| Android Gradle Plugin | **8.11.1** | `android/settings.gradle` |
| Kotlin | **2.2.20** | `android/settings.gradle` |
| Gradle | **8.14** | `android/gradle/wrapper/gradle-wrapper.properties` |
| JDK | **17** | the machine that builds the app |

```groovy
// android/settings.gradle
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}
```

```properties
# android/gradle/wrapper/gradle-wrapper.properties
distributionUrl=https\://services.gradle.org/distributions/gradle-8.14-all.zip
```

### 3. iOS

Keep the `PERMISSION_CAMERA=1` / `PERMISSION_MICROPHONE=1` macros in your `Podfile` (see the README's
*Podfile Permission Macros* section).

#### Location purpose string

Add `NSLocationWhenInUseUsageDescription` to your `Info.plist`. The SDK never asks for location, but a file
picker library it uses references location APIs (for optional photo geotagging, which is not enabled), and
App Store submission fails when a referenced purpose string is missing:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app does not use your location.</string>
```

#### Deployment target

iOS **14.0** is still the minimum. Recent Xcode versions warn about pods that declare an older deployment
target. To silence those warnings, raise the pods' target in your `Podfile`'s `post_install` block (use your
app's own target if it is higher than 15.0):

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 15.0
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      end
      # ...keep the PERMISSION_CAMERA / PERMISSION_MICROPHONE macros here
    end
  end
end
```

#### Building with the iOS 27 SDK (Xcode 27): UIScene life cycle

Apps built with the iOS 27 SDK must use the UIScene life cycle, or they fail to launch. With UIScene there is
no window or root view controller when `application(_:didFinishLaunchingWithOptions:)` runs, so the iOS
screen-sharing setup must register plugins and the ReplayKit channel later, once Flutter's engine exists.

1. Add a scene manifest to your `Info.plist`:

   ```xml
   <key>UIApplicationSceneManifest</key>
   <dict>
     <key>UIApplicationSupportsMultipleScenes</key>
     <false/>
     <key>UISceneConfigurations</key>
     <dict>
       <key>UIWindowSceneSessionRoleApplication</key>
       <array>
         <dict>
           <key>UISceneClassName</key>
           <string>UIWindowScene</string>
           <key>UISceneConfigurationName</key>
           <string>flutter</string>
           <key>UISceneDelegateClassName</key>
           <string>FlutterSceneDelegate</string>
           <key>UISceneStoryboardFile</key>
           <string>Main</string>
         </dict>
       </array>
     </dict>
   </dict>
   ```

2. In `AppDelegate.swift`, adopt `FlutterImplicitEngineDelegate` and move plugin registration and the
   ReplayKit channel into `didInitializeImplicitFlutterEngine`:

   ```swift
   @main
   @objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

       var replayKitChannel: FlutterMethodChannel! = nil

       override func application(
           _ application: UIApplication,
           didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
       ) -> Bool {
           return super.application(application, didFinishLaunchingWithOptions: launchOptions)
       }

       func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
           GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

           replayKitChannel = FlutterMethodChannel(
               name: "daakia_vc/replaykit-channel",
               binaryMessenger: engineBridge.applicationRegistrar.messenger())
           replayKitChannel.setMethodCallHandler { [weak self] call, result in
               self?.handleReplayKitFromFlutter(result: result, call: call)
           }
       }

       // handleReplayKitFromFlutter(...) and the rest stay as in the screen-sharing setup.
   }
   ```

   Remove the old `window?.rootViewController` lookup and the `GeneratedPluginRegistrant.register(with: self)`
   call from `didFinishLaunchingWithOptions`. Without this change the app launches, but screen sharing never
   starts because the ReplayKit channel is not registered. The full file is in the
   [iOS screen-sharing setup](../example/ios/README.md#step-5-configure-appdelegateswift).

If your app uses **Swift Package Manager**:

- The `Podfile` permission macros are not used. Camera and microphone access are enabled from the
  `NSCameraUsageDescription` and `NSMicrophoneUsageDescription` keys in your `Info.plist`, so both must be
  present (the SDK already requires them).
- Xcode caches package settings. After adding or changing `Info.plist` usage keys, clear DerivedData once,
  or permissions will keep reporting as denied:

  ```bash
  rm -rf ~/Library/Developer/Xcode/DerivedData
  ```

### 4. `DaakiaSdk.initialize(baseUrl:)` takes the unversioned API root (only if you set it)

`baseUrl` is **optional**. Most apps never pass it, and the SDK uses its built-in default. If you don't
pass `baseUrl`, there is nothing to change here.

If you do pass a custom `baseUrl`, drop the `/v2.0/` suffix. Each endpoint now adds its own API version:

```dart
// Before
DaakiaSdk.initialize(secret: key, baseUrl: 'https://<your-api-host>/v2.0/');

// After
DaakiaSdk.initialize(secret: key, baseUrl: 'https://<your-api-host>/');
```

### 5. Dependency conflicts in your app

The SDK now uses the latest versions of its dependencies. If your app depends on older versions of the same
packages, `flutter pub get` can fail to resolve. This is a version conflict, not a breaking change in the
SDK, and it is fixed by updating the conflicting packages in your app:

1. Set `daakia_vc_flutter_sdk: ^4.6.0` in your app's `pubspec.yaml` and run `flutter pub get`.
2. If it fails, the error names the package that conflicts. Raise that package in your app's `pubspec.yaml`
   to its latest version, then run `flutter pub get` again. Repeat until it resolves.
   `flutter pub upgrade --major-versions` can update them all at once.
3. If a package your own code uses moved to a new major version, check that package's changelog for API
   changes in your code.
4. Run `flutter clean && flutter pub get` and build both platforms.

No other parameters or behavior change as part of this migration.

---

## Moving `secretKey` to `DaakiaSdk.initialize` (since v4.5.2)

Starting in **v4.5.2**, `DaakiaVideoConferenceWidget.secretKey` is optional and **deprecated**. The
recommended flow is to set the secret key once at app startup via `DaakiaSdk.initialize`, instead of
passing it to every `DaakiaVideoConferenceWidget` instance.

> **Note:** The old flow still works. `secretKey` will continue to be honored as a fallback, but it will
> be removed in a future major version — migrate when convenient.

### Before

```dart
DaakiaVideoConferenceWidget(
  meetingId: meetingUID,
  secretKey: licenseKey,
  isHost: isHost,
)
```

### After

```dart
// main.dart, once at app startup, before runApp()
DaakiaSdk.initialize(secret: '<YOUR_SECRET_KEY>');

// meeting screen — no need to pass secretKey anymore
DaakiaVideoConferenceWidget(
  meetingId: meetingUID,
  isHost: isHost,
)
```

### Why migrate

- Avoids repeating the secret key on every widget instantiation.
- If neither `secretKey` nor `DaakiaSdk.initialize(secret: ...)` is set, the widget now shows a clear
  license error instead of failing silently.

### Steps

1. Call `DaakiaSdk.initialize(secret: '<YOUR_SECRET_KEY>')` once in `main()`, before `runApp()`.
2. Remove the `secretKey` argument from every `DaakiaVideoConferenceWidget(...)` call site.

No other parameters or behavior change as part of this migration.
