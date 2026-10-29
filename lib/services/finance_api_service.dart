import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Client for the Journey To Balance Cloudflare Worker finance API.
///
/// Sends the Firebase ID token in `Authorization: Bearer …`.
/// The Worker verifies the token and derives the UID — never trust a body UID.
abstract class PasswordResetApi {
  Future<void> requestPasswordReset({required String email});
  Future<String> verifyPasswordResetCode({
    required String email,
    required String code,
  });
  Future<void> confirmPasswordReset({
    required String email,
    required String resetToken,
    required String newPassword,
  });
}

class FinanceApiService implements PasswordResetApi {
  FinanceApiService({
    http.Client? httpClient,
    FirebaseAuth? auth,
    String? baseUrl,
  }) : _http = httpClient ?? http.Client(),
       _auth = auth ?? FirebaseAuth.instance,
       _baseUrl = (baseUrl ?? defaultBaseUrl).replaceAll(RegExp(r'/$'), '');

  /// Deployed Worker URL (workers.dev).
  static const defaultBaseUrl =
      'https://journey-to-balance-api.nu-clouds.workers.dev';

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

  Future<String> _idToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const FinanceApiException(
        code: 'unauthenticated',
        message: 'Please sign in again to continue.',
      );
    }
    final token = await user.getIdToken(forceRefresh);
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
    Map<String, dynamic> data, {
    bool forceRefresh = false,
  }) async {
    try {
      final token = await _idToken(forceRefresh: forceRefresh);
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

  Future<Map<String, dynamic>> _postPublic(
    String path,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _http.post(
        Uri.parse('$_baseUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      Map<String, dynamic> payload = const {};
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return payload;
      }
      throw FinanceApiException.fromHttp(
        response.statusCode,
        payload,
        headers: response.headers,
      );
    } on FinanceApiException {
      rethrow;
    } catch (_) {
      throw const FinanceApiException(
        code: 'unavailable',
        message: 'No internet connection.',
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
    String? iconAsset,
    String? fundingSourceId,
    String? fundingSourceLabel,
  }) {
    return _post('/api/finance/add-transaction', {
      'category': category,
      'title': title,
      'amount': amount,
      'entryId': entryId,
      'createdAtMs': createdAtMs,
      'requestId': requestId,
      if (iconAsset != null && iconAsset.isNotEmpty) 'iconAsset': iconAsset,
      if (fundingSourceId != null && fundingSourceId.isNotEmpty)
        'fundingSourceId': fundingSourceId,
      if (fundingSourceLabel != null && fundingSourceLabel.isNotEmpty)
        'fundingSourceLabel': fundingSourceLabel,
    });
  }

  Future<Map<String, dynamic>> updateTransaction({
    required String category,
    required String entryId,
    required String title,
    required double amount,
    required String requestId,
    String? iconAsset,
  }) {
    return _post('/api/finance/update-transaction', {
      'category': category,
      'entryId': entryId,
      'title': title,
      'amount': amount,
      'requestId': requestId,
      if (iconAsset != null && iconAsset.isNotEmpty) 'iconAsset': iconAsset,
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
    required String fundingSourceId,
    required String fundingSourceLabel,
    required double amount,
    required String entryId,
    required int createdAtMs,
    required String requestId,
  }) {
    return _post('/api/finance/contribute-to-savings-goal', {
      'source': source,
      'fundingSourceId': fundingSourceId,
      'fundingSourceLabel': fundingSourceLabel,
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

  Future<Map<String, dynamic>> requestPinResetOtp({required String email}) {
    return _post('/api/auth/forgot-pin/request', {'email': email});
  }

  Future<Map<String, dynamic>> verifyPinResetOtp({
    required String email,
    required String otp,
  }) {
    return _post('/api/auth/forgot-pin/verify', {'email': email, 'otp': otp});
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    await _postPublic('/auth/password-reset/request', {'email': email});
  }

  @override
  Future<String> verifyPasswordResetCode({
    required String email,
    required String code,
  }) async {
    final result = await _postPublic('/auth/password-reset/verify', {
      'email': email,
      'code': code,
    });
    final token = result['resetToken'];
    if (token is! String || token.isEmpty) {
      throw const FinanceApiException(
        code: 'invalid_code',
        message: 'Wrong or expired code',
      );
    }
    return token;
  }

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    await _postPublic('/auth/password-reset/confirm', {
      'email': email,
      'resetToken': resetToken,
      'newPassword': newPassword,
    });
  }

  Future<void> deleteAccount({required String confirmationEmail}) async {
    await _post(
      '/api/auth/delete-account',
      {'confirmationEmail': confirmationEmail},
      forceRefresh: true,
    );
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
    if (error is String) {
      code = error;
    } else if (error is Map) {
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
        code: code,
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
