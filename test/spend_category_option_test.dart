import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/financial_entry.dart';
import 'package:just_budget/models/spend_category_option.dart';

void main() {
  test('uses a category default when a synced transaction has no icon', () {
    expect(
      SpendCategoryPresets.iconAssetOrDefault(FinancialCategory.bills, null),
      'material:receipt_long',
    );
    expect(
      SpendCategoryPresets.iconAssetOrDefault(FinancialCategory.personal, '  '),
      'material:person',
    );
  });

  test('preserves and trims a synced transaction icon', () {
    expect(
      SpendCategoryPresets.iconAssetOrDefault(
        FinancialCategory.savings,
        ' material:savings ',
      ),
      'material:savings',
    );
  });
}
