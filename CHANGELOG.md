# CHANGELOG

## v4.6.0-SNAPSHOT – Unreleased

> **Snapshot, not released yet.** The final version number and date are set when this is published.
> Requires **Flutter 3.38+ (Dart SDK ^3.10.0)**. After upgrading, run `flutter clean && flutter pub get`.

### ⚠️ Migration
- **LiveKit upgraded from 2.7 to 2.13.** LiveKit 2.7 no longer builds on current Flutter / Xcode, and LiveKit
  2.12+ needs Flutter 3.38+ and Dart 3.10+. Speaker, earpiece and headset behaviour is kept the same as before.
- **`DaakiaSdk.initialize(baseUrl:)` now takes the unversioned API root**, e.g. `https://api.daakia.co.in/`.
  Each endpoint now adds its own API version, so drop any `/v2.0/` suffix from a custom base URL.

### 🚀 New Features
- **Live Whiteboard Collaboration** — Collaborate on the whiteboard live from mobile, with host controls.
- **Landscape Meeting Layout** — The meeting screen now supports landscape.
- **New Pre-Join Page** — Redesigned pre-join page with a two-column landscape layout, the user's avatar in the
  camera-off preview, and a styled mic/camera permission dialog with "ask again" and Settings options.
- **Guest Join** — Guest mode for password-protected meetings, guest user identification, and role-wise colours.
- **Meeting-Ending Warnings** — Two-tier warnings with a live countdown, inline extend, a 10-minute heads-up for
  moderators, and an end-of-meeting chime that hosts can turn off.
- **Workshop Mode** — Everyone is alerted when workshop mode changes; raised hands get a workshop actions menu.
- **Join Diagnostics** — Network diagnostics and clear messages when joining fails; a failed join is retried
  without media.
- **`DaakiaMeetingConfiguration.userEmail`** — Pass the signed-in user's email so the backend can match
  pre-invited co-hosts. It is not shared with other participants.
- **Same-Device Sessions** — A stable, hashed device id is sent when joining, so rejoining from the same device
  no longer shows the duplicate-device sheet.
- **Mic and Audio Output Feedback** — The mic button shows a spinner while switching, is dimmed with a
  "Reconnecting…" message during reconnects, and shows a message if the switch fails.
- **Remove Participant Confirmation** — Hosts confirm before removing a participant.

### 🧩 Improvements
- **Audio routing:** Wired and USB-C headsets are detected like Bluetooth ones, Earpiece is hidden while a
  headset is connected, and the chosen output is restored after a phone call.
- **Android mic:** The mic follows the selected output: the phone's mic on Speaker, the headset's own mic on
  the headset.
- **Audio output picker:** Updates at once and ignores taps on the current output.
- **Diagnostics:** Added audio diagnostics logging (`audio_diag`). Sentry noise is reduced (no info logs or
  reconnect attempts, only bad-response API errors), and backend type changes are reported.
- **Resilience:** Type changes in the meeting details payload are tolerated, and API connection errors name the
  likely cause.
- **Chat:** The unread badge is anchored to the chat tab label.
- **Dependencies:** `dio` ^5.10.0, `timezone` ^0.9.0.

### 🐞 Bug Fixes
- **Android meeting service:**
  - Fixed an orphaned meeting service and notification.
  - The service now waits for a pending foreground start before stopping.
  - It doesn't start if the meeting was stopped during the permission check.
  - Notification actions now go only to the app instance that started the meeting.
- **Reconnects:** "Connection Lost" is now shown when a reconnect replaces the user's own session. Only the
  first disconnect event is handled, and the reconnecting banner is cleared when the meeting ends.
- **Back button:** Now closes the open sheet or page instead of leaving the meeting.
- **Keyboard:**
  - Pre-join: tapping outside the fields closes the keyboard.
  - Participants: search and rename stay above the keyboard.
  - Chat: the keyboard no longer carries across tabs or hides the input.
  - Captions: the language search stays above the keyboard in landscape.
- **Pre-join:**
  - Host email/PIN verification works in landscape and with the keyboard open.
  - Host mic/camera locks are respected.
  - The password is kept on rotation.
- **Meeting end:** Participants can rejoin after a meeting is extended, and `end_date` is used for the meeting
  end time.
- **Layout:** The screen-share request dialog and bottom sheets stay within short screens. All participant roles
  are shown, and the duplicate Rename option is removed.

## v4.5.2 – (2026-07)

### ⚠️ Migration
- **`secretKey` is now optional and deprecated** on `DaakiaVideoConferenceWidget` — set it once via
  `DaakiaSdk.initialize(secret: ...)` at app startup instead. The old flow still works but will be removed
  in a future major version. See the [Migration Guide](doc/MigrationGuide.md).

