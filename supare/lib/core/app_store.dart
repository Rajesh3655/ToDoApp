import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'crypto_service.dart';
import 'native_bridge.dart';
import 'vault_auth.dart';

/// Encrypted local records and document files. SQL indexes contain opaque IDs only.
class AppStore extends ChangeNotifier {
  AppStore._(this._db, this._directory, this._crypto, this.auth, this.native);
  final Database _db;
  final Directory _directory;
  final CryptoService _crypto;
  final VaultAuth auth;
  final NativeBridge native;
  final List<TaskItem> _tasks = [];
  final List<FamilyMember> _members = [];
  final List<WalletDocument> _documents = [];
  final Map<String, String> _settings = {};
  Future<void> _pending = Future.value();
  bool _closed = false;
  String? lastAlarmError;
  String? lastWalletError;
  static const maxFileBytes = 25 * 1024 * 1024;
  static const maxBackupBytes = 200 * 1024 * 1024;
  static const _uuid = Uuid();
  List<TaskItem> get tasks => List.unmodifiable(_tasks);
  List<FamilyMember> get members =>
      List.unmodifiable(auth.isUnlocked ? _members : <FamilyMember>[]);
  List<WalletDocument> get documents =>
      List.unmodifiable(auth.isUnlocked ? _documents : <WalletDocument>[]);
  Map<String, String> get settings => Map.unmodifiable(_settings);

