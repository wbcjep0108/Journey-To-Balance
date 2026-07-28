import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/budget_provider.dart';

class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    super.key,
    required this.child,
    this.edgeOffset = 0,
  });

  final Widget child;
  final double edgeOffset;

  Future<void> _refresh(BuildContext context) async {
    try {
      await context.read<BudgetProvider>().refreshAllData();
    } catch (_) {
      if (!context.mounted) return;
      final message =
          context.read<BudgetProvider>().errorMessage ??
          'Unable to refresh. Please try again.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: Colors.black,
      backgroundColor: Colors.white,
      displacement: 48,
      edgeOffset: edgeOffset,
      strokeWidth: 2.6,
      semanticsLabel: 'Refresh financial data',
      semanticsValue: 'Pull down to retrieve the latest saved data',
      onRefresh: () => _refresh(context),
      child: child,
    );
  }
}
