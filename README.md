![Logo](https://www.daakia.co.in/assets/images/frontend/logo-dark.svg)

# Daakia VC Flutter SDK
Integrate Daakia's video conferencing capabilities into your Flutter applications with ease.

This SDK provides a simple and efficient way to add video conferencing features to your Flutter apps, supporting both Android and iOS platforms.

## Supported Platforms
✅ **Android**  | ✅ **iOS**

## Latest Release
**v4.5.0** - See [CHANGELOG.md](CHANGELOG.md) for detailed release notes and what's new.

# How to use



## Installation

add ``daakia_vc_flutter_sdk:`` to your ``pubspec.yaml`` dependencies then run ``flutter pub get``

```yaml
  dependencies:
    daakia_vc_flutter_sdk: ^4.5.0
```



## Android
We require a set of permissions that need to be declared in your AppManifest.xml. These are required permissions

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.your.package">
  <!-- Camera & Audio -->
  <uses-feature android:name="android.hardware.camera" />
  <uses-feature android:name="android.hardware.camera.autofocus" />
  <uses-permission android:name="android.permission.CAMERA" />
  <uses-permission android:name="android.permission.RECORD_AUDIO" />
  
  <!-- Network -->
  <uses-permission android:name="android.permission.INTERNET" />
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
  <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
  <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
  
  <!-- Bluetooth -->
  <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
  <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
  <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
  
  <!-- Foreground Service (Meeting Notifications & Screen Share) -->
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
  
  <!-- Notifications (Android 13+) -->
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
  
  <!-- Storage -->
  <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
  <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
  <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
  ...
</manifest>
```

### ℹ️ Permission Details

- **Foreground Service Permissions** (new in v4.4.1):
  - `FOREGROUND_SERVICE`: Required for background meeting notifications
  - `FOREGROUND_SERVICE_MEDIA_PLAYBACK`: For meeting audio when app is backgrounded
  - `FOREGROUND_SERVICE_MEDIA_PROJECTION`: **Required for screen sharing on Android 10+**
  
- **POST_NOTIFICATIONS**: Required for meeting notifications on Android 13+

These permissions are **automatically merged** from the SDK's manifest. You don't need to manually add them unless your app targets Android versions that require explicit declaration.

## 🪟 Picture-in-Picture (PiP) Support (Android Only)

Daakia SDK supports **Picture-in-Picture (PiP)** mode on Android to allow users to continue their meeting while navigating away from the app.

📱 **Note:** PiP is currently available only on Android. iOS support will be added in a future release.

### Android Setup

1. **Update `AndroidManifest.xml`**

    ```xml
    <application>
      <activity
              android:name=".MainActivity"
              android:supportsPictureInPicture="true">
      </activity>
    </application>
    ```

2. **Update `MainActivity.kt`**

   Change your activity from:

    ```kotlin
    import io.flutter.embedding.android.FlutterActivity

    class MainActivity: FlutterActivity()
    ```

   to:

    ```kotlin
    import cl.puntito.simple_pip_mode.PipCallbackHelperActivityWrapper

    class MainActivity : PipCallbackHelperActivityWrapper()
    ```

## iOS

### Required Info.plist Permissions

All of the following entries **must** be present in your `Info.plist`. Apple will reject your App Store submission if any purpose string is missing — even if your app doesn't call the API directly, a dependency may reference it.

```xml
<dict>
  ...
  <!-- Required: video conferencing -->
  <key>NSCameraUsageDescription</key>
  <string>$(PRODUCT_NAME) uses your camera for video conferencing</string>

  <!-- Required: audio conferencing -->
  <key>NSMicrophoneUsageDescription</key>
  <string>$(PRODUCT_NAME) uses your microphone for audio conferencing</string>

  <!-- Required: sharing images in chat -->
  <key>NSPhotoLibraryUsageDescription</key>
  <string>$(PRODUCT_NAME) accesses your photo library to share images in the conference chat</string>

  <!-- Required: keep audio running when app is backgrounded -->
  <key>UIBackgroundModes</key>
  <array>
    <string>audio</string>
  </array>
  ...
</dict>
```

> **Note:** `NSPhotoLibraryUsageDescription` is required by the SDK's chat attachment feature. Omitting it will cause App Store submission to fail even if the user never picks a photo.

To keep audio running when the app is backgrounded, also enable **Background Modes → Audio, AirPlay, and Picture in Picture** in Xcode under your target's Capabilities tab.

### Minimum Deployment Target

For iOS, the minimum supported deployment target is 14.0. Add the following to your Podfile:

```ruby
platform :ios, '14.0'
```

You may need to delete `Podfile.lock` and re-run `pod install` after updating the deployment target.

### Podfile Permission Macros

The SDK uses [`permission_handler`](https://pub.dev/packages/permission_handler) to check and request camera/microphone access at the OS level. On iOS, you must explicitly enable these permissions in your `Podfile`'s `post_install` block, otherwise permission checks will always return denied and the controls will not function correctly.

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_CAMERA=1',
        'PERMISSION_MICROPHONE=1',
      ]
    end
  end
end
```

After updating your Podfile, run:

```bash
cd ios && pod install
```
## Usage/Examples

```dart
import 'package:daakia_vc_flutter_sdk/daakia_vc_flutter_sdk.dart';

await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => DaakiaVideoConferenceWidget(
                    meetingId: meetingUID,
                    secretKey: licenseKey,
                    isHost: isHost,
                    configuration: DaakiaMeetingConfiguration (optional),
                  ),
                ),
              );
```

Use ``DaakiaVideoConferenceWidget`` to start the meeting.


## Parameters

To run the `DaakiaVideoConferenceWidget`, you will need to pass the following parameters:

- **`meetingId`** (`String`):  
  This parameter is required to join a specific meeting. It helps identify the unique meeting to which the user will connect.

- **`secretKey`** (`String`):  
  This is a license key that grants access to the meeting service. It is necessary for secure access.

- **`isHost`** (`bool`, optional):  
  This optional parameter defines the user's role. When set to `true`, the user will join as the host of the meeting; otherwise, they will be a participant.

- **`configuration`** (`DaakiaMeetingConfiguration`, optional):
> Provides advanced customization like metadata and participant name behavior.  
> For full details, see [DaakiaMeetingConfiguration Documentation](doc/DaakiaMeetingConfiguration.md)


## Obtaining Meeting ID and License Key

To use the Daakia Video Conference SDK, you will need a `meetingId` and a `secretKey` (license key). These are required for accessing and initiating meetings.

**How to Obtain:**

* **Contact Us:** Reach out to us directly at [contact@daakia.co.in](mailto:contact@daakia.co.in). Our team will assist you in setting up your account and providing the necessary credentials.
* **Visit Our Website:** You can also find more information and request access by visiting our website: [https://www.daakia.co.in/](https://www.daakia.co.in/).

We will guide you through the process of creating meetings and obtaining your unique license key.

## 📊 Optional: Datadog Logging

The SDK supports **Datadog integration** for advanced logging, monitoring, and crash reporting.  
This is **optional** — your app will run normally without it.

If enabled, all SDK-related logs are automatically sent to Datadog.  
You don’t need to call any manual log functions — everything is handled internally by the SDK.

### Initialization

To enable Datadog, initialize the service at app startup (e.g., in `main.dart`):

```dart
import 'package:daakia_vc_flutter_sdk/service/daakia_vc_datadog_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DaakiaVcDatadogService.initialize(
    clientToken: "<YOUR_DATADOG_CLIENT_TOKEN>",
    env: "<YOUR_ENV>",
    serviceName: "<YOUR_SERVICE_NAME>",
    applicationId: "<YOUR_DATADOG_APPLICATION_ID>",
    version: "<YOUR_APP_VERSION>",
  );

  runApp(const MyApp());
}
```

👉 You can obtain the required **Datadog credentials** in the same way as the **`meetingId`** and **`secretKey`** — by reaching out to our team.

## Screen Share

### Android

Screen sharing is supported on Android 10+. The SDK uses a 
[media projection foreground service](https://developer.android.com/develop/background-work/services/fg-service-types#media-projection) for this functionality.

**Required permissions** (automatically merged from SDK's manifest):
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_MEDIA_PROJECTION` (required for screen capture)
- `POST_NOTIFICATIONS` (for Android 13+)

**⚠️ v4.4.1 Update**: For Android versions < 14, update your app's `AndroidManifest.xml` to declare the service with `mediaProjection` type only:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
  
  <application>
    ...
    <service
        android:name="de.julianassmann.flutter_background.IsolateHolderService"
        android:enabled="true"
        android:exported="false"
        android:foregroundServiceType="mediaProjection" />
  </application>
</manifest>
```

> **Note**: In v4.4.1, the `foregroundServiceType` was changed from `"mediaProjection|microphone|camera"` to only `"mediaProjection"` to fix Android 16 compatibility issues. Remove `FOREGROUND_SERVICE_CAMERA` and `FOREGROUND_SERVICE_MICROPHONE` permissions if they were previously declared.

### iOS
On iOS, screen sharing requires a broadcast extension to capture content from other apps. Refer to the [iOS setup guide](example/ios/README.md) for detailed instructions.
## Support

For support, email contact@daakia.co.in.