# Local security and data formats

Supare makes no network requests and uses no account, telemetry, cloud storage, external OCR or backend. Native user-initiated sharing passes a selected plaintext attachment to the receiving app. That app controls any subsequent upload or retention; cancel sharing if the destination is not trusted.

## Storage

All task titles, descriptions, dates, family profiles, document fields, settings and renewal records are JSON encrypted with AES-256-GCM before insertion into SQLite. SQLite contains only record kind, opaque record ID and authenticated ciphertext. Attachments are separate AES-256-GCM encrypted files in the private application-support directory. Every write uses a fresh 96-bit cryptographically random nonce and a 128-bit authentication tag. Associated data binds ciphertext to its record kind/ID or attachment ID, preventing swapping valid ciphertext between records. A SHA-256 digest also detects duplicate attachment imports and verifies attachments during backup restore.

The random 256-bit master key is held by Android Keystore-backed flutter_secure_storage / iOS device-only, unlocked Keychain storage. Android automatic backup and device-transfer backup must be disabled in the manifest and extraction rules; iOS application-support and document directories are excluded from backup by native code. Do not add application data or private signing keys to source control.

This protects data at rest on a normally secured device. An unlocked operating system running compromised/rooted application code can access process memory and protected key APIs. Supare does not claim protection against a compromised operating system, forensic capture of an unlocked device, or files retained by third-party recipients.

## Wallet access

The wallet requires a 6–12 digit PIN or real OS device/biometric authentication after PIN enrollment. PIN verification uses an independent random salt and Argon2id (64 MiB memory, three passes, one lane, 32-byte output). After five incorrect attempts, a persisted exponential retry delay begins at 30 seconds and caps at 15 minutes. Wallet plaintext caches are cleared when locking, and document APIs recheck authorization after asynchronous decryption. Backgrounding locks access; incoming platform authentication dialogs must not themselves trigger premature locking. Change a PIN only after unlocking.

The application PIN gates access in the legitimate app; it does not replace the device passcode or biometric enrollment. The master key also encrypts scheduled-task data and is not derived from the PIN. No PIN recovery service exists. Device authentication may allow access if a PIN is forgotten; otherwise use a previously exported encrypted backup on a fresh install. Uninstalling can remove the only device key and local files.

Sensitive screens use Android FLAG_SECURE. iOS obscures app-switcher snapshots; iOS cannot guarantee prevention of ordinary screenshots. Clipboard content is a deliberate user export visible to other apps permitted by the OS. The UI should clear its own copied sensitive value after a short interval if it still owns that value.

Android stores an independently encrypted native alarm journal in private preferences so scheduling can survive Flutter process death and reboot. The journal contains the title/body needed for a ringing alarm. OS notifications may show task titles on the lock screen as requested; users should avoid including sensitive wallet identifiers in task titles. Wallet renewal notifications always use a generic title/body.

## Portable backup v1

The `.supare` backup is a single encrypted envelope:

- Bytes 0–4: `SUPB` and version 1.
- Bytes 5–20: independent random 16-byte Argon2id salt.
- Bytes 21–32: independent random 12-byte AES-GCM nonce.
- Remaining body: AES-256-GCM ciphertext followed by a 16-byte tag.
- Authenticated associated data: complete magic/version/salt header.

Argon2id parameters are fixed to 64 MiB, three passes and one lane, producing a 32-byte key. No decryption key is embedded in the backup. Use a unique password of at least 12 characters; losing the password may make the backup permanently unrecoverable. No server can reset it. A corrupted/tampered file or incorrect password fails authentication before parsing records.

A backup contains all tasks/history, family profiles, document metadata, attachments and display settings. It does not include the device master key, wallet PIN verifier, biometric enrollment or transient native-action dedup state. Attachment imports are limited to 25 MiB each; one backup is limited to 80 MiB of original attachments to bound JSON/base64 expansion and memory use. External files are accepted only when their magic bytes identify PDF, JPEG, PNG, WebP or a supported HEIF image. Filenames from backups never become filesystem paths.

Restore decrypts and validates the entire backup, all IDs, references and attachment digests before changing existing records. New encrypted attachments are staged under fresh random IDs; all metadata changes occur in a single SQLite transaction. A precommit failure removes staged files and leaves existing data unchanged. Merge retains existing records on ID conflicts and skips duplicate attachments. Explicit replacement removes previous records only after validation succeeds. Existing device authentication remains in place. Native reminders are rebuilt after the database commit; a permission/scheduling failure is reported as a restored-data/reminder warning, not falsely described as a rollback. The UI must obtain explicit confirmation for replacement.

## Reminder lifecycle

Native alarm actions are persisted before Flutter reconciliation. Completion archives its occurrence and creates exactly one fresh-ID future task for a repeating series. Stop leaves an unfinished task pending. Snooze moves the pending due time by the selected interval. Native repeat fire does not overwrite the original pending due time in SQLite; doing so would skip a cycle when completing the task. On startup, an overdue repeating task refreshes the native future horizon using a computed future due time while retaining the overdue occurrence in the UI. Restoring a completed historical occurrence makes that occurrence one-time because the recurring successor already exists.

These mechanisms need real Android/iOS device tests for power management, OEM restrictions, lock-screen presentation, reboot, permission revocation and shared-file retention. Automated unit tests alone cannot establish those platform guarantees.
