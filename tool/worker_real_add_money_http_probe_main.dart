import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:just_budget/firebase_options.dart';

/// Hits the REAL production POST /api/finance/add-money path 21 times quickly
/// to compare HTTP status vs the non-mutating addMoney rate-limit probe.
///
/// WARNING: This mutates available balance (adds ₱1 twenty times if unlimited).
/// Prefer a throwaway test account. Token is never printed.
///
///   flutter run -d <device-id> -t tool/worker_real_add_money_http_probe_main.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const workerBase = 'https://journey-to-balance-api.bcueva1217.workers.dev';
  const endpoint = '$workerBase/api/finance/add-money';
  const total = 21;

  final lines = <String>[];
  void log(String m) {
    lines.add(m);
    debugPrint(m);
  }

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      log('FAIL: sign in first');
      runApp(_App(lines: lines, passed: false));
      return;
    }

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      log('FAIL: no token');
      runApp(_App(lines: lines, passed: false));
      return;
    }

    log('uid suffix: ${user.uid.substring(user.uid.length - 6)}');
    log('POST $endpoint × $total (amount=1 each)');
    log('Expect if limiter works: ~20×200 then 429 (or 500 if DO throw bug).');
    log('');

    var ok200 = 0;
    var status429 = 0;
    var status500 = 0;
    var other = 0;

    for (var i = 1; i <= total; i++) {
      final requestId =
          '${DateTime.now().microsecondsSinceEpoch}_${i}_probe';
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'amount': 1.0, 'requestId': requestId}),
      );

      log('--- $i --- HTTP ${response.statusCode}');
      if (response.statusCode == 200) {
        ok200++;
      } else if (response.statusCode == 429) {
        status429++;
      } else if (response.statusCode >= 500) {
        status500++;
        log('body: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
      } else {
        other++;
        log('body: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
      }
    }

    log('');
    log('summary: 200=$ok200 429=$status429 5xx=$status500 other=$other');
    final passed = ok200 <= 20 && (status429 > 0 || status500 > 0);
    log(
      passed
          ? 'BLOCKED after ~20 (limiter engaged; check if status is 429 vs 500).'
          : 'NOT BLOCKED: more than 20 HTTP 200 — production path bypassed limit.',
    );
    runApp(_App(lines: lines, passed: passed && status429 > 0));
  } catch (e, st) {
    log('FAIL: $e\n$st');
    runApp(_App(lines: lines, passed: false));
  }
}

class _App extends StatelessWidget {
  const _App({required this.lines, required this.passed});
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