### 🚀 New Features
- **Duplicate Identity Handling** — Detects multi-device/duplicate joins and shows a modal dialog with platform-specific guidance instead of a snackbar; skipped for guest users.
- **SDK Theme Isolation** — Introduced an isolated SDK theme applied consistently across pre-meeting and in-meeting screens, replacing ad-hoc theme usage in `Room`.
- **Invited Participants & Reminder Flow** — Track invited participants and send join reminders, with a "remind all" action.
- **Participant Quick Actions** — Tap a participant tile to open a quick-actions bottom sheet, including a "You" badge for the local participant.
- **Advance Password / Join Status Improvements** — Track participant join status, update participant email before the joining-status notification, and refine password verification.
- **Screen-Share Paused State UI** — Visual indicator when screen sharing is paused.
- **Call Terminology Support** — `DaakiaMeetingConfiguration.useCallTerminology` support in `RoomPage`, with documentation.
- **End Meeting Confirmation** — Added a confirmation dialog to `EndMeetingBottomSheet`.

### 🧩 Improvements
- Centralized participant action logic into a unified specification.
- Refactored private chat navigation and initialization/event subscription handling.

### 🐞 Bug Fixes
- Fixed reconnection UI flicker during network drops.
- Fixed public chat history request handling.
- Fixed remind-all button visibility.
- Normalized iOS platform identifier to lowercase.

## v4.5.1 – (2026-06)

### 🚀 New Features
- **Notification Permission Dialog (Android)** — Customizable dialog enforcing notification permission before starting screen sharing.

### 🧩 Improvements
- Debounced participant list sorting to reduce main-thread churn.

### 🐞 Bug Fixes
- Fixed concurrent screen-share actions causing ANRs.
- Fixed ANRs during app resume by refactoring `restartIfActive`.
- Fixed cleanup and navigation on all room disconnect events.
- Added missing microphone/camera foreground service types to `DaakiaMeetingService`.
- Fixed screen-share service availability handling on Android 14+.

## v4.5.0 – (2026-06)

> **Major release.** Requires **Flutter 3.22+ (Dart SDK ^3.8.0)**. After upgrading, run `flutter clean && flutter pub get` to avoid conflicts from major dependency updates.

### 🚀 New Features
- **Screen-Share Annotation** — Draw and annotate over shared screens in real time. Includes host controls to allow/deny annotation, annotation toolbar, and permission dialog.
- **Audio Output Device Selection** — Users can switch audio output devices (earpiece, speaker, Bluetooth) via a bottom sheet. Improved iOS audio routing and default speakerphone handling.
- **Save Chat Attachments to Downloads** — Participants can save received files to the device Downloads folder on both Android and iOS.
- **Camera in Chat Attachment Picker** — Added camera option alongside file picker in the chat attachment sheet.
- **Hide Participant List in Webinars** — New `hideParticipantDrawer` host control to show/hide the participant panel in webinar mode.
- **Pinch-to-Zoom for Active Speaker** — Pinch-to-zoom and reset button on the active speaker video tile.
- **Workshop Mode in Webinar Controls** — Workshop mode is now supported alongside webinar mode in participant controls.
- **Quick Actions Menu for Participants** — Tap a participant tile to get a quick-actions bottom sheet for faster host controls.
- **iOS Audio Interruption Handling** — Meetings gracefully handle incoming phone calls and audio session interruptions on iOS.
- **Custom Base URL + SDK Initialization** — Support for custom API URL configuration and explicit SDK initialization.
- **Participant Platform Metadata** — Client platform (iOS/Android/etc.) is now sent as part of join metadata.

### 🧩 Improvements
- Unified `getHostControls` API endpoint; deprecated individual per-control endpoints.
- Replaced `ScaffoldMessenger` with a custom `RoomNotification` overlay for in-room toasts.
- Participant list header now shows total participant count.
- Staggered non-critical permission requests on room init for faster join.
- Moved local screen-share overlay from room level into the participant widget.
- Co-hosts can now configure auto-recording.

### 🐞 Bug Fixes
- Fixed URI decoding in `getFileName` for file names with special characters.
- Fixed stale raised-hand state for disconnected participants.
- Fixed participant drawer visibility state assignment.
- Fixed co-host rejoin authorization with stale host token.
- Fixed `DaakiaPiP` method channel error handling on unsupported Android versions.
- Fixed recording permission validation before auto-recording starts.
- Fixed accidental meeting exit when navigating back from the transcription screen.
- Fixed local sharer not seeing incoming annotations on their own shared screen.
- Fixed MIME type resolution for varied file link formats.
- Fixed status bar visibility and background color in the RTC room.

### 📦 Dependency Updates
- Dart SDK: `^3.5.3` → `^3.8.0`
- `livekit_client`: `^2.5.3` → `^2.7.0`
- `flutter_webrtc`: `^1.1.0` → `^1.4.0`
- `connectivity_plus`: `^6.1.5` → `^7.0.0`
- `device_info_plus`: `^11.5.0` → `^12.2.0`
- `datadog_flutter_plugin`: `^2.13.1` → `^2.16.1`
- Added: `image_picker: ^1.1.2`

