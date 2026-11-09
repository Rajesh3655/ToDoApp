# iOS implementation and validation

Supare contains a complete Flutter Runner Xcode project with bundle ID `app.supare.offline`, deployment target iOS 13, Swift native integration, and CocoaPods configuration. No team ID, provisioning profile, signing key, or signing password is supplied.

## Implemented platform behavior

- OS-delivered local notifications using `UNUserNotificationCenter`, with Done, Snooze, and Stop actions. The Snooze text input accepts 5, 10, or 15 minutes (other input defaults to 5), keeping the category within iOS’s four-action presentation limit. Done requires device authentication. Stop leaves the task pending. Opening a notification does not mark it complete.
- One-time and recurring schedules. Recurrence is pre-scheduled for up to eight occurrences per task, with calendar-aware daily, weekly and monthly intervals, and custom day intervals. Pending notifications are capped at 60 (below the operating system's 64 limit). A capacity error is returned rather than silently discarding reminders. Reopen Supare to refresh the scheduling horizon. Native notification queues survive ordinary app termination.
- Snooze requests are scheduled directly by iOS notification actions, without requiring Flutter to be running. Native completion/snooze actions are queued for reconciliation by the Flutter data store.
- Native reminder snapshots/action IDs encrypted using CryptoKit AES-256-GCM; key stored in Keychain using `AfterFirstUnlockThisDeviceOnly`. Reminder titles necessarily appear in OS notifications as part of the reminder feature.
- Application Documents and Application Support directories are excluded from automatic backup. Native state uses file protection. No iCloud entitlements, network requests, cloud synchronization, analytics, or remote notification registration.
- Native PDF/image preview through Quick Look. Preview file paths are restricted to the app sandbox, set to complete file protection, excluded from backup, and deleted on dismissal. The Dart caller also cleans up temporary plaintext files.
- Wallet privacy cover while the application is inactive. iOS does not expose an API to reliably prevent user screenshots; the capabilities response states this explicitly.
- Face ID, camera, and photo-library usage descriptions are present. Device biometric authentication and the app PIN are provided by the Flutter core.

## AlarmKit limitation

This implementation uses local notifications on all iOS versions. It does **not** include a verified AlarmKit implementation. It does not claim continuous ringtone playback, full-screen lock-screen alarms, critical-alert entitlement, or bypass of mute, Focus or notification settings. Adding AlarmKit for supported devices and validating with the shipping Xcode/iOS SDK is a remaining platform feature. Do not advertise the iOS alarm experience as equivalent to Android's ringing alarm.

The notification fallback is real operating-system scheduling, not a Flutter timer or simulated notification. Because iOS applies notification limits and settings, delivery cannot be guaranteed. Notification permissions must be enabled by the user. Alarm-mode notifications request time-sensitive presentation on iOS 15+, subject to the user’s time-sensitive notification/Focus settings and the matching signing capability. Normal reminders use the default interruption level.

## Build on macOS

From `supare/` with Flutter 3.35.7 (or a deliberately validated newer version), Xcode and CocoaPods installed:

```sh
flutter pub get
cd ios
pod install
cd ..
flutter build ios --release --no-codesign
```

For device/archive distribution, open `ios/Runner.xcworkspace`, select an owned development team, replace the bundle ID only if needed for that team, and configure signing, Keychain Sharing, Data Protection and Time Sensitive Notifications capabilities matching `Runner.entitlements`. Never commit signing material. Then run:

```sh
flutter build ipa --release --export-options-plist=/secure/path/ExportOptions.plist
mkdir -p releases/ios
cp build/ios/ipa/*.ipa releases/ios/
```

Review App Store privacy declarations, encryption exemption and required privacy manifests for all linked SDK versions before submission. Source privacy declarations must describe the exact submitted binary.

## Validation status

The Linux environment cannot run Xcode, the iOS simulator, `pod install` against an iOS toolchain, code signing, or device tests. No iOS compilation, XCTest execution, simulator test, device alarm test, or IPA generation is claimed. Native XCTest cases are supplied in `RunnerTests` for one-time, weekly, custom and month-end recurrence; execute them on macOS with a simulator selected in the Runner scheme.

Required device validation before release: permissions allowed/denied, notification receipt with app closed, Focus/mute behavior, all notification action buttons, recurrence horizon refresh, snooze, device restart, protected-data availability, Face ID/PIN flows, app-switcher privacy, Quick Look file cleanup, clipboard lifetime, user-controlled sharing, and backup exclusion.
