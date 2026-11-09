import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../core/app_store.dart';
import '../models/models.dart';
import 'document_crop.dart';

const _categories = [
  'Aadhaar Card',
  'PAN Card',
  'Voter ID',
  'Driving Licence',
  'Passport',
  'Vehicle RC',
  'Birth Certificate',
  'Caste Certificate',
  'Income Certificate',
  'Education Certificate',
  'Marks Card',
  'Bank Document',
  'Insurance Document',
  'Other',
];
const _relationships = [
  'Myself',
  'Father',
  'Mother',
  'Brother',
  'Sister',
  'Spouse',
  'Child',
  'Custom',
];
String _date(DateTime value) => DateFormat('d MMM yyyy').format(value);
void _message(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
  );
}

/// This gate also works after an external picker has paused and locked the app.
Future<bool> unlockWallet(BuildContext context, AppStore store) async {
  if (store.auth.isUnlocked) return true;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: WalletUnlock(
          store: store,
          onUnlocked: () => Navigator.pop(context, true),
        ),
      ),
    ),
  );
  return result == true;
}

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  String _query = '', _filter = 'All';
  String? _memberId;
  @override
  void initState() {
    super.initState();
    unawaited(widget.store.native.setSecure(true).catchError((_) {}));
    unawaited(cleanWalletTemporaryFiles());
  }

  Future<void> _add() async {
    if (!await unlockWallet(context, widget.store) || !mounted) return;
    if (widget.store.members.isEmpty) {
      await _editMember(context, widget.store);
      if (!mounted || widget.store.members.isEmpty) return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DocumentEditor(store: widget.store, initialMember: _memberId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      if (!widget.store.auth.isUnlocked) {
        return Center(
          child: SingleChildScrollView(
            child: WalletUnlock(
              store: widget.store,
              onUnlocked: () {
                if (mounted) setState(() {});
              },
            ),
          ),
        );
      }
      final store = widget.store;
      final docs = store.documents.where((d) {
        final member = store.members
            .where((m) => m.id == d.memberId)
            .firstOrNull;
        final text =
            '${d.name} ${d.category} ${member?.name ?? ''} ${d.number} ${d.fields.values.join(' ')}'
                .toLowerCase();
        return (_memberId == null || d.memberId == _memberId) &&
            (_query.isEmpty || text.contains(_query.toLowerCase())) &&
            (_filter != 'Favorites' || d.favorite) &&
            (_filter != 'Recent' || d.lastOpened != null);
      }).toList();
      if (_filter == 'Recent') {
        docs.sort((a, b) => b.lastOpened!.compareTo(a.lastOpened!));
      } else {
        docs.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      }
      return Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('Add document'),
        ),
        body: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Family wallet',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Manage family',
                          onPressed: () => _family(context, store),
                          icon: const Icon(Icons.people_outline),
                        ),
                        IconButton(
                          tooltip: 'Lock wallet',
                          onPressed: () {
                            store.auth.lock();
                            setState(() {});
                          },
                          icon: const Icon(Icons.lock_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your documents. Only on this device.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Find a document or number',
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final label in ['All', 'Favorites', 'Recent'])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(label),
                                selected: _filter == label,
                                onSelected: (_) =>
                                    setState(() => _filter = label),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: const Text('Everyone'),
                              selected: _memberId == null,
                              onSelected: (_) =>
                                  setState(() => _memberId = null),
                            ),
                          ),
                          for (final member in store.members)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(member.name),
                                selected: _memberId == member.id,
                                onSelected: (_) =>
                                    setState(() => _memberId = member.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            if (docs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 100),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        store.documents.isEmpty
                            ? Icons.folder_open_outlined
                            : Icons.search_off,
                        size: 56,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        store.documents.isEmpty
                            ? 'Keep important things close'
                            : 'No matching documents',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        store.documents.isEmpty
                            ? 'Add a family member, then securely save a PDF or image. Numbers and files stay encrypted.'
                            : 'Try another name, family member, or filter.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
                      if (store.documents.isEmpty)
                        FilledButton.icon(
                          onPressed: _add,
                          icon: const Icon(Icons.add),
                          label: const Text('Add your first document'),
                        ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                sliver: SliverList.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final member = store.members
                        .where((m) => m.id == d.memberId)
                        .firstOrNull;
                    final expired =
                        d.expiryDate?.isBefore(DateTime.now()) ?? false;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          child: Icon(
                            d.mimeType == 'application/pdf'
                                ? Icons.picture_as_pdf_outlined
                                : Icons.description_outlined,
                          ),
                        ),
                        title: Text(
                          d.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${member?.name ?? 'Family'} · ${d.category}${expired ? '\nExpired ${_date(d.expiryDate!)}' : ''}',
                            style: expired
                                ? TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  )
                                : null,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: d.favorite ? 'Remove favorite' : 'Favorite',
                          icon: Icon(
                            d.favorite
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                          ),
                          onPressed: () async {
                            try {
                              await store.updateDocument(
                                d.copyWith(favorite: !d.favorite),
                              );
                            } catch (e) {
                              if (context.mounted) _message(context, e);
                            }
                          },
                        ),
                        onTap: () async {
                          try {
                            await store.updateDocument(
                              d.copyWith(lastOpened: DateTime.now()),
                            );
                            if (!context.mounted) return;
                            await Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    DocumentDetail(store: store, id: d.id),
                              ),
                            );
                          } catch (e) {
                            if (context.mounted) _message(context, e);
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
}

