# Android evaluation releases

Supare 1.0.0 (build 1), application ID `app.supare.offline`.

- `supare-1.0.0-test-key.apk`: installable, optimized Flutter release-mode APK, signed with a local evaluation/test certificate. This is not a debug-mode build or a production upload-signing identity.
- `supare-1.0.0-test-key.aab`: matching release App Bundle, JAR-signed with the same evaluation certificate; not directly installable or ready for production store submission.
- `SHA256SUMS`: SHA256 hashes of the final two artifacts.

Minimum Android 7 / API 24, target/compile API 36. Final binary checks verified nondebuggable, no INTERNET permission, disabled automatic backup, valid signatures and static 16 KB ELF/ZIP alignment. Static 16 KB alignment is not a test on a physical 16 KB page device.

From this directory verify `sha256sum -c SHA256SUMS`. Install with `adb install -r supare-1.0.0-test-key.apk`, then open Supare and review notification/exact-alarm/full-screen access in Settings. See ../../docs/BUILD_VERIFICATION.md for actual tests, ../../docs/RELEASE.md for production signing/build commands, and ../../docs/DEVICE_TESTS.md for remaining physical-device qualification. Source is separately packaged in ../supare-source-1.0.0.zip.
