import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/financial_entry.dart';
import '../providers/budget_provider.dart';
import '../providers/currency_provider.dart';
import '../providers/wallet_cards_provider.dart';
import '../providers/wallet_cash_provider.dart';
import 'app_refresh_indicator.dart';
import 'budget_modal.dart';
import 'entry_title_with_icon.dart';
import 'rate_limit_dialog.dart';
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
  bool _showOlderEntries = false;

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
    final currency = context.watch<CurrencyProvider>();
    final percentage = switch (category) {
      FinancialCategory.bills => budget.billsPercentage,
      FinancialCategory.savings => budget.savingsPercentage,
      FinancialCategory.personal => budget.personalPercentage,
    };
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Keep today + yesterday visible; hide anything 2+ days old until "View more".
    final recentCutoff = today.subtract(const Duration(days: 1));
    final recentEntries = <FinancialEntry>[];
    final olderEntries = <FinancialEntry>[];
    for (final entry in entries) {
      final local = entry.createdAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (day.isBefore(recentCutoff)) {
        olderEntries.add(entry);
      } else {
        recentEntries.add(entry);
      }
    }
    final visibleEntries =
        _showOlderEntries ? [...recentEntries, ...olderEntries] : recentEntries;

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
                                      currency.formatAmount(allocatedBalance),
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
                          : visibleEntries.isEmpty && !_showOlderEntries
                          ? Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 28,
                                  ),
                                  child: Text(
                                    'No recent transactions',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                if (olderEntries.isNotEmpty)
                                  _ViewMoreButton(
                                    onPressed: () {
                                      setState(() => _showOlderEntries = true);
                                    },
                                  ),
                              ],
                            )
                          : Column(
                              children: [
                                _buildGroupedHistory(context, visibleEntries),
                                if (olderEntries.isNotEmpty &&
                                    !_showOlderEntries) ...[
                                  const SizedBox(height: 22),
                                  _ViewMoreButton(
                                    onPressed: () {
                                      setState(() => _showOlderEntries = true);
                                    },
                                  ),
                                ],
                              ],
                            ),
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
              onRefund: groupedDays[groupIndex].value[entryIndex].isRefund
                  ? null
                  : () => _refundOrDelete(
                      context,
                      groupedDays[groupIndex].value[entryIndex],
                      refund: true,
                    ),
              onDelete: () => _refundOrDelete(
                context,
                groupedDays[groupIndex].value[entryIndex],
                refund: false,
              ),
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
    final walletCash = context.read<WalletCashProvider>();
    final walletCards = context.read<WalletCardsProvider>();
    final availableBalance =
        provider.remainingFor(widget.category) + (entry?.amount ?? 0);

    await BudgetModal.show(
      context: context,
      category: widget.category,
      title: 'Use ${widget.title}',
      availableBalance: availableBalance,
      initialEntry: entry,
      onSave: (name, amount, iconAsset, source) async {
        if (entry == null) {
          await provider.addEntry(
            widget.category,
            title: name,
            amount: amount,
            iconAsset: iconAsset,
          );
          // Deduct the spent amount from the chosen wallet or card.
          if (source != null) {
            if (source.isWallet) {
              await walletCash.setAmount(walletCash.amount - amount);
            } else if (source.cardId != null) {
              final card = walletCards.cardById(source.cardId!);
              if (card != null) {
                await walletCards.setCardAmount(
                  cardId: card.id,
                  amount: card.amount - amount,
                );
              }
            }
          }
        } else {
          await provider.updateEntry(
            widget.category,
            entry.copyWith(
              title: name,
              amount: amount,
              iconAsset: iconAsset,
              clearIconAsset: iconAsset == null || iconAsset.isEmpty,
            ),
          );
        }
      },
    );
  }

  Future<bool> _refundOrDelete(
    BuildContext context,
    FinancialEntry entry, {
    required bool refund,
  }) async {
    final amountLabel = NumberFormat('#,##0.##').format(entry.amount);
    final symbol = context.read<CurrencyProvider>().symbol;
    final authorized = await showSensitiveActionAuth(
      context: context,
      title: refund ? 'Confirm refund' : 'Confirm delete',
      description: refund
          ? 'Enter your PIN or use fingerprint to refund $symbol$amountLabel '
                'back to ${widget.title}.'
          : 'Enter your PIN or use fingerprint to delete "${entry.title}". '
                'This will not return the money.',
    );
    if (!authorized || !context.mounted) return false;

    try {
      await context.read<BudgetProvider>().deleteEntry(
        widget.category,
        entry,
        refund: refund,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                refund
                    ? '$symbol$amountLabel returned to ${widget.title}.'
                    : '"${entry.title}" deleted.',
              ),
            ),
          );
      }
      return true;
    } catch (error) {
      if (isFinanceRateLimitError(error)) return false;
      if (context.mounted) _showError(context);
      return false;
    }
  }

  void _showError(BuildContext context) {
    final budget = context.read<BudgetProvider>();
    if (budget.pendingRateLimit != null) return;
    final message = budget.errorMessage ?? 'The change could not be saved.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ViewMoreButton extends StatelessWidget {
  const _ViewMoreButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        child: const Text(
          'View more',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatefulWidget {
  const _EntryRow({
    required this.entry,
    required this.onRefund,
    required this.onDelete,
  });

  final FinancialEntry entry;
  final Future<bool> Function()? onRefund;
  final Future<bool> Function() onDelete;

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  static const _decreaseColor = Color(0xFFFF5252);
  static const _refundColor = Color(0xFF5CB450);
  static const _actionsWidth = 168.0;
  double _dragExtent = 0;
  bool _busy = false;

  double get _panelWidth =>
      widget.onRefund == null ? _actionsWidth / 2 : _actionsWidth;

  void _close() {
    if (_dragExtent == 0) return;
    setState(() => _dragExtent = 0);
  }

  Future<void> _runAction(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final done = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (done) {
        _dragExtent = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isRefund = widget.entry.isRefund;
    final symbol = context.watch<CurrencyProvider>().symbol;
    final amountLabel =
        '${isRefund ? '+' : '-'}$symbol${NumberFormat('#,##0.##').format(widget.entry.amount)}';
    final panelWidth = _panelWidth;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Actions stay behind the row until the user swipes.
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onRefund != null)
                    _SlideAction(
                      width: _actionsWidth / 2,
                      color: _refundColor,
                      icon: Icons.replay_rounded,
                      label: 'Refund',
                      onTap: _busy
                          ? null
                          : () => _runAction(widget.onRefund!),
                    ),
                  _SlideAction(
                    width: _actionsWidth / 2,
                    color: const Color(0xFFE11D48),
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                    onTap: _busy ? null : () => _runAction(widget.onDelete),
                  ),
                ],
              ),
            ),
            // Full-width cover so amounts never sit on top of the action colors.
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                if (_busy) return;
                setState(() {
                  _dragExtent = (_dragExtent + details.delta.dx).clamp(
                    -panelWidth,
                    0.0,
                  );
                });
              },
              onHorizontalDragEnd: (details) {
                if (_busy) return;
                final velocity = details.primaryVelocity ?? 0;
                setState(() {
                  if (velocity < -400 || _dragExtent < -panelWidth / 2) {
                    _dragExtent = -panelWidth;
                  } else {
                    _dragExtent = 0;
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(_dragExtent, 0, 0),
                width: double.infinity,
                height: double.infinity,
                color: const Color(0xFF161616),
                alignment: Alignment.centerLeft,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _dragExtent < 0 ? _close : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: EntryTitleWithIcon(
                              title: widget.entry.title,
                              iconAsset: widget.entry.iconAsset,
                              titleStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            amountLabel,
                            style: TextStyle(
                              color: isRefund ? _refundColor : _decreaseColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideAction extends StatelessWidget {
  const _SlideAction({
    required this.width,
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final double width;
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
