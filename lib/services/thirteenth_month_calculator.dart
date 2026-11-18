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
    final totalTaxExempt = _roundMoney(
      taxExempt + roundedOtherBenefits.clamp(0.0, taxExemptCap).toDouble(),
    );

    // The extra tax is the difference between the annual tax with and without
    // the taxable excess, so it follows the graduated brackets instead of a
    // flat rate. The annual basic salary is the base the excess stacks on.
    final annualBasicSalary = _roundMoney(totalBasicSalary);
    final additionalIncomeTax = _roundMoney(
      annualIncomeTax(annualBasicSalary + taxableExcess) -
          annualIncomeTax(annualBasicSalary),
    );
    final takeHome = _roundMoney(totalBenefits - additionalIncomeTax);

    return ThirteenthMonthResult(
      gross: gross,
      otherBenefits: roundedOtherBenefits,
      totalBenefits: totalBenefits,
      taxExempt: taxExempt,
      totalTaxExempt: totalTaxExempt,
      taxableExcess: taxableExcess,
      annualBasicSalary: annualBasicSalary,
      additionalIncomeTax: additionalIncomeTax,
      takeHome: takeHome,
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

  /// Graduated annual income tax brackets for individuals (TRAIN law, in
  /// effect from 2023): lower bound, base tax at that bound, marginal rate.
  static const List<({double from, double baseTax, double rate})>
  _taxBrackets = [
    (from: 0, baseTax: 0, rate: 0),
    (from: 250000, baseTax: 0, rate: 0.15),
    (from: 400000, baseTax: 22500, rate: 0.20),
    (from: 800000, baseTax: 102500, rate: 0.25),
    (from: 2000000, baseTax: 402500, rate: 0.30),
    (from: 8000000, baseTax: 2202500, rate: 0.35),
  ];

  /// Annual income tax on [annualTaxableIncome] using the graduated brackets.
  static double annualIncomeTax(double annualTaxableIncome) {
    if (annualTaxableIncome <= 0 || !annualTaxableIncome.isFinite) return 0;
    var bracket = _taxBrackets.first;
    for (final candidate in _taxBrackets) {
      if (annualTaxableIncome > candidate.from) bracket = candidate;
    }
    return bracket.baseTax +
        (annualTaxableIncome - bracket.from) * bracket.rate;
  }

  static double _roundMoney(double amount) => (amount * 100).round() / 100;
}
