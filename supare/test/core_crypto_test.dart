import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supare/core/crypto_service.dart';
import 'package:supare/core/vault_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService crypto;
  setUp(() async {
    crypto = CryptoService(
      testingKey: Uint8List.fromList(List.generate(32, (i) => i)),
    );
    await crypto.initialize();
  });

  test('AES-GCM roundtrip binds ciphertext to its record context', () async {
    final clear = Uint8List.fromList(utf8.encode('private document metadata'));
    final sealed = await crypto.seal(clear, context: 'document:1');
    expect(
      await crypto.open(sealed, context: 'document:1'),
      orderedEquals(clear),
    );
    await expectLater(
      crypto.open(sealed, context: 'document:2'),
      throwsFormatException,
    );
  });

  test('AES-GCM generates unique nonces and rejects tampering', () async {
    final clear = Uint8List.fromList([1, 2, 3, 4]);
    final first = await crypto.seal(clear);
    final second = await crypto.seal(clear);
    expect(first, isNot(orderedEquals(second)));
    first[18] ^= 1;
    await expectLater(crypto.open(first), throwsFormatException);
    await expectLater(
      crypto.open(Uint8List.fromList([1, 2])),
      throwsFormatException,
    );
  });

  test('ciphertext cannot be read under a different device key', () async {
    final other = CryptoService(testingKey: Uint8List(32));
    await other.initialize();
    final sealed = await crypto.seal(Uint8List.fromList([9, 8, 7]));
    await expectLater(other.open(sealed), throwsFormatException);
  });

  test(
    'Argon2id derivation matches independent libargon2 reference',
    () async {
      // Fixture computed with argon2-cffi 25.1.0 / libargon2: ID v19,
      // memory_cost=65536, time_cost=3, parallelism=1, hash_len=32.
      final key = await CryptoService.derivePassword(
        'Supare test derivation',
        Uint8List.fromList(List.generate(16, (i) => i)),
      );
      final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(
        hex,
        'dcd42a4c9ac00d1959edbe343cf95fb51e11358cb8cc5adbec4442cdc05f4959',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'portable backup restores without original device key and rejects wrong password',
    () async {
      const password = 'a long private backup password';
      final clear = Uint8List.fromList(
        utf8.encode('{"tasks":[],"documents":[]}'),
      );
      final backup = await crypto.exportEncrypted(clear, password);
      final independent = CryptoService(testingKey: Uint8List(32));
      await independent.initialize();
      expect(
        await independent.importEncrypted(backup, password),
        orderedEquals(clear),
      );
      await expectLater(
        independent.importEncrypted(backup, 'an incorrect password'),
        throwsFormatException,
      );
      backup[4] = 99;
      await expectLater(
        independent.importEncrypted(backup, password),
        throwsFormatException,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('backup rejects weak passwords before deriving a key', () async {
    await expectLater(
      crypto.exportEncrypted(Uint8List(0), 'short'),
      throwsFormatException,
    );
    await expectLater(
      crypto.importEncrypted(Uint8List(0), 'valid long password'),
      throwsFormatException,
    );
  });

  test('PIN retry throttling survives a recreated auth gate', () async {
    FlutterSecureStorage.setMockInitialValues({
      'supare.pin.attempts.v1': '{"failures":5,"until":60000}',
    });
    final auth = VaultAuth(
      now: () => DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await expectLater(auth.unlockWithPin('123456'), throwsStateError);
    final reopened = VaultAuth(
      now: () => DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await expectLater(reopened.unlockWithPin('123456'), throwsStateError);
    expect(reopened.isUnlocked, isFalse);
  });

  test(
    'locking invalidates in-flight PIN enrollment and unlock',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final auth = VaultAuth();
      final enrolling = auth.setPin('572946');
      auth.lock();
      await expectLater(auth.unlockWithPin('572946'), throwsStateError);
      await enrolling;
      expect(await auth.hasPin, isTrue);
      expect(auth.isUnlocked, isFalse);
      final unlocking = auth.unlockWithPin('572946');
      auth.lock();
      expect(await unlocking, isFalse);
      expect(auth.isUnlocked, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'PIN requires enrollment, survives new auth instance and cannot change while locked',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final auth = VaultAuth();
      expect(await auth.hasPin, isFalse);
      await expectLater(auth.setPin('1234'), throwsFormatException);
      await auth.setPin('739182');
      expect(await auth.hasPin, isTrue);
      expect(auth.isUnlocked, isTrue);
      auth.lock();
      expect(auth.isUnlocked, isFalse);
      final reopened = VaultAuth();
      expect(await reopened.hasPin, isTrue);
      await expectLater(reopened.setPin('987654'), throwsStateError);
      expect(await reopened.unlockWithPin('111111'), isFalse);
      expect(reopened.isUnlocked, isFalse);
      expect(await reopened.unlockWithPin('739182'), isTrue);
      expect(reopened.isUnlocked, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
