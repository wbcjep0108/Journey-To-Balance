import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

/// How well the app can currently reach the internet.
///
/// [slow] is still online: the app keeps working and inputs stay enabled.
/// Only [offline] should ever block the UI.
enum ConnectionStatus { good, slow, offline }

/// Detects offline state in two speeds.
///
/// 1. Instant: when the OS reports no network at all, the status becomes
///    [ConnectionStatus.offline] immediately, with no ping and no delay.
/// 2. Confirm: when the OS reports a network, a GET to the health endpoint
///    must fail [failureThreshold] times in a row before the status becomes
///    offline. A ping that succeeds slowly is [ConnectionStatus.slow], never
///    offline.
///
/// While offline, a periodic timer re-checks so the app recovers on its own.
class ConnectivityService {
  ConnectivityService({
    http.Client? client,
    Uri? healthUri,
    this.pingTimeout = const Duration(seconds: 5),
    this.slowThreshold = const Duration(seconds: 3),
    this.offlinePollInterval = const Duration(seconds: 20),
    this.retryDelay = const Duration(seconds: 1),
    this.failureThreshold = 2,
    Future<List<ConnectivityResult>> Function()? checkConnectivity,
    Stream<List<ConnectivityResult>>? connectivityChanges,
  }) : _ownsClient = client == null,
       _client = client ?? http.Client(),
       _healthUri = healthUri ?? Uri.parse(defaultHealthUrl),
       _checkConnectivity =
           checkConnectivity ?? (() => Connectivity().checkConnectivity()),
       _connectivityStream = connectivityChanges;

  /// Health route of the Journey to Balance Worker. Expects `{"ok": true}`.
  static const defaultHealthUrl =
      'https://journey-to-balance-api.nu-clouds.workers.dev/health';

  /// Maximum time a single ping may take before it counts as a failure.
  final Duration pingTimeout;

  /// A successful ping slower than this marks the connection as slow.
  final Duration slowThreshold;

  /// How often to re-check while offline.
  final Duration offlinePollInterval;

  /// Pause between consecutive confirmation pings.
  final Duration retryDelay;

  /// Consecutive ping failures required before reporting offline.
  final int failureThreshold;

  final bool _ownsClient;
  final http.Client _client;
  final Uri _healthUri;
  final Future<List<ConnectivityResult>> Function() _checkConnectivity;
  final Stream<List<ConnectivityResult>>? _connectivityStream;

  final StreamController<ConnectionStatus> _controller =
      StreamController<ConnectionStatus>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _pollTimer;
  Future<void>? _inFlight;
  ConnectionStatus _status = ConnectionStatus.good;
  DateTime? _lastChecked;
  bool _started = false;
  bool _disposed = false;

  /// Bumped whenever the OS reports no network, so results of an older
  /// in-flight check can never overwrite the newer offline state.
  int _epoch = 0;

  ConnectionStatus get status => _status;
  DateTime? get lastChecked => _lastChecked;

  /// Emits only when the status changes.
  Stream<ConnectionStatus> get onStatusChanged => _controller.stream;

  /// Starts listening to the OS connectivity stream and runs a first check.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    final stream = _connectivityStream ?? Connectivity().onConnectivityChanged;
    _subscription = stream.listen(_onConnectivityChanged, onError: (_) {});
    await checkNow();
  }

  /// Runs a check now. Calls made while a check is running share its result.
  /// Never throws.
  Future<void> checkNow() {
    if (_disposed) return Future<void>.value();
    final running = _inFlight;
    if (running != null) return running;
    final check = _verify();
    _inFlight = check;
    unawaited(
      check.whenComplete(() {
        if (identical(_inFlight, check)) _inFlight = null;
      }),
    );
    return check;
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (_disposed) return;
    if (_hasNoNetwork(results)) {
      _goOffline();
    } else {
      unawaited(checkNow());
    }
  }

  bool _hasNoNetwork(List<ConnectivityResult> results) =>
      results.isEmpty || results.every((r) => r == ConnectivityResult.none);

  void _goOffline() {
    _epoch++;
    _inFlight = null;
    _lastChecked = DateTime.now();
    _setStatus(ConnectionStatus.offline);
  }

  Future<void> _verify() async {
    final epoch = _epoch;
    try {
      List<ConnectivityResult> results;
      try {
        results = await _checkConnectivity();
      } catch (_) {
        // Unknown OS state: fall back to the ping.
        results = const [ConnectivityResult.other];
      }
      if (_disposed || epoch != _epoch) return;
      if (_hasNoNetwork(results)) {
        _goOffline();
        return;
      }

      // Already offline: one successful ping is enough to recover. Otherwise
      // require consecutive failures so a single hiccup never blocks anyone.
      final attempts = _status == ConnectionStatus.offline
          ? 1
          : (failureThreshold < 1 ? 1 : failureThreshold);

      for (var i = 0; i < attempts; i++) {
        final elapsed = await _ping();
        if (_disposed || epoch != _epoch) return;
        if (elapsed != null) {
          _lastChecked = DateTime.now();
          _setStatus(
            elapsed >= slowThreshold
                ? ConnectionStatus.slow
                : ConnectionStatus.good,
          );
          return;
        }
        if (i < attempts - 1 && retryDelay > Duration.zero) {
          await Future<void>.delayed(retryDelay);
          if (_disposed || epoch != _epoch) return;
        }
      }

      _lastChecked = DateTime.now();
      _setStatus(ConnectionStatus.offline);
    } catch (_) {
      // A check must never throw into the UI; keep the current status.
    }
  }

  /// Returns the round-trip time on success, or null on any failure
  /// (timeout, socket error, non-200, or a body that is not `{"ok": true}`).
  Future<Duration?> _ping() async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client
          .get(_healthUri, headers: const {'Cache-Control': 'no-cache'})
          .timeout(pingTimeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is Map && body['ok'] == true) return stopwatch.elapsed;
      return null;
    } catch (_) {
      return null;
    }
  }

  void _setStatus(ConnectionStatus next) {
    if (_disposed || next == _status) return;
    _status = next;
    if (next == ConnectionStatus.offline) {
      _pollTimer ??= Timer.periodic(
        offlinePollInterval,
        (_) => unawaited(checkNow()),
      );
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
    _controller.add(next);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    if (_ownsClient) _client.close();
    unawaited(_controller.close());
  }
}
