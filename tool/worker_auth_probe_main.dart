import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:just_budget/firebase_options.dart';

/// Safe non-mutating Worker auth probe (web + desktop safe).
///
/// Run:
///   flutter run -d chrome -t tool/worker_auth_probe_main.dart
///
/// Does NOT print the Firebase ID token.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const workerBase = 'https://journey-to-balance-api.bcueva1217.workers.dev';

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
      log('FAIL: No Firebase user is currently signed in on this Flutter environment.');
      log('Sign in with the Journey To Balance app on this same platform, then re-run.');
      runApp(_ProbeApp(lines: lines, passed: false));
      return;
    }

    log('Local Firebase user present.');
    log('Local uid: ${user.uid}');
    log('Email present: ${user.email != null && user.email!.isNotEmpty}');

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      log('FAIL: Could not obtain Firebase ID token.');
      runApp(_ProbeApp(lines: lines, passed: false));
      return;
    }
    log('Firebase ID token obtained (not printed).');
    log('Token length: ${token.length}');

    final unauth = await http.get(Uri.parse('$workerBase/api/auth/me'));
    log('');
    log('--- Unauthenticated GET /api/auth/me ---');
    log('HTTP ${unauth.statusCode}');
    log(unauth.body);

    final auth = await http.get(
      Uri.parse('$workerBase/api/auth/me'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    log('');
    log('--- Authenticated GET /api/auth/me ---');
    log('HTTP ${auth.statusCode}');
    log(auth.body);

    if (auth.statusCode != 200) {
      log('FAIL: Authenticated probe did not return HTTP 200.');
      runApp(_ProbeApp(lines: lines, passed: false));
      return;
    }

    final decoded = jsonDecode(auth.body);
    if (decoded is! Map) {
      log('FAIL: Unexpected response shape.');
      runApp(_ProbeApp(lines: lines, passed: false));
      return;
    }

    final authenticated = decoded['authenticated'] == true;
    final uid = decoded['uid']?.toString() ?? '';
    if (!authenticated || uid.isEmpty) {
      log('FAIL: Worker did not confirm authentication / UID.');
      runApp(_ProbeApp(lines: lines, passed: false));
      return;
    }

    if (uid != user.uid) {
      log('FAIL: Worker UID ($uid) does not match local Firebase UID (${user.uid}).');
      runApp(_ProbeApp(lines: lines, passed: false));
      return;
    }

    log('');
    log('PASS: Worker verified Firebase token and extracted matching UID.');
    log('No financial data was read or modified.');
    runApp(_ProbeApp(lines: lines, passed: true));
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
        backgroundColor: passed ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
        body: SafeArea(
          child: Padding(
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