class WalletUnlock extends StatefulWidget {
  const WalletUnlock({
    super.key,
    required this.store,
    required this.onUnlocked,
  });
  final AppStore store;
  final VoidCallback onUnlocked;
  @override
  State<WalletUnlock> createState() => _WalletUnlockState();
}

class _WalletUnlockState extends State<WalletUnlock> {
  final _pin = TextEditingController(), _confirm = TextEditingController();
  bool? _hasPin;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final has = await widget.store.auth.hasPin;
      if (mounted) setState(() => _hasPin = has);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Secure storage could not be opened. $e');
      }
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _unlock({bool biometric = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_hasPin == false) {
        if (!RegExp(r'^\d{6,12}$').hasMatch(_pin.text)) {
          throw const FormatException('Choose a PIN with 6 to 12 digits.');
        }
        if (_pin.text != _confirm.text) {
          throw const FormatException('The PINs do not match.');
        }
        await widget.store.auth.setPin(_pin.text);
      } else {
        final ok = biometric
            ? await widget.store.auth.authenticate()
            : await widget.store.auth.unlockWithPin(_pin.text);
        if (!ok) {
          throw const FormatException(
            'Could not unlock. Check your PIN or use device authentication.',
          );
        }
      }
      await widget.store.refreshWallet();
      if (mounted) widget.onUnlocked();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e.toString().replaceFirst('FormatException: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: const Icon(Icons.lock_outline_rounded, size: 32),
          ),
          const SizedBox(height: 24),
          Text(
            _hasPin == false ? 'Your private space' : 'Unlock your wallet',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            _hasPin == false
                ? 'Create a 6–12 digit PIN. Your documents are encrypted on this device. Remember your PIN and keep a password-protected backup.'
                : 'Use your wallet PIN or your device’s secure authentication.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (_hasPin == null && _error == null)
            const CircularProgressIndicator(),
          if (_hasPin != null) ...[
            TextField(
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 12,
              enableSuggestions: false,
              autocorrect: false,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: _hasPin! ? 'Wallet PIN' : 'New PIN',
                counterText: '',
              ),
              onSubmitted: (_) {
                if (_hasPin! && !_busy) _unlock();
              },
            ),
            if (!_hasPin!) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: true,
                maxLength: 12,
                keyboardType: TextInputType.number,
                enableSuggestions: false,
                autocorrect: false,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Confirm PIN',
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : () => _unlock(),
                child: Text(
                  _busy
                      ? 'Unlocking…'
                      : _hasPin!
                      ? 'Unlock'
                      : 'Create secure wallet',
                ),
              ),
            ),
            if (_hasPin!)
              TextButton.icon(
                onPressed: _busy ? null : () => _unlock(biometric: true),
                icon: const Icon(Icons.fingerprint),
                label: const Text('Use device authentication'),
              ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    ),
  );
}

