![Logo](https://www.daakia.co.in/assets/images/frontend/logo-dark.svg)

# Daakia VC Flutter SDK
Integrate Daakia's video conferencing capabilities into your Flutter applications with ease.

This SDK provides a simple and efficient way to add video conferencing features to your Flutter apps, supporting both Android and iOS platforms.

## Supported Platforms
✅ **Android**  | ✅ **iOS**


# How to use



## Installation

add ``daakia_vc_flutter_sdk:`` to your ``pubspec.yaml`` dependencies then run ``flutter pub get``

```yaml
  dependencies:
    daakia_vc_flutter_sdk: ^4.4.0
```



## Android
We require a set of permissions that need to be declared in your AppManifest.xml. These are required permissions

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.your.package">
  <uses-feature android:name="android.hardware.camera" />
  <uses-feature android:name="android.hardware.camera.autofocus" />
  <uses-permission android:name="android.permission.CAMERA" />
  <uses-permission android:name="android.permission.RECORD_AUDIO" />
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
  <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
  <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
  <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
  <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
  <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
  <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
  <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
  <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
  ...
</manifest>
```

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

Camera and microphone usage need to be declared in your `Info.plist` file.

```
<dict>
  ...
  <key>NSCameraUsageDescription</key>
  <string>$(PRODUCT_NAME) uses your camera</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>$(PRODUCT_NAME) uses your microphone</string>
```

Your application can still run the voice call when it is switched to the background if the background mode is enabled. Select the app target in Xcode, click the Capabilities tab, enable __Background Modes__, and check __Audio, AirPlay, and Picture in Picture__.

Your `Info.plist` should have the following entries.

```
<dict>
  ...
  <key>UIBackgroundModes</key>
  <array>
    <string>audio</string>
  </array>
```

For iOS, the minimum supported deployment target is 12.1. You will need to add the following to your Podfile.

```
platform :ios, '12.1'
```

You may need to delete Podfile.lock and re-run pod install after updating deployment target.
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

On Android, you will have to use a
[media projection foreground service](https://developer.android.com/develop/background-work/services/fg-service-types#media-projection).

In the app's AndroidManifest.xml file, declare the service with the appropriate types and permissions as following:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <!-- Required permissions for screen share -->
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CAMERA"/>
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE"/>
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
  <application>
    ...
    <service
            android:name="de.julianassmann.flutter_background.IsolateHolderService"
            android:enabled="true"
            android:exported="false"
            android:foregroundServiceType="mediaProjection|microphone|camera" />
  </application>
</manifest>
```
### iOS
On iOS, a broadcast extension is needed in order to capture screen content from other apps. See For iOS-specific setup, refer to the [setup guide](example/ios/README.md) for instructions.
## Support

For support, email contact@daakia.co.in.