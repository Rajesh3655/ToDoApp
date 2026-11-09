# Build, sign, and install

Version: 1.0.0 (1). Application ID: app.supare.offline.

## Android

Run `source tool/environment.sh`, install tools via `bash tool/setup.sh`, then `bash tool/build_android.sh` from the supare directory. Analysis/tests must pass before artifacts are copied. The script generates a private local **evaluation** key only when production configuration is absent; this is standard test signing, not an app-store identity. APK installation: `adb install -r releases/android/supare-1.0.0-test-key.apk` (only if that file actually exists). Grant notification, exact-alarm and optional full-screen access in app Settings. Test a near-future alarm with the app closed and screen locked.

For a distributable release, create your own upload key outside the checkout, protect it securely, and configure ignored `android/key.properties`:

```
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=<enter locally, never commit>
keyAlias=<your alias>
keyPassword=<enter locally, never commit>
```

Re-run the build script; outputs have the `signed` suffix. Verify the signing certificate with `apksigner verify --print-certs` and inspect the manifest with Android SDK `apkanalyzer manifest print`. Enable Play App Signing and upload the signed AAB. An AAB is not directly installable. Store policy review of exact alarms and full-screen intents remains required; the app must only request these for user-selected alarm features. Test-key builds must not be published as production releases. Changing signing identity prevents in-place upgrades; export an encrypted backup before uninstalling an evaluation build.

## iOS

Use a Mac with Xcode, CocoaPods, a connected/simulated device, and the iOS SDK compatible with Flutter 3.35.7:

```sh
flutter pub get --enforce-lockfile
cd ios && pod install && cd ..
flutter analyze
flutter test
flutter build ios --release --no-codesign
# For distribution, configure Runner's team/profile in Xcode first:
flutter build ipa --release
mkdir -p releases/ios
cp build/ios/ipa/*.ipa releases/ios/
```

No iOS artifact is implied by these instructions. Linux cannot compile/sign iOS applications. Set the real development team and distribution profile; never add private signing material to source control. AlarmKit is not implemented; this build uses notification fallback with explicitly described restrictions. Do not advertise equivalent iOS ringing alarms.

## Before publication

Execute the checklist in DEVICE_TESTS.md on supported real devices, including release builds and offline launch. Independently review cryptographic storage, backup restore, temp-file lifetimes and app-store alarm entitlements. Select the final reverse-DNS application identity before first publication if `app.supare.offline` is not owned by your organization. Verify generated privacy disclosures and current store requirements. Publish only after release artifacts, certificate, functionality and device evidence are reviewed.