  static Future<AppStore> open({
    Directory? directory,
    DatabaseFactory? databaseFactory,
    CryptoService? crypto,
    VaultAuth? auth,
    NativeBridge? native,
  }) async {
    final root =
        directory ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'supare'),
        );
    await root.create(recursive: true);
    await Directory(p.join(root.path, 'files')).create(recursive: true);
    final cipher = crypto ?? CryptoService();
    await cipher.initialize();
    final factory = databaseFactory ?? sqlite.databaseFactory;
    final database = await factory.openDatabase(
      p.join(root.path, 'supare.db'),
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA secure_delete = ON');
        },
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE records(kind TEXT NOT NULL, id TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(kind,id))',
          );
        },
      ),
    );
    final store = AppStore._(
      database,
      root,
      cipher,
      auth ?? VaultAuth(),
      native ?? NativeBridge(),
    );
    await store._loadPublic();
    store.auth.addListener(store._authChanged);
    if (store.auth.isUnlocked) await store.refreshWallet();
    await store.reconcileNativeActions();
    await store.rescheduleAlarms();
    return store;
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _pending = _pending.then((_) async {
      if (_closed) {
        completer.completeError(StateError('The database is closed'));
        return;
      }
      try {
        completer.complete(await operation());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  void _requireUnlocked() {
    if (!auth.isUnlocked) {
      throw StateError('Unlock the wallet to access family documents');
    }
  }

  void _authChanged() {
    if (!auth.isUnlocked) {
      _members.clear();
      _documents.clear();
      lastWalletError = null;
      notifyListeners();
    } else {
      unawaited(
        refreshWallet().catchError((Object error) {
          lastWalletError = 'Could not open the encrypted wallet: $error';
          notifyListeners();
        }),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _records(String kind) async {
    final rows = await _db.query(
      'records',
      where: 'kind = ?',
      whereArgs: [kind],
    );
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final plain = await _crypto.open(
        row['payload'] as Uint8List,
        context: 'record:$kind:${row['id']}',
      );
      result.add(
        Map<String, dynamic>.from(jsonDecode(utf8.decode(plain)) as Map),
      );
    }
    return result;
  }

  Future<Map<String, Object>> _encoded(
    String kind,
    String id,
    Map<String, dynamic> value,
  ) async => {
    'kind': kind,
    'id': id,
    'payload': await _crypto.seal(
      Uint8List.fromList(utf8.encode(jsonEncode(value))),
      context: 'record:$kind:$id',
    ),
  };

  Future<void> _put(String kind, String id, Map<String, dynamic> value) async {
    await _db.insert(
      'records',
      await _encoded(kind, id, value),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _loadPublic() async {
    final tasks = (await _records('task')).map(TaskItem.fromJson).toList();
    final settings = await _records('setting');
    _tasks
      ..clear()
      ..addAll(tasks);
    _settings.clear();
    for (final setting in settings) {
      _settings[setting['id'] as String] = setting['value'] as String;
    }
  }

  Future<void> refreshWallet() => _serial(() async {
    _requireUnlocked();
    final members = (await _records(
      'member',
    )).map(FamilyMember.fromJson).toList();
    final documents = (await _records(
      'document',
    )).map(WalletDocument.fromJson).toList();
    if (members.isEmpty) {
      const myself = FamilyMember(
        id: 'myself',
        name: 'Myself',
        relationship: 'Myself',
      );
      await _put('member', myself.id, myself.toJson());
      members.add(myself);
    }
    // Authentication may have expired while the encrypted rows were read.
    _requireUnlocked();
    _members
      ..clear()
      ..addAll(members);
    _documents
      ..clear()
      ..addAll(documents);
    lastWalletError = null;
    notifyListeners();
  });

  Future<void> setSetting(String name, String value) => _serial(() async {
    _validateId(name);
    if (value.length > 10000) {
      throw const FormatException('Setting is too long');
    }
    await _put('setting', name, {'id': name, 'value': value});
    _settings[name] = value;
    notifyListeners();
  });

  Future<void> saveTask(TaskItem task) => _serial(() async {
    _validateTask(task);
    await _put('task', task.id, task.toJson());
    _tasks.removeWhere((item) => item.id == task.id);
    _tasks.add(task);
    notifyListeners();
    await _scheduleTask(task);
  });
  Future<void> deleteTask(String id) => _serial(() async {
    await _db.delete(
      'records',
      where: 'kind = ? AND id = ?',
      whereArgs: ['task', id],
    );
    _tasks.removeWhere((task) => task.id == id);
    notifyListeners();
    await native.cancelTask(id);
  });
  Future<void> completeTask(String id) => _serial(() => _completeTask(id));
  Future<void> _completeTask(
    String id, {
    DateTime? completedAt,
    DateTime? occurrenceDue,
  }) async {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0 || _tasks[index].isCompleted) return;
    final task = _tasks[index];
    final complete = task.copyWith(
      completedAt: completedAt ?? DateTime.now(),
      due: occurrenceDue,
    );
    final next = task.nextOccurrence();
    final successor = next == null
        ? null
        : task.copyWith(id: _uuid.v4(), due: next, clearCompleted: true);
    final oldRow = await _encoded('task', complete.id, complete.toJson());
    final nextRow = successor == null
        ? null
        : await _encoded('task', successor.id, successor.toJson());
    await _db.transaction((txn) async {
      await txn.insert(
        'records',
        oldRow,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (nextRow != null) await txn.insert('records', nextRow);
    });
    _tasks[index] = complete;
    if (successor != null) _tasks.add(successor);
    notifyListeners();
    await native.cancelTask(id);
    if (successor != null) await _scheduleTask(successor);
  }

  Future<void> restoreTask(String id) => _serial(() async {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    // A recurring completion already created its successor. Restore the historical
    // occurrence as a one-time task so undo cannot fork duplicate recurring series.
    final restored = _tasks[index].copyWith(
      clearCompleted: true,
      repeat: _tasks[index].isCompleted ? 'none' : _tasks[index].repeat,
    );
    await _put('task', id, restored.toJson());
    _tasks[index] = restored;
    notifyListeners();
    await _scheduleTask(restored);
  });
  Future<void> snoozeTask(String id, int minutes) => _serial(() async {
    if (![5, 10, 15].contains(minutes)) {
      throw const FormatException('Choose 5, 10 or 15 minutes');
    }
    final index = _tasks.indexWhere(
      (task) => task.id == id && !task.isCompleted,
    );
    if (index < 0) return;
    final task = _tasks[index].copyWith(
      due: DateTime.now().add(Duration(minutes: minutes)),
    );
    await _put('task', id, task.toJson());
    _tasks[index] = task;
    notifyListeners();
    await _scheduleTask(task);
  });

  Future<void> _scheduleTask(TaskItem task) async {
    try {
      if (task.isCompleted) {
        await native.cancelTask(task.id);
      } else if (task.due.isAfter(DateTime.now())) {
        await native.schedule(task);
      } else if (task.repeat != 'none') {
        await native.schedule(task.copyWith(due: task.nextOccurrence()!));
      } else {
        await native.cancelTask(task.id);
      }
      lastAlarmError = null;
    } catch (error) {
      lastAlarmError =
          'Task saved locally, but its reminder could not be scheduled: $error';
      notifyListeners();
      throw StateError(lastAlarmError!);
    }
  }

  /// Native receiver actions survive app closure; reconcile before rescheduling.
  Future<void> reconcileNativeActions() => _serial(() async {
    List<Map<String, dynamic>> actions;
    try {
      actions = await native.drainActions();
    } catch (error) {
      lastAlarmError = 'Cannot read native reminder actions: $error';
      notifyListeners();
      return;
    }
    for (final event in actions) {
      final id = event['id'] as String?;
      if (id == null) continue;
      final eventKey =
          event['eventId'] as String? ??
          '${event['atMillis']}:$id:${event['action']}';
      final index = _tasks.indexWhere((task) => task.id == id);
      if (index < 0 || _settings['lastNativeEvent'] == eventKey) {
        await native.ackActions([eventKey]);
        continue;
      }
      if (event['action'] == 'done') {
        final eventTime = DateTime.fromMillisecondsSinceEpoch(
          event['atMillis'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        );
        final occurrenceMillis = event['occurrenceMillis'] as int?;
        final original = _tasks[index];
        if (!original.isCompleted) {
          await _completeTask(
            id,
            completedAt: eventTime,
            occurrenceDue: occurrenceMillis == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(occurrenceMillis),
          );
        } else if (original.repeat != 'none' &&
            eventTime.isAfter(original.completedAt!)) {
          // Several native recurrences may be completed while Flutter is closed.
          // Each event becomes a deterministic one-time history row; replay is
          // idempotent and only the first completion creates a future successor.
          final hash = (await Sha256().hash(utf8.encode(eventKey))).bytes;
          final historyId =
              'nativehistory:${hash.map((value) => value.toRadixString(16).padLeft(2, '0')).join()}';
          final history = original.copyWith(
            id: historyId,
            repeat: 'none',
            due: occurrenceMillis == null
                ? eventTime
                : DateTime.fromMillisecondsSinceEpoch(occurrenceMillis),
            completedAt: eventTime,
          );
          await _put('task', historyId, history.toJson());
          _tasks.removeWhere((task) => task.id == historyId);
          _tasks.add(history);
        }
      } else if (event['action'] == 'snooze') {
        final dueMillis = event['dueMillis'] as int?;
        final atMillis =
            event['atMillis'] as int? ?? DateTime.now().millisecondsSinceEpoch;
        final minutes = event['minutes'] as int? ?? 5;
        if (dueMillis != null || event['action'] == 'snooze') {
          final due = DateTime.fromMillisecondsSinceEpoch(
            dueMillis ?? atMillis + minutes * 60000,
          );
          final source = _tasks[index];
          final pendingIndex = source.isCompleted
              ? _tasks.indexWhere(
                  (task) =>
                      !task.isCompleted && task.seriesId == source.seriesId,
                )
              : index;
          if (pendingIndex >= 0) {
            final updated = _tasks[pendingIndex].copyWith(due: due);
            await _put('task', updated.id, updated.toJson());
            _tasks[pendingIndex] = updated;
          }
        }
      }
      await _put('setting', 'lastNativeEvent', {
        'id': 'lastNativeEvent',
        'value': eventKey,
      });
      _settings['lastNativeEvent'] = eventKey;
      await native.ackActions([eventKey]);
    }
    notifyListeners();
  });

  Future<void> rescheduleAlarms() => _serial(_rescheduleAlarms);

  Future<void> _rescheduleAlarms() async {
    final errors = <String>[];
    for (final task in List<TaskItem>.of(_tasks)) {
      if (task.isCompleted) continue;
      final scheduledTask = task.due.isAfter(DateTime.now())
          ? task
          : task.repeat == 'none'
          ? null
          : task.copyWith(due: task.nextOccurrence()!);
      if (scheduledTask == null) continue;
      try {
        await native.schedule(scheduledTask);
      } catch (error) {
        errors.add(error.toString());
      }
    }
    // Expiry scheduling can be recovered without decrypting wallet metadata by a
    // dedicated encrypted record whose title is deliberately generic.
    for (final expiry in await _records('expiry')) {
      if ((expiry['dueMillis'] as int) <=
          DateTime.now().millisecondsSinceEpoch) {
        continue;
      }
      try {
        await native.scheduleTask(expiry);
      } catch (error) {
        errors.add(error.toString());
      }
    }
    lastAlarmError = errors.isEmpty
        ? null
        : 'Some reminders need permission or could not be scheduled: ${errors.first}';
    notifyListeners();
  }

  Future<void> saveMember(FamilyMember member) => _serial(() async {
    _requireUnlocked();
    _validateMember(member);
    await _put('member', member.id, member.toJson());
    if (auth.isUnlocked) {
      _members.removeWhere((value) => value.id == member.id);
      _members.add(member);
    }
    notifyListeners();
  });
  Future<void> deleteMember(String id) => _serial(() async {
    _requireUnlocked();
    if (_documents.any((doc) => doc.memberId == id)) {
      throw StateError('Move or delete this family member\'s documents first');
    }
    await _db.delete(
      'records',
      where: 'kind = ? AND id = ?',
      whereArgs: ['member', id],
    );
    _members.removeWhere((value) => value.id == id);
    notifyListeners();
  });

  Future<void> importDocument(WalletDocument document, Uint8List bytes) =>
      _serial(() async {
        _requireUnlocked();
        _validateDocument(document);
        _validateFile(bytes, document.mimeType);
        if (!_members.any((m) => m.id == document.memberId)) {
          throw StateError('Select an existing family member');
        }
        final digest = (await Sha256().hash(bytes)).bytes;
        final checksum = base64UrlEncode(digest);
        if (_documents.any(
          (value) => value.id != document.id && value.digest == checksum,
        )) {
          throw StateError('This file is already saved in the wallet');
        }
        final old = _documents
            .where((value) => value.id == document.id)
            .firstOrNull;
        final fileId = _uuid.v4();
        final encrypted = await _crypto.seal(bytes, context: 'file:$fileId');
        _requireUnlocked();
        final file = _file(fileId);
        await file.writeAsBytes(encrypted, flush: true);
        final saved = document.copyWith(fileId: fileId, digest: checksum);
        try {
          _requireUnlocked();
          await _put('document', saved.id, saved.toJson());
        } catch (_) {
          await file.delete();
          rethrow;
        }
        if (auth.isUnlocked) {
          _documents.removeWhere((value) => value.id == saved.id);
          _documents.add(saved);
        }
        notifyListeners();
        if (old != null &&
            old.fileId != fileId &&
            await _file(old.fileId).exists()) {
          await _file(old.fileId).delete();
        }
        await _scheduleExpiry(saved);
      });

  Future<void> updateDocument(WalletDocument document) => _serial(() async {
    _requireUnlocked();
    _validateDocument(document);
    final index = _documents.indexWhere((value) => value.id == document.id);
    if (index < 0) throw StateError('Document no longer exists');
    if (!_members.any((m) => m.id == document.memberId)) {
      throw StateError('Select an existing family member');
    }
    final existing = _documents[index];
    // File identity changes only through authenticated import/replace.
    final saved = document.copyWith(
      fileId: existing.fileId,
      digest: existing.digest,
    );
    await _put('document', saved.id, saved.toJson());
    if (auth.isUnlocked &&
        index < _documents.length &&
        _documents[index].id == saved.id) {
      _documents[index] = saved;
    }
    notifyListeners();
    await _scheduleExpiry(saved);
  });
  Future<void> deleteDocument(String id) => _serial(() async {
    _requireUnlocked();
    final doc = _documents.where((value) => value.id == id).firstOrNull;
    await _db.transaction((txn) async {
      await txn.delete(
        'records',
        where: 'kind = ? AND id = ?',
        whereArgs: ['document', id],
      );
      await txn.delete(
        'records',
        where: 'kind = ? AND id = ?',
        whereArgs: ['expiry', 'expiry:$id'],
      );
    });
    _documents.removeWhere((value) => value.id == id);
    notifyListeners();
    if (doc != null && await _file(doc.fileId).exists()) {
      await _file(doc.fileId).delete();
    }
    await native.cancelTask('expiry:$id');
  });
  Future<Uint8List> readDocument(String id) => _serial(() async {
    _requireUnlocked();
    final doc = _documents.where((value) => value.id == id).firstOrNull;
    if (doc == null) throw StateError('Document no longer exists');
    final bytes = await _crypto.open(
      await _file(doc.fileId).readAsBytes(),
      context: 'file:${doc.fileId}',
    );
    _requireUnlocked();
    final checksum = base64UrlEncode((await Sha256().hash(bytes)).bytes);
    if (checksum != doc.digest) {
      throw const FormatException('Document integrity check failed');
    }
    _requireUnlocked();
    return bytes;
  });
  File _file(String id) {
    _validateId(id);
    return File(p.join(_directory.path, 'files', '$id.enc'));
  }

  Future<void> _scheduleExpiry(WalletDocument doc) async {
    final id = 'expiry:${doc.id}';
    try {
      await _db.delete(
        'records',
        where: 'kind = ? AND id = ?',
        whereArgs: ['expiry', id],
      );
      await native.cancelTask(id);
      if (doc.expiryDate == null) return;
      final expiry = doc.expiryDate!;
      var due = DateTime(
        expiry.year,
        expiry.month,
        expiry.day,
        9,
      ).subtract(const Duration(days: 30));
      if (!due.isAfter(DateTime.now())) {
        due = DateTime(expiry.year, expiry.month, expiry.day, 9);
      }
      if (!due.isAfter(DateTime.now())) return;
      final record = {
        'id': id,
        'title': 'Document renewal reminder',
        'body': 'Open your secure wallet to review an expiring document.',
        'dueMillis': due.millisecondsSinceEpoch,
        'mode': 'normal',
        'repeat': 'none',
        'intervalDays': 1,
      };
      await _put('expiry', id, record);
      await native.scheduleTask(record);
    } catch (error) {
      lastAlarmError =
          'Document saved, but its expiry reminder could not be scheduled: $error';
      notifyListeners();
      throw StateError(lastAlarmError!);
    }
  }

  Future<Uint8List> exportBackup(String password) => _serial(() async {
    _requireUnlocked();
    _validatePassword(password);
    final files = <String, String>{};
    var total = 0;
    for (final doc in _documents) {
      final bytes = await _crypto.open(
        await _file(doc.fileId).readAsBytes(),
        context: 'file:${doc.fileId}',
      );
      total += bytes.length;
      if (total > 80 * 1024 * 1024) {
        throw StateError('Backup exceeds the 80 MB document limit');
      }
      _requireUnlocked();
      files[doc.id] = base64Encode(bytes);
    }
    final bundle = {
      'format': 'supare-backup',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'tasks': _tasks.map((value) => value.toJson()).toList(),
      'members': _members.map((value) => value.toJson()).toList(),
      'documents': _documents.map((value) => value.toJson()).toList(),
      'files': files,
      'settings': Map.of(_settings)..remove('lastNativeEvent'),
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(bundle)));
    _requireUnlocked();
    return _crypto.exportEncrypted(bytes, password);
  });

  Future<void> restoreBackup(
    Uint8List encrypted,
    String password, {
    bool replace = false,
  }) => _serial(() async {
    _requireUnlocked();
    _validatePassword(password);
    if (encrypted.length > maxBackupBytes) {
      throw const FormatException('Backup exceeds 200 MB');
    }
    final plain = await _crypto.importEncrypted(encrypted, password);
    final data = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(plain)) as Map,
    );
    if (data['format'] != 'supare-backup' || data['version'] != 1) {
      throw const FormatException('Unsupported backup');
    }
    final taskList = data['tasks'] as List;
    final memberList = data['members'] as List;
    final documentList = data['documents'] as List;
    if (taskList.length > 100000 ||
        memberList.length > 1000 ||
        documentList.length > 10000) {
      throw const FormatException('Backup contains too many records');
    }
    final tasks = taskList
        .map(
          (value) => TaskItem.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
    final members = memberList
        .map(
          (value) =>
              FamilyMember.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
    final docs = documentList
        .map(
          (value) =>
              WalletDocument.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
    final fileData = Map<String, String>.from(data['files'] as Map);
    final settings = Map<String, String>.from(data['settings'] as Map? ?? {});
    _unique(tasks.map((value) => value.id));
    _unique(members.map((value) => value.id));
    _unique(docs.map((value) => value.id));
    for (final task in tasks) {
      _validateTask(task);
    }
    for (final member in members) {
      _validateMember(member);
    }
    final memberIds = {
      ...members.map((value) => value.id),
      if (!replace) ..._members.map((value) => value.id),
    };
    final verifiedFiles = <String, Uint8List>{};
    var total = 0;
    for (final doc in docs) {
      _validateDocument(doc);
      if (!memberIds.contains(doc.memberId)) {
        throw const FormatException('Backup document has no family member');
      }
      final encoded = fileData[doc.id];
      if (encoded == null || encoded.length > maxFileBytes * 2) {
        throw const FormatException('Missing or oversized backup attachment');
      }
      final bytes = base64Decode(encoded);
      _validateFile(bytes, doc.mimeType);
      total += bytes.length;
      if (total > 80 * 1024 * 1024) {
        throw const FormatException('Backup attachments exceed 80 MB');
      }
      if (base64UrlEncode((await Sha256().hash(bytes)).bytes) != doc.digest) {
        throw const FormatException('Backup attachment integrity check failed');
      }
      verifiedFiles[doc.id] = bytes;
    }
    for (final entry in settings.entries) {
      _validateId(entry.key);
      if (entry.value.length > 10000) {
        throw const FormatException('Invalid setting');
      }
    }
    _requireUnlocked();
    final oldTasks = List<TaskItem>.of(_tasks);
    final oldDocs = List<WalletDocument>.of(_documents);
    final staged = <File>[];
    final importedDocs = <WalletDocument>[];
    final rows = <Map<String, Object>>[];
    try {
      for (final doc in docs) {
        if (!replace &&
            (_documents.any(
              (value) => value.id == doc.id || value.digest == doc.digest,
            ))) {
          continue;
        }
        final fileId = _uuid.v4();
        final file = _file(fileId);
        staged.add(file);
        await file.writeAsBytes(
          await _crypto.seal(verifiedFiles[doc.id]!, context: 'file:$fileId'),
          flush: true,
        );
        final imported = doc.copyWith(fileId: fileId);
        importedDocs.add(imported);
        rows.add(await _encoded('document', imported.id, imported.toJson()));
      }
      for (final task in tasks) {
        if (!replace && _tasks.any((value) => value.id == task.id)) continue;
        rows.add(await _encoded('task', task.id, task.toJson()));
      }
      for (final member in members) {
        if (!replace && _members.any((value) => value.id == member.id)) {
          continue;
        }
        rows.add(await _encoded('member', member.id, member.toJson()));
      }
      for (final entry in settings.entries) {
        if (entry.key == 'lastNativeEvent' ||
            (!replace && _settings.containsKey(entry.key))) {
          continue;
        }
        rows.add(
          await _encoded('setting', entry.key, {
            'id': entry.key,
            'value': entry.value,
          }),
        );
      }
      _requireUnlocked();
      await _db.transaction((txn) async {
        if (replace) await txn.delete('records');
        for (final row in rows) {
          await txn.insert(
            'records',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } catch (_) {
      for (final file in staged) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    }
    await _loadPublic();
    if (auth.isUnlocked) {
      final refreshedMembers = (await _records(
        'member',
      )).map(FamilyMember.fromJson).toList();
      final refreshedDocs = (await _records(
        'document',
      )).map(WalletDocument.fromJson).toList();
      if (auth.isUnlocked) {
        _members
          ..clear()
          ..addAll(refreshedMembers);
        _documents
          ..clear()
          ..addAll(refreshedDocs);
      }
    }
    notifyListeners();
    // Database commit has succeeded. Native errors cannot undo this restore;
    // surface them explicitly rather than misreporting an atomic rollback.
    final alarmErrors = <String>[];
    if (replace) {
      for (final task in oldTasks) {
        try {
          await native.cancelTask(task.id);
        } catch (e) {
          alarmErrors.add(e.toString());
        }
      }
      for (final doc in oldDocs) {
        try {
          await native.cancelTask('expiry:${doc.id}');
        } catch (e) {
          alarmErrors.add(e.toString());
        }
        if (await _file(doc.fileId).exists()) await _file(doc.fileId).delete();
      }
    }
    for (final doc in importedDocs) {
      try {
        await _scheduleExpiry(doc);
      } catch (e) {
        alarmErrors.add(e.toString());
      }
    }
    await _rescheduleAlarms();
    if (alarmErrors.isNotEmpty) {
      lastAlarmError =
          'Backup restored; some reminders need attention: ${alarmErrors.first}';
    }
    notifyListeners();
  });

  Future<void> close() async {
    await _pending;
    _closed = true;
    auth.removeListener(_authChanged);
    auth.lock();
    _members.clear();
    _documents.clear();
    _tasks.clear();
    await _db.close();
    super.dispose();
  }

  static void _validateId(String id) {
    if (!RegExp(r'^[a-zA-Z0-9._:-]{1,100}$').hasMatch(id)) {
      throw const FormatException('Invalid record identifier');
    }
  }

  static void _unique(Iterable<String> ids) {
    final list = ids.toList();
    if (list.toSet().length != list.length) {
      throw const FormatException('Duplicate backup identifiers');
    }
  }

  static void _validateTask(TaskItem task) {
    _validateId(task.id);
    _validateId(task.seriesId);
    if (task.title.trim().isEmpty ||
        task.title.length > 500 ||
        task.description.length > 10000) {
      throw const FormatException('Task needs a title of 1–500 characters');
    }
    if (!['normal', 'alarm'].contains(task.reminder) ||
        ![
          'none',
          'daily',
          'weekly',
          'monthly',
          'custom',
        ].contains(task.repeat) ||
        task.intervalDays < 1 ||
        task.intervalDays > 3660 ||
        task.recurrenceDay < 1 ||
        task.recurrenceDay > 31) {
      throw const FormatException('Invalid reminder or repeat setting');
    }
  }

  static void _validateMember(FamilyMember member) {
    _validateId(member.id);
    if (member.name.trim().isEmpty ||
        member.name.length > 100 ||
        member.relationship.length > 100) {
      throw const FormatException(
        'Family member name must be 1–100 characters',
      );
    }
  }

  static void _validateDocument(WalletDocument doc) {
    _validateId(doc.id);
    _validateId(doc.memberId);
    if (doc.name.trim().isEmpty ||
        doc.name.length > 200 ||
        doc.category.length > 100 ||
        doc.number.length > 500 ||
        doc.authority.length > 500 ||
        doc.fileName.length > 500 ||
        doc.fields.length > 100) {
      throw const FormatException('Document fields are missing or too long');
    }
    for (final entry in doc.fields.entries) {
      if (entry.key.trim().isEmpty ||
          entry.key.length > 100 ||
          entry.value.length > 2000) {
        throw const FormatException(
          'Custom field is missing a name or too long',
        );
      }
    }
    if (doc.issueDate != null &&
        doc.expiryDate != null &&
        doc.expiryDate!.isBefore(doc.issueDate!)) {
      throw const FormatException('Expiry date must follow the issue date');
    }
  }

  static void _validatePassword(String password) {
    if (password.length < 12 || password.length > 1024) {
      throw const FormatException(
        'Use a backup password of at least 12 characters',
      );
    }
  }

  static void _validateFile(Uint8List bytes, String mime) {
    if (bytes.isEmpty || bytes.length > maxFileBytes) {
      throw const FormatException('Choose a document between 1 byte and 25 MB');
    }
    bool starts(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((v) => v);
    final pdf = starts([0x25, 0x50, 0x44, 0x46, 0x2D]);
    final jpeg = starts([0xFF, 0xD8, 0xFF]);
    final png = starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    final webp =
        bytes.length > 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
    final heif =
        bytes.length > 16 &&
        ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'ftyp' &&
        [
          'heic',
          'heix',
          'hevc',
          'hevx',
          'mif1',
          'msf1',
          'avif',
        ].contains(ascii.decode(bytes.sublist(8, 12), allowInvalid: true));
    if (!(pdf || jpeg || png || webp || heif) ||
        !(mime == 'application/pdf' || mime.startsWith('image/'))) {
      throw const FormatException(
        'Choose a supported PDF, JPEG, PNG, WebP or HEIF image',
      );
    }
    if ((mime == 'application/pdf') != pdf) {
      throw const FormatException(
        'Document file content does not match its type',
      );
    }
  }
}
