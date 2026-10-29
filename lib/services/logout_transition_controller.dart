import 'dart:async';

import 'package:flutter/foundation.dart';

class LogoutTransitionController extends ChangeNotifier {
  LogoutTransitionController({
    this.minimumDuration = const Duration(milliseconds: 500),
    this.maximumDuration = const Duration(seconds: 3),
  });

  final Duration minimumDuration;
  final Duration maximumDuration;

  Timer? _minimumTimer;
  Timer? _maximumTimer;
  bool _active = false;
  bool _minimumElapsed = false;
  bool _logoutComplete = false;
  bool _signedOut = false;
  bool _loginReady = false;
  bool _showLogin = false;
  bool _visualFinished = false;

  bool get active => _active;
  bool get showLogin => _showLogin;

  void begin() {
    if (_active) return;
    _active = true;
    _minimumElapsed = false;
    _logoutComplete = false;
    _signedOut = false;
    _loginReady = false;
    _showLogin = false;
    _visualFinished = false;
    _minimumTimer = Timer(minimumDuration, () {
      _minimumElapsed = true;
      _evaluate();
    });
    _maximumTimer = Timer(maximumDuration, () {
      if (!_active || _showLogin) return;
      _showLogin = true;
      notifyListeners();
    });
    notifyListeners();
  }

  void markLogoutComplete() {
    if (!_active) return;
    _logoutComplete = true;
    _evaluate();
  }

  void markSignedOut() {
    if (!_active) return;
    _signedOut = true;
    if (_showLogin && _visualFinished) {
      _complete();
      return;
    }
    _evaluate();
  }

  void markLoginReady() {
    if (!_active) return;
    _loginReady = true;
    _evaluate();
  }

  void _evaluate() {
    if (!_active || _showLogin) return;
    if (_minimumElapsed && _logoutComplete && _signedOut && _loginReady) {
      _showLogin = true;
      _maximumTimer?.cancel();
      notifyListeners();
    }
  }

  void finish() {
    if (!_active) return;
    _visualFinished = true;
    if (!_signedOut) return;
    _complete();
  }

  void _complete() {
    _cancelTimers();
    _active = false;
    notifyListeners();
  }

  void abort() {
    _cancelTimers();
    _active = false;
    _showLogin = false;
    notifyListeners();
  }

  void _cancelTimers() {
    _minimumTimer?.cancel();
    _maximumTimer?.cancel();
    _minimumTimer = null;
    _maximumTimer = null;
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }
}
