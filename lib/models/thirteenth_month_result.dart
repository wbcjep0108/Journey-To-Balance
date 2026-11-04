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
    required this.taxableExcess,
    required this.monthlyBreakdown,
  });

  final double gross;
  final double otherBenefits;
  final double totalBenefits;
  final double taxExempt;
  final double taxableExcess;
  final List<ThirteenthMonthBreakdown> monthlyBreakdown;
}
