# Build and verification evidence

Date: 10 November 2026 (Asia/Kolkata). Supare 1.0.0 (build 1), `app.supare.offline`. These are test-signed Android evaluation releases, with production and physical-device qualification still outstanding.

## Automated checks executed

| Check | Result | Evidence |
| --- | --- | --- |
| Flutter static analysis | No issues | flutter-analysis.txt; final-android-build.txt |
| Flutter unit/widget suite | 30 passed, 0 failed | flutter-tests.txt |
| Kotlin calendar recurrence tests | 7 passed, 0 failed, 0 skipped through the Android Gradle project | android-gradle-unit-tests.xml |
| Android instrumented tests on API 30 | 10 passed, 0 failed, 0 errors, 0 skipped | android-instrumentation-tests.xml and .txt |
| Real-plugin Android task integration | Passed in the corrected targeted run | android-integration-task-retry.txt |
| Real-plugin Android wallet integration | Passed in the earlier combined run | android-integration-wallet-pass-task-race.txt |
| Platform privacy/configuration assertions | Passed | platform-config-checks.txt |

The 30 Flutter cases include 11 encrypted-store/recurrence tests, 9 cryptography/authentication tests, 4 model tests, 3 application widget tests and 3 wallet/crop widget tests. The 10 Android instrumented cases exercise actual AlarmManager delivery, native foreground service cancellation, Keystore encryption, stale/duplicate delivery tokens, durable acknowledgments, and actual AlarmActivity button clicks. The three UI cases cover all five buttons, including 5/10/15-minute snooze deadlines and silencing.

Both named real-plugin integration scenarios passed in their latest relevant executions. They were not rerun together after correcting the task test's asynchronous wait: the first combined run had one wallet pass and one premature task UI assertion failure; the unchanged wallet scenario was retained and the corrected task scenario then passed separately. See android-integration-tests.txt for exact commands, outcomes and runner diagnostics. No assertion was disabled, no cryptographic parameters were lowered, and no platform dependency was replaced with a fake to obtain these device results.

## Release artifacts and binary checks

- APK: `releases/android/supare-1.0.0-test-key.apk`
- App Bundle: `releases/android/supare-1.0.0-test-key.aab`
- Hash manifest: `releases/android/SHA256SUMS`

The APK and AAB were rebuilt after the device-discovered fixes. APK v2 signing verification passed with the local evaluation RSA certificate. AAB ZIP integrity and JAR-signature verification passed; self-signed test-certificate/timestamp warnings do not establish a production upload identity. Final binary metadata verified version 1.0.0/code 1, minimum API 24, target/compile API 36, nondebuggable, no INTERNET permission, and disabled automatic backup. See android-apk-{signature,metadata,permissions,manifest}.txt and android-aab-signature.txt.

Static 16 KB compatibility checks passed: APK `zipalign -c -P 16`, plus arm64/x86_64 ELF PT_LOAD alignment of at least 0x4000 for packaged libraries. These are static checks, not a run on a physical device with 16 KB pages. See android-apk-zipalign.txt and android-arm64-elf-alignment.txt.

```text
APK SHA256: e4f54be1cc72b09d2c34fe724cef954946631bb544fe252064f41c9fc2d7f7d9
AAB SHA256: ba4e68afe1435e261c829e285f19d6c67995591a0e73f41f3b78557e999c7a46
```

## Offline release execution

Device: official AOSP Android 11/API 30 x86_64 emulator, software TCG/SwiftShader, no KVM. Airplane mode 1, Wi-Fi 0, mobile data 0. The exact corrected release APK installed and cold-started successfully; Today/Upcoming/Wallet/Settings and the empty Today view were visible in the accessibility hierarchy, with no database or fatal application errors. Protected screenshot attempts were refused; no empty images or protection bypasses are offered as screenshots.

The exact final APK also passed the app-closed alarm and real Snooze button check. After Home + am kill (not force-stop) left no application PID and the screen was powered off, Android restarted the native receiver/service and foregrounded the full-title AlarmActivity. Tapping Snooze 5 stopped the service, left one future alarm about five minutes ahead (298 seconds at inspection), and the Flutter task showed the updated due time on reopening. See android-release-smoke.txt for timestamps and cleanup evidence.

The final UI-fixed release was observed about one second after the selected minute on this software device. This observation is specific to that run and is not a physical-device timing guarantee. The earlier candidate and test failures are retained as historical evidence, with their fixes described below.

## Issues found and corrected

- The Linux image lacked the SQLite linker alias used by FFI tests; setup now supplies a local alias without replacing system libraries. Widget database fixtures run real SQLite operations outside simulated async zones.
- Android SQLite requires a query call for `PRAGMA secure_delete = ON`; using execute prevented initial release startup even though host FFI tests accepted it. The production code now uses rawQuery, validated through actual Android plugin operations.
- Synchronous MediaPlayer preparation delayed Stop dispatch. Asynchronous preparation with guarded callbacks and cleanup passed the original cancellation timing assertion.
- Kotlin Button.apply resolved unqualified id to View.id rather than the task string ID. Explicit outer Activity ID dispatch now passes actual native button-click tests for Done, Stop and all snooze intervals.
- Test-runner initialization needed project-contained Dart CLI state with analytics disabled. A five-second direct VM connection timeout on software emulation was avoided using the normal supported DDS workflow, without SDK patches. Flutter tooling and release builds were serialized to preserve correct debug/release plugin registration.

Initial failures are preserved in the corresponding initial-failure/timing reports. The delivered artifacts are rebuilt outputs rather than the failed candidates.

## Remaining qualification and platform limits

- No physical Android phone or iPhone was connected. Audibility/vibration, real lock screens, reboot delivery, OEM power management, modern exact-alarm/notification/full-screen access flows, biometric hardware, external camera/file providers/share recipients, accessibility and low-memory behavior need DEVICE_TESTS.md. The emulator was launched with host audio disabled, so service delivery is not a physical sound test.
- iOS has source, local-notification fallback, actions and privacy configuration. No iOS binary/XCTest/signing was generated on Linux. **AlarmKit is not implemented**, and this build does not provide continuous/full-screen iOS ringing. macOS/Xcode and Apple signing are required for iOS qualification/distribution.
- Production Android signing credentials and final application-identity/store eligibility review are outstanding. Evaluation keys must not be treated as a production signing identity. Independent security review remains part of production qualification.
- Cloud configuration draft saving returned INVALID_ARGUMENT and persistence/publication could not be confirmed. Tested setup/start instructions are included locally; no fresh-task snapshot restoration is claimed. See ENVIRONMENT.md.

## Reproduce

From the supare directory, source `tool/environment.sh`; use `tool/setup.sh`, `tool/build_android.sh`, and RELEASE.md. EMULATOR.md documents the actual software device. Run device suites only on disposable installations: Android instrumentation setup can clear target application data. Portable source packaging uses `python3 tool/package_source.py` and excludes SDKs/caches, app data, machine-specific configuration and private signing material.
