import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:just_budget/firebase_options.dart';

/// Non-mutating rate-limit probe against the deployed Worker.
///
/// Run on the signed-in Android device:
///   flutter run -d <device-id> -t tool/worker_rate_limit_probe_main.dart
///
/// Does NOT print the Firebase ID token.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const workerBase = 'https://journey-to-balance-api.bcueva1217.workers.dev';
  const endpoint = '$workerBase/api/test/rate-limit';

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
    log('Calling GET /api/test/rate-limit six times (token not printed).');
    log('No financial endpoints will be called.');
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
    for (var i = 1; i <= 6; i++) {
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
        } catch (_) {
          // Ignore non-JSON bodies for logging.
        }
      }

      final bucket = bucketHeader ?? bodyBucket ?? '(missing)';
      final limit = limitHeader ?? (bodyLimit?.toString() ?? '(missing)');
      final remaining =
          remainingHeader ?? (bodyRemaining?.toString() ?? '(missing)');

      log('--- Request $i ---');
      log('HTTP ${response.statusCode}');
      log('bucket: $bucket');
      log('limit: $limit');
      log('remaining: $remaining');
      log('X-RateLimit-Limit: ${limitHeader ?? '(missing)'}');
      log('X-RateLimit-Remaining: ${remainingHeader ?? '(missing)'}');
      log('X-RateLimit-Reset: ${resetHeader ?? '(missing)'}');
      log('X-RateLimit-Bucket: ${bucketHeader ?? '(missing)'}');
      log('Retry-After: ${retryAfter ?? '(missing)'}');
      log('');

      if (i <= 5) {
        if (response.statusCode != 200) {
          passed = false;
          log('UNEXPECTED: request $i expected HTTP 200.');
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
        }
      }
    }

    log(
      passed
          ? 'PASS: Requests 1–5 returned 200; request 6 returned 429 with rate-limit headers.'
          : 'FAIL: Rate-limit sequence did not match expected 5×200 then 1×429.',
    );
    log('Confirmed: only /api/test/rate-limit was called (non-mutating).');
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
