# Supare implementation contracts

Standalone Flutter application, Android package `app.supare.offline`, iOS bundle `app.supare.offline`. Offline only; no INTERNET permission in release. Four tabs: Today, Upcoming, Wallet, Settings.

## Shared Dart APIs (core agent owns lib/core/ and lib/models/)
- `AppStore.open()` async factory; `tasks`, `members`, `documents` getters; ChangeNotifier.
- `TaskItem`: id,title,description,due(DateTime), reminder (`normal`/`alarm`), repeat (`none`/`daily`/`weekly`/`monthly`/`custom`), intervalDays(int), important(bool), completedAt(DateTime?), createdAt. copyWith. serialize.
- `FamilyMember`: id,name,relationship; serialize.
- `WalletDocument`: id,name,category,memberId,number,authority,issueDate(DateTime?),expiryDate(DateTime?),fields(Map<String,String>),fileName,mimeType,fileId,favorite,lastOpened(DateTime?),digest; serialize/copyWith.
- AppStore methods: `saveTask(TaskItem)`, `deleteTask(String)`, `completeTask(String)`, `restoreTask(String)`, `snoozeTask(String,int)`, `saveMember(FamilyMember)`, `deleteMember(String)`, `importDocument(WalletDocument,Uint8List)`, `updateDocument(WalletDocument)`, `deleteDocument(String)`, `readDocument(String)` -> Uint8List, `exportBackup(String)` -> Uint8List, `restoreBackup(Uint8List,String,{bool replace=false})`, `close()`.
- `VaultAuth`: `hasPin` async getter; `setPin(String)`, `unlockWithPin(String)` -> bool; `authenticate()` -> bool (real device credentials/biometric); `lock()`; `isUnlocked` bool; store enforces wallet access with this singleton.
- `AppStore.auth` VaultAuth instance. `AppStore.settings` Map<String,String>; `setSetting(String,String)`.
- IDs from uuid. Encrypted metadata stored inside SQLite rows. All task/document/member data encrypted AES-256-GCM, key in platform secure storage. Backup uses Argon2id and AES-GCM.
- `NativeBridge` owned core wraps MethodChannel `app.supare/native`: scheduleTask(Map task), cancelTask(id), getCapabilities(), requestAlarmPermissions(), setSecure(bool), drainActions()-> List<Map>. `scheduleTask` args: id,title,body,dueMillis,mode,repeat,intervalDays. Native actions: id, action(done/snooze/stop), minutes. Flutter reconciles actions before rescheduling. Persist task before schedule; propagate scheduling errors truthfully. Android handles app-closed repeat and snooze independently; event queue reconciles later.

## Native ownership
Android agent owns android/ (full generated Gradle project with flutter embedding), implements MethodChannel and native alarm lifecycle, app-private storage, no backups, secure screens, plus PDF preview via `previewFile` args path,mimeType and native image/PDF viewer if possible. iOS agent owns ios/ and docs/IOS.md; same channel with UNUserNotificationCenter fallback; only add AlarmKit if actual compile-safe API verified. Report unsupported AlarmKit explicitly.

## Main/UI ownership
Root owns pubspec.yaml, lib/main.dart, lib/ui/, assets, test/ integration. Use real APIs above. Errors displayed, no mock release data. UI includes PIN setup/unlock and biometric, task forms, wallet CRUD/detail/copy/share/preview, family management, backup/restore. No inactive buttons.
