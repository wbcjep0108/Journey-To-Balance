import 'package:flutter_test/flutter_test.dart';
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

    test('maps 429 and rate-limit-exceeded', () {
      final a = FinanceApiException.fromHttp(429, const {});
      expect(a.code, 'resource-exhausted');
      expect(a.message, contains('quickly'));

      final b = FinanceApiException.fromHttp(429, {
        'error': {'code': 'rate-limit-exceeded'},
      });
      expect(b.code, 'resource-exhausted');
    });

    test('maps 400 validation', () {
      final e = FinanceApiException.fromHttp(400, {
        'error': {'code': 'invalid-argument', 'message': 'bad amount'},
      });
      expect(e.code, 'invalid-argument');
      expect(e.message, 'bad amount');
    });

    test('maps 500', () {
      final e = FinanceApiException.fromHttp(500, const {});
      expect(e.code, 'internal');
      expect(e.message, contains('budget server'));
    });
  });
}
