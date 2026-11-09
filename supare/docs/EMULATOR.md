# Software Android emulator

The managed Linux environment does not expose KVM virtualization, but the official Android emulator boots using software TCG emulation. The tested device is `emulator-5554`: Android 11 / API 30, default AOSP x86_64 image revision 11, emulator 37.2.13, two virtual CPUs, 2 GiB guest RAM, 480×800 display and SwiftShader GLES. First boot took approximately 5½ minutes while Android builds shared the host CPUs.

The SDK manager installed both packages from official Google repositories, retaining TLS and repository-checksum validation:

- `emulator`
- `system-images;android-30;default;x86_64`

The image, AVD, generated state and emulator logs stay under `supare/tool/`. Start the prepared device from the project directory:

```sh
source tool/environment.sh
tool/start-emulator.sh > tool/emulator-boot.log 2>&1 &
SUPARE_EMULATOR_PID=$!
adb -s emulator-5554 wait-for-device
adb -s emulator-5554 shell getprop sys.boot_completed
```

Wait until the final property returns `1`. An adb device may appear online before Android framework services finish booting. The helper avoids the deprecated `ANDROID_SDK_HOME` setting because it conflicts with `ANDROID_USER_HOME` in the Android command-line tools; its AVD index is under `tool/android-user/avd/` and data under `tool/avd/`.

For an offline test session:

```sh
adb -s emulator-5554 shell cmd connectivity airplane-mode enable
adb -s emulator-5554 shell svc wifi disable
adb -s emulator-5554 shell svc data disable
adb -s emulator-5554 shell settings put global mobile_data 0
adb -s emulator-5554 shell settings get global airplane_mode_on
adb -s emulator-5554 shell settings get global wifi_on
adb -s emulator-5554 shell settings get global mobile_data
```

Expected settings are `1`, `0`, `0`. The ordinary shell cannot send the protected `android.intent.action.AIRPLANE_MODE` broadcast directly; use the supported connectivity command instead.

Run Flutter integration only after concurrent release Gradle builds finish, so tests do not replace their debug/release outputs mid-build:

```sh
flutter test integration_test/app_test.dart -d emulator-5554 --reporter expanded --timeout 300s
```

Terminate only the emulator process you started using `kill "$SUPARE_EMULATOR_PID"`. The emulator console can be unavailable in a sandbox with a read-only home directory; adb and Android application execution still work.

An emulator does not validate physical-device audibility, vibration, biometric enrollment, OEM battery policy, a real lock screen, or app-store eligibility. This API-30 device also cannot validate Android 12+ exact-alarm permission prompts or Android 14+ full-screen intent restrictions. Those remain real-device checks even when automated emulator tests pass.
