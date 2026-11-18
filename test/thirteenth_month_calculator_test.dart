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

    test('no taxable excess means no additional tax', () {
      final result = ThirteenthMonthCalculator.calculate(
        List<double?>.filled(12, 20000),
      );

      expect(result.additionalIncomeTax, 0);
      expect(result.takeHome, result.totalBenefits);
      expect(result.totalTaxExempt, 20000);
    });

    test('additional tax follows the bracket the excess lands in', () {
      // Annual base 1,200,000 (25% bracket), 13th month 100,000,
      // taxable excess 10,000 -> extra tax 2,500, not a flat rate.
      final result = ThirteenthMonthCalculator.calculate(
        List<double?>.filled(12, 100000),
      );

      expect(result.gross, 100000);
      expect(result.taxableExcess, 10000);
      expect(result.additionalIncomeTax, 2500);
      expect(result.takeHome, 97500);
      expect(result.totalTaxExempt, 90000);
    });

    test('excess that stays under the first taxable bracket adds no tax', () {
      // Base 120,000, gross 10,000, other benefits use the whole cap.
      final result = ThirteenthMonthCalculator.calculate(
        List<double?>.filled(12, 10000),
        otherBenefits: 90000,
      );

      expect(result.taxableExcess, 10000);
      expect(result.additionalIncomeTax, 0);
      expect(result.takeHome, 100000);
    });

    test('excess that crosses a bracket is taxed per bracket', () {
      // Base 780,000 (20% bracket), excess 65,000 -> 845,000 (25% bracket).
      // Tax 113,750 - 98,500 = 15,250.
      final result = ThirteenthMonthCalculator.calculate(
        List<double?>.filled(12, 65000),
        otherBenefits: 90000,
      );

      expect(result.taxableExcess, 65000);
      expect(result.additionalIncomeTax, 15250);
      expect(result.takeHome, 155000 - 15250);
    });

    test('annual tax uses the graduated brackets', () {
      expect(ThirteenthMonthCalculator.annualIncomeTax(250000), 0);
      expect(ThirteenthMonthCalculator.annualIncomeTax(400000), 22500);
      expect(ThirteenthMonthCalculator.annualIncomeTax(800000), 102500);
      expect(ThirteenthMonthCalculator.annualIncomeTax(2000000), 402500);
      expect(ThirteenthMonthCalculator.annualIncomeTax(8000000), 2202500);
      expect(ThirteenthMonthCalculator.annualIncomeTax(0), 0);
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
