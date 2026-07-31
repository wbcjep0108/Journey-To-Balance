import 'package:flutter/widgets.dart';

import '../services/security_service.dart';

enum AppLockStatus {
  checking,
  needsSetup,
  locked,
  unlocked,
}

class AppLockProvider extends ChangeNotifier with WidgetsBindingObserver {
  AppLockProvider({SecurityService? securityService})
    : _security = securityService ?? SecurityService();

  final SecurityService _security;

  String? _uid;
  AppLockStatus _status = AppLockStatus.checking;
  bool _biometricEnabled = false;
  bool _biometricsAvailable = false;
  AutoLockOption _autoLockOption = AutoLockOption.immediately;
  DateTime? _pausedAt;
  bool _observingLifecycle = false;

  AppLockStatus get status => _status;
  bool get biometricEnabled => _biometricEnabled;
  bool get biometricsAvailable => _biometricsAvailable;
  AutoLockOption get autoLockOption => _autoLockOption;
  SecurityService get security => _security;

  Future<void> bindUser(String uid) async {
    if (_uid == uid && _status != AppLockStatus.checking) {
      return;
    }

    _uid = uid;
    _status = AppLockStatus.checking;
    notifyListeners();

    final hasPin = await _security.hasPin(uid);
    _biometricEnabled = await _security.isBiometricEnabled(uid);
    _biometricsAvailable = await _security.canCheckBiometrics();
    _autoLockOption = await _security.getAutoLockOption(uid);

    _ensureLifecycleObserver();

    if (!hasPin) {
      _status = AppLockStatus.needsSetup;
    } else {
      _status = AppLockStatus.locked;
    }
    notifyListeners();
  }

  void clearUser() {
    _uid = null;
    _status = AppLockStatus.checking;
    _biometricEnabled = false;
    _biometricsAvailable = false;
    _autoLockOption = AutoLockOption.immediately;
    _pausedAt = null;
    _removeLifecycleObserver();
    notifyListeners();
  }

  Future<void> completePinSetup(String pin) async {
    final uid = _uid;
    if (uid == null) return;
    await _security.savePin(uid, pin);
  }

  Future<void> enableBiometric(bool enabled) async {
    final uid = _uid;
    if (uid == null) return;

    if (enabled) {
      final ok = await _security.authenticateWithBiometrics(
        reason: 'Enable fingerprint unlock',
      );
      if (!ok) return;
    }

    await _security.setBiometricEnabled(uid, enabled);
    _biometricEnabled = enabled;
    notifyListeners();
  }

  Future<void> finishSetup({required bool enableBiometric}) async {
    if (enableBiometric) {
      await this.enableBiometric(true);
    }
    unlock();
  }

  Future<bool> verifyPin(String pin) async {
    final uid = _uid;
    if (uid == null) return false;
    return _security.verifyPin(uid, pin);
  }

  Future<bool> unlockWithPin(String pin) async {
    final ok = await verifyPin(pin);
    if (ok) unlock();
    return ok;
  }

  Future<bool> unlockWithBiometric() async {
    final uid = _uid;
    if (uid == null || !_biometricEnabled) return false;
    final ok = await _security.authenticateWithBiometrics();
    if (ok) unlock();
    return ok;
  }

  void unlock() {
    _status = AppLockStatus.unlocked;
    _pausedAt = null;
    notifyListeners();
  }

  void lock() {
    if (_uid == null) return;
    if (_status == AppLockStatus.needsSetup) return;
    _status = AppLockStatus.locked;
    notifyListeners();
  }

  Future<void> changePin(String newPin) async {
    final uid = _uid;
    if (uid == null) return;
    await _security.savePin(uid, newPin);
  }

  Future<void> setAutoLockOption(AutoLockOption option) async {
    final uid = _uid;
    if (uid == null) return;
    await _security.setAutoLockOption(uid, option);
    _autoLockOption = option;
    notifyListeners();
  }

  Future<void> refreshBiometricAvailability() async {
    _biometricsAvailable = await _security.canCheckBiometrics();
    notifyListeners();
  }

  void _ensureLifecycleObserver() {
    if (_observingLifecycle) return;
    WidgetsBinding.instance.addObserver(this);
    _observingLifecycle = true;
  }

  void _removeLifecycleObserver() {
    if (!_observingLifecycle) return;
    WidgetsBinding.instance.removeObserver(this);
    _observingLifecycle = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_uid == null || _status == AppLockStatus.needsSetup) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Only track backgrounding while already unlocked. Biometric / system
      // auth UI while locked must not count as leaving the app.
      if (_status == AppLockStatus.unlocked) {
        _pausedAt ??= DateTime.now();
      }
      return;
    }

    if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      // Require a real unlocked-background timestamp. Null pausedAt used to
      // become Duration.zero and immediately re-lock (fingerprint loop).
      final shouldLock = _status == AppLockStatus.unlocked &&
          pausedAt != null &&
          DateTime.now().difference(pausedAt).inSeconds >=
              _autoLockOption.seconds;
      if (!shouldLock) return;
      lock();
    }
  }

  @override
  void dispose() {
    _removeLifecycleObserver();
    super.dispose();
  }
}
