import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Client for the Journey To Balance Cloudflare Worker finance API.
///
/// Sends the Firebase ID token in `Authorization: Bearer …`.
/// The Worker verifies the token and derives the UID — never trust a body UID.
class FinanceApiService {
  FinanceApiService({
    http.Client? httpClient,
    FirebaseAuth? auth,
    String? baseUrl,
  }) : _http = httpClient ?? http.Client(),
       _auth = auth ?? FirebaseAuth.instance,
       _baseUrl = (baseUrl ?? defaultBaseUrl).replaceAll(RegExp(r'/$'), '');

  /// Deployed Worker URL (workers.dev).
  static const defaultBaseUrl =
      'https://journey-to-balance-api.bcueva1217.workers.dev';

  final http.Client _http;
  final FirebaseAuth _auth;
  final String _baseUrl;
  final _random = Random.secure();

  /// Unique idempotency key for a single user action.
  String newRequestId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 32);
    return '${now}_$salt';
  }

  Future<String> _idToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const FinanceApiException(
        code: 'unauthenticated',
        message: 'Please sign in again to continue.',
      );
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const FinanceApiException(
        code: 'unauthenticated',
        message: 'Please sign in again to continue.',
      );
    }
    return token;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> data,
  ) async {
    try {
      final token = await _idToken();
      final uri = Uri.parse('$_baseUrl$path');
      final response = await _http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(data),
      );

      Map<String, dynamic> payload = const {};
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          payload = Map<String, dynamic>.from(decoded);
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return payload;
      }

      debugPrint(
        'FinanceApiService $path → HTTP ${response.statusCode} '
        'code=${payload['error'] is Map ? (payload['error'] as Map)['code'] : null} '
        'retry-after=${response.headers['retry-after']} '
        'bucket=${response.headers['x-ratelimit-bucket']}',
      );

      throw FinanceApiException.fromHttp(
        response.statusCode,
        payload,
        headers: response.headers,
      );
    } on FinanceApiException {
      rethrow;
    } catch (error, stack) {
      debugPrint('FinanceApiService $path failed: $error\n$stack');
      throw const FinanceApiException(
        code: 'unavailable',
        message:
            'Could not reach the budget server. Check your connection and try again.',
      );
    }
  }

  Future<Map<String, dynamic>> receiveSalary({required String requestId}) {
    return _post('/api/finance/receive-salary', {'requestId': requestId});
  }

  Future<Map<String, dynamic>> addMoney({
    required double amount,
    required String requestId,
  }) {
    return _post('/api/finance/add-money', {
      'amount': amount,
      'requestId': requestId,
    });
  }

  Future<Map<String, dynamic>> updateAvailableBalance({
    required double availableBalance,
    required String requestId,
  }) {
    return _post('/api/finance/update-available-balance', {
      'availableBalance': availableBalance,
      'requestId': requestId,
    });
  }

  Future<Map<String, dynamic>> updatePercentages({
    required double billsPercentage,
    required double savingsPercentage,
    required double personalPercentage,
    required String requestId,
  }) {
    return _post('/api/finance/update-percentages', {
      'billsPercentage': billsPercentage,
      'savingsPercentage': savingsPercentage,
      'personalPercentage': personalPercentage,
      'requestId': requestId,
    });
  }

  Future<Map<String, dynamic>> updateMonthlySalary({
    required double monthlySalary,
    required String requestId,
  }) {
    return _post('/api/finance/update-monthly-salary', {
      'monthlySalary': monthlySalary,
      'requestId': requestId,
    });
  }

  Future<Map<String, dynamic>> addTransaction({
    required String category,
    required String title,
    required double amount,
    required String entryId,
    required int createdAtMs,
    required String requestId,
  }) {
    return _post('/api/finance/add-transaction', {
      'category': category,
      'title': title,
      'amount': amount,
      'entryId': entryId,
      'createdAtMs': createdAtMs,
      'requestId': requestId,
    });
  }

  Future<Map<String, dynamic>> updateTransaction({
    required String category,
    required String entryId,
    required String title,
    required double amount,
    required String requestId,
  }) {
    return _post('/api/finance/update-transaction', {
      'category': category,
      'entryId': entryId,
      'title': title,
      'amount': amount,
      'requestId': requestId,
    });
  }

  Future<Map<String, dynamic>> deleteTransaction({
    required String category,
    required String entryId,
    required bool refund,
    required String requestId,
  }) {
    return _post('/api/finance/delete-transaction', {
      'category': category,
      'entryId': entryId,
      'refund': refund,
      'requestId': requestId,
    });
  }

  Future<Map<String, dynamic>> contributeToSavingsGoal({
    required String source,
    required double amount,
    required String entryId,
    required int createdAtMs,
    required String requestId,
  }) {
    return _post('/api/finance/contribute-to-savings-goal', {
      'source': source,
      'amount': amount,
      'entryId': entryId,
      'createdAtMs': createdAtMs,
      'requestId': requestId,
    });
  }

  Future<Map<String, dynamic>> updateSavingsGoalSettings({
    required double target,
    required int targetDateMs,
    required String title,
    required String requestId,
  }) {
    return _post('/api/finance/update-savings-goal-settings', {
      'target': target,
      'targetDateMs': targetDateMs,
      'title': title,
      'requestId': requestId,
    });
  }

  Future<Map<String, dynamic>> migrateBudgetSchema({
    required String requestId,
  }) {
    return _post('/api/finance/migrate-budget-schema', {
      'requestId': requestId,
    });
  }
}

