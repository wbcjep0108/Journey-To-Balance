import 'package:flutter/material.dart';

import '../models/financial_entry.dart';

/// Quick-select option shown in the spend modal (icon + label).
class SpendCategoryOption {
  const SpendCategoryOption({
    required this.label,
    required this.assetPath,
    this.materialIcon,
  });

  final String label;

  /// A Material-icon sentinel. Legacy PNG paths remain supported for saved data.
  final String assetPath;

  /// When set, UI renders this Material icon instead of a PNG.
  final IconData? materialIcon;

  static const materialOthers = 'material:more_horiz';

  bool get usesMaterialIcon =>
      materialIcon != null || isMaterialAsset(assetPath) || _legacyPaths.contains(assetPath);

  static bool isMaterialAsset(String? path) =>
      path != null && path.startsWith('material:');

  static bool usesMaterialIconForAsset(String path) =>
      isMaterialAsset(path) || _legacyPaths.contains(path);

  static IconData materialIconForAsset(String path) {
    switch (path) {
      case 'material:electric_bolt':
      case 'assets/images/icons_bills/electricity.png':
        return Icons.electric_bolt_outlined;
      case 'material:restaurant':
      case 'assets/images/icons_bills/food.png':
      case 'assets/images/icons_personal/restaurant.png':
        return Icons.restaurant_outlined;
      case 'material:router':
      case 'assets/images/icons_bills/internet.png':
        return Icons.router_outlined;
      case 'material:account_balance':
      case 'assets/images/icons_bills/loan.png':
        return Icons.account_balance_outlined;
      case 'material:medication':
      case 'assets/images/icons_bills/medicine.png':
        return Icons.medication_outlined;
      case 'material:home':
      case 'assets/images/icons_bills/rent.png':
        return Icons.home_outlined;
      case 'material:directions_bus':
      case 'assets/images/icons_bills/transpo.png':
        return Icons.directions_bus_outlined;
      case 'material:water_drop':
      case 'assets/images/icons_bills/water.png':
        return Icons.water_drop_outlined;
      case 'material:checkroom':
      case 'assets/images/icons_personal/clothes.png':
        return Icons.checkroom_outlined;
      case 'material:coffee':
      case 'assets/images/icons_personal/coffee.png':
        return Icons.coffee_outlined;
      case 'material:theaters':
      case 'assets/images/icons_personal/entertainment.png':
        return Icons.theaters_outlined;
      case 'material:card_giftcard':
      case 'assets/images/icons_personal/gift.png':
        return Icons.card_giftcard_outlined;
      case 'material:shopping_bag':
      case 'assets/images/icons_personal/shopping.png':
        return Icons.shopping_bag_outlined;
      case 'material:savings':
      case 'assets/images/icons_savings/emergency fund.png':
        return Icons.savings_outlined;
      case 'material:receipt_long':
        return Icons.receipt_long_outlined;
      case 'material:person':
        return Icons.person_outline;
      case materialOthers:
        return Icons.more_horiz;
      default:
        return Icons.more_horiz;
    }
  }

  static const _legacyPaths = {
    'assets/images/icons_bills/electricity.png',
    'assets/images/icons_bills/food.png',
    'assets/images/icons_bills/internet.png',
    'assets/images/icons_bills/loan.png',
    'assets/images/icons_bills/medicine.png',
    'assets/images/icons_bills/rent.png',
    'assets/images/icons_bills/transpo.png',
    'assets/images/icons_bills/water.png',
    'assets/images/icons_bills/others.png',
    'assets/images/icons_personal/clothes.png',
    'assets/images/icons_personal/coffee.png',
    'assets/images/icons_personal/entertainment.png',
    'assets/images/icons_personal/gift.png',
    'assets/images/icons_personal/restaurant.png',
    'assets/images/icons_personal/shopping.png',
    'assets/images/icons_personal/others.png',
    'assets/images/icons_savings/emergency fund.png',
  };
}

/// Preset chips per financial category, bound to on-disk icon folders.
class SpendCategoryPresets {
  const SpendCategoryPresets._();

  static const billsAssetDir = 'assets/images/icons_bills';
  static const personalAssetDir = 'assets/images/icons_personal';
  static const savingsAssetDir = 'assets/images/icons_savings';

