import '../models/thirteenth_month_result.dart';

class ThirteenthMonthCalculator {
  const ThirteenthMonthCalculator._();

  static const double taxExemptCap = 90000;
  static const int monthCount = 12;

  static ThirteenthMonthResult calculate(
    List<double?> monthlyBasicSalaries, {
    double otherBenefits = 0,
  }) {
    if (monthlyBasicSalaries.length > monthCount) {
      throw ArgumentError('At most 12 monthly salaries are allowed.');
    }
    if (otherBenefits < 0 || !otherBenefits.isFinite) {
      throw ArgumentError('Other benefits must be a non-negative amount.');
    }

    final salaries = List<double>.generate(monthCount, (index) {
      final double amount = index < monthlyBasicSalaries.length
          ? monthlyBasicSalaries[index] ?? 0
          : 0.0;
      if (amount < 0 || !amount.isFinite) {
        throw ArgumentError('Monthly salaries must be non-negative amounts.');
      }
      return amount;
    }, growable: false);

    final totalBasicSalary = salaries.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    final gross = _roundMoney(totalBasicSalary / monthCount);
    final roundedOtherBenefits = _roundMoney(otherBenefits);
    final totalBenefits = _roundMoney(gross + roundedOtherBenefits);
    final remainingExemption = (taxExemptCap - roundedOtherBenefits).clamp(
      0.0,
      taxExemptCap,
    ).toDouble();
    final taxExempt = _roundMoney(
      gross.clamp(0.0, remainingExemption).toDouble(),
    );
    final taxableExcess = _roundMoney(gross - taxExempt);

    return ThirteenthMonthResult(
      gross: gross,
      otherBenefits: roundedOtherBenefits,
      totalBenefits: totalBenefits,
      taxExempt: taxExempt,
      taxableExcess: taxableExcess,
      monthlyBreakdown: List<ThirteenthMonthBreakdown>.generate(
        monthCount,
        (index) => ThirteenthMonthBreakdown(
          month: index + 1,
          basicSalary: _roundMoney(salaries[index]),
          thirteenthMonthShare: _roundMoney(salaries[index] / monthCount),
        ),
        growable: false,
      ),
    );
  }

  static double _roundMoney(double amount) => (amount * 100).round() / 100;
}