class FinanceApiException implements Exception {
  const FinanceApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.retryAfterSeconds,
    this.bucket,
  });

  final String code;
  final String message;

  /// HTTP status when this exception came from a Worker response.
  final int? statusCode;

  /// Parsed `Retry-After` header (seconds), when present.
  final int? retryAfterSeconds;

  /// Parsed `X-RateLimit-Bucket` header (Worker action name), when present.
  final String? bucket;

  bool get isRateLimited =>
      statusCode == 429 ||
      code == 'rate-limit-exceeded' ||
      code == 'resource-exhausted';

  static bool isRateLimitError(Object error) =>
      error is FinanceApiException && error.isRateLimited;

  factory FinanceApiException.fromHttp(
    int status,
    Map<String, dynamic> payload, {
    Map<String, String>? headers,
  }) {
    final error = payload['error'];
    String code = 'internal';
    String? message;
    if (error is Map) {
      code = error['code']?.toString() ?? code;
      message = error['message']?.toString();
    }

    final retryAfter = _parseRetryAfter(headers);
    final bucket = _header(headers, 'x-ratelimit-bucket');

    if (status == 429 ||
        code == 'resource-exhausted' ||
        code == 'rate-limit-exceeded') {
      return FinanceApiException(
        code: code == 'rate-limit-exceeded'
            ? 'rate-limit-exceeded'
            : 'resource-exhausted',
        message:
            'You\'re doing that a little too quickly. Please try again in a moment.',
        statusCode: status,
        retryAfterSeconds: retryAfter,
        bucket: bucket,
      );
    }
    if (status == 401 || code == 'unauthenticated') {
      return FinanceApiException(
        code: 'unauthenticated',
        message: 'Please sign in again to continue.',
        statusCode: status,
      );
    }
    if (status == 403 || code == 'permission-denied') {
      return FinanceApiException(
        code: 'permission-denied',
        message: 'You do not have permission to perform this action.',
        statusCode: status,
      );
    }
    if (status == 400 || code == 'invalid-argument') {
      return FinanceApiException(
        code: 'invalid-argument',
        message: (message != null && message.isNotEmpty)
            ? message
            : 'That request was invalid. Please check your input and try again.',
        statusCode: status,
      );
    }
    if (status >= 500 || code == 'internal') {
      return FinanceApiException(
        code: 'internal',
        message: (message != null && message.isNotEmpty)
            ? message
            : 'The budget server had a problem. Please try again.',
        statusCode: status,
      );
    }
    if (message != null && message.isNotEmpty) {
      return FinanceApiException(
        code: code,
        message: message,
        statusCode: status,
      );
    }
    return FinanceApiException(
      code: code,
      message: 'Something went wrong. Please try again.',
      statusCode: status,
    );
  }

  static String? _header(Map<String, String>? headers, String name) {
    if (headers == null) return null;
    final value = headers[name] ?? headers[name.toLowerCase()];
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static int? _parseRetryAfter(Map<String, String>? headers) {
    final raw = _header(headers, 'retry-after');
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds == null || seconds < 0) return null;
    return seconds;
  }

  @override
  String toString() => message;
}
