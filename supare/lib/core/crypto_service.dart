import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/argon2.dart';

/// Versioned, authenticated local encryption and portable password backups.
///
/// Device keys stay in Android Keystore-backed storage/iOS device-only Keychain.
/// No key is ever stored alongside its encrypted files or inside a backup.
class CryptoService {
  CryptoService({Uint8List? testingKey, FlutterSecureStorage? secureStorage})
    : _rawKey = testingKey == null ? null : Uint8List.fromList(testingKey),
      _storage =
          secureStorage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
          );

  static const _keyName = 'supare.master.v1';
  static const _localMagic = <int>[83, 85, 80, 86, 1]; // SUPV + version
  static const _backupMagic = <int>[83, 85, 80, 66, 1]; // SUPB + version
  static const maxPayloadBytes = 128 * 1024 * 1024;
  final FlutterSecureStorage _storage;
  final AesGcm _aes = AesGcm.with256bits();
  Uint8List? _rawKey;
  bool _initialized = false;
  Future<void>? _initializing;

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initializing ??= _loadKey().catchError((
      Object error,
      StackTrace trace,
    ) {
      _initializing = null;
      Error.throwWithStackTrace(error, trace);
    });
  }

  Future<void> _loadKey() async {
    if (_rawKey == null) {
      final encoded = await _storage.read(key: _keyName);
      if (encoded == null) {
        final generated = secureRandomBytes(32);
        await _storage.write(key: _keyName, value: base64Encode(generated));
        // Ensure the keystore write completed; never silently use an ephemeral key.
        if (await _storage.read(key: _keyName) != base64Encode(generated)) {
          throw StateError('Protected device key could not be saved.');
        }
        _rawKey = generated;
      } else {
        _rawKey = base64Decode(encoded);
      }
    }
    if (_rawKey!.length != 32) {
      throw StateError(
        'The protected device key is invalid. Restore an encrypted backup.',
      );
    }
    _initialized = true;
  }

  Future<Uint8List> seal(Uint8List clear, {String context = ''}) async {
    _ensureReady();
    _checkSize(clear.length);
    final aad = <int>[..._localMagic, ...utf8.encode(context)];
    final box = await _aes.encrypt(
      clear,
      secretKey: SecretKey(_rawKey!),
      nonce: secureRandomBytes(12),
      aad: aad,
    );
    return Uint8List.fromList([
      ..._localMagic,
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<Uint8List> open(Uint8List encoded, {String context = ''}) async {
    _ensureReady();
    _validateEnvelope(encoded, _localMagic, minimum: 33);
    try {
      final clear = await _aes.decrypt(
        SecretBox(
          encoded.sublist(17, encoded.length - 16),
          nonce: encoded.sublist(5, 17),
          mac: Mac(encoded.sublist(encoded.length - 16)),
        ),
        secretKey: SecretKey(_rawKey!),
        aad: <int>[..._localMagic, ...utf8.encode(context)],
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'Encrypted data failed integrity validation.',
      );
    }
  }

  Future<Uint8List> exportEncrypted(Uint8List clear, String password) async {
    validateBackupPassword(password);
    _checkSize(clear.length);
    final salt = secureRandomBytes(16);
    final derived = await derivePassword(password, salt);
    try {
      final header = <int>[..._backupMagic, ...salt];
      final box = await _aes.encrypt(
        clear,
        secretKey: SecretKey(derived),
        nonce: secureRandomBytes(12),
        aad: header,
      );
      return Uint8List.fromList([
        ...header,
        ...box.nonce,
        ...box.cipherText,
        ...box.mac.bytes,
      ]);
    } finally {
      derived.fillRange(0, derived.length, 0);
    }
  }

  Future<Uint8List> importEncrypted(Uint8List encoded, String password) async {
    validateBackupPassword(password);
    _validateEnvelope(encoded, _backupMagic, minimum: 49);
    // V1 fixes Argon2id parameters; attacker-controlled memory/iterations cannot
    // make an imported file allocate arbitrary memory or downgrade derivation.
    final derived = await derivePassword(password, encoded.sublist(5, 21));
    try {
      final clear = await _aes.decrypt(
        SecretBox(
          encoded.sublist(33, encoded.length - 16),
          nonce: encoded.sublist(21, 33),
          mac: Mac(encoded.sublist(encoded.length - 16)),
        ),
        secretKey: SecretKey(derived),
        aad: encoded.sublist(0, 21),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'Incorrect backup password or damaged backup.',
      );
    } finally {
      derived.fillRange(0, derived.length, 0);
    }
  }

  void _ensureReady() {
    if (!_initialized || _rawKey == null) {
      throw StateError('Device encryption has not been initialized.');
    }
  }

  static void _checkSize(int size) {
    if (size > maxPayloadBytes) {
      throw const FormatException('Data exceeds the 128 MB safety limit.');
    }
  }

  static void _validateEnvelope(
    Uint8List bytes,
    List<int> magic, {
    required int minimum,
  }) {
    if (bytes.length < minimum ||
        bytes.length > maxPayloadBytes + 64 ||
        !constantTimeEquals(
          bytes.sublist(0, min(bytes.length, magic.length)),
          magic,
        )) {
      throw const FormatException('Unsupported or damaged encrypted file.');
    }
  }

  static void validateBackupPassword(String password) {
    if (password.runes.length < 12 || utf8.encode(password).length > 1024) {
      throw const FormatException(
        'Use a backup password with at least 12 characters (maximum 1024 bytes).',
      );
    }
  }

  static Uint8List secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static bool constantTimeEquals(List<int> a, List<int> b) {
    var mismatch = a.length ^ b.length;
    final length = max(a.length, b.length);
    for (var i = 0; i < length; i++) {
      mismatch |= (i < a.length ? a[i] : 0) ^ (i < b.length ? b[i] : 0);
    }
    return mismatch == 0;
  }

  /// Argon2id v1.3, 64 MiB, three passes, one lane, 256-bit output.
  /// Runs off the UI isolate; parameters are fixed by the envelope version.
  static Future<Uint8List> derivePassword(
    String password,
    Uint8List salt,
  ) async {
    if (salt.length != 16) throw ArgumentError('Salt must contain 16 bytes.');
    return Isolate.run(() {
      final bytes = Uint8List.fromList(utf8.encode(password));
      final generator = Argon2BytesGenerator()
        ..init(
          Argon2Parameters(
            Argon2Parameters.ARGON2_id,
            salt,
            version: Argon2Parameters.ARGON2_VERSION_13,
            memoryPowerOf2: 16,
            iterations: 3,
            lanes: 1,
            desiredKeyLength: 32,
          ),
        );
      try {
        return generator.process(bytes);
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    });
  }
}