---

## v4.4.1 – (2026-05)

### 🐞 Bug Fixes
- **Android 16 (targetSDK=36) Screen Share Crash**
    - Fixed `SecurityException: Media projections require a foreground service of type ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION` on Android 16.
    - Resolved race condition when rapidly stopping and restarting screen share on any Android version.
    - Implemented synchronous foreground service type management via `DaakiaMeetingService`.

- **Meeting Notifications & Background Service**
    - Refactored Android meeting notification handling from `flutter_background` to native `DaakiaMeetingService`.
    - Fixed notification lifecycle and foreground service type management on Android.
    - Improved meeting service stability across Android versions (10+).

- **Live Captions/Transcription**
    - Fixed transcription screen lifecycle and language selection state management.
    - Added snackbar notification when live captions are stopped.
    - Improved language selection defaults and persistence.

### 🎨 Improvements

- **Screen Sharing (Android)**
    - Replaced async `flutter_background` calls with synchronous `DaakiaMeetingService.startScreenShare()` / `stopScreenShare()`.
    - No more race conditions on rapid screen share toggling.
    - Cleaner separation of foreground service concerns (mediaPlayback vs mediaProjection).

- **iOS Meeting Service**
    - Added native `DaakiaMeetingService` with AVAudioSession management for iOS.
    - Improved background audio handling during meetings.
    - Better lifecycle management for audio playback on iOS.

### 📱 Platform-Specific
- **Android**: Added `FOREGROUND_SERVICE_MEDIA_PROJECTION` permission and dynamic foreground service type upgrades.
- **iOS**: Implemented `DaakiaMeetingService` with proper AVAudioSession configuration for meeting audio continuity.

---

## v4.4.0 – (2026-03)

### 🚀 New Features
- **Skip Pre-Join Flow**
    - Added `skipPreJoinPage` option to bypass pre-join UI for faster meeting join.
- **Default Media State Configuration**
    - Added support to configure **microphone and camera default state** before joining a meeting.
- **UI Enhancements (Example App)**
    - Added **edge-to-edge UI support** for improved visual experience.

---

### 🧩 Improvements
- Improved meeting join experience for **faster and automated flows**
- Enhanced developer control over **initial media states (mic/camera)**
- Updated documentation for `skipPreJoinPage` with **strict usage conditions**

---

### 🐞 Bug Fixes
- Fixed issue with **automatic navigation when meeting ends** while pre-join is skipped
- Improved meeting closure and navigation handling across flows

## v4.3.0 – (2025-12)

### 🚀 New Features
- **Screen-Share Permission System**
    - Host controls to enable/disable screen sharing.
    - Screen-share consent model & API.
    - Screen-share request/response mechanism.
    - “Allow Screen Share for All” support.
    - Screen-share request dialog + request list.
- **Chat System Enhancements**
    - **Unread counters** for private chat with badges and sync logic.
    - **Pinned messages** for public & private chat with navigation + highlight.
    - **Reply message system** with models, UI, preview widgets & sender-side logic.
    - **Edit message feature** with draft support, models, UI updates & sync logic.
    - **Message reactions** with reaction bar, mapping, details sheet & sender logic.
    - **Copy message** functionality added.
- **Chat Attachments**
    - File-type preview widget with link/file detection.
    - Attachment permission control via host settings & API sync.
    - Receiver-side logic and restriction handling.
- **Webinar Mode**
    - Webinar permissions model & API.
    - Audio/video permission sync for Host/Co-Host.
    - Sync older audio/video states when joining.
- **Live Captions / Transcription**
    - New caption data model and constants.
    - Updated logic through `rtc-registerTextStreamHandler`.
    - Register/unregister caption handlers to prevent data leak.
    - Stopped pooling for caption start API.

### 🧩 Improvements
- Major chat code refactor (public, private, and message bubble).
- Enhanced UI/UX for emoji reactions and chat interactions.
- Improved navigation to pinned and replied messages.
- Reusable host-control switch with enable/disable state.
- Multiple null-handling, JSON mismatch, and model consistency fixes.

### 🐞 Bug Fixes
- Fixed **screen share event not going from iOS** and removed duplicates.
- Fixed private chat reaction issues for sender messages.
- Fixed unread count not updating.
- Fixed reply/reaction visibility on deleted messages.
- Fixed CDN link handling and file-type detection.
- General bug fixes and code cleanup.

## v4.2.1 – (2025-10)

