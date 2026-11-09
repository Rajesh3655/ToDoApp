import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as imaging;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:supare/core/app_store.dart';
import 'package:supare/core/crypto_service.dart';
import 'package:supare/core/native_bridge.dart';
import 'package:supare/core/vault_auth.dart';
import 'package:supare/models/models.dart';
import 'package:supare/ui/app.dart';
import 'package:uuid/uuid.dart';

/// This bridge executes the actual native plugin. Its only specialization scopes
/// non-destructive queue reads and acknowledgments to this fixture's reminders,
/// so an integration test cannot consume an existing user's reminder actions.
class _ScopedNative extends NativeBridge {
  final ownIds = <String>{};
  final _acknowledgeableEvents = <String>{};

  @override
  Future<void> scheduleTask(Map<String, dynamic> task) async {
    ownIds.add(task['id'] as String);
    await super.scheduleTask(task);
  }

  @override
  Future<void> cancelTask(String id) async {
    // Calls originate only from this fixture's isolated SQLite records.
    ownIds.add(id);
    await super.cancelTask(id);
  }

  @override
  Future<List<Map<String, dynamic>>> drainActions() async {
    final events = (await super.drainActions())
        .where((event) => ownIds.contains(event['id']))
        .toList();
    _acknowledgeableEvents.addAll(
      events.map(
        (event) =>
            event['eventId'] as String? ??
            '${event['atMillis']}:${event['id']}:${event['action']}',
      ),
    );
    return events;
  }

  @override
  Future<void> ackActions(List<String> eventIds) async {
    final scoped = eventIds.where(_acknowledgeableEvents.contains).toList();
    if (scoped.isNotEmpty) await super.ackActions(scoped);
    _acknowledgeableEvents.removeAll(scoped);
  }
}

class _DeviceFixture {
  _DeviceFixture._(this.id, this.directory, this.protectedStorage);
  final String id;
  final Directory directory;
  final FlutterSecureStorage protectedStorage;
  final native = _ScopedNative();
  AppStore? _store;
  AppStore get store => _store!;

  static Future<_DeviceFixture> create() async {
    final id = const Uuid().v4().replaceAll('-', '');
    final root = await getTemporaryDirectory();
    final fixture = _DeviceFixture._(
      id,
      await Directory(path.join(root.path, 'supare-integration-$id')).create(),
      FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
          sharedPreferencesName: 'supare_integration_$id',
          preferencesKeyPrefix: 'supare_integration_$id',
        ),
        iOptions: IOSOptions(
          accountName: 'app.supare.integration.$id',
          accessibility: KeychainAccessibility.unlocked_this_device,
          synchronizable: false,
        ),
      ),
    );
    try {
      await fixture.open();
      return fixture;
    } catch (_) {
      await fixture.dispose();
      rethrow;
    }
  }

  Future<void> open() async {
    _store = await AppStore.open(
      directory: directory,
      crypto: CryptoService(secureStorage: protectedStorage),
      auth: VaultAuth(secureStorage: protectedStorage),
      native: native,
    );
  }

  Future<void> reopen() async {
    final previous = _store;
    _store = null;
    if (previous != null) {
      await previous.close();
      previous.auth.dispose();
    }
    await open();
  }

  Future<void> dispose() async {
    try {
      for (final id in native.ownIds.toList()) {
        await native.cancelTask(id);
      }
    } finally {
      final previous = _store;
      _store = null;
      if (previous != null) {
        await previous.close();
        previous.auth.dispose();
      }
      if (await directory.exists()) await directory.delete(recursive: true);
      // Delete only Supare's three keys within this unique test namespace.
      // Never call deleteAll against a platform key store.
      for (final key in [
        'supare.master.v1',
        'supare.pin.v1',
        'supare.pin.attempts.v1',
      ]) {
        await protectedStorage.delete(key: key);
      }
    }
  }
}

Future<void> _requireNotifications(_DeviceFixture fixture) async {
  final capabilities = await fixture.native.getCapabilities();
  expect(
    capabilities['notifications'],
    true,
    reason:
        'Grant Supare notification access on the test device before running.',
  );
}

