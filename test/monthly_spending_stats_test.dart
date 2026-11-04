import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/financial_entry.dart';
import 'package:just_budget/models/monthly_spending_stats.dart';

void main() {
  test(
    'bounded month results include totals beyond the first history page',
    () {
      final entries = <FinancialCategory, List<FinancialEntry>>{
        FinancialCategory.bills: [
          for (var index = 0; index < 60; index++)
            FinancialEntry(
              id: 'bill-$index',
              title: 'Bill',
              amount: 10,
              createdAt: DateTime(2026, 10, 1 + (index % 28)),
            ),
        ],
        FinancialCategory.savings: const [],
        FinancialCategory.personal: const [],
      };

      final stats = MonthlySpendingStats.fromEntries(
        entries: entries,
        month: DateTime(2026, 10),
      );

      expect(stats.total, 600);
    },
  );
}
