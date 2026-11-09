# Supare delivery status

Date: 10 November 2026 (Asia/Kolkata). Package/bundle identifier: `app.supare.offline`. Version: `1.0.0+1`.

This is an Android evaluation build and a Flutter/Android/iOS source delivery. It is not a production-qualification or store-approval claim.

## Implemented

- Four-tab task workflow: local task CRUD, completion/history/restore, search, importance, scheduling, rescheduling, normal/alarm modes, snooze and calendar recurrence.
- Android native AlarmManager scheduling, notification actions, foreground ringing service, full-screen alarm activity where permitted, encrypted action journal, durable acknowledgment, and reboot/time-change rescheduling.
- iOS native local notifications, actions, snooze and bounded recurring-notification refresh. **AlarmKit is not implemented.** This iOS implementation does not offer continuous ringing or a full-screen alarm equivalent to Android.
- Family profiles, encrypted document metadata and PDF/image attachments, individual masked/copyable fields, favorites/recent/search, file replacement/deletion, camera capture/manual crop, private native preview and explicit native sharing.
- AES-256-GCM local encryption, platform-protected device keys, real PIN verification and device-authentication integration, wallet lock/lifecycle privacy, generic document-expiry reminders, and authenticated Argon2id password backups with validated merge/replace restore.
- No backend, account, analytics, advertisements or application network client. The main/release Android manifest omits INTERNET; a separate debug-only permission supports Flutter's development/test connection. User-selected file providers or recipient apps can transfer exported data outside Supare.

Optional on-device OCR and natural-language date parsing are not included. No inactive controls are presented for those features.

## Executed evidence

| Check | Result and scope |
| --- | --- |
| Flutter analysis | No issues in the recorded full analysis; integration-test analysis also reports no issues. |
| Flutter unit/widget suite | 30 passed, 0 failed. Real SQLite/encryption tests plus models, application navigation/forms, wallet gating and crop tests. Platform interactions are substituted in host widget tests and are not device evidence. |
| Kotlin recurrence tests | 7 passed, 0 failed, 0 skipped against production AlarmMath code on the host JVM. |
| Android task integration | Passed separately on the software API-30 Android emulator after correcting the test's asynchronous wait. Uses actual SQLite, secure-storage and native scheduling/cancellation plugins; tests task UI creation, reopen persistence and completion. |
| Android wallet integration | Passed on the software API-30 Android emulator. Uses actual namespaced platform secure storage, SQLite, PIN derivation, encrypted PNG import/retrieval, family CRUD, duplicate rejection, lock/reopen and authenticated backup/restore including wrong-password/tamper rejection. |
| Static platform configuration | XML/plist parsing and source privacy assertions passed. These are not permission/delivery runtime tests. |

The initial combined Android integration run had one task-test timing failure and a wallet-test pass. The task test subsequently passed in a separate run. Do not describe that initial combined run as a two-test pass. Integration fixture code uses isolated temporary stores, separate secure-storage namespaces and scoped native-action acknowledgment. Android instrumentation installation/reset can clear the target app's data; run device suites only on a disposable test installation.

See `flutter-tests.txt`, `native-jvm-tests.xml`, `integration-analysis.txt`, `android-integration-wallet-pass-task-race.txt`, and `android-integration-task-retry.txt`. Final Android instrumentation passed 10 tests with no failures or skips, including actual clicks on every alarm button. Full build/instrumentation/smoke-test evidence is tracked in `BUILD_VERIFICATION.md`.

## Release artifact gate

Final APK/AAB files were rebuilt after the SQLite startup, asynchronous audio-preparation and native button-ID fixes. Signatures, hashes, binary manifest and static 16 KB alignment checks passed. The exact final APK installed and launched offline, delivered its alarm after the application process was killed, and passed a real Snooze click with silencing, one future alarm and the updated Flutter due time. See `BUILD_VERIFICATION.md` and `android-release-smoke.txt` for the delivered hashes and exact scope. The certificate remains an evaluation/test identity.

No iOS executable, archive or IPA has been generated. Linux cannot perform Xcode compilation, iOS XCTest or Apple signing. Production Android upload-signing credentials have not been supplied; test-key artifacts must not be represented as production-signed or ready for Play Store publication.

## Remaining concrete qualification

- Physical Android alarm audibility/vibration, app-closed and lock-screen presentation, reboot delivery, OEM battery restrictions, and Android 12+/13+/14+ exact-alarm/notification/full-screen permission cases remain unrun. The API-30 emulator cannot validate those newer permission flows or physical hardware behavior.
- Real biometric enrollment/authentication, external camera/file-provider workflows, PDF/image preview on representative devices, native share recipients, clipboard retention, accessibility/large text, low-memory behavior and release backup recovery remain physical-device acceptance work. Source and host tests do not establish these results.
- iOS compilation, XCTest, signing and physical-device operation remain unrun. AlarmKit support is a remaining requested platform feature, beyond local-notification fallback.
- Final application identity ownership, production upload key, store permission eligibility/disclosures and independent security review remain distribution work.
- Reusable cloud-configuration draft persistence/publication could not be confirmed because the draft service returned INVALID_ARGUMENT. Tested setup/start instructions are saved in the project; no fresh-task restoration/publication is claimed.

## Source archive boundary

An exported source archive should contain project source/assets, platform projects, the dependency lockfile, tests, documentation and reusable setup/build helper scripts. It must exclude private signing configuration/keys, local machine paths, tool/package/Gradle caches, SDK/JDK/emulator/AVD state, generated build directories, telemetry/runtime state and the archive itself. APK/AAB files are separate deliverables. A source archive is not the prepared environment snapshot and does not imply that caches, processes or signing credentials are restored.
