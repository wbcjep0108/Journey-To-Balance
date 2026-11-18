import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/connectivity_service.dart';

/// App-wide connection state for the UI.
///
/// Only [online] == false should block the app. [isSlow] is informational.
class ConnectivityProvider extends ChangeNotifier with WidgetsBindingObserver {
  ConnectivityProvider({
    ConnectivityService? service,
    this.minimumRetrySpinner = const Duration(milliseconds: 500),
  }) : _service = service ?? ConnectivityService() {
    _status = _service.status;
    _lastChecked = _service.lastChecked;
    _subscription = _service.onStatusChanged.listen(_onStatus);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_service.start());
  }

  final ConnectivityService _service;

  /// The spinner on "Try again" stays visible at least this long.
  final Duration minimumRetrySpinner;

  StreamSubscription<ConnectionStatus>? _subscription;
  ConnectionStatus _status = ConnectionStatus.good;
  DateTime? _lastChecked;
  bool _checking = false;
  bool _disposed = false;

  ConnectionStatus get status => _status;

  /// False only when the device is confirmed offline.
  bool get online => _status != ConnectionStatus.offline;

  bool get isSlow => _status == ConnectionStatus.slow;

  /// True while a manual "Try again" check is running.
  bool get checking => _checking;

  DateTime? get lastChecked => _lastChecked;

  void _onStatus(ConnectionStatus status) {
    _status = status;
    _lastChecked = _service.lastChecked ?? DateTime.now();
    _notify();
  }

  /// Re-runs the check for the "Try again" button.
  Future<void> retry() async {
    if (_checking) return;
    _checking = true;
    _notify();
    try {
      await Future.wait<void>([
        _service.checkNow(),
        Future<void>.delayed(minimumRetrySpinner),
      ]);
    } finally {
      _checking = false;
      _status = _service.status;
      _lastChecked = _service.lastChecked ?? DateTime.now();
      _notify();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_service.checkNow());
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    _service.dispose();
    super.dispose();
  }
}
