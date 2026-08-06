import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/financial_entry.dart';
import '../providers/budget_provider.dart';
import 'app_refresh_indicator.dart';
import 'budget_modal.dart';
import 'sensitive_action_auth.dart';

class FinancialCategoryPage extends StatefulWidget {
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
  State<FinancialCategoryPage> createState() => _FinancialCategoryPageState();
}

class _FinancialCategoryPageState extends State<FinancialCategoryPage> {
  BudgetProvider? _budget;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final budget = context.read<BudgetProvider>();
    if (!identical(_budget, budget)) {
      _budget?.removeListener(_onBudgetChanged);
      _budget = budget;
      _budget?.addListener(_onBudgetChanged);
    }
  }

  @override
  void dispose() {
    _budget?.removeListener(_onBudgetChanged);
    super.dispose();
  }

  void _onBudgetChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final budget = _budget ?? context.watch<BudgetProvider>();
    return _buildContent(context, budget);
  }

  Widget _buildContent(BuildContext context, BudgetProvider budget) {
    final category = widget.category;
    final title = widget.title;
    final sectionTitle = widget.sectionTitle;
    final iconPath = widget.iconPath;
    final entries = budget.entriesFor(category);
    final allocatedBalance = budget.allocationFor(category);
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
                                      '${NumberFormat('#,##0.##').format(allocatedBalance)}php',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 40,
                                        fontWeight: FontWeight.w800,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${percentage.toStringAsFixed(0)}% of Available Balance',
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 13,
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
        provider.remainingFor(widget.category) + (entry?.amount ?? 0);

    await BudgetModal.show(
      context: context,
      category: widget.category,
      title: 'Use ${widget.title}',
      availableBalance: availableBalance,
      initialEntry: entry,
      onSave: (name, amount) async {
        if (entry == null) {
          await provider.addEntry(
            widget.category,
            title: name,
            amount: amount,
          );
        } else {
          await provider.updateEntry(
            widget.category,
            entry.copyWith(title: name, amount: amount),
          );
        }
      },
    );
  }

  Future<bool> _delete(BuildContext context, FinancialEntry entry) async {
    final authorized = await showSensitiveActionAuth(
      context: context,
      title: 'Confirm delete',
      description:
          'Enter your PIN or use fingerprint to delete "${entry.title}".',
    );
    if (!authorized || !context.mounted) return false;

    try {
      await context.read<BudgetProvider>().deleteEntry(
        widget.category,
        entry,
      );
      return true;
    } catch (_) {
      if (context.mounted) _showError(context);
      return false;
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
  final Future<bool> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(entry.id),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
