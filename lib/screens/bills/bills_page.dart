import 'package:flutter/material.dart';

import '../../models/financial_entry.dart';
import '../../widgets/financial_category_page.dart';

class BillsPage extends StatelessWidget {
  const BillsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FinancialCategoryPage(
      category: FinancialCategory.bills,
      title: 'Bills',
      sectionTitle: 'Recent Bills',
      iconPath: 'assets/images/icons/bills.png',
    );
  }
}
