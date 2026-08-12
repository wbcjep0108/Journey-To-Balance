import 'dart:convert';

import 'package:http/http.dart' as http;

/// Debug-mode NDJSON logger → Cursor ingest (requires `adb reverse tcp:7578 tcp:7578`).
/// Uses [print] (not debugPrint) so profile-mode throttling cannot drop lines.
void agentDebugLog({
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, Object?> data = const {},
  String runId = 'pre',
}) {
  // #region agent log
  final payload = <String, Object?>{
    'sessionId': '91551e',
    'runId': runId,
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  final body = jsonEncode(payload);
  // ignore: avoid_print
  print('AGENT_DEBUG $body');
  http
      .post(
        Uri.parse(
          'http://127.0.0.1:7578/ingest/670d1888-1348-4706-9b81-16821c3d946e',
        ),
        headers: {
          'Content-Type': 'application/json',
          'X-Debug-Session-Id': '91551e',
        },
        body: body,
      )
      .catchError((_) => http.Response('', 500));
  // #endregion
}
