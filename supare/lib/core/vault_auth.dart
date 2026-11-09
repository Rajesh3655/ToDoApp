import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'crypto_service.dart';

/// Wallet authorization is deliberately independent of task access.
/// The caller locks this gate when backgrounding the app and must obtain fresh
/// authorization before showing, copying, decrypting or exporting wallet data.
class VaultAuth extends ChangeNotifier {
  VaultAuth({
    FlutterSecureStorage? secureStorage,
    LocalAuthentication? localAuth,
    DateTime Function()? now,
  }) : _storage =
           secureStorage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(encryptedSharedPreferences: true),
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.unlocked_this_device,
             ),
           ),
       _localAuth = localAuth ?? LocalAuthentication(),
       _now = now ?? DateTime.now;

  static const _pinKey = 'supare.pin.v1';
  static const _attemptKey = 'supare.pin.attempts.v1';
  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;
  final DateTime Function() _now;
  bool _unlocked = false;
  bool _busy = false;
  int _lockGeneration = 0;

  bool get isUnlocked => _unlocked;
  Future<bool> get hasPin async => await _storage.read(key: _pinKey) != null;

  Future<void> setPin(String pin) async {
    if (_busy) throw StateError('Authentication is already in progress.');
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) {
      throw const FormatException('Choose a PIN containing 6 to 12 digits.');
    }
    _busy = true;
    final generation = _lockGeneration;
    try {
      if (await hasPin && !_unlocked) {
        throw StateError('Unlock the wallet before changing its PIN.');
      }
      final salt = CryptoService.secureRandomBytes(16);
      final hash = await CryptoService.derivePassword(pin, salt);
      try {
        final record = jsonEncode({
          'version': 1,
          'salt': base64Encode(salt),
          'hash': base64Encode(hash),
        });
        await _storage.write(key: _pinKey, value: record);
        if (await _storage.read(key: _pinKey) != record) {
          throw StateError('The wallet PIN could not be securely saved.');
        }
        await _clearAttempts();
        _unlocked = generation == _lockGeneration;
        notifyListeners();
      } finally {
        hash.fillRange(0, hash.length, 0);
      }
    } finally {
      _busy = false;
    }
  }

  Future<bool> unlockWithPin(String pin) async {
    if (_busy) throw StateError('Authentication is already in progress.');
    _busy = true;
    final generation = _lockGeneration;
    try {
      final attempts = await _attempts();
      final lockedUntil = attempts['until'] ?? 0;
      if (_now().millisecondsSinceEpoch < lockedUntil) {
        final seconds = ((lockedUntil - _now().millisecondsSinceEpoch) / 1000)
            .ceil();
        throw StateError(
          'Too many incorrect PINs. Try again in $seconds seconds.',
        );
      }
      final encoded = await _storage.read(key: _pinKey);
      if (encoded == null) throw StateError('Create a wallet PIN first.');
      final Map<String, dynamic> record;
      try {
        record = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
        if (record['version'] != 1) throw const FormatException();
      } catch (_) {
        throw StateError(
          'The stored PIN record is damaged. Device authentication may still be available.',
        );
      }
      Uint8List salt;
      Uint8List expected;
      try {
        salt = base64Decode(record['salt'] as String);
        expected = base64Decode(record['hash'] as String);
        if (salt.length != 16 || expected.length != 32) {
          throw const FormatException();
        }
      } catch (_) {
        throw StateError('The stored PIN record is damaged.');
      }
      final validShape = RegExp(r'^\d{6,12}$').hasMatch(pin);
      final actual = await CryptoService.derivePassword(
        validShape ? pin : 'invalid-pin-input',
        salt,
      );
      final success =
          CryptoService.constantTimeEquals(actual, expected) && validShape;
      actual.fillRange(0, actual.length, 0);
      expected.fillRange(0, expected.length, 0);
      if (success) {
        await _clearAttempts();
        _unlocked = generation == _lockGeneration;
        notifyListeners();
        return _unlocked;
      }
      final failures = min((attempts['failures'] ?? 0) + 1, 50);
      // Persist retry throttling in protected storage so app restarts do not reset it.
      final delay = failures < 5
          ? 0
          : min(900, 30 * (1 << min(failures - 5, 5)));
      await _storage.write(
        key: _attemptKey,
        value: jsonEncode({
          'failures': failures,
          'until': _now().add(Duration(seconds: delay)).millisecondsSinceEpoch,
        }),
      );
      return false;
    } finally {
      _busy = false;
    }
  }

  Future<bool> authenticate() async {
    if (_busy) return false;
    _busy = true;
    final generation = _lockGeneration;
    try {
      if (!await hasPin) return false;
      if (!await _localAuth.isDeviceSupported()) return false;
      final success = await _localAuth.authenticate(
        localizedReason: 'Unlock your Supare family document wallet',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: false,
          sensitiveTransaction: true,
        ),
      );
      if (success) {
        await _clearAttempts();
        _unlocked = generation == _lockGeneration;
        notifyListeners();
      }
      return success && _unlocked;
    } on PlatformException {
      return false;
    } finally {
      _busy = false;
    }
  }

  void lock() {
    _lockGeneration++;
    if (!_unlocked) return;
    _unlocked = false;
    notifyListeners();
  }

  Future<void> _clearAttempts() => _storage.delete(key: _attemptKey);

  Future<Map<String, int>> _attempts() async {
    final encoded = await _storage.read(key: _attemptKey);
    if (encoded == null) return {};
    try {
      return (jsonDecode(encoded) as Map).map(
        (k, v) => MapEntry(k as String, (v as num).toInt()),
      );
    } catch (_) {
      // Fail closed rather than dropping a damaged persisted retry limit.
      throw StateError(
        'PIN retry protection could not be read. Use device authentication.',
      );
    }
  }
}
