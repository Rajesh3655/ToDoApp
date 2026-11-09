# Physical-device release acceptance

**Physical-device status: every case below remains UNRUN on physical hardware.** Android API 30 emulator results are recorded separately in BUILD_VERIFICATION.md and do not replace this qualification. Source inspection, Dart tests and Android compilation do not establish physical-device alarm, notification, authentication, sharing or lock-screen behavior. Record a new dated result with device model, OS version, app build/hash, permission state, exact steps and observed output for each case. Do not replace UNRUN with PASS without executing the case on that target.

Use only synthetic documents and test identifiers. Run the exact signed release candidate, with airplane mode enabled for offline cases. Include at least one lower-end Android device, an Android 12+ exact-alarm device, Android 13+ notification permission, Android 14+ full-screen intent restrictions, current Android, and supported iPhones with and without Face ID. Add manufacturer battery restrictions to the Android matrix.

## Tasks and persistence — UNRUN

- Fresh offline installation: all four tabs open, loading/error/empty states make sense, no account or network is requested.
- Create a task with title, optional notes, date/time, importance and each reminder mode. Kill/reopen the app and reboot; verify persisted fields.
- Edit title/date/description, quick reschedule, search with mixed case, complete, inspect history, restore and delete. Verify only the intended records change.
- Verify overdue status before/after midnight, today/upcoming boundaries, locale date formatting, 12/24 hour settings and a timezone change.
- Daily, weekly, monthly (January 31, leap/nonleap February), and custom day recurrence: inspect the next occurrence, completion history, no duplicate active tasks, and restore behavior.
- Complete or delete a task immediately before its scheduled trigger. Confirm the obsolete reminder does not ring.
- Deny reminder permissions, save a task, verify persistence and a visible actionable scheduling error. Grant permission later and confirm rescheduling.
- Exercise large text scaling, screen reader labels, keyboard/safe-area handling, dark/light appearance, landscape and narrow displays.

## Android alarms — UNRUN

- Schedule one-time normal and alarm reminders a few minutes ahead. Check unlocked foreground, background, app swiped from recents, and locked screen states separately. A running process/open notification is insufficient evidence.
- At the trigger, verify full task title, repeating ringtone, vibration subject to user settings, prominent notification, and full-screen presentation where permission/policy permits.
- Test Done, Stop, notification dismissal, and each Snooze (5/10/15 minutes). Done records completion once; Stop/dismiss preserves pending; each snooze fires once at its actual chosen deadline, including when Supare remains closed.
- Test recurrence with the app closed and after Done/Stop/Snooze. Reopen after several missed recurrences; verify native queued actions reconcile exactly once and no stale notification overwrites current task state.
- Exact alarm special access: denied initially, granted, revoked after scheduling. Verify truthful errors/fallback behavior, no crash, and no claim of precision when unavailable.
- Notification permission and channel sound/vibration disabled separately; full-screen intent permission denied on Android 14+. Verify accessible fallback notification and accurate Settings capability text.
- Enable Doze/battery saver and manufacturer restrictions. Verify actual delivery and document deviations; do not promise unrestricted exactness across vendors.
- Reboot with scheduled reminders, unlock as required, and verify boot rescheduling from encrypted native state. Repeat with an overdue reminder and a future recurrence.
- Change timezone, manually change clock forwards/backwards, cross DST forward/back transitions; verify next occurrence and no duplicate trigger.
- Android Settings **Force stop**: verify the OS stops delivery until reopening; record this limitation. Swiping recents and force stop are distinct cases.
- Cancel/replace a reminder while ringing; repeated action taps, simultaneous reminders and stale PendingIntent delivery cannot mark a different occurrence complete.
- Verify alarm service stops audio/vibration/wakelock on Done/Stop/Snooze and after its bounded safety timeout; no indefinite battery drain.

## iOS notification fallback — UNRUN

- Build/install with the selected Xcode/iOS SDK and signing profile. Run `RunnerTests` in Xcode before device acceptance.
- This source currently uses `UNUserNotificationCenter`, **not AlarmKit**. Verify the user sees this limitation. Continuous ringtone, full-screen lock-screen alarm and Focus/mute bypass are not supported claims.
- Permissions allowed/denied, sound disabled, Focus on/off and mute on/off: observe local notification delivery with app foreground/background/terminated and locked/unlocked.
- Expand a delivered notification and test Done, Stop and Snooze input 5/10/15; invalid input defaults to 5. Done authenticates and reconciles completion; Stop preserves pending; opening a notification alone does not complete it.
- Recurring tasks schedule up to eight future occurrences. Reopen to refresh the horizon; exceed the 60-pending-request cap and verify a readable error instead of silent loss. Check month-end recurrence and timezone/DST changes.
- Snooze while app is closed, wait beyond deadline before reopening, then verify the app retains the true native snooze deadline instead of shifting it by the time of reopening.
- Reboot and test delivered/pending reminders and protected storage before/after first unlock. Confirm notification queue restoration and no unencrypted native snapshots.
- On a supported AlarmKit-capable iPhone, record AlarmKit integration as **NOT IMPLEMENTED**, not PASS, until a separately compiled and device-verified implementation is supplied.

