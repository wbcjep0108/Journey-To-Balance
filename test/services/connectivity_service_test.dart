import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_budget/services/connectivity_service.dart';

http.Response _ok() => http.Response('{"ok":true}', 200);

void main() {
  late StreamController<List<ConnectivityResult>> osStream;
  late List<ConnectivityResult> osState;
  late List<ConnectionStatus> emitted;
  late int pingCount;
  ConnectivityService? service;

  setUp(() {
    osStream = StreamController<List<ConnectivityResult>>.broadcast();
    osState = [ConnectivityResult.wifi];
    emitted = [];
    pingCount = 0;
  });

  tearDown(() async {
    service?.dispose();
    service = null;
    await osStream.close();
  });

  /// Lets broadcast stream events reach the test listener.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  ConnectivityService build(
    Future<http.Response> Function(http.Request request) handler, {
    Duration pingTimeout = const Duration(seconds: 5),
    Duration slowThreshold = const Duration(seconds: 3),
    Duration offlinePollInterval = const Duration(seconds: 20),
  }) {
    final built = ConnectivityService(
      client: MockClient((request) {
        pingCount++;
        return handler(request);
      }),
      healthUri: Uri.parse('https://example.test/health'),
      pingTimeout: pingTimeout,
      slowThreshold: slowThreshold,
      offlinePollInterval: offlinePollInterval,
      retryDelay: Duration.zero,
      checkConnectivity: () async => osState,
      connectivityChanges: osStream.stream,
    );
    built.onStatusChanged.listen(emitted.add);
    service = built;
    return built;
  }

  test('a single failed ping never marks the app offline', () async {
    var calls = 0;
    final s = build((_) async {
      calls++;
      if (calls == 1) throw http.ClientException('hiccup');
      return _ok();
    });

    await s.checkNow();

    expect(pingCount, 2);
    expect(s.status, ConnectionStatus.good);
    expect(emitted, isEmpty);
  });

  test('two consecutive ping failures mark the app offline', () async {
    final s = build((_) async => throw http.ClientException('down'));

    await s.checkNow();
    await settle();

    expect(pingCount, 2);
    expect(s.status, ConnectionStatus.offline);
    expect(emitted, [ConnectionStatus.offline]);
  });

  test('a body that is not {ok:true} counts as a failure', () async {
    final s = build(
      (_) async => http.Response('<html>Sign in to Wi-Fi</html>', 200),
    );

    await s.checkNow();

    expect(s.status, ConnectionStatus.offline);
  });

  test('a ping that exceeds the timeout counts as a failure', () async {
    final s = build(
      (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return _ok();
      },
      pingTimeout: const Duration(milliseconds: 30),
    );

    await s.checkNow();

    expect(s.status, ConnectionStatus.offline);
  });

  test('a slow but successful ping is slow, never offline', () async {
    final s = build(
      (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return _ok();
      },
      slowThreshold: const Duration(milliseconds: 40),
    );

    await s.checkNow();
    await settle();

    expect(pingCount, 1);
    expect(s.status, ConnectionStatus.slow);
    expect(emitted, [ConnectionStatus.slow]);
    expect(emitted, isNot(contains(ConnectionStatus.offline)));
  });

  test('OS reporting no network goes offline instantly without a ping', () async {
    final s = build((_) async => _ok());
    await s.start();
    emitted.clear();
    pingCount = 0;

    osStream.add([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);

    expect(s.status, ConnectionStatus.offline);
    expect(emitted, [ConnectionStatus.offline]);
    expect(pingCount, 0);
  });

  test('offline at launch is detected without a ping', () async {
    osState = [ConnectivityResult.none];
    final s = build((_) async => _ok());

    await s.start();

    expect(s.status, ConnectionStatus.offline);
    expect(pingCount, 0);
  });

  test('one successful ping recovers from offline', () async {
    var fail = true;
    final s = build((_) async {
      if (fail) throw http.ClientException('down');
      return _ok();
    });
    await s.checkNow();
    expect(s.status, ConnectionStatus.offline);

    fail = false;
    await s.checkNow();
    await settle();

    expect(s.status, ConnectionStatus.good);
    expect(emitted, [ConnectionStatus.offline, ConnectionStatus.good]);
  });

  test('connectivity returning triggers a confirming ping', () async {
    var fail = true;
    final s = build((_) async {
      if (fail) throw http.ClientException('down');
      return _ok();
    });
    await s.start();
    expect(s.status, ConnectionStatus.offline);

    fail = false;
    osStream.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(s.status, ConnectionStatus.good);
  });

  test('polls while offline and recovers on its own', () async {
    var fail = true;
    final s = build(
      (_) async {
        if (fail) throw http.ClientException('down');
        return _ok();
      },
      offlinePollInterval: const Duration(milliseconds: 40),
    );
    await s.checkNow();
    expect(s.status, ConnectionStatus.offline);

    fail = false;
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(s.status, ConnectionStatus.good);
  });

  test('does not poll while online', () async {
    final s = build(
      (_) async => _ok(),
      offlinePollInterval: const Duration(milliseconds: 20),
    );
    await s.checkNow();
    final before = pingCount;

    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(pingCount, before);
  });
}
