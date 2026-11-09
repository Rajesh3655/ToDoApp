# Reusable cloud development environment

Use the existing `/workspace/ToDoApp/supare` checkout. Cloud tasks already run in isolation; do not create a Git worktree unless the user asks.

From that directory, source `tool/environment.sh` to activate the pinned Flutter SDK, JDK, Android tools, private build/package caches, analyzer state directory, and proxy/CA configuration. `bash tool/setup.sh` installs or refreshes the tools and locked dependencies. Its complete command sequence was executed successfully in this machine; see setup-log.txt. The Android toolchain and licenses are available. Doctor warnings for missing Chrome/Linux desktop development tools/Android Studio and blocked optional Maven-root/CocoaPods probes do not describe the Android Gradle destinations actually used successfully by this project. iOS compilation needs a Mac.

The platform's reusable-configuration draft read/update service returned INVALID_ARGUMENT and could not confirm persistence. Installation and startup instructions are therefore saved in this project, not confirmed in the environment-settings draft; no publication or new-task restoration has been verified.

## Start and test

```sh
cd /workspace/ToDoApp/supare
source tool/environment.sh
flutter analyze
flutter test --reporter expanded --timeout 60s
adb devices -l
```

Run device suites only on a disposable test installation: Android instrumentation installation/reset can clear the target app's data. For the prepared optional Android emulator, follow EMULATOR.md. A running emulator process does not survive environment restoration; restart it with `tool/start-emulator.sh` and wait for `sys.boot_completed=1` before tests. No backend/web service is required.

Do not run Flutter analyze/test/pub commands concurrently with Android release Gradle builds. Flutter can regenerate the shared plugin registrant for debug/dev dependencies while a release build correctly excludes those dependencies; serialize these operations. The release script already does so.

`bash tool/build_android.sh` runs analysis/tests then generates the APK and AAB. Test-key signing is for evaluation; use external production credentials for distribution. Never print credential values, disable TLS/checksum verification, or add key files to source control.
