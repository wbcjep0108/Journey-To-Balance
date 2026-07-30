import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/financial_entry.dart';
import '../providers/budget_provider.dart';
import 'app_refresh_indicator.dart';
import 'budget_modal.dart';

class FinancialCategoryPage extends StatelessWidget {
  const FinancialCategoryPage({
    super.key,
    required this.category,
    required this.title,
    required this.sectionTitle,
    required this.iconPath,
  });

  final FinancialCategory category;
  final String title;
  final String sectionTitle;
  final String iconPath;

  @override
  Widget build(BuildContext context) {
    final budget = context.read<BudgetProvider>();
    return ListenableBuilder(
      listenable: budget,
      builder: (context, _) => _buildContent(context, budget),
    );
  }

  Widget _buildContent(BuildContext context, BudgetProvider budget) {
    final entries = budget.entriesFor(category);
    final remainingBalance = budget.remainingFor(category);
    final percentage = switch (category) {
      FinancialCategory.bills => budget.billsPercentage,
      FinancialCategory.savings => budget.savingsPercentage,
      FinancialCategory.personal => budget.personalPercentage,
    };

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: AppRefreshIndicator(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 108),
            child: Column(
              children: [
                Container(
                  height: 220,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1A1A1A), Color(0xFF4A4A4A)],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: 20,
                        top: 20,
                        child: Opacity(
                          opacity: 0.25,
                          child: Image.asset(
                            iconPath,
                            width: 140,
                            height: 140,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                              ),
                            ),
                            const Spacer(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${NumberFormat('#,##0.##').format(remainingBalance)}php',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 40,
                                        fontWeight: FontWeight.w800,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Remaining balance',
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${percentage.toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                IconButton.filledTonal(
                                  onPressed: () => _openEditor(context),
                                  icon: const Icon(Icons.add),
                                  color: Colors.white,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
                      Text(
                        sectionTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 20),
                      entries.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 42,
                                ),
                                child: Text(
                                  'No entries yet',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            )
                          : _buildGroupedHistory(context, entries),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupedHistory(
    BuildContext context,
    List<FinancialEntry> entries,
  ) {
    final sortedEntries = [...entries]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final groups = <DateTime, List<FinancialEntry>>{};

    for (final entry in sortedEntries) {
      final localDate = entry.createdAt.toLocal();
      final day = DateTime(localDate.year, localDate.month, localDate.day);
      groups.putIfAbsent(day, () => []).add(entry);
    }

    final groupedDays = groups.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (
          var groupIndex = 0;
          groupIndex < groupedDays.length;
          groupIndex++
        ) ...[
          if (groupIndex > 0) const SizedBox(height: 26),
          Text(
            DateFormat('MMMM d, yyyy').format(groupedDays[groupIndex].key),
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 14),
          for (
            var entryIndex = 0;
            entryIndex < groupedDays[groupIndex].value.length;
            entryIndex++
          ) ...[
            _EntryRow(
              entry: groupedDays[groupIndex].value[entryIndex],
              onEdit: () => _openEditor(
                context,
                groupedDays[groupIndex].value[entryIndex],
              ),
              onDelete: () =>
                  _delete(context, groupedDays[groupIndex].value[entryIndex]),
            ),
            if (entryIndex < groupedDays[groupIndex].value.length - 1)
              Divider(color: Colors.white.withValues(alpha: 0.1), height: 28),
          ],
        ],
      ],
    );
  }

  Future<void> _openEditor(
    BuildContext context, [
    FinancialEntry? entry,
  ]) async {
    final provider = context.read<BudgetProvider>();
    final availableBalance =
        provider.remainingFor(category) + (entry?.amount ?? 0);

    await BudgetModal.show(
      context: context,
      category: category,
      title: 'Use $title',
      availableBalance: availableBalance,
      initialEntry: entry,
      onSave: (name, amount) async {
        if (entry == null) {
          await provider.addEntry(category, title: name, amount: amount);
        } else {
          await provider.updateEntry(
            category,
            entry.copyWith(title: name, amount: amount),
          );
        }
      },
    );
  }

  Future<void> _delete(BuildContext context, FinancialEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text('Delete "${entry.title}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await context.read<BudgetProvider>().deleteEntry(category, entry);
    } catch (_) {
      if (context.mounted) _showError(context);
    }
  }

  void _showError(BuildContext context) {
    final message =
        context.read<BudgetProvider>().errorMessage ??
        'The change could not be saved.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final FinancialEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                entry.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        Text(
          '-₱${NumberFormat('#,##0.##').format(entry.amount)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        PopupMenuButton<String>(
          iconColor: Colors.white70,
          onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ],
    );
  }
}
