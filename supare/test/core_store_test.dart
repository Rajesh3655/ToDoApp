import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supare/core/app_store.dart';
import 'package:supare/core/crypto_service.dart';
import 'package:supare/core/native_bridge.dart';
import 'package:supare/core/vault_auth.dart';
import 'package:supare/models/models.dart';

class TestAuth extends VaultAuth {
  bool unlocked = true;
  @override
  bool get isUnlocked => unlocked;
  @override
  void lock() {
    unlocked = false;
    notifyListeners();
  }

  void unlock() {
    unlocked = true;
    notifyListeners();
  }
}

class TestNative extends NativeBridge {
  final scheduled = <String, Map<String, dynamic>>{};
  final events = <Map<String, dynamic>>[];
  bool fail = false;
  @override
  Future<void> scheduleTask(Map<String, dynamic> task) async {
    if (fail) throw StateError('Exact alarm permission denied');
    scheduled[task['id'] as String] = task;
  }

  @override
  Future<void> cancelTask(String id) async {
    scheduled.remove(id);
  }

  @override
  Future<void> ackActions(List<String> eventIds) async {
    events.removeWhere(
      (event) => eventIds.contains(
        event['eventId'] ??
            '${event['atMillis']}:${event['id']}:${event['action']}',
      ),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> drainActions() async =>
      List<Map<String, dynamic>>.from(events);
}

/// Store transaction tests use quick authenticated backup envelopes; the separate
/// crypto tests exercise the real Argon2id portable backup implementation.
class TestCrypto extends CryptoService {
  TestCrypto()
    : super(testingKey: Uint8List.fromList(List.generate(32, (i) => i)));
  @override
  Future<Uint8List> exportEncrypted(Uint8List clear, String password) =>
      seal(clear, context: password);
  @override
  Future<Uint8List> importEncrypted(Uint8List encoded, String password) =>
      open(encoded, context: password);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late AppStore store;
  late TestAuth auth;
  late TestNative native;
  final future = DateTime.now().add(const Duration(days: 10));
  final pdf = Uint8List.fromList(
    utf8.encode('%PDF-1.4\nA sensitive document\n%%EOF'),
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('supare_store_test_');
    auth = TestAuth();
    native = TestNative();
    store = await AppStore.open(
      directory: directory,
      databaseFactory: databaseFactoryFfi,
      crypto: TestCrypto(),
      auth: auth,
      native: native,
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'task CRUD, native scheduling, complete, restore and persistence',
    () async {
      final task = TaskItem(
        id: 'task-one',
        title: 'Book a ticket for Delhi',
        due: future,
        reminder: 'alarm',
      );
      await store.saveTask(task);
      expect(native.scheduled['task-one']!['mode'], 'alarm');
      await store.completeTask(task.id);
      expect(store.tasks.single.isCompleted, true);
      expect(native.scheduled, isEmpty);
      await store.restoreTask(task.id);
      expect(store.tasks.single.isCompleted, false);
      await store.close();
      store = await AppStore.open(
        directory: directory,
        databaseFactory: databaseFactoryFfi,
        crypto: TestCrypto(),
        auth: auth,
        native: native,
      );
      expect(store.tasks.single.title, task.title);
      await store.deleteTask(task.id);
      expect(store.tasks, isEmpty);
    },
  );

  test(
    'recurrence archives completion and schedules exactly one successor',
    () async {
      await store.saveTask(
        TaskItem(
          id: 'daily',
          title: 'Daily medicine',
          due: future,
          repeat: 'daily',
        ),
      );
      await store.completeTask('daily');
      await store.completeTask('daily');
      expect(store.tasks.where((task) => task.isCompleted), hasLength(1));
      expect(store.tasks.where((task) => !task.isCompleted), hasLength(1));
      expect(native.scheduled.length, 1);
      final next = store.tasks.singleWhere((task) => !task.isCompleted);
      expect(next.due.day, future.add(const Duration(days: 1)).day);
    },
  );

  test(
    'scheduling permission failure retains saved task and reports failure',
    () async {
      native.fail = true;
      await expectLater(
        store.saveTask(
          TaskItem(id: 'denied', title: 'Saved offline', due: future),
        ),
        throwsStateError,
      );
      expect(store.tasks.single.id, 'denied');
      expect(store.lastAlarmError, contains('saved locally'));
    },
  );

  test(
    'encrypted wallet, duplicate prevention and authentication gating',
    () async {
      final doc = WalletDocument(
        id: 'document-one',
        name: 'Income Certificate',
        memberId: 'myself',
        number: 'SECRET-12345',
        fileName: 'income.pdf',
        mimeType: 'application/pdf',
      );
      await store.importDocument(doc, pdf);
      expect(await store.readDocument(doc.id), pdf);
      await expectLater(
        store.importDocument(
          const WalletDocument(
            id: 'duplicate',
            name: 'Duplicate',
            memberId: 'myself',
            mimeType: 'application/pdf',
          ),
          pdf,
        ),
        throwsStateError,
      );
      final allBytes = <int>[];
      await for (final file in directory.list(recursive: true)) {
        if (file is File) allBytes.addAll(await file.readAsBytes());
      }
      final contents = latin1.decode(allBytes);
      expect(contents, isNot(contains('SECRET-12345')));
      expect(contents, isNot(contains('A sensitive document')));
      auth.lock();
      expect(store.documents, isEmpty);
      expect(store.members, isEmpty);
      await expectLater(store.readDocument(doc.id), throwsStateError);
      auth.unlock();
      await store.refreshWallet();
      expect(store.documents.single.name, doc.name);
    },
  );

  test(
    'document replacement keeps metadata and updates encrypted file',
    () async {
      final original = WalletDocument(
        id: 'replace',
        name: 'PAN',
        memberId: 'myself',
        mimeType: 'application/pdf',
      );
      await store.importDocument(original, pdf);
      final oldFile = store.documents.single.fileId;
      final replacement = Uint8List.fromList(
        utf8.encode('%PDF-1.4\nUpdated\n%%EOF'),
      );
      await store.importDocument(
        store.documents.single.copyWith(name: 'New PAN'),
        replacement,
      );
      expect(await store.readDocument('replace'), replacement);
      expect(
        await File('${directory.path}/files/$oldFile.enc').exists(),
        false,
      );
    },
  );

  test(
    'backup validates before replacing, then restores all data and reminders',
    () async {
      await store.saveTask(
        TaskItem(id: 'ticket', title: 'Ticket', due: future),
      );
      await store.saveMember(
        const FamilyMember(
          id: 'father',
          name: 'Father',
          relationship: 'Father',
        ),
      );
      await store.importDocument(
        WalletDocument(
          id: 'cert',
          name: 'Certificate',
          memberId: 'father',
          mimeType: 'application/pdf',
          expiryDate: future.add(const Duration(days: 60)),
        ),
        pdf,
      );
      final backup = await store.exportBackup('a strong backup password');
      await store.deleteTask('ticket');
      await store.saveTask(
        TaskItem(id: 'local', title: 'Keep until valid restore', due: future),
      );
      final damaged = Uint8List.fromList(backup);
      damaged[damaged.length - 1] ^= 1;
      await expectLater(
        store.restoreBackup(damaged, 'a strong backup password', replace: true),
        throwsFormatException,
      );
      expect(store.tasks.single.id, 'local');
      await expectLater(
        store.restoreBackup(backup, 'incorrect password', replace: true),
        throwsFormatException,
      );
      expect(store.tasks.single.id, 'local');
      await store.restoreBackup(
        backup,
        'a strong backup password',
        replace: true,
      );
      expect(store.tasks.single.id, 'ticket');
      expect(store.documents.single.memberId, 'father');
      expect(await store.readDocument('cert'), pdf);
      expect(native.scheduled.containsKey('ticket'), true);
      expect(native.scheduled.containsKey('expiry:cert'), true);
      expect(native.scheduled.containsKey('local'), false);
    },
  );

  test(
    'native action queue reconciles snooze and completion without duplicates',
    () async {
      await store.saveTask(TaskItem(id: 'native', title: 'Alarm', due: future));
      final due = DateTime.now().add(const Duration(minutes: 10));
      native.events.add({
        'id': 'native',
        'action': 'snooze',
        'minutes': 10,
        'atMillis': 1,
        'dueMillis': due.millisecondsSinceEpoch,
      });
      await store.reconcileNativeActions();
      expect(
        store.tasks.single.due.millisecondsSinceEpoch,
        due.millisecondsSinceEpoch,
      );
      native.events.add({'id': 'native', 'action': 'done', 'atMillis': 2});
      await store.reconcileNativeActions();
      await store.reconcileNativeActions();
      expect(store.tasks.single.isCompleted, true);
    },
  );

  test('snoozed recurrence retains original hour and monthly anchor', () {
    final original = TaskItem(
      id: 'cadence',
      title: 'Daily medicine',
      due: DateTime(2027, 1, 31, 9),
      repeat: 'daily',
    );
    final snoozed = original.copyWith(due: DateTime(2027, 1, 31, 9, 10));
    expect(
      snoozed.nextOccurrence(DateTime(2027, 1, 31, 9, 11)),
      DateTime(2027, 2, 1, 9),
    );
    final monthly = original.copyWith(repeat: 'monthly');
    final february = monthly.copyWith(due: DateTime(2027, 2, 28, 9));
    expect(
      february.nextOccurrence(DateTime(2027, 2, 28, 10)),
      DateTime(2027, 3, 31, 9),
    );
    final restored = TaskItem.fromJson(february.toJson());
    expect(restored.recurrenceAnchor, original.due);
    expect(
      restored.nextOccurrence(DateTime(2027, 2, 28, 10)),
      DateTime(2027, 3, 31, 9),
    );
  });

  test(
    'multiple closed-app completions preserve history without duplicate successors',
    () async {
      final old = DateTime.now().subtract(const Duration(days: 5));
      await store.saveTask(
        TaskItem(id: 'closed-daily', title: 'Daily', due: old, repeat: 'daily'),
      );
      for (var days = 3; days > 0; days--) {
        final occurred = DateTime.now().subtract(Duration(days: days));
        native.events.add({
          'id': 'closed-daily',
          'action': 'done',
          'atMillis': occurred.millisecondsSinceEpoch,
          'occurrenceMillis': occurred
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        });
      }
      await store.reconcileNativeActions();
      expect(store.tasks.where((task) => task.isCompleted), hasLength(3));
      expect(store.tasks.where((task) => !task.isCompleted), hasLength(1));
      expect(native.events, isEmpty);
      await store.reconcileNativeActions();
      expect(store.tasks.where((task) => task.isCompleted), hasLength(3));
    },
  );

  test(
    'closed-app snooze after earlier recurrence Done targets pending successor',
    () async {
      final old = DateTime.now().subtract(const Duration(days: 2));
      await store.saveTask(
        TaskItem(id: 'done-snooze', title: 'Daily', due: old, repeat: 'daily'),
      );
      final doneAt = DateTime.now().subtract(const Duration(days: 1));
      final snoozedUntil = DateTime.now().add(const Duration(minutes: 10));
      native.events.add({
        'id': 'done-snooze',
        'action': 'done',
        'atMillis': doneAt.millisecondsSinceEpoch,
      });
      native.events.add({
        'id': 'done-snooze',
        'action': 'snooze',
        'atMillis': DateTime.now().millisecondsSinceEpoch,
        'dueMillis': snoozedUntil.millisecondsSinceEpoch,
        'minutes': 10,
      });
      await store.reconcileNativeActions();
      final pending = store.tasks.singleWhere((task) => !task.isCompleted);
      expect(
        pending.due.millisecondsSinceEpoch,
        snoozedUntil.millisecondsSinceEpoch,
      );
      expect(store.tasks.singleWhere((task) => task.isCompleted).due, old);
    },
  );

  test(
    'calendar recurrence clamps month ends and custom days remain bounded',
    () {
      final task = TaskItem(
        id: 'month',
        title: 'Monthly',
        due: DateTime(2027, 1, 31, 10, 30),
        repeat: 'monthly',
      );
      expect(
        task.nextOccurrence(DateTime(2027, 2, 1)),
        DateTime(2027, 2, 28, 10, 30),
      );
      expect(
        task.nextOccurrence(DateTime(2027, 2, 28, 11)),
        DateTime(2027, 3, 31, 10, 30),
      );
    },
  );
}