Future<void> _family(BuildContext context, AppStore store) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Family members',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final member in store.members)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Text(member.name.characters.first.toUpperCase()),
                      ),
                      title: Text(member.name),
                      subtitle: Text(member.relationship),
                      onTap: () => _editMember(context, store, member: member),
                      trailing: IconButton(
                        tooltip: 'Delete family member',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final count = store.documents
                              .where((d) => d.memberId == member.id)
                              .length;
                          if (count > 0) {
                            _message(
                              context,
                              'Move or delete this member’s $count documents before removing them.',
                            );
                            return;
                          }
                          final yes = await _confirm(
                            context,
                            'Remove ${member.name}?',
                            'This removes the local family profile.',
                          );
                          if (yes) {
                            try {
                              await store.deleteMember(member.id);
                            } catch (e) {
                              if (context.mounted) _message(context, e);
                            }
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _editMember(context, store),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add family member'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _editMember(
  BuildContext context,
  AppStore store, {
  FamilyMember? member,
}) async {
  final name = TextEditingController(text: member?.name ?? '');
  var relation = member?.relationship ?? 'Myself';
  if (!_relationships.contains(relation)) relation = 'Custom';
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          member == null ? 'Add family member' : 'Edit family member',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: relation,
                decoration: const InputDecoration(labelText: 'Relationship'),
                items: _relationships
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => relation = v!,
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) {
                setState(() => error = 'Enter a name.');
                return;
              }
              try {
                await store.saveMember(
                  FamilyMember(
                    id: member?.id ?? const Uuid().v4(),
                    name: name.text.trim(),
                    relationship: relation,
                  ),
                );
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) setState(() => error = e.toString());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
}

