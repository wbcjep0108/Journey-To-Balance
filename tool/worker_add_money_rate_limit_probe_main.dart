import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:just_budget/firebase_options.dart';

/// Non-mutating probe of the production **addMoney** rate-limit bucket.
///
/// Hits GET /api/test/rate-limit-add-money (same UID / DO / `addMoney` +
/// `general` counters as real Add Money). Does NOT mutate Firestore.
///
/// Expect: requests 1–20 → HTTP 200; request 21 → HTTP 429.
///
/// Run on a signed-in device (full restart if switching entrypoint):
///   flutter run -d <device-id> -t tool/worker_add_money_rate_limit_probe_main.dart
///
/// Does NOT print the Firebase ID token.
///
/// Warning: this consumes your real addMoney + general rate-limit window.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const workerBase = 'https://journey-to-balance-api.bcueva1217.workers.dev';
  const endpoint = '$workerBase/api/test/rate-limit-add-money';
  const totalRequests = 21;
  const expectedOk = 20;

  final lines = <String>[];
  void log(String message) {
    lines.add(message);
    debugPrint(message);
  }

  try {
    log('Initializing Firebase…');
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      log('FAIL: No Firebase user signed in on this device.');
      runApp(_ProbeApp(lines: lines, passed: false));
      return;
    }

    log('Authenticated Firebase user present.');
    log('Local uid: ${user.uid}');
    log('Calling GET /api/test/rate-limit-add-money $totalRequests times.');
    log('Expected: 1–$expectedOk → 200; request $totalRequests → 429.');
    log('Bucket under test: addMoney (limit 20 / 60s) + general.');
    log('No Firestore mutations.');
    log('');

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      log('FAIL: Could not obtain Firebase ID token.');
      runApp(_ProbeApp(lines: lines, passed: false));
      return;
    }
    log('Firebase ID token obtained (not printed). length=${token.length}');
    log('');

    var passed = true;
    for (var i = 1; i <= totalRequests; i++) {
      final response = await http.get(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      final limitHeader = response.headers['x-ratelimit-limit'];
      final remainingHeader = response.headers['x-ratelimit-remaining'];
      final resetHeader = response.headers['x-ratelimit-reset'];
      final bucketHeader = response.headers['x-ratelimit-bucket'];
      final retryAfter = response.headers['retry-after'];

      String? bodyBucket;
      int? bodyLimit;
      int? bodyRemaining;
      if (response.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            bodyBucket = decoded['bucket']?.toString();
            bodyLimit = int.tryParse('${decoded['limit']}');
            bodyRemaining = int.tryParse('${decoded['remaining']}');
          }
        } catch (_) {}
      }

      log('--- Request $i ---');
      log('HTTP ${response.statusCode}');
      log('bucket: ${bucketHeader ?? bodyBucket ?? '(missing)'}');
      log('limit: ${limitHeader ?? bodyLimit?.toString() ?? '(missing)'}');
      log(
        'remaining: ${remainingHeader ?? bodyRemaining?.toString() ?? '(missing)'}',
      );
      log('X-RateLimit-Limit: ${limitHeader ?? '(missing)'}');
      log('X-RateLimit-Remaining: ${remainingHeader ?? '(missing)'}');
      log('X-RateLimit-Reset: ${resetHeader ?? '(missing)'}');
      log('X-RateLimit-Bucket: ${bucketHeader ?? '(missing)'}');
      log('Retry-After: ${retryAfter ?? '(missing)'}');
      log('');

      if (i <= expectedOk) {
        if (response.statusCode != 200) {
          passed = false;
          log('UNEXPECTED: request $i expected HTTP 200.');
        } else if (bucketHeader != null && bucketHeader != 'addMoney') {
          passed = false;
          log('UNEXPECTED: bucket should be addMoney, got $bucketHeader');
        } else if (limitHeader != null && limitHeader != '20') {
          passed = false;
          log('UNEXPECTED: limit should be 20, got $limitHeader');
        }
      } else {
        if (response.statusCode != 429) {
          passed = false;
          log('UNEXPECTED: request $i expected HTTP 429.');
        } else {
          final headersOk = limitHeader != null &&
              remainingHeader != null &&
              resetHeader != null &&
              bucketHeader != null &&
              retryAfter != null;
          if (!headersOk) {
            passed = false;
            log('UNEXPECTED: 429 missing one or more rate-limit headers.');
          }
          if (bucketHeader != 'addMoney') {
            passed = false;
            log('UNEXPECTED: 429 bucket should be addMoney.');
          }
        }
      }
    }

    log(
      passed
          ? 'PASS: Requests 1–$expectedOk returned 200; request $totalRequests returned 429 (addMoney).'
          : 'FAIL: addMoney rate-limit sequence did not match expected.',
    );
    runApp(_ProbeApp(lines: lines, passed: passed));
  } catch (error, stack) {
    log('FAIL: $error');
    log('$stack');
    runApp(_ProbeApp(lines: lines, passed: false));
  }
}

class _ProbeApp extends StatelessWidget {
  const _ProbeApp({required this.lines, required this.passed});

  final List<String> lines;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor:
            passed ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              lines.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}
