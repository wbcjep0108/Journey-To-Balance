import 'package:flutter/material.dart';

import '../../models/financial_entry.dart';
import '../../widgets/financial_category_page.dart';

class PersonalPage extends StatelessWidget {
  const PersonalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FinancialCategoryPage(
      category: FinancialCategory.personal,
      title: 'Personal',
      sectionTitle: 'Recent Personal Expenses',
      iconPath: 'assets/images/icons/personal.png',
    );
  }
}
