# Android implementation and release

Application ID: `app.supare.offline`. Display name: Supare. Android minimum API 24 (Android 7); compile API 36; target API 36. Flutter owns version name/code from `pubspec.yaml`. Flutter 3.35.7 sets the minimum supported SDK. Kotlin native sources are in `android/app/src/main/kotlin/app/supare/offline/`.

## Alarm operation

`AlarmManager.setAlarmClock` schedules alarm-mode tasks, with an immutable explicit PendingIntent addressed by task ID URI. Normal reminders use `setExactAndAllowWhileIdle` when available, otherwise `setAndAllowWhileIdle` and may arrive late. Each fire atomically checks the persisted due-time token and marks it fired or advances recurrence, preventing duplicate delivery of the same occurrence. Native state and pending actions are AES-256-GCM encrypted using a randomly generated nonexportable Android Keystore key. The encrypted queue reconciles user actions into Flutter after reopening with explicit acknowledgements after Dart persistence (draining does not destroy unacknowledged events); unfinished dismissed tasks remain pending.

An exact-alarm receiver starts the `mediaPlayback` foreground alarm service, which plays the device's alarm sound in a loop with alarm audio attributes, vibrates, and holds a bounded partial wakelock. Ringing stops after ten minutes to avoid unbounded battery use. Done, Stop, and Snooze 5/10/15 minutes use native receivers. Notification offers Done, Snooze 10, and Stop; the full-screen alarm activity offers all snooze choices. A second simultaneous alarm replaces the active ringing interface; the earlier task remains pending. Recurring alarms retain their future native occurrence after Done before Flutter reopens.

Boot, package replacement, time/timezone changes, and exact-access grants reschedule saved alarms. The boot receiver never starts a foreground service. Missed one-time reminders stay overdue without surprise ringing on reboot; missed recurring occurrences advance to the next future occurrence. Recurrence uses local calendar arithmetic, preserving the chosen wall-clock hour over daylight-saving transitions; monthly dates clamp at month end while retaining the original day-of-month anchor.

Android permission restrictions are surfaced through capability checks and scheduling errors. Notification permission and exact-alarm special access must be enabled before alarm-mode scheduling. Full-screen intent use is subject to Android special access and Google Play policy eligibility; if unavailable, alarms use the notification. `requestAlarmPermissions` opens one missing permission/access step per call. Recheck capabilities on resume. Normal reminders can use inexact delivery when exact access is absent.

Device volume, Do Not Disturb, manufacturer power restrictions, force-stop, permission revocation, and device shutdown can affect alarms. The app cannot promise delivery in those conditions. Full-screen task titles are intentionally visible for alarm reminders; wallet identifiers are never included.

## Privacy and preview

The release manifest does not request INTERNET or broad storage permissions. `allowBackup=false`, legacy backup exclusions, and Android 12+ data-extraction exclusions prevent automatic app data backup and transfer. No analytics/network SDK is included by the app.

The Flutter activity defaults to `FLAG_SECURE`, can relax it outside sensitive screens, and reapplies it while paused. The private native PDF/image viewer always uses `FLAG_SECURE`, accepts only app-private files/cache paths, and returns its MethodChannel result only after closing so Flutter can promptly remove the decrypted temporary file. PDF rendering is bounded to one page at a time; images are downsampled. External app sharing is user initiated through the OS share sheet. A receiving app can retain shared copies independently of Supare.

## Building

From the project root with Flutter and Android SDK configured:

```
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build appbundle --release
cd android
./gradlew :app:testReleaseUnitTest
```

The wrapper uses Gradle 8.12, Android Gradle plugin 8.9.1, and Kotlin 2.1.0. Java 17+ is required (the current environment uses Java 21). Platform SDK 36 and build tools 35.0.0 are needed. Keep TLS verification enabled and configure the managed proxy/CA for Java when required. Tools and build outputs belong under `supare/`.

Without `android/key.properties`, release optimization runs with the **test debug signing certificate**, not a production certificate. The test keystore is local at `tool/test-signing/debug.keystore`; never publish it. Release-mode builds signed with this key are suitable only for evaluation installations, not Play Store production. Root build tooling creates this local standard Android test key as needed. AABs require Play signing and a production upload key for actual distribution.

For distributable signing, create a private keystore outside version control and an ignored `android/key.properties` with `storeFile` (absolute path), `storePassword`, `keyAlias`, and `keyPassword`. Configure all four locally/securely; never commit them. The app's production signing configuration reads that file. Build and verify again, then copy actual artifacts into `releases/android/`. Remove the test installation first if Android rejects installation due to mismatched signing identity; uninstalling deletes local app data, so manually export an encrypted backup first.

## Validation status

`AlarmMathTest` contains seven tests covering one-time, daily, weekly, month-end and anchor retention, bounded custom repeat, and daylight-saving arithmetic. `AlarmStoreDeviceTest` contains three device tests covering Android Keystore encryption, stale-token rejection, duplicate-fire prevention, and durable action acknowledgement. `AlarmDeliveryDeviceTest` adds four real AlarmManager/service tests covering delivery, cancellation, a five-minute native snooze, and durable Done actions on a granted test installation. An emulator execution does not establish audible ringing or physical lock-screen behavior. Execution results are recorded in the final validation report; source presence is not a passing result.

Physical-device verification remains necessary for closed-app ringing, lock-screen presentation, notification and exact-access denial/revocation, boot/time changes, battery restriction behavior, ringtone/vibration, biometric enrollment, native sharing/preview, and release installs on representative Android versions. No physical-device success is implied by a source review or host unit tests.

## Recorded validation for this build

- Final reproducible `tool/build_android.sh`: static analysis clean, 30 Flutter tests passed, release-mode APK and AAB generated. See `final-android-build.txt`.
- Seven Android unit tests passed through `:app:testReleaseUnitTest`; see `android-gradle-unit-tests.xml`.
- Ten Android instrumented tests passed with zero failures/errors/skips on the software Android 11 / API 30 emulator; see `android-instrumentation-tests.xml`. These exercised the real Android Keystore, AlarmManager receiver/foreground-service delivery, cancellation, native snooze/Done actions, duplicate/stale rejection, durable action acknowledgement, and actual AlarmActivity button clicks for Snooze 5/10/15, Done, and Stop. The button tests verify the activity passes the task UUID rather than the Button view ID. Audio preparation is asynchronous so Stop/Done remain responsive during ringtone loading.
- Final APK binary manifest verifies API 24 minimum/API 36 target, release debuggability disabled, INTERNET absent, automatic backup disabled. APK v2 signature and AAB JAR signature verified using the local test certificate. `releases/android/SHA256SUMS` records artifact integrity.
- Final APK `zipalign -c -P 16` passed. All arm64 and x86_64 ELF load segments in libapp, libflutter, and libdartjni have alignment at least 16 KB. These are static compatibility checks, not an execution on a 16 KB device.

See `BUILD_VERIFICATION.md` for the overall application findings and release smoke results. Physical-phone audio, modern permission flows, lock screens, reboot behavior, biometrics, and store eligibility still require their stated device/policy validation.
