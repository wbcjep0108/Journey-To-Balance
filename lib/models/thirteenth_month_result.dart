class ThirteenthMonthBreakdown {
  const ThirteenthMonthBreakdown({
    required this.month,
    required this.basicSalary,
    required this.thirteenthMonthShare,
  });

  final int month;
  final double basicSalary;
  final double thirteenthMonthShare;
}

class ThirteenthMonthResult {
  const ThirteenthMonthResult({
    required this.gross,
    required this.otherBenefits,
    required this.totalBenefits,
    required this.taxExempt,
    required this.totalTaxExempt,
    required this.taxableExcess,
    required this.annualBasicSalary,
    required this.additionalIncomeTax,
    required this.takeHome,
    required this.monthlyBreakdown,
  });

  final double gross;
  final double otherBenefits;
  final double totalBenefits;
  /// Tax-exempt part of the 13th month pay alone.
  final double taxExempt;

  /// Tax-exempt part of 13th month pay plus other benefits (up to the cap).
  final double totalTaxExempt;
  final double taxableExcess;

  /// Sum of the entered monthly basic salaries, used as the annual tax base.
  final double annualBasicSalary;

  /// Extra annual income tax caused by the taxable excess, from the
  /// graduated brackets (not a flat rate).
  final double additionalIncomeTax;

  /// Total combined benefits minus [additionalIncomeTax].
  final double takeHome;
  final List<ThirteenthMonthBreakdown> monthlyBreakdown;
}
