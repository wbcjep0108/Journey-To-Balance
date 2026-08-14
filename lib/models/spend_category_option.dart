import '../models/financial_entry.dart';

/// Quick-select option shown in the spend modal (icon + label).
class SpendCategoryOption {
  const SpendCategoryOption({
    required this.label,
    required this.assetPath,
  });

  final String label;
  final String assetPath;
}

/// Preset chips per financial category, bound to on-disk icon folders.
class SpendCategoryPresets {
  const SpendCategoryPresets._();

  static const billsAssetDir = 'assets/images/icons_bills';
  static const personalAssetDir = 'assets/images/icons_personal';
  static const savingsAssetDir = 'assets/images/icons_savings';

  static List<SpendCategoryOption> forCategory(FinancialCategory category) {
    switch (category) {
      case FinancialCategory.bills:
        return const [
          SpendCategoryOption(
            label: 'Electricity',
            assetPath: '$billsAssetDir/electricity.png',
          ),
          SpendCategoryOption(
            label: 'Food',
            assetPath: '$billsAssetDir/food.png',
          ),
          SpendCategoryOption(
            label: 'Internet',
            assetPath: '$billsAssetDir/internet.png',
          ),
          SpendCategoryOption(
            label: 'Loan',
            assetPath: '$billsAssetDir/loan.png',
          ),
          SpendCategoryOption(
            label: 'Medicine',
            assetPath: '$billsAssetDir/medicine.png',
          ),
          SpendCategoryOption(
            label: 'Rent',
            assetPath: '$billsAssetDir/rent.png',
          ),
          SpendCategoryOption(
            label: 'Transpo',
            assetPath: '$billsAssetDir/transpo.png',
          ),
          SpendCategoryOption(
            label: 'Water',
            assetPath: '$billsAssetDir/water.png',
          ),
        ];
      case FinancialCategory.personal:
        return const [
          SpendCategoryOption(
            label: 'Clothes',
            assetPath: '$personalAssetDir/clothes.png',
          ),
          SpendCategoryOption(
            label: 'Coffee',
            assetPath: '$personalAssetDir/coffee.png',
          ),
          SpendCategoryOption(
            label: 'Entertainment',
            assetPath: '$personalAssetDir/entertainment.png',
          ),
          SpendCategoryOption(
            label: 'Gift',
            assetPath: '$personalAssetDir/gift.png',
          ),
          SpendCategoryOption(
            label: 'Restaurant',
            assetPath: '$personalAssetDir/restaurant.png',
          ),
          SpendCategoryOption(
            label: 'Shopping',
            assetPath: '$personalAssetDir/shopping.png',
          ),
        ];
      case FinancialCategory.savings:
        return const [
          SpendCategoryOption(
            label: 'Emergency Fund',
            assetPath: '$savingsAssetDir/emergency fund.png',
          ),
        ];
    }
  }
}
