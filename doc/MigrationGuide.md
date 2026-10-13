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

After upgrading, run:

```bash
flutter clean && flutter pub get
```

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

### 3. iOS

No change is needed if you build with CocoaPods. Keep the `PERMISSION_CAMERA=1` / `PERMISSION_MICROPHONE=1`
macros in your `Podfile` (see the README's *Podfile Permission Macros* section).

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

Because the SDK now uses the latest versions of its dependencies, older versions of the same packages in
your app may conflict with it, and `flutter pub get` will fail to resolve. If that happens, upgrade
the conflicting packages in your app to their latest versions (`flutter pub upgrade --major-versions`
can help).

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
