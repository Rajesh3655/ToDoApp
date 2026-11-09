import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/app_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  Map<dynamic, dynamic>? capabilities;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  Future<void> load() async {
    try {
      final value = await widget.store.native.getCapabilities();
      if (mounted) setState(() => capabilities = value);
    } catch (_) {
      if (mounted) {
        setState(() => capabilities = {'platform': Platform.operatingSystem});
      }
    }
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> run(Future<void> Function() fn) async {
    setState(() => busy = true);
    try {
      await fn();
    } catch (_) {
      message(
        'Could not finish this operation. Check your password, file, and free storage. Reopen the wallet to review current data.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> unlock() async {
    if (widget.store.auth.isUnlocked) return true;
    final hasPin = await widget.store.auth.hasPin;
    if (!hasPin) {
      message('Set up your wallet PIN in the Wallet tab first.');
      return false;
    }
    if (!mounted) return false;
    final pin = TextEditingController();
    String? error;
    bool checking = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Unlock protected data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Wallet PIN',
                  errorText: error,
                ),
              ),
              TextButton.icon(
                onPressed: checking
                    ? null
                    : () async {
                        update(() => checking = true);
                        final ok = await widget.store.auth.authenticate();
                        if (c.mounted && ok) {
                          Navigator.pop(c, true);
                        } else if (c.mounted) {
                          update(() {
                            checking = false;
                            error = 'Authentication was not completed';
                          });
                        }
                      },
                icon: const Icon(Icons.fingerprint),
                label: const Text('Use device authentication'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: checking ? null : () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: checking
                  ? null
                  : () async {
                      update(() => checking = true);
                      try {
                        final ok = await widget.store.auth.unlockWithPin(
                          pin.text,
                        );
                        if (c.mounted && ok) {
                          Navigator.pop(c, true);
                        } else if (c.mounted) {
                          update(() {
                            checking = false;
                            error =
                                'Incorrect PIN. Please wait before retrying.';
                          });
                        }
                      } catch (_) {
                        if (c.mounted) {
                          update(() {
                            checking = false;
                            error = 'Try again later.';
                          });
                        }
                      }
                    },
              child: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
    pin.dispose();
    return result == true;
  }

  Future<String?> password({required bool confirm}) async {
    final first = TextEditingController(), second = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(confirm ? 'Protect your backup' : 'Unlock backup'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Use a strong, unique password. Lost passwords cannot be recovered. The backup includes all tasks and family documents.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: first,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Backup password',
                  ),
                ),
                if (confirm) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: second,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Repeat password',
                    ),
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      error!,
                      style: TextStyle(color: Theme.of(c).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (first.text.length < 12) {
                  update(() => error = 'Use at least 12 characters.');
                  return;
                }
                if (confirm && first.text != second.text) {
                  update(() => error = 'Passwords do not match.');
                  return;
                }
                Navigator.pop(c, first.text);
              },
              child: Text(confirm ? 'Create backup' : 'Restore'),
            ),
          ],
        ),
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  Future<void> export() async {
    if (!await unlock() || !mounted) return;
    final pw = await password(confirm: true);
    if (pw == null) return;
    if (!widget.store.auth.isUnlocked && !await unlock()) return;
    final bytes = await widget.store.exportBackup(pw);
    final file = await FilePicker.platform.saveFile(
      dialogTitle: 'Save encrypted Supare backup',
      fileName:
          'supare-${DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first}.supare',
      bytes: bytes,
      type: FileType.any,
    );
    if (file != null) {
      message('Encrypted backup exported. Keep your password somewhere safe.');
    }
  }

  Future<void> restore() async {
    if (!await unlock()) return;
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select encrypted Supare backup',
      type: FileType.any,
      withData: false,
    );
    if (picked == null || picked.files.single.path == null || !mounted) return;
    final f = File(picked.files.single.path!);
    if (await f.length() > 256 * 1024 * 1024) {
      throw StateError('Backup too large');
    }
    final Uint8List bytes = await f.readAsBytes();
    if (!mounted) return;
    final pw = await password(confirm: false);
    if (pw == null || !mounted) return;
    final replace = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restore options'),
        content: const Text(
          'Merge keeps existing records and adds missing items. Replace deletes current data only after the backup has been authenticated and validated. Export a backup first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Merge'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (replace == null) return;
    if (!widget.store.auth.isUnlocked && !await unlock()) return;
    await widget.store.restoreBackup(bytes, pw, replace: replace);
    message(
      widget.store.lastAlarmError ??
          'Backup restored. Reminder schedules refreshed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final caps = capabilities;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 36),
      children: [
        Text(
          'Your space.',
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text('Private by design. Yours to control.'),
        const SizedBox(height: 28),
        Text(
          'APPEARANCE',
          style: TextStyle(
            letterSpacing: 2,
            fontSize: 12,
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: widget.store.settings['theme'] ?? 'system',
          decoration: const InputDecoration(labelText: 'Theme'),
          items: const [
            DropdownMenuItem(value: 'system', child: Text('Follow device')),
            DropdownMenuItem(value: 'light', child: Text('Light')),
            DropdownMenuItem(value: 'dark', child: Text('Dark')),
          ],
          onChanged: busy
              ? null
              : (v) => run(() => widget.store.setSetting('theme', v!)),
        ),
        const SizedBox(height: 28),
        Text(
          'REMINDERS',
          style: TextStyle(
            letterSpacing: 2,
            fontSize: 12,
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notifications'),
                subtitle: Text(
                  caps == null
                      ? 'Checking device…'
                      : caps['notifications'] == true
                      ? 'Allowed'
                      : 'Check device notification settings',
                ),
              ),
              if (Platform.isAndroid)
                ListTile(
                  leading: const Icon(Icons.alarm),
                  title: const Text('Exact alarms'),
                  subtitle: Text(
                    caps?['exactAlarms'] == true
                        ? 'Allowed'
                        : 'Alarm access required for precise ringing reminders',
                  ),
                ),
              if (Platform.isAndroid)
                ListTile(
                  leading: const Icon(Icons.fullscreen),
                  title: const Text('Lock-screen presentation'),
                  subtitle: Text(
                    caps?['fullScreen'] == true
                        ? 'Full-screen access allowed'
                        : 'System may show a notification instead',
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            await widget.store.native.requestAlarmPermissions();
                            await load();
                          }),
                    child: const Text('Review reminder permissions'),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            Platform.isIOS
                ? 'This build uses iOS local notifications. iOS controls sound, Focus, delivery, and pending limits. It cannot promise a repeating alarm when the app is closed.'
                : 'Android may restrict alarms when force-stopped, after a reboot before unlock, or under manufacturer battery policies. Grant alarm and notification access; test on your device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'SECURITY & BACKUP',
          style: TextStyle(
            letterSpacing: 2,
            fontSize: 12,
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Lock wallet now'),
                subtitle: const Text(
                  'Authenticate again to reveal private data',
                ),
                onTap: busy
                    ? null
                    : () {
                        widget.store.auth.lock();
                        message('Wallet locked.');
                      },
              ),
              ListTile(
                leading: const Icon(Icons.password),
                title: const Text('Change wallet PIN'),
                onTap: busy
                    ? null
                    : () => run(() async {
                        if (!await unlock() || !context.mounted) return;
                        final controller = TextEditingController();
                        String? error;
                        final pin = await showDialog<String>(
                          context: context,
                          builder: (c) => StatefulBuilder(
                            builder: (c, update) => AlertDialog(
                              title: const Text('New wallet PIN'),
                              content: TextField(
                                controller: controller,
                                obscureText: true,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'At least 6 digits',
                                  errorText: error,
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () {
                                    if (!RegExp(
                                      r'^\d{6,12}$',
                                    ).hasMatch(controller.text)) {
                                      update(() => error = 'Use 6–12 digits');
                                      return;
                                    }
                                    Navigator.pop(c, controller.text);
                                  },
                                  child: const Text('Save'),
                                ),
                              ],
                            ),
                          ),
                        );
                        controller.dispose();
                        if (pin != null) {
                          if (!widget.store.auth.isUnlocked &&
                              !await unlock()) {
                            return;
                          }
                          await widget.store.auth.setPin(pin);
                          message('PIN updated.');
                        }
                      }),
              ),
              ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('Export encrypted backup'),
                subtitle: const Text(
                  'Password protected · save to a location you choose',
                ),
                onTap: busy ? null : () => run(export),
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('Restore encrypted backup'),
                subtitle: const Text('Validate, then merge or replace'),
                onTap: busy ? null : () => run(restore),
              ),
            ],
          ),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Only on your device',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'No account, ads, analytics, server, or automatic cloud backup. Tasks and family documents are encrypted locally. Clipboard content and files shared to another app leave Supare’s protection. Your chosen file provider may upload exported files; choose a local location for offline storage.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Uninstalling the app or losing its device key removes access to local data. Export an encrypted backup and keep its password safe.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Center(child: Text('Supare 1.0.0 (1) · app.supare.offline')),
      ],
    );
  }
}
