import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/services/thirteenth_month_calculator.dart';

void main() {
  group('ThirteenthMonthCalculator', () {
    test('handles fewer than 12 months worked', () {
      final result = ThirteenthMonthCalculator.calculate([
        30000,
        30000,
        30000,
        30000,
        30000,
        30000,
      ]);

      expect(result.gross, 15000);
      expect(result.taxExempt, 15000);
      expect(result.taxableExcess, 0);
      expect(result.monthlyBreakdown, hasLength(12));
    });

    test('treats zero and empty months as zero salary', () {
      final empty = ThirteenthMonthCalculator.calculate(const []);
      final zeros = ThirteenthMonthCalculator.calculate(
        List<double?>.filled(12, 0),
      );

      expect(empty.gross, 0);
      expect(zeros.gross, 0);
      expect(empty.taxExempt, 0);
      expect(empty.taxableExcess, 0);
    });

    test('other benefits above the cap make the full gross taxable', () {
      final result = ThirteenthMonthCalculator.calculate(
        List<double?>.filled(12, 100000),
        otherBenefits: 100000,
      );

      expect(result.gross, 100000);
      expect(result.taxExempt, 0);
      expect(result.taxableExcess, 100000);
    });

    test('gross exactly at the cap is fully exempt', () {
      final result = ThirteenthMonthCalculator.calculate(
        List<double?>.filled(12, 90000),
      );

      expect(result.gross, ThirteenthMonthCalculator.taxExemptCap);
      expect(result.taxExempt, 90000);
      expect(result.taxableExcess, 0);
    });

    test('rounds gross and tax portions to centavos', () {
      final result = ThirteenthMonthCalculator.calculate([
        10000.01,
      ], otherBenefits: 89900);

      expect(result.gross, 833.33);
      expect(result.taxExempt, 100);
      expect(result.taxableExcess, 733.33);
      expect(result.monthlyBreakdown.first.thirteenthMonthShare, 833.33);
    });
  });
}
