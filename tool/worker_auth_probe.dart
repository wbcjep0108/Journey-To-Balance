import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import 'package:just_budget/firebase_options.dart';

/// Safe non-mutating Worker auth probe.
///
/// Does NOT print the Firebase ID token.
/// Usage (from repo root):
///   dart run tool/worker_auth_probe.dart
Future<void> main() async {
  const workerBase = 'https://journey-to-balance-api.bcueva1217.workers.dev';

  stdout.writeln('Initializing Firebase…');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    stderr.writeln(
      'FAIL: No Firebase user is currently signed in on this environment.\n'
      'Sign in once with the Flutter Windows/web app, then re-run this probe.',
    );
    exitCode = 2;
    return;
  }

  stdout.writeln('Local Firebase user present.');
  stdout.writeln('Local uid: ${user.uid}');
  stdout.writeln('Email present: ${user.email != null && user.email!.isNotEmpty}');

  final token = await user.getIdToken();
  if (token == null || token.isEmpty) {
    stderr.writeln('FAIL: Could not obtain Firebase ID token.');
    exitCode = 3;
    return;
  }
  stdout.writeln('Firebase ID token obtained (not printed).');
  stdout.writeln('Token length: ${token.length}');

  // Control: unauthenticated request must be 401.
  final unauth = await http.get(Uri.parse('$workerBase/api/auth/me'));
  stdout.writeln('');
  stdout.writeln('--- Unauthenticated GET /api/auth/me ---');
  stdout.writeln('HTTP ${unauth.statusCode}');
  stdout.writeln(unauth.body);

  // Authenticated probe.
  final auth = await http.get(
    Uri.parse('$workerBase/api/auth/me'),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
  );

  stdout.writeln('');
  stdout.writeln('--- Authenticated GET /api/auth/me ---');
  stdout.writeln('HTTP ${auth.statusCode}');
  stdout.writeln(auth.body);

  if (auth.statusCode != 200) {
    stderr.writeln('FAIL: Authenticated probe did not return HTTP 200.');
    exitCode = 4;
    return;
  }

  final decoded = jsonDecode(auth.body);
  if (decoded is! Map) {
    stderr.writeln('FAIL: Unexpected response shape.');
    exitCode = 5;
    return;
  }

  final authenticated = decoded['authenticated'] == true;
  final uid = decoded['uid']?.toString() ?? '';
  if (!authenticated || uid.isEmpty) {
    stderr.writeln('FAIL: Worker did not confirm authentication / UID.');
    exitCode = 6;
    return;
  }

  if (uid != user.uid) {
    stderr.writeln(
      'FAIL: Worker UID ($uid) does not match local Firebase UID (${user.uid}).',
    );
    exitCode = 7;
    return;
  }

  stdout.writeln('');
  stdout.writeln('PASS: Worker verified Firebase token and extracted matching UID.');
  stdout.writeln('No financial data was read or modified.');
}