  /// Icon shown when a legacy or system-created transaction has no saved
  /// quick-select icon. This keeps every transaction visually identifiable.
  static String defaultIconAsset(FinancialCategory category) {
    return switch (category) {
      FinancialCategory.bills => 'material:receipt_long',
      FinancialCategory.savings => 'material:savings',
      FinancialCategory.personal => 'material:person',
    };
  }

  static String iconAssetOrDefault(
    FinancialCategory category,
    String? iconAsset,
  ) {
    final trimmed = iconAsset?.trim();
    return trimmed == null || trimmed.isEmpty
        ? defaultIconAsset(category)
        : trimmed;
  }

  static String labelForAsset(
    FinancialCategory category,
    String assetPath,
  ) {
    for (final option in forCategory(category)) {
      if (option.assetPath == assetPath) return option.label;
    }
    for (final otherCategory in FinancialCategory.values) {
      for (final option in forCategory(otherCategory)) {
        if (option.assetPath == assetPath) return option.label;
      }
    }
    final legacyLabel = switch (assetPath) {
      'assets/images/icons_bills/electricity.png' => 'Electricity',
      'assets/images/icons_bills/food.png' => 'Food',
      'assets/images/icons_bills/internet.png' => 'Internet',
      'assets/images/icons_bills/loan.png' => 'Loan',
      'assets/images/icons_bills/medicine.png' => 'Medicine',
      'assets/images/icons_bills/rent.png' => 'Rent',
      'assets/images/icons_bills/transpo.png' => 'Transpo',
      'assets/images/icons_bills/water.png' => 'Water',
      'assets/images/icons_personal/clothes.png' => 'Clothes',
      'assets/images/icons_personal/coffee.png' => 'Coffee',
      'assets/images/icons_personal/entertainment.png' => 'Entertainment',
      'assets/images/icons_personal/gift.png' => 'Gift',
      'assets/images/icons_personal/restaurant.png' => 'Restaurant',
      'assets/images/icons_personal/shopping.png' => 'Shopping',
      'assets/images/icons_savings/emergency fund.png' => 'Emergency Fund',
      'assets/images/icons_bills/others.png' ||
      'assets/images/icons_personal/others.png' => 'Others',
      _ => null,
    };
    if (legacyLabel != null) return legacyLabel;
    return switch (category) {
      FinancialCategory.bills => 'Bills',
      FinancialCategory.savings => 'Savings',
      FinancialCategory.personal => 'Personal',
    };
  }

  static List<SpendCategoryOption> forCategory(FinancialCategory category) {
    switch (category) {
      case FinancialCategory.bills:
        return const [
          SpendCategoryOption(
            label: 'Electricity',
            assetPath: 'material:electric_bolt',
          ),
          SpendCategoryOption(
            label: 'Food',
            assetPath: 'material:restaurant',
          ),
          SpendCategoryOption(
            label: 'Internet',
            assetPath: 'material:router',
          ),
          SpendCategoryOption(
            label: 'Loan',
            assetPath: 'material:account_balance',
          ),
          SpendCategoryOption(
            label: 'Medicine',
            assetPath: 'material:medication',
          ),
          SpendCategoryOption(
            label: 'Rent',
            assetPath: 'material:home',
          ),
          SpendCategoryOption(
            label: 'Transpo',
            assetPath: 'material:directions_bus',
          ),
          SpendCategoryOption(
            label: 'Water',
            assetPath: 'material:water_drop',
          ),
          SpendCategoryOption(
            label: 'Others',
            assetPath: SpendCategoryOption.materialOthers,
          ),
        ];
      case FinancialCategory.personal:
        return const [
          SpendCategoryOption(
            label: 'Clothes',
            assetPath: 'material:checkroom',
          ),
          SpendCategoryOption(
            label: 'Coffee',
            assetPath: 'material:coffee',
          ),
          SpendCategoryOption(
            label: 'Entertainment',
            assetPath: 'material:theaters',
          ),
          SpendCategoryOption(
            label: 'Gift',
            assetPath: 'material:card_giftcard',
          ),
          SpendCategoryOption(
            label: 'Restaurant',
            assetPath: 'material:restaurant',
          ),
          SpendCategoryOption(
            label: 'Shopping',
            assetPath: 'material:shopping_bag',
          ),
          SpendCategoryOption(
            label: 'Others',
            assetPath: SpendCategoryOption.materialOthers,
          ),
        ];
      case FinancialCategory.savings:
        return const [
          SpendCategoryOption(
            label: 'Emergency Fund',
            assetPath: 'material:savings',
          ),
        ];
    }
  }
}