Future<void> _unlockFixture(_DeviceFixture fixture) async {
  expect(await fixture.store.auth.unlockWithPin('739182'), true);
  await fixture.store.refreshWallet();
}

/// These tests use actual SQLite, platform secure storage and native scheduling.
/// They do not validate biometrics, camera/share UI, ringing, reboot or lock screen.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'offline native task creation, restart persistence, and completion',
    (tester) async {
      final fixture = await _DeviceFixture.create();
      try {
        await _requireNotifications(fixture);
        final title =
            'Integration task ${DateTime.now().microsecondsSinceEpoch}';
        await tester.pumpWidget(SupareApp(store: fixture.store));
        await tester.pumpAndSettle();
        await tester.tap(find.text('New task'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'What needs doing?'),
          title,
        );
        await tester.ensureVisible(find.text('Save task'));
        await tester.tap(find.text('Save task'));
        await tester.pumpAndSettle();
        final saveDeadline = Stopwatch()..start();
        while ((!fixture.store.tasks.any((task) => task.title == title) ||
                find.text('A new intention').evaluate().isNotEmpty) &&
            saveDeadline.elapsed < const Duration(minutes: 2)) {
          final schedulingError = fixture.store.lastAlarmError;
          if (schedulingError != null) {
            fail('Real native reminder scheduling failed: $schedulingError');
          }
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(fixture.store.lastAlarmError, isNull);
        final createdID = fixture.store.tasks
            .singleWhere((task) => task.title == title)
            .id;
        expect(
          find.text('A new intention'),
          findsNothing,
          reason:
              'The form closes only after the real native schedule call succeeds.',
        );
        await tester.pumpWidget(const SizedBox());
        await fixture.reopen();
        expect(
          fixture.store.tasks.singleWhere((task) => task.id == createdID).title,
          title,
        );
        await fixture.store.completeTask(createdID);
        expect(
          fixture.store.tasks
              .singleWhere((task) => task.id == createdID)
              .isCompleted,
          true,
        );
        await tester.pumpWidget(SupareApp(store: fixture.store));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Completed'));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await fixture.dispose();
      }
    },
  );

  testWidgets(
    'device encrypted wallet, PIN, persistence and authenticated backup restore',
    (tester) async {
      final fixture = await _DeviceFixture.create();
      try {
        await _requireNotifications(fixture);
        expect(await fixture.store.auth.hasPin, false);
        await fixture.store.auth.setPin('739182');
        expect(await fixture.store.auth.hasPin, true);
        await fixture.store.refreshWallet();
        final father = FamilyMember(
          id: '${fixture.id}-father',
          name: 'Father',
          relationship: 'Father',
        );
        await fixture.store.saveMember(father);
        await fixture.store.saveMember(father.copyWith(name: 'Father profile'));
        await fixture.store.saveMember(
          FamilyMember(
            id: '${fixture.id}-temporary',
            name: 'Temporary',
            relationship: 'Custom',
          ),
        );
        await fixture.store.deleteMember('${fixture.id}-temporary');
        expect(
          fixture.store.members
              .where((member) => member.id == father.id)
              .single
              .name,
          'Father profile',
        );
        expect(
          fixture.store.members.any(
            (member) => member.id == '${fixture.id}-temporary',
          ),
          false,
        );

        final picture = imaging.Image(width: 2, height: 2)
          ..setPixelRgba(0, 0, 24, 104, 78, 255);
        final png = Uint8List.fromList(imaging.encodePng(picture));
        expect(imaging.decodePng(png), isNotNull);
        final document = WalletDocument(
          id: '${fixture.id}-certificate',
          name: 'Income Certificate',
          memberId: father.id,
          category: 'Income Certificate',
          number: 'INTEGRATION-PRIVATE-123',
          authority: 'Test issuing authority',
          issueDate: DateTime(2026, 1, 1),
          expiryDate: DateTime.now().add(const Duration(days: 60)),
          fields: const {'Annual income': '120000'},
          fileName: 'certificate.png',
          mimeType: 'image/png',
        );
        await fixture.store.importDocument(document, png);
        expect(
          await fixture.store.readDocument(document.id),
          orderedEquals(png),
        );
        expect(fixture.native.ownIds, contains('expiry:${document.id}'));
        await expectLater(
          fixture.store.importDocument(
            WalletDocument(
              id: '${fixture.id}-duplicate',
              name: 'Duplicate',
              memberId: father.id,
              mimeType: 'image/png',
            ),
            png,
          ),
          throwsStateError,
        );
        await fixture.store.updateDocument(
          fixture.store.documents.single.copyWith(
            favorite: true,
            name: 'Verified Certificate',
          ),
        );
        expect(fixture.store.documents.single.favorite, true);
        final encryptedFile = File(
          path.join(
            fixture.directory.path,
            'files',
            '${fixture.store.documents.single.fileId}.enc',
          ),
        );
        final protectedBytes = await encryptedFile.readAsBytes();
        expect(protectedBytes, isNot(orderedEquals(png)));
        fixture.store.auth.lock();
        expect(fixture.store.documents, isEmpty);
        await expectLater(
          fixture.store.readDocument(document.id),
          throwsStateError,
        );
        expect(await fixture.store.auth.unlockWithPin('000000'), false);
        await _unlockFixture(fixture);
        expect(
          fixture.store.documents.single.fields['Annual income'],
          '120000',
        );

        await fixture.reopen();
        expect(await fixture.store.auth.hasPin, true);
        expect(fixture.store.auth.isUnlocked, false);
        await _unlockFixture(fixture);
        expect(fixture.store.documents.single.name, 'Verified Certificate');
        expect(
          await fixture.store.readDocument(document.id),
          orderedEquals(png),
        );
        final task = TaskItem(
          id: '${fixture.id}-renewal-task',
          title: 'Prepare application form',
          due: DateTime.now().add(const Duration(days: 2)),
          important: true,
        );
        await fixture.store.saveTask(task);
        for (final entry
            in await fixture.directory.list(recursive: true).toList()) {
          if (entry is File) {
            final raw = await entry.readAsBytes();
            expect(String.fromCharCodes(raw), isNot(contains(document.number)));
          }
        }
        const password = 'Supare isolated device backup password';
        final backup = await fixture.store.exportBackup(password);
        final tampered = Uint8List.fromList(backup)..[backup.length - 1] ^= 1;
        await fixture.store.deleteTask(task.id);
        await fixture.store.deleteDocument(document.id);
        await fixture.store.deleteMember(father.id);
        await fixture.store.saveMember(
          FamilyMember(
            id: '${fixture.id}-kept',
            name: 'Keep until valid restore',
          ),
        );
        await expectLater(
          fixture.store.restoreBackup(tampered, password, replace: true),
          throwsFormatException,
        );
        expect(
          fixture.store.members.any(
            (member) => member.id == '${fixture.id}-kept',
          ),
          true,
        );
        await expectLater(
          fixture.store.restoreBackup(
            backup,
            'wrong but long password',
            replace: true,
          ),
          throwsFormatException,
        );
        expect(
          fixture.store.members.any(
            (member) => member.id == '${fixture.id}-kept',
          ),
          true,
        );
        await fixture.store.restoreBackup(backup, password, replace: true);
        expect(
          fixture.store.members.any(
            (member) => member.id == '${fixture.id}-kept',
          ),
          false,
        );
        expect(fixture.store.tasks.single.id, task.id);
        expect(fixture.store.tasks.single.important, true);
        expect(fixture.store.documents.single.memberId, father.id);
        expect(fixture.store.documents.single.number, document.number);
        expect(fixture.store.documents.single.favorite, true);
        expect(
          await fixture.store.readDocument(document.id),
          orderedEquals(png),
        );
        expect(fixture.store.lastAlarmError, isNull);
        await fixture.store.deleteDocument(document.id);
        await fixture.store.deleteMember(father.id);
        expect(fixture.store.documents, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await fixture.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
