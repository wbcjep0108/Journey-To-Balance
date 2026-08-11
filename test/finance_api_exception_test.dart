import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/rate_limit_info.dart';
import 'package:just_budget/services/finance_api_service.dart';

void main() {
  group('FinanceApiException.fromHttp', () {
    test('maps 401', () {
      final e = FinanceApiException.fromHttp(401, const {});
      expect(e.code, 'unauthenticated');
    });

    test('maps 403', () {
      final e = FinanceApiException.fromHttp(403, const {});
      expect(e.code, 'permission-denied');
    });

    test('maps 429 and rate-limit-exceeded with headers', () {
      final a = FinanceApiException.fromHttp(429, const {});
      expect(a.code, 'resource-exhausted');
      expect(a.isRateLimited, isTrue);
      expect(a.statusCode, 429);

      final b = FinanceApiException.fromHttp(
        429,
        {
          'error': {'code': 'rate-limit-exceeded'},
        },
        headers: {
          'retry-after': '42',
          'x-ratelimit-bucket': 'addMoney',
        },
      );
      expect(b.code, 'rate-limit-exceeded');
      expect(b.isRateLimited, isTrue);
      expect(b.retryAfterSeconds, 42);
      expect(b.bucket, 'addMoney');
      expect(FinanceApiException.isRateLimitError(b), isTrue);
    });

    test('maps 400 validation', () {
      final e = FinanceApiException.fromHttp(400, {
        'error': {'code': 'invalid-argument', 'message': 'bad amount'},
      });
      expect(e.code, 'invalid-argument');
      expect(e.message, 'bad amount');
      expect(e.isRateLimited, isFalse);
    });

    test('maps 500', () {
      final e = FinanceApiException.fromHttp(500, const {});
      expect(e.code, 'internal');
      expect(e.message, contains('budget server'));
    });
  });

  group('RateLimitInfo', () {
    test('prefers action label in title', () {
      const info = RateLimitInfo(
        code: 'rate-limit-exceeded',
        actionLabel: 'Bills',
        retryAfterSeconds: 12,
      );
      expect(info.dialogTitle, 'Bills Limit Reached');
      expect(info.dialogMessage, contains('12 seconds'));
    });

    test('falls back to bucket label and generic message', () {
      const info = RateLimitInfo(
        code: 'rate-limit-exceeded',
        bucket: 'contributeToSavingsGoal',
      );
      expect(info.dialogTitle, 'Savings Goal Limit Reached');
      expect(info.dialogMessage, contains('shortly'));
    });

    test('uses Too Many Requests when unknown', () {
      const info = RateLimitInfo(code: 'rate-limit-exceeded');
      expect(info.dialogTitle, 'Too Many Requests');
    });
  });
}