## Wallet, family and files — UNRUN

- PIN setup/confirmation, correct/incorrect PINs, rate limits and lock state; Face ID/Touch ID/Android biometrics success, cancel, no enrollment, lockout and credential fallback. No fake authentication success.
- Lock the wallet by leaving/backgrounding the app. Return from camera/file-picker/share sheet and verify safe authentication recovery and no sensitive flash in the app switcher.
- Create/edit each family relationship and a custom member. Add/view/edit/delete documents, optional fields and multiple custom fields. Verify member deletion cannot silently orphan private files.
- Import a real PDF and JPEG/PNG/HEIF image from device storage; malformed, unsupported, zero-byte, oversized and misleading-extension files are rejected safely. Camera capture/crop works or returns a clear error on permission denial.
- Rename/replace/delete, search, favorites, recent documents and duplicate detection persist across restart. Replace/import failure leaves the original encrypted file and metadata consistent.
- Sensitive document numbers stay masked until authenticated reveal. Copy each individual field; verify exact pasted content and any clipboard cleanup delay without erasing unrelated later clipboard content.
- Native PDF/image preview displays the correct file and zoom/pages; dismiss and confirm decrypted temporary files are removed. Lock/background during preview, reopen and verify access control.
- Share uses the OS sheet only after explicit user action and explains that the receiving app may transfer/store the plaintext. Cancel and complete share, then verify plaintext temporary cleanup. Receiver-owned copies cannot be recalled by Supare.
- Inspect app-private SQLite, WAL/SHM, encrypted document files and native alarm storage with approved test-device tools. Search for known synthetic identifiers; metadata/document contents must not appear plaintext at rest.
- Android wallet screenshots/recents protection works; iOS app-switcher cover works and screenshot limitation is accurately disclosed. Inspect file-picker/camera caches after import, cancellation and crash recovery.
- Verify document expiry reminder has a generic privacy-safe title, triggers once, updates after editing expiry and cancels after deleting its document.
- Check Android backup/data-extraction rules and iOS backup exclusions; neither encrypted keys nor vault files should silently sync to cloud backup. Verify restoring a phone backup does not create orphaned readable secrets.

## Manual encrypted backup and recovery — UNRUN

- Export a password-protected local backup containing tasks, reminders, families, all metadata and actual document bytes. Open it in a hex/text viewer: no known synthetic plaintext, embedded usable key or password.
- Restore into a fresh installation with the correct password, unlock and compare counts/content/files. Confirm alarms are rescheduled with truthful permission errors when denied.
- Restore merge with duplicate IDs/digests and explicit replacement with existing unrelated records; verify the documented choice and no silent destructive replacement.
- Wrong password, single-bit tampering, truncated file, malformed header, unsupported version, oversized lengths and altered KDF parameters: reject without exposing partial data or changing live records.
- Interrupt export/restore (background, low storage, OS kill) and retry. The original live data must remain usable after failed restore; temporary staging must be cleaned.
- Lost password warning is visible and accurate: there is no password recovery server or key hidden only inside the backup. Confirm a wrong password cannot be bypassed by changing the app PIN.
- Restore on another device to prove backup portability independent of the original device's Keystore/Keychain. Device authentication must be configured locally after restore.

## Release and privacy — UNRUN

- Install the reported APK on a clean device and verify package ID/version/signing certificate, release mode, icon, splash and no development/sample data.
- Use the Play Console's internal testing track for a properly signed AAB and review full-screen alarm/exact-alarm policy eligibility. Test-key APK/AAB are not production-distribution approval.
- Capture network activity under offline/online use: Supare initiates no network calls. User-initiated third-party sharing is a separate app's behavior.
- Complete app-store privacy/security, encryption-export and permission declarations based on the actual binary and dependencies. Verify no debug INTERNET permission leaks into release.
- Review security independently before storing real government IDs. Record remaining failures and release-blocking risks explicitly; do not convert unrun tests or source review into a production-readiness claim.
