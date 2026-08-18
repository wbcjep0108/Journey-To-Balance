import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/financial_entry.dart';
import '../../providers/budget_provider.dart';
import '../../providers/currency_provider.dart';
import '../../widgets/category_icon_badge.dart';
import '../../widgets/rate_limit_dialog.dart';
import '../../widgets/sensitive_action_auth.dart';

class DailySpendingPage extends StatelessWidget {
  const DailySpendingPage({super.key, required this.day});

  final DateTime day;

  static String categoryLabel(FinancialCategory category) {
    return switch (category) {
      FinancialCategory.bills => 'Bills',
      FinancialCategory.savings => 'Savings',
      FinancialCategory.personal => 'Personal',
    };
  }

  @override
  Widget build(BuildContext context) {
    final budget = context.watch<BudgetProvider>();
    final currency = context.watch<CurrencyProvider>();
    final target = DateTime(day.year, day.month, day.day);
    final transactions = budget.entriesForDay(target);
    final total = transactions.fold<double>(
      0,
      (sum, item) => sum + item.entry.amount,
    );
    final dateLabel = DateFormat('EEEE, MMMM d, yyyy').format(target);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text(
          'Day Spending',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A1A1A), Color(0xFF4A4A4A)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLabel,
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    currency.formatAmount(total),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${transactions.length} transaction${transactions.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF161616),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Transactions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (transactions.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 42),
                        child: Text(
                          'No spending recorded this day.',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < transactions.length; i++) ...[
                      _DayEntryRow(
                        item: transactions[i],
                        onDelete: () => _delete(context, transactions[i]),
                      ),
                      if (i < transactions.length - 1)
                        Divider(
                          color: Colors.white.withValues(alpha: 0.1),
                          height: 28,
                        ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _delete(BuildContext context, DayTransaction item) async {
    final authorized = await showSensitiveActionAuth(
      context: context,
      title: 'Confirm delete',
      description:
          'Enter your PIN or use fingerprint to delete "${item.entry.title}".',
    );
    if (!authorized || !context.mounted) return false;

    try {
      await context.read<BudgetProvider>().deleteEntry(
        item.category,
        item.entry,
      );
      return true;
    } catch (error) {
      if (isFinanceRateLimitError(error)) return false;
      if (!context.mounted) return false;
      final budget = context.read<BudgetProvider>();
      if (budget.pendingRateLimit != null) return false;
      final message =
          budget.errorMessage ?? 'The change could not be saved.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return false;
    }
  }
}

class _DayEntryRow extends StatelessWidget {
  const _DayEntryRow({
    required this.item,
    required this.onDelete,
  });

  final DayTransaction item;
  final Future<bool> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('${item.category.name}_${item.entry.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFE11D48),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
            SizedBox(width: 8),
            Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            if (item.entry.iconAsset != null &&
                item.entry.iconAsset!.isNotEmpty) ...[
              CategoryIconBadge(
                iconAsset: item.entry.iconAsset!,
                size: 34,
                showBorder: false,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DailySpendingPage.categoryLabel(item.category),
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${item.entry.isRefund ? '+' : '-'}${context.watch<CurrencyProvider>().symbol}${NumberFormat('#,##0.##').format(item.entry.amount)}',
              style: TextStyle(
                color: item.entry.isRefund
                    ? const Color(0xFF5CB450)
                    : const Color(0xFFFF5252),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
