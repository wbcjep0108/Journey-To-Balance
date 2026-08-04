import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

enum AutoLockOption {
  immediately(0, 'Immediately'),
  oneMinute(60, 'After 1 minute'),
  fiveMinutes(300, 'After 5 minutes'),
  fifteenMinutes(900, 'After 15 minutes');

  const AutoLockOption(this.seconds, this.label);

  final int seconds;
  final String label;

  static AutoLockOption fromSeconds(int seconds) {
    return AutoLockOption.values.firstWhere(
      (option) => option.seconds == seconds,
      orElse: () => AutoLockOption.immediately,
    );
  }
}

class SecurityService {
  SecurityService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _localAuth = localAuth ?? LocalAuthentication();

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  /// Zero-width space: Android requires non-empty title/reason strings, but
  /// these keep the system biometric sheet free of "Authentication required"
  /// / "Verify identity" copy.
  static const String _silentPrompt = '\u200B';

  String _pinKey(String uid) => 'pin_hash_$uid';
  String _biometricKey(String uid) => 'biometric_enabled_$uid';
  String _autoLockKey(String uid) => 'auto_lock_seconds_$uid';

  String _hashPin(String uid, String pin) {
    final bytes = utf8.encode('$uid:$pin');
    return sha256.convert(bytes).toString();
  }

  Future<bool> hasPin(String uid) async {
    final stored = await _storage.read(key: _pinKey(uid));
    return stored != null && stored.isNotEmpty;
  }

  Future<void> savePin(String uid, String pin) async {
    await _storage.write(key: _pinKey(uid), value: _hashPin(uid, pin));
  }

  Future<bool> verifyPin(String uid, String pin) async {
    final stored = await _storage.read(key: _pinKey(uid));
    if (stored == null || stored.isEmpty) return false;
    return stored == _hashPin(uid, pin);
  }

  Future<void> clearPin(String uid) async {
    await _storage.delete(key: _pinKey(uid));
  }

  Future<bool> isBiometricEnabled(String uid) async {
    final value = await _storage.read(key: _biometricKey(uid));
    return value == 'true';
  }

  Future<void> setBiometricEnabled(String uid, bool enabled) async {
    await _storage.write(
      key: _biometricKey(uid),
      value: enabled ? 'true' : 'false',
    );
  }

  Future<AutoLockOption> getAutoLockOption(String uid) async {
    final value = await _storage.read(key: _autoLockKey(uid));
    final seconds = int.tryParse(value ?? '') ?? 0;
    return AutoLockOption.fromSeconds(seconds);
  }

  Future<void> setAutoLockOption(String uid, AutoLockOption option) async {
    await _storage.write(
      key: _autoLockKey(uid),
      value: option.seconds.toString(),
    );
  }

  Future<bool> canCheckBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics({
    String reason = 'Unlock Journey to Balance',
  }) async {
    try {
      return await _localAuth.authenticate(
        // Android: title only. iOS: localizedReason is the visible prompt.
        localizedReason: defaultTargetPlatform == TargetPlatform.iOS
            ? reason
            : _silentPrompt,
        biometricOnly: true,
        // Avoid the extra "confirm" step some devices show after biometrics.
        sensitiveTransaction: false,
        persistAcrossBackgrounding: true,
        authMessages: <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: reason,
            signInHint: _silentPrompt,
            cancelButton: 'Cancel',
          ),
          const IOSAuthMessages(localizedFallbackTitle: ''),
        ],
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> clearAllForUser(String uid) async {
    await Future.wait([
      _storage.delete(key: _pinKey(uid)),
      _storage.delete(key: _biometricKey(uid)),
      _storage.delete(key: _autoLockKey(uid)),
    ]);
  }
}
