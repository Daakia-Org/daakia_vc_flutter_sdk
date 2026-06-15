# DaakiaMeetingConfiguration

The `DaakiaMeetingConfiguration` class allows advanced customization for the Daakia Video Conference SDK.  
It includes optional metadata, participant name behavior, pre-join flow behavior, and default local media state.

> **Note:** This is optional. If not provided, default behavior will be used.

---

## Table of Contents
- [Usage](#usage)
- [Metadata](#metadata)
- [Participant Name Configuration](#participant-name-configuration)
- [Skip Pre-Join Page](#skip-pre-join-page)
- [Default Mic and Camera State](#default-mic-and-camera-state)
- [Save Attachments to Downloads](#save-attachments-to-downloads)
- [Examples](#examples)
- [Best Practices](#best-practices)

---

## Usage

Pass an instance of `DaakiaMeetingConfiguration` when launching a meeting:

```dart
import 'package:daakia_vc_flutter_sdk/daakia_vc_flutter_sdk.dart';

await Navigator.push<void>(
  context,
  MaterialPageRoute(
    builder: (_) => DaakiaVideoConferenceWidget(
      meetingId: meetingUID,
      secretKey: licenseKey,
      isHost: isHost,
      configuration: DaakiaMeetingConfiguration(
        metadata: {'identifier': 'user123', 'email': 'user@example.com'},
        participantNameConfig: ParticipantNameConfig(
          name: 'John Doe',
          isEditable: false,
        ),
        skipPreJoinPage: false,
      ),
    ),
  ),
);
```

---
## Metadata

The `metadata` field allows you to provide additional, dynamic information about the participant. It is optional and marked as **[BETA]**, which means it may change in future versions.

### Features

- Attach custom key-value pairs for participants (e.g., `"name"`, `"email"`, `"role"`, etc.).
- Useful for advanced features like **attendance tracking**, **analytics**, or **personalization**.
- If using the **attendance tracking feature**, ensure to include a unique `"identifier"` key in the metadata.

### Example

```dart
DaakiaMeetingConfiguration(
  metadata: {
    'identifier': 'user123',
    'name': 'John Doe',
    'email': 'john.doe@example.com'
  },
);
```

---
## Participant Name Configuration

The `participantNameConfig` field allows you to control the behavior of the participant name field in the pre-join screen. It is optional.

### Features

- **Set a default name:** Pre-fill the participant name with a value.
- **Control editability:** Decide whether participants can edit their name before joining the meeting.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `name` | `String` | The default display name for the participant. If not provided or empty, the name field will always be editable. |
| `isEditable` | `bool` | Determines if the participant can modify the name in the pre-join screen. Defaults to `true` if `name` is empty. |

### Example

```dart
DaakiaMeetingConfiguration(
  participantNameConfig: ParticipantNameConfig(
    name: 'John Doe',
    isEditable: false,
  ),
);
```

---
## Skip Pre-Join Page

The `skipPreJoinPage` flag lets you bypass the interactive pre-join UI
and start joining immediately with a loader screen.

### Use Cases

-   1:1 video call flows where camera/mic/name setup UI is not needed\
-   Fast join experiences where everything is pre-configured by the host
    app

------------------------------------------------------------------------

### ⚠️ When to Use

This flag should **only be enabled when the meeting does NOT require any
pre-join interaction**.

Ensure the meeting is created with the following API configuration:

``` json
{
  "allow_common_password": false,
  "is_lobby_mode": false,
  "allow_standard_password": false,
  "is_participant_mode": true
}
```

------------------------------------------------------------------------

### ❗ Important Notes

-   All the above conditions **must be strictly satisfied**
-   If any of these flags differ, enabling `skipPreJoinPage` will result
    in **unexpected behavior or join failure**
-   This feature is intended only for **fully automated join flows**
    where no validation or user input is required

------------------------------------------------------------------------

### Example

``` dart
DaakiaMeetingConfiguration(
  participantNameConfig: ParticipantNameConfig(
    name: 'Quick Caller',
    isEditable: false,
  ),
  skipPreJoinPage: true,
);
```

---
## Default Mic and Camera State

The `enableMicrophoneByDefault` and `enableCameraByDefault` flags control the initial local media state used by the SDK.

### Behavior

- Both fields are optional.
- If not provided, both default to `false` to preserve the existing SDK behavior.
- The SDK only starts with mic/camera enabled when the corresponding field is explicitly set to `true`.
- If the required permission is already granted, the SDK starts with that device enabled.
- If permission is not granted yet, the SDK safely falls back to the disabled state.
- When `skipPreJoinPage` is `true` and you want mic/camera to be enabled immediately, request the corresponding permission before opening the SDK.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `enableMicrophoneByDefault` | `bool` | Controls whether the local microphone should start enabled. Defaults to `false`. Falls back to disabled if microphone permission is unavailable. |
| `enableCameraByDefault` | `bool` | Controls whether the local camera should start enabled. Defaults to `false`. Falls back to disabled if camera permission is unavailable. |

### Example

```dart
DaakiaMeetingConfiguration(
  skipPreJoinPage: true,
  participantNameConfig: ParticipantNameConfig(
    name: 'Quick Caller',
    isEditable: false,
  ),
  enableMicrophoneByDefault: true,
  enableCameraByDefault: false,
);
```

---
## Save Attachments to Downloads

The `saveAttachmentToDownloads` flag controls whether received chat file attachments are saved to a persistent, user-accessible location instead of a temporary cache directory.

> **Default:** `false` — attachments are stored in a temporary directory and may be cleared by the OS.

### Behavior

| Platform | Where the file is saved |
|----------|------------------------|
| Android API 29+ | Public Downloads folder via MediaStore (no permission needed) |
| Android API < 29 | Public Downloads folder via direct file copy (requests `WRITE_EXTERNAL_STORAGE` at runtime) |
| iOS | `Documents/Downloads/` inside the app sandbox |

- Only **received** attachments are saved to downloads. Files sent by the local user are unaffected.
- On Android the file is accessible in any file manager app immediately after saving.
- On iOS the file is saved persistently but is only visible in **Files > On My iPhone > [App Name] > Downloads** if the host app adds `UIFileSharingEnabled` to its `Info.plist` (see iOS setup below).

### Permissions

#### Android

No changes to your `AndroidManifest.xml` are required. The SDK's manifest already declares:

```xml
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />
```

This is automatically merged into your app. On Android 10+ (API 29+) no storage permission is needed at all. On Android 9 and below, the SDK requests `WRITE_EXTERNAL_STORAGE` at runtime **only when this feature is enabled and the user taps a received attachment** — it is never requested otherwise.

> **Existing users not using this feature:** no impact. The permission is declared in the merged manifest but the runtime request is never triggered.

#### iOS

No mandatory changes are required. The file is always saved successfully to the app's `Documents/Downloads/` directory.

To make saved files visible to the user in the **Files app**, add these keys to your host app's `Info.plist`:

```xml
<key>UIFileSharingEnabled</key>
<true/>
<key>LSSupportsOpeningDocumentsInPlace</key>
<true/>
```

Without these keys the feature still works — files are saved persistently — but users cannot browse them through the Files app.

> **Existing users not using this feature:** no `Info.plist` changes are needed and no behavior changes occur.

### Example

```dart
DaakiaMeetingConfiguration(
  saveAttachmentToDownloads: true,
);
```

---
## Examples

### Example 1: Basic Metadata

```dart
DaakiaMeetingConfiguration(
  metadata: {
    'identifier': 'user123',
    'email': 'user@example.com',
  },
);
```
### Example 2: Participant Name Configuration

```dart
DaakiaMeetingConfiguration(
  participantNameConfig: ParticipantNameConfig(
    name: 'John Doe',
    isEditable: false,
  ),
);
```

### Example 3: Combined Metadata and Participant Name

```dart
DaakiaMeetingConfiguration(
  metadata: {
    'identifier': 'user123',
    'email': 'user@example.com',
  },
  participantNameConfig: ParticipantNameConfig(
    name: 'John Doe',
    isEditable: true,
  ),
  skipPreJoinPage: false,
);
```

> ✅ Tip: Including a unique `identifier` key in `metadata` is recommended if you plan to use attendance tracking features.

---
## Best Practices

- **Unique Identifier:** Always include a unique `"identifier"` key in `metadata` for tracking participants reliably.
- **Minimal Metadata:** Only include the necessary keys in `metadata` to reduce payload size and improve performance.
- **Editable Names:** Set `isEditable` in `ParticipantNameConfig` thoughtfully. If participants shouldn’t change their names, set it to `false`.
- **Consistency:** Use consistent keys and naming conventions in `metadata` across all participants for easier data handling.
- **Security:** Avoid storing sensitive information in `metadata` as it may be accessible on the client side.
- **Future-Proofing:** Since this is a BETA feature, keep your implementation flexible to accommodate future updates or new fields.
- **Permission Flow:** If you use `skipPreJoinPage` and expect mic/camera to start enabled, request camera/microphone permission in your app before opening the SDK. Otherwise the SDK joins with those devices disabled.
- **Save Attachments:** `saveAttachmentToDownloads` is opt-in and off by default. Enable it only when you want received files to persist after the meeting. On iOS, pair it with `UIFileSharingEnabled` in `Info.plist` so users can find their files in the Files app.
