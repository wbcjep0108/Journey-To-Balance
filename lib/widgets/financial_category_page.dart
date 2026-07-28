import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/financial_entry.dart';
import '../providers/budget_provider.dart';

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
    final budget = context.watch<BudgetProvider>();
    final entries = budget.entriesFor(category);
    final allocation = switch (category) {
      FinancialCategory.bills => budget.billsAmount,
      FinancialCategory.savings => budget.savingsAmount,
      FinancialCategory.personal => budget.personalAmount,
    };
    final usedAmount = entries.fold<double>(
      0,
      (total, entry) => total + entry.amount,
    );
    final remainingBalance = allocation - usedAmount;
    final percentage = switch (category) {
      FinancialCategory.bills => budget.billsPercentage,
      FinancialCategory.savings => budget.savingsPercentage,
      FinancialCategory.personal => budget.personalPercentage,
    };

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
              Expanded(
                child: Container(
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
                      Expanded(
                        child: entries.isEmpty
                            ? Center(
                                child: Text(
                                  'No entries yet',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 15,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                physics: const BouncingScrollPhysics(),
                                itemCount: entries.length,
                                separatorBuilder: (_, _) => Divider(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  height: 28,
                                ),
                                itemBuilder: (context, index) {
                                  final entry = entries[index];
                                  return _EntryRow(
                                    entry: entry,
                                    category: category,
                                    onEdit: () => _openEditor(context, entry),
                                    onDelete: () => _delete(context, entry),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context, [
    FinancialEntry? entry,
  ]) async {
    final result = await showDialog<_EntryFormResult>(
      context: context,
      builder: (_) => _EntryDialog(title: title, entry: entry),
    );
    if (result == null || !context.mounted) return;

    try {
      final provider = context.read<BudgetProvider>();
      if (entry == null) {
        await provider.addEntry(
          category,
          title: result.title,
          amount: result.amount,
        );
      } else {
        await provider.updateEntry(
          category,
          entry.copyWith(title: result.title, amount: result.amount),
        );
      }
    } catch (_) {
      if (context.mounted) _showError(context);
    }
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
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  final FinancialEntry entry;
  final FinancialCategory category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final sign = category == FinancialCategory.savings ? '+' : '-';
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
          '$sign${NumberFormat('#,##0.##').format(entry.amount)}php',
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

class _EntryDialog extends StatefulWidget {
  const _EntryDialog({required this.title, this.entry});

  final String title;
  final FinancialEntry? entry;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.entry?.title ?? '');
    _amountController = TextEditingController(
      text: widget.entry?.amount.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());
    if (title.isEmpty || amount == null || amount <= 0) {
      setState(() => _error = 'Enter a name and an amount greater than zero.');
      return;
    }
    Navigator.pop(context, _EntryFormResult(title: title, amount: amount));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.entry == null ? 'Add' : 'Edit'} ${widget.title}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: '₱ ',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _EntryFormResult {
  const _EntryFormResult({required this.title, required this.amount});

  final String title;
  final double amount;
}