### 🚀 New Features
- **Pin to Screen:** Added the ability to pin participants’ video to the main screen for focused view.
- **Restrict Multiple Screen Shares:** Prevents multiple users from sharing their screen simultaneously.
- **Guest Name Storage:** Stores guest user names for better participant identification in meetings.
- **Background Support (Android):** Added a **foreground service** to improve meeting stability and ensure continued operation when the app is in the background.
- **Picture-in-Picture (PiP):** Added PiP mode support for Android to allow multitasking during meetings.
- **Meeting Alerts & Actions:** Added in-meeting alerts and real-time action handling for better event visibility.
- **Recording Flow Update:** Improved recording start/stop logic with `dispatchId` integration, failsafe handling, and UI enhancements.

### 🧩 Improvements
- **UI/UX Enhancements:** General interface refinements and layout improvements.
- Enhanced recording reliability and button state control.
- Improved meeting flow stability and background performance.

---

## v4.2.0 – (2025-09)

### 📱 Android Support
- Added **16KB screen size support** for better compatibility on larger devices.

### 📦 Dependency Updates
- Upgraded to the **latest library versions** for improved stability, security, and long-term support.

### 🛠 Bug Fixes & Improvements
- Various bug fixes and performance enhancements.

---

## v4.1.0 – (2025-09)

### 📊 Analytics & Monitoring
- Implemented **Datadog logging** for improved observability and performance tracking.

---

## v4.0.0 - (2025-08)

### 🚀 New Features
- **Metadata Config:** Introduced configurable metadata support for meetings.
- **Transcript Download:** Participants can now download meeting transcripts.
- **Connectivity Status:** Added in-meeting connectivity banners and participant connectivity indicators.
- **Participant Attendance:** Added tracking of participant attendance.
- **Chat Restrictions:** Host can restrict chat to “Everyone”, “Host & Co-host only”, or “Disabled”.
- **Consent Flow:** Introduced recording/streaming consent popups for participants.
- **SDK Config:** Added centralized configuration for SDK features.
- **Co-Host Management:** Improved APIs and controls for assigning/removing co-hosts.
- **Role-Based Features:** Feature gating based on user role (host, co-host, participant).

### 🛠 Bug Fixes & Improvements
- Fixed memory leaks and optimized participant UI updates.
- Improved transcript accuracy and fixed missing metadata issues.
- Fixed iOS navigation and permission handling.
- Improved state management for recording and live streaming.
- Various stability, crash, and UI fixes across Android & iOS.
- Refactored participant structure for better scalability.
- General performance optimizations and dependency upgrades.

---

## v3.1.2 (2025-04)

### 🚀 New Features
- **Whiteboard (Preview):** Introduced collaborative whiteboard functionality for real-time visual collaboration during meetings.

### 🛠 Bug Fixes & Improvements
- Various bug fixes and performance enhancements.
- Minor UI adjustments for a smoother experience.

## v3.0.1 (2025-04)

### 🚀 New Features
- **Live Transcription:** Automatically transcribe meetings in real time.
- **Translation:** Support for multilingual translations during meetings.
- **End Meeting:** Hosts can now end meetings for all participants.
- **Scheduled Meeting End:** Meetings will now automatically end at the scheduled time based on the subscription plan.
- **Co-Host Modification:** Enhanced co-host management capabilities.
- **Participant Name Change:** Participants can update their display names during a meeting.
- **Auto-Recording:** Meetings now support automatic recording upon start.
- **Meeting Extension:** Host can extend meetings based on their subscription plan.

### 🛠 Bug Fixes & Improvements
- Stability enhancements and performance optimizations.
- General UI and user experience improvements.
- Resolved caching problems affecting co-host functionality.
- Upgraded dependencies for better performance and compatibility.


## 2.1.3 (2025-01) _(Internal Release)_

**Enhancements:**

* **Upload attachments:** Users can now share files within both public and private chat rooms.
* **Web-View:** Added support for displaying web content directly within the chat interface for chat links.
* **Improved UI:** Enhanced the user interface for different media types (images, videos, etc.) for a better visual experience.

## 2.0.1 (2024-12) _(Internal Release)_

- **Bug Fixes**:
  - Null-Safety for participant.
  - Lobby mode bug fixes.
  - Navigation bug fixes.

## 2.0.0 (2024-12) _(Internal Release)_

- **New Features**:
  - Added raise hand feature.
  - Webinar mode & Host controls added.
  - Private & Public chat added.
  - Reaction added.
  - Password Protected event added.
  - Lobby Mode added.
  - Screen Share Added for Android & iOs.
  - PIP Mode added in Android (iOs don't support right now)
- **Bug Fixes**:
  - Connection bug fixes.
  - Permission issue fixed in iOs.

## 1.0.0 (2024-11) _(Internal Release)_

- **Initial Release**:
  - Implemented Web-RTC integration for real-time video and audio calls.
  - Added core functionality for video conferencing.
  - Introduced participant management with local and remote participants.
  - Added cloud recording.