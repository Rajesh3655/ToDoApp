# Supare

An offline Flutter app for personal tasks, native reminders, and an encrypted family document wallet. Android application ID / iOS bundle ID: `app.supare.offline`. Version `1.0.0+1`.

## Open the project

Use this existing checkout; each cloud task already has its own isolation. Do not create a Git worktree unless requested.

```sh
cd /workspace/ToDoApp/supare
source tool/environment.sh
bash tool/setup.sh
flutter analyze
flutter test
flutter run -d <device-id>
```

Pinned SDK: Flutter 3.35.7 / Dart 3.9. Android: JDK 21 (Java/Kotlin bytecode 17), platform 36, build tools 35.0.0, minimum Android 7/API 24, target API 36. iOS: minimum 13, macOS/Xcode and CocoaPods required. Build-time package/tool downloads use the Internet; the installed app has no backend or network client.

Official build destinations include `github.com`, `storage.googleapis.com`, `pub.dev`, `dl.google.com`, `repo.maven.apache.org`, `plugins.gradle.org`, `plugins-artifacts.gradle.org`, `services.gradle.org`, `downloads.gradle.org`, `maven.google.com`. In a managed environment, allow needed destinations in settings. Use inherited proxies and trust; never disable TLS or checksum verification.

## Features

- Today and Upcoming lists, task CRUD, completion history, restore, star, local search, rescheduling and 5/10/15-minute snooze; daily/weekly/monthly/every-N-days recurrence.
- Android AlarmManager + lock-screen alarm activity, audible foreground alarm service, notification actions, encrypted reboot scheduling. Requires device permissions. Force-stop and manufacturer restrictions can prevent delivery.
- iOS local notifications with Done/Snooze/Stop actions. This implementation does **not** integrate AlarmKit and does not provide continuous ringing/full-screen alarms on iOS. See [iOS limitations](docs/IOS.md).
- PIN and device-authenticated wallet, family profiles, optional metadata/custom fields, PDF/image import, on-device camera crop, masked individual copy actions, local search, recent/favorites, replacement/deletion, native preview/share, generic expiry reminders.
- AES-256-GCM encrypted SQLite record payloads and document files; device-only protected key storage. Argon2id-derived, authenticated password backups, manual export and validated merge/replace restore. No automatic backup/sync, analytics, ads, accounts or external APIs. OCR and natural-language parsing are not included (optional in the request).

Read [security boundaries](docs/SECURITY.md), [Android behavior](docs/ANDROID.md), and the [physical-device acceptance tests](docs/DEVICE_TESTS.md) before relying on the app for critical reminders or irreplaceable documents.

## Release builds

```sh
source tool/environment.sh
bash tool/build_android.sh
```

Outputs go to `releases/android/`. Without an external production identity, the build uses a generated **test key**, even though Flutter is in release mode. Such builds are for evaluation, not Play Store publication. See [release instructions](docs/RELEASE.md). Never commit production signing secrets.

For actual validation results and blockers see [BUILD_VERIFICATION.md](docs/BUILD_VERIFICATION.md). Source implementation is not proof of release readiness; unexecuted device tests and unsigned/unbuilt platforms remain outstanding.

## Optional cloud emulator

A software-only Android API 30 emulator was booted and used for actual offline plugin and native alarm tests in this environment. It does not substitute for physical-device alarm tests. Install its official packages and launch using:

```sh
source tool/environment.sh
python3 tool/sdkmanager.py emulator 'system-images;android-30;default;x86_64'
bash tool/start-emulator.sh > tool/emulator.log 2>&1 &
adb -s emulator-5554 wait-for-device
# Wait until `adb -s emulator-5554 shell getprop sys.boot_completed` returns 1.
flutter test integration_test/app_test.dart -d emulator-5554 --reporter expanded --timeout 300s
```

`tool/setup.sh` targets this Linux x64 cloud environment. On a Mac, install Flutter 3.35.7 and Xcode normally and follow `docs/RELEASE.md` for iOS builds.

## Portable source archive

Run `python3 tool/package_source.py` to create `releases/supare-source-1.0.0.zip`. The archive contains the complete portable project and tested helper scripts, excluding private keys, local machine configuration, SDKs/caches, emulator state and generated binaries. Android APK/AAB files remain separate deliverables.