class DocumentEditor extends StatefulWidget {
  const DocumentEditor({
    super.key,
    required this.store,
    this.document,
    this.initialMember,
  });
  final AppStore store;
  final WalletDocument? document;
  final String? initialMember;
  @override
  State<DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<DocumentEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _number, _authority;
  late String _category, _member, _id;
  DateTime? _issued, _expires;
  final List<(TextEditingController, TextEditingController)> _custom = [];
  Uint8List? _bytes;
  String _fileName = '', _mime = '';
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    final d = widget.document;
    _id = d?.id ?? const Uuid().v4();
    widget.store.addListener(_changed);
    _name = TextEditingController(text: d?.name ?? '');
    _number = TextEditingController(text: d?.number ?? '');
    _authority = TextEditingController(text: d?.authority ?? '');
    _category = d?.category ?? 'Other';
    if (!_categories.contains(_category)) _category = 'Other';
    _member =
        d?.memberId ?? widget.initialMember ?? widget.store.members.first.id;
    _issued = d?.issueDate;
    _expires = d?.expiryDate;
    _fileName = d?.fileName ?? '';
    _mime = d?.mimeType ?? '';
    for (final entry in (d?.fields ?? <String, String>{}).entries) {
      _custom.add((
        TextEditingController(text: entry.key),
        TextEditingController(text: entry.value),
      ));
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_changed);
    _name.dispose();
    _number.dispose();
    _authority.dispose();
    for (final c in _custom) {
      c.$1.dispose();
      c.$2.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _pick({bool camera = false}) async {
    try {
      Uint8List bytes;
      String fileName;
      if (camera) {
        final photo = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 3200,
          maxHeight: 3200,
          imageQuality: 92,
        );
        if (photo == null) return;
        bytes = await photo.readAsBytes();
        fileName = 'Scan-${DateTime.now().millisecondsSinceEpoch}.jpg';
        // The camera plugin's private capture is only an import staging file.
        try {
          await File(photo.path).delete();
        } on FileSystemException {
          /* OS may already remove it. */
        }
        if (!mounted ||
            !await unlockWallet(context, widget.store) ||
            !mounted) {
          return;
        }
        final cropped = await Navigator.push<Uint8List>(
          context,
          MaterialPageRoute(
            builder: (_) => DocumentCrop(
              bytes: bytes,
              privacyGuard: (context, child) => AnimatedBuilder(
                animation: widget.store,
                builder: (context, _) {
                  if (widget.store.auth.isUnlocked) return child;
                  return Scaffold(
                    appBar: AppBar(title: const Text('Scan document')),
                    body: Center(
                      child: SingleChildScrollView(
                        child: WalletUnlock(
                          store: widget.store,
                          onUnlocked: _changed,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        if (cropped == null) return;
        bytes = cropped;
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'pdf',
            'jpg',
            'jpeg',
            'png',
            'heic',
            'heif',
            'webp',
          ],
          withData: false,
        );
        if (result == null) return;
        final file = result.files.single;
        if (file.size > AppStore.maxFileBytes) {
          throw const FormatException('Choose a file smaller than 25 MB.');
        }
        bytes = file.bytes ?? await File(file.path!).readAsBytes();
        fileName = file.name;
        await FilePicker.platform.clearTemporaryFiles();
      }
      if (bytes.length > AppStore.maxFileBytes) {
        throw const FormatException('Choose a file smaller than 25 MB.');
      }
      if (!mounted || !await unlockWallet(context, widget.store)) return;
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _fileName = path.basename(fileName);
        _mime = switch (path.extension(fileName).toLowerCase()) {
          '.pdf' => 'application/pdf',
          '.png' => 'image/png',
          '.heic' || '.heif' => 'image/heic',
          '.webp' => 'image/webp',
          _ => 'image/jpeg',
        };
        if (_name.text.trim().isEmpty) {
          _name.text = path.basenameWithoutExtension(fileName);
        }
      });
    } catch (e) {
      if (mounted) _message(context, e);
    } finally {
      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {
        /* No staged file may exist. */
      }
    }
  }

  Future<void> _chooseDate(bool expiry) async {
    final date = await showDatePicker(
      context: context,
      initialDate: (expiry ? _expires : _issued) ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (date != null && mounted) {
      setState(() {
        if (expiry) {
          _expires = date;
        } else {
          _issued = date;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_bytes == null && widget.document == null) {
      _message(context, 'Attach a document file or scan before saving.');
      return;
    }
    if (_issued != null && _expires != null && _expires!.isBefore(_issued!)) {
      _message(context, 'Expiry date must be on or after the issue date.');
      return;
    }
    if (!await unlockWallet(context, widget.store) || !mounted) return;
    setState(() => _busy = true);
    try {
      final fields = <String, String>{};
      for (final c in _custom) {
        final key = c.$1.text.trim();
        final value = c.$2.text.trim();
        if (key.isEmpty && value.isEmpty) continue;
        if (key.isEmpty) {
          throw const FormatException('Give each additional field a label.');
        }
        if ([
          'name',
          'document number',
          'owner',
          'issuing authority',
          'issue date',
          'expiry date',
        ].contains(key.toLowerCase())) {
          throw const FormatException(
            'Choose an additional field label different from the standard details.',
          );
        }
        if (fields.keys.any(
          (label) => label.toLowerCase() == key.toLowerCase(),
        )) {
          throw const FormatException(
            'Additional field labels must be unique.',
          );
        }
        fields[key] = value;
      }
      final old = widget.document;
      final doc = WalletDocument(
        id: _id,
        name: _name.text.trim(),
        category: _category,
        memberId: _member,
        number: _number.text.trim(),
        authority: _authority.text.trim(),
        issueDate: _issued,
        expiryDate: _expires,
        fields: fields,
        fileName: _fileName,
        mimeType: _mime,
        fileId: old?.fileId ?? '',
        favorite: old?.favorite ?? false,
        lastOpened: old?.lastOpened,
        digest: old?.digest ?? '',
      );
      if (_bytes != null) {
        await widget.store.importDocument(doc, _bytes!);
      } else {
        await widget.store.updateDocument(doc);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        final saved = widget.store.documents
            .where((d) => d.id == _id)
            .firstOrNull;
        if (saved != null && e.toString().contains('Document saved')) {
          _message(
            context,
            'Document saved. Its renewal reminder needs attention: $e',
          );
          Navigator.pop(context);
        } else {
          _message(context, e);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.store.auth.isUnlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Document')),
        body: Center(
          child: SingleChildScrollView(
            child: WalletUnlock(store: widget.store, onUnlocked: _changed),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.document == null ? 'Add document' : 'Edit document'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
          children: [
            Text(
              'The details you need, close at hand.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              maxLength: 120,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Document name'),
              validator: (v) =>
                  v!.trim().isEmpty ? 'Enter a document name.' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _member,
              decoration: const InputDecoration(labelText: 'Family member'),
              items: widget.store.members
                  .map(
                    (m) => DropdownMenuItem(value: m.id, child: Text(m.name)),
                  )
                  .toList(),
              onChanged: (v) => _member = v!,
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => _category = v!,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _number,
              maxLength: 160,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Document number (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _authority,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'Issuing authority (optional)',
              ),
            ),
            const SizedBox(height: 12),
            _dateTile(
              'Issue date',
              _issued,
              () => _chooseDate(false),
              () => setState(() => _issued = null),
            ),
            _dateTile(
              'Expiry date',
              _expires,
              () => _chooseDate(true),
              () => setState(() => _expires = null),
            ),
            if (_expires != null)
              const Padding(
                padding: EdgeInsets.only(top: 6, bottom: 14),
                child: Text(
                  'A local renewal reminder is scheduled 30 days before expiry (or on expiry if closer), where notification permission allows.',
                ),
              ),
            const SizedBox(height: 18),
            Text(
              'Additional details',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (var i = 0; i < _custom.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          TextField(
                            controller: _custom[i].$1,
                            maxLength: 80,
                            decoration: const InputDecoration(
                              labelText: 'Field label',
                            ),
                          ),
                          TextField(
                            controller: _custom[i].$2,
                            maxLength: 500,
                            decoration: const InputDecoration(
                              labelText: 'Value',
                            ),
                            enableSuggestions: false,
                            autocorrect: false,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove field',
                      onPressed: () {
                        final pair = _custom.removeAt(i);
                        setState(() {});
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          pair.$1.dispose();
                          pair.$2.dispose();
                        });
                      },
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _custom.length >= 30
                    ? null
                    : () => setState(
                        () => _custom.add((
                          TextEditingController(),
                          TextEditingController(),
                        )),
                      ),
                icon: const Icon(Icons.add),
                label: const Text('Add a field'),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attachment',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _fileName.isEmpty
                          ? 'PDF, JPG, PNG, HEIC or WebP · up to 25 MB'
                          : _fileName,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _pick,
                          icon: const Icon(Icons.attach_file),
                          label: Text(
                            _fileName.isEmpty ? 'Choose file' : 'Replace file',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _pick(camera: true),
                          icon: const Icon(Icons.document_scanner_outlined),
                          label: const Text('Scan & crop'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Encrypting & saving…' : 'Save securely'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateTile(
    String label,
    DateTime? value,
    VoidCallback choose,
    VoidCallback clear,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(value == null ? 'Optional' : _date(value)),
    onTap: choose,
    trailing: value == null
        ? const Icon(Icons.calendar_today_outlined)
        : IconButton(
            tooltip: 'Clear $label',
            onPressed: clear,
            icon: const Icon(Icons.close),
          ),
  );
}

class DocumentDetail extends StatefulWidget {
  const DocumentDetail({super.key, required this.store, required this.id});
  final AppStore store;
  final String id;
  @override
  State<DocumentDetail> createState() => _DocumentDetailState();
}

class _DocumentDetailState extends State<DocumentDetail> {
  bool _revealed = false, _busy = false;
  Future<void> _copy(String value) async {
    if (!await unlockWallet(context, widget.store) || !mounted) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      _message(
        context,
        'Copied. Clipboard cleanup is attempted in 45 seconds if unchanged.',
      );
    }
    Timer(const Duration(seconds: 45), () async {
      try {
        if ((await Clipboard.getData(Clipboard.kTextPlain))?.text == value) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      } catch (_) {
        /* OS clipboard policy may deny background access. */
      }
    });
  }

  Future<void> _file(WalletDocument doc, {bool share = false}) async {
    if (share &&
        !await _confirm(
          context,
          'Share this document?',
          'The selected app will receive a decrypted copy and may upload or retain it. A temporary share copy is removed after 10 minutes while Supare is running, or on a later opening. Share only with apps you trust.',
          confirm: 'Continue',
        )) {
      return;
    }
    if (!mounted || !await unlockWallet(context, widget.store) || !mounted) {
      return;
    }
    setState(() => _busy = true);
    Directory? directory;
    try {
      final bytes = await widget.store.readDocument(doc.id);
      final temp = await getTemporaryDirectory();
      if (!mounted || !widget.store.auth.isUnlocked) {
        throw StateError('Wallet locked. Unlock and try again.');
      }
      directory = await Directory(
        path.join(temp.path, 'supare-private-${const Uuid().v4()}'),
      ).create();
      var safeName = doc.fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_');
      final extension = switch (doc.mimeType) {
        'application/pdf' => '.pdf',
        'image/png' => '.png',
        'image/heic' || 'image/heif' => '.heic',
        'image/webp' => '.webp',
        _ => '.jpg',
      };
      if (path.basenameWithoutExtension(safeName).trim().isEmpty ||
          safeName == '.' ||
          safeName == '..') {
        safeName = 'document';
      }
      final allowedExtensions = switch (doc.mimeType) {
        'application/pdf' => ['.pdf'],
        'image/png' => ['.png'],
        'image/heic' || 'image/heif' => ['.heic', '.heif'],
        'image/webp' => ['.webp'],
        _ => ['.jpg', '.jpeg'],
      };
      if (!allowedExtensions.contains(path.extension(safeName).toLowerCase())) {
        safeName = '$safeName$extension';
      }
      final file = File(path.join(directory.path, safeName));
      if (!mounted || !widget.store.auth.isUnlocked) {
        throw StateError('Wallet locked. Unlock and try again.');
      }
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted || !widget.store.auth.isUnlocked) {
        throw StateError('Wallet locked. Unlock and try again.');
      }
      if (share) {
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: doc.mimeType)],
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
      } else {
        await widget.store.native.previewFile(file.path, doc.mimeType);
      }
    } catch (e) {
      if (mounted) _message(context, e);
    } finally {
      if (share) {
        // Give receiving apps time to open the granted file. Supare does not
        // control copies retained by the receiving app.
        Timer(
          const Duration(minutes: 10, seconds: 1),
          () => unawaited(cleanWalletTemporaryFiles()),
        );
      } else if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      if (!widget.store.auth.isUnlocked) {
        return Scaffold(
          appBar: AppBar(title: const Text('Document')),
          body: Center(
            child: SingleChildScrollView(
              child: WalletUnlock(
                store: widget.store,
                onUnlocked: () {
                  if (mounted) setState(() => _revealed = false);
                },
              ),
            ),
          ),
        );
      }
      final d = widget.store.documents
          .where((d) => d.id == widget.id)
          .firstOrNull;
      if (d == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Document')),
          body: const Center(child: Text('This document was removed.')),
        );
      }
      final member = widget.store.members
          .where((m) => m.id == d.memberId)
          .firstOrNull;
      final fields = <String, String>{
        'Name': d.name,
        if (d.number.isNotEmpty) 'Document number': d.number,
        if (member != null) 'Owner': member.name,
        if (d.authority.isNotEmpty) 'Issuing authority': d.authority,
        if (d.issueDate != null) 'Issue date': _date(d.issueDate!),
        if (d.expiryDate != null) 'Expiry date': _date(d.expiryDate!),
        ...d.fields,
      };
      return Scaffold(
        appBar: AppBar(
          title: const Text('Document'),
          actions: [
            IconButton(
              tooltip: 'Edit document',
              onPressed: _busy
                  ? null
                  : () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            DocumentEditor(store: widget.store, document: d),
                      ),
                    ),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Delete document',
              onPressed: _busy
                  ? null
                  : () async {
                      if (await _confirm(
                        context,
                        'Delete document?',
                        'The encrypted file and its details will be removed from this device.',
                      )) {
                        try {
                          await widget.store.deleteDocument(d.id);
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          if (context.mounted) _message(context, e);
                        }
                      }
                    },
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: const Icon(Icons.description_outlined, size: 32),
            ),
            const SizedBox(height: 20),
            Text(
              d.name,
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '${member?.name ?? 'Family'} · ${d.category}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _file(d),
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(_busy ? 'Opening…' : 'View document'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _file(d, share: true),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Quick copy',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    if (!_revealed &&
                        !await unlockWallet(context, widget.store)) {
                      return;
                    }
                    if (mounted) setState(() => _revealed = !_revealed);
                  },
                  icon: Icon(
                    _revealed
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  label: Text(_revealed ? 'Hide details' : 'Reveal details'),
                ),
              ],
            ),
            const Text(
              'Tap a copy button to paste a field into a form. Clipboard contents may be visible to other apps.',
            ),
            const SizedBox(height: 16),
            for (final field in fields.entries)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 5,
                  ),
                  title: Text(
                    field.key,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _revealed || field.key == 'Name' || field.key == 'Owner'
                          ? field.value
                          : '••••••••',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Copy ${field.key}',
                    onPressed: () => _copy(field.value),
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(d.fileName, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  await widget.store.updateDocument(
                    d.copyWith(favorite: !d.favorite),
                  );
                } catch (e) {
                  if (context.mounted) _message(context, e);
                }
              },
              icon: Icon(d.favorite ? Icons.star : Icons.star_border),
              label: Text(
                d.favorite ? 'Remove from favorites' : 'Add to favorites',
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String description, {
  String confirm = 'Remove',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirm),
          ),
        ],
      ),
    ) ??
    false;

Future<void> cleanWalletTemporaryFiles() async {
  try {
    final cache = await getTemporaryDirectory();
    await for (final entity in cache.list()) {
      if (entity is Directory &&
          path.basename(entity.path).startsWith('supare-private-') &&
          DateTime.now().difference((await entity.stat()).modified) >
              const Duration(minutes: 10)) {
        await entity.delete(recursive: true);
      }
    }
    await _cleanShareCache();
  } on FileSystemException {
    /* OS may already have purged cache files. */
  } on MissingPluginException {
    /* Not a supported mobile runtime. */
  } on PlatformException {
    /* Cache access may be temporarily unavailable. */
  }
}

Future<void> _cleanShareCache() async {
  try {
    final cache = await getTemporaryDirectory();
    for (final name in ['share', 'share_plus']) {
      final directory = Directory(path.join(cache.path, name));
      if (await directory.exists() &&
          DateTime.now().difference((await directory.stat()).modified) >
              const Duration(minutes: 10)) {
        await directory.delete(recursive: true);
      }
    }
  } on FileSystemException {
    /* Files may be in use by the native share sheet. */
  } on MissingPluginException {
    /* Not a supported mobile runtime. */
  } on PlatformException {
    /* Cache access may be temporarily unavailable. */
  }
}
