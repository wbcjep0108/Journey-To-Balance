import 'package:flutter/material.dart';

import '../../models/financial_entry.dart';
import '../../widgets/financial_category_page.dart';

class SavingsPage extends StatelessWidget {
  const SavingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FinancialCategoryPage(
      category: FinancialCategory.savings,
      title: 'Savings',
      sectionTitle: 'Recent Savings',
      icon: Icons.savings_outlined,
    );
  }
}
