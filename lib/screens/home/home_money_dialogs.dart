import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/budget_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/wallet_cards_provider.dart';
import '../../providers/wallet_cash_provider.dart';
import '../../widgets/allocation_confirm_dialog.dart';
import '../../widgets/rate_limit_dialog.dart';
import '../../widgets/sensitive_action_auth.dart';

Widget homeDialogField({
  required String label,
  required TextEditingController controller,
  String? prefixText,
  String? suffixText,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF121212),
        ),
      ),
      const SizedBox(height: 8),
      RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF121212),
            ),
            decoration: InputDecoration(
              prefixText: prefixText,
              suffixText: suffixText,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 16,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ),
    ],
  );
}

class SalarySetupDialog extends StatefulWidget {
  const SalarySetupDialog({
    super.key,
    required this.hostContext,
    required this.onSaved,
  });

  final BuildContext hostContext;
  final VoidCallback onSaved;

  @override
  State<SalarySetupDialog> createState() => _SalarySetupDialogState();
}

class _SalarySetupDialogState extends State<SalarySetupDialog> {
  late final TextEditingController _salaryController;

  @override
  void initState() {
    super.initState();
    final budget = widget.hostContext.read<BudgetProvider>();
    _salaryController = TextEditingController(
      text: budget.monthlySalary.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _salaryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<CurrencyProvider>().symbol;
    return Dialog(
      insetAnimationDuration: Duration.zero,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.68,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Budget Setup',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF121212),
                ),
              ),
              const SizedBox(height: 24),
              homeDialogField(
                label: 'Monthly Salary/Income',
                controller: _salaryController,
                prefixText: '$symbol ',
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () async {
                      final monthlySalary =
                          double.tryParse(_salaryController.text) ?? -1;
                      if (monthlySalary < 0) {
                        ScaffoldMessenger.of(widget.hostContext).showSnackBar(
                          const SnackBar(
                            content: Text('Enter a valid monthly salary.'),
                          ),
                        );
                        return;
                      }

                      if (!widget.hostContext.mounted) return;
                      final authorized = await showSensitiveActionAuth(
                        context: widget.hostContext,
                        title: 'Confirm income change',
                        description:
                            'Enter your PIN or use fingerprint to update '
                            'your monthly salary or income.',
                      );
                      if (!widget.hostContext.mounted || authorized != true) {
                        return;
                      }

                      try {
                        await widget.hostContext
                            .read<BudgetProvider>()
                            .updateMonthlySalary(monthlySalary);
                        if (context.mounted) Navigator.pop(context);
                        widget.onSaved();
                      } catch (error) {
                        if (isFinanceRateLimitError(error)) return;
                        if (widget.hostContext.mounted) {
                          final budget =
                              widget.hostContext.read<BudgetProvider>();
                          ScaffoldMessenger.of(widget.hostContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                budget.errorMessage ??
                                    'Budget changes could not be saved.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        color: Color(0xFF121212),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BalanceEditDialog extends StatefulWidget {
  const BalanceEditDialog({
    super.key,
    required this.hostContext,
    required this.onSaved,
  });

  final BuildContext hostContext;
  final VoidCallback onSaved;

  @override
  State<BalanceEditDialog> createState() => _BalanceEditDialogState();
}

class _BalanceEditDialogState extends State<BalanceEditDialog> {
  late final TextEditingController _walletController;
  late final TextEditingController _billsController;
  late final TextEditingController _savingsController;
  late final TextEditingController _personalController;
  late final List<WalletCardModel> _cards;
  late final List<TextEditingController> _cardControllers;

  double _parseAmount(TextEditingController controller) {
    return double.tryParse(controller.text.replaceAll(',', '').trim()) ?? 0;
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final budget = widget.hostContext.read<BudgetProvider>();
    final cash = widget.hostContext.read<WalletCashProvider>().amount;
    _cards = widget.hostContext.read<WalletCardsProvider>().cards.toList();

    _walletController = TextEditingController(
      text: cash == 0 ? '' : cash.toStringAsFixed(0),
    );
    _cardControllers = [
      for (final card in _cards)
        TextEditingController(
          text: card.amount == 0 ? '' : card.amount.toStringAsFixed(0),
        ),
    ];
    _billsController = TextEditingController(
      text: budget.billsPercentage.toStringAsFixed(0),
    );
    _savingsController = TextEditingController(
      text: budget.savingsPercentage.toStringAsFixed(0),
    );
    _personalController = TextEditingController(
      text: budget.personalPercentage.toStringAsFixed(0),
    );

    _walletController.addListener(_onFieldChanged);
    for (final controller in _cardControllers) {
      controller.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    _walletController
      ..removeListener(_onFieldChanged)
      ..dispose();
    for (final controller in _cardControllers) {
      controller
        ..removeListener(_onFieldChanged)
        ..dispose();
    }
    _billsController.dispose();
    _savingsController.dispose();
    _personalController.dispose();
    super.dispose();
  }

  double get _previewTotal {
    var total = _parseAmount(_walletController);
    for (final controller in _cardControllers) {
      total += _parseAmount(controller);
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final budget = widget.hostContext.read<BudgetProvider>();
    final symbol = context.watch<CurrencyProvider>().symbol;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 40,
              spreadRadius: 2,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Edit available balance',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF121212),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Available balance is wallet cash plus your selected cards.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 18),
              homeDialogField(
                label: 'Wallet',
                controller: _walletController,
                prefixText: '$symbol ',
              ),
              for (var i = 0; i < _cards.length; i++) ...[
                const SizedBox(height: 14),
                homeDialogField(
                  label: _cards[i].bankLabel,
                  controller: _cardControllers[i],
                  prefixText: '$symbol ',
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Available balance: $symbol${_previewTotal.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF121212),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              homeDialogField(
                label: 'Bills %',
                controller: _billsController,
                suffixText: '%',
              ),
              const SizedBox(height: 14),
              homeDialogField(
                label: 'Savings %',
                controller: _savingsController,
                suffixText: '%',
              ),
              const SizedBox(height: 14),
              homeDialogField(
                label: 'Personal %',
                controller: _personalController,
                suffixText: '%',
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      overlayColor: const Color(
                        0xFF6B7280,
                      ).withValues(alpha: 0.08),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () async {
                      final walletCash = _parseAmount(_walletController);
                      final cardAmounts = <String, double>{
                        for (var i = 0; i < _cards.length; i++)
                          _cards[i].id: _parseAmount(_cardControllers[i]),
                      };
                      final billsPercentage =
                          double.tryParse(_billsController.text) ?? 0;
                      final savingsPercentage =
                          double.tryParse(_savingsController.text) ?? 0;
                      final personalPercentage =
                          double.tryParse(_personalController.text) ?? 0;
                      final totalPercentage =
                          billsPercentage +
                          savingsPercentage +
                          personalPercentage;
                      final balance = walletCash +
                          cardAmounts.values.fold<double>(
                            0,
                            (sum, amount) => sum + amount,
                          );

                      if (walletCash < 0 ||
                          cardAmounts.values.any((amount) => amount < 0)) {
                        ScaffoldMessenger.of(widget.hostContext).showSnackBar(
                          const SnackBar(
                            content: Text('Enter valid money amounts.'),
                          ),
                        );
                        return;
                      }
                      if ((totalPercentage - 100).abs() > 0.001) {
                        ScaffoldMessenger.of(widget.hostContext).showSnackBar(
                          const SnackBar(
                            content: Text('Percentages must total 100%.'),
                          ),
                        );
                        return;
                      }

                      final previewCards = [
                        for (final card in _cards)
                          card.copyWith(amount: cardAmounts[card.id] ?? 0),
                      ];
                      final confirmed = await AllocationConfirmDialog
                          .showWalletSourcesConfirm(
                        context: widget.hostContext,
                        walletCash: walletCash,
                        cards: [
                          for (final card in previewCards)
                            (card.bankLabel, card.amount),
                        ],
                        billsPercentage: billsPercentage,
                        savingsPercentage: savingsPercentage,
                        personalPercentage: personalPercentage,
                      );
                      if (confirmed != true) return;

                      if (!widget.hostContext.mounted) return;
                      final authorized = await showSensitiveActionAuth(
                        context: widget.hostContext,
                        title: 'Confirm budget change',
                        description:
                            'Enter your PIN or use fingerprint to update '
                            'your wallet, cards, and allocation percentages.',
                      );
                      if (!widget.hostContext.mounted || authorized != true) {
                        return;
                      }

                      try {
                        await widget.hostContext
                            .read<WalletCashProvider>()
                            .setAmount(walletCash);
                        await widget.hostContext
                            .read<WalletCardsProvider>()
                            .setCardAmounts(cardAmounts);
                        await budget.updatePercentages(
                          billsPercentage: billsPercentage,
                          savingsPercentage: savingsPercentage,
                          personalPercentage: personalPercentage,
                        );
                        await budget.updateAvailableBalance(balance);
                        if (context.mounted) Navigator.pop(context);
                        widget.onSaved();
                      } catch (error) {
                        if (isFinanceRateLimitError(error)) return;
                        if (widget.hostContext.mounted) {
                          ScaffoldMessenger.of(widget.hostContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                budget.errorMessage ??
                                    'Available balance could not be updated.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF121212),
                      overlayColor: const Color(
                        0xFF121212,
                      ).withValues(alpha: 0.08),
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddMoneyDialog extends StatefulWidget {
  const AddMoneyDialog({
    super.key,
    required this.hostContext,
    required this.onBusyChanged,
  });

  final BuildContext hostContext;
  final ValueChanged<bool> onBusyChanged;

  @override
  State<AddMoneyDialog> createState() => _AddMoneyDialogState();
}

class _AddMoneyDialogState extends State<AddMoneyDialog> {
  late final TextEditingController _amountController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final budget = widget.hostContext.read<BudgetProvider>();
    final symbol = context.watch<CurrencyProvider>().symbol;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add Money',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF121212),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add funds to your available balance.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 24),
            homeDialogField(
              label: 'Amount',
              controller: _amountController,
              prefixText: '$symbol ',
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          final amount =
                              double.tryParse(_amountController.text) ?? 0;
                          if (amount <= 0) {
                            ScaffoldMessenger.of(
                              widget.hostContext,
                            ).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Enter an amount greater than zero.',
                                ),
                              ),
                            );
                            return;
                          }

                          final confirmed =
                              await AllocationConfirmDialog.showNewMoneyConfirm(
                                context: widget.hostContext,
                                kind: AllocationConfirmKind.addMoney,
                                amount: amount,
                                billsPercentage: budget.billsPercentage,
                                savingsPercentage: budget.savingsPercentage,
                                personalPercentage: budget.personalPercentage,
                              );
                          if (confirmed != true) return;

                          if (!widget.hostContext.mounted) return;
                          final authorized = await showSensitiveActionAuth(
                            context: widget.hostContext,
                            title: 'Confirm add money',
                            description:
                                'Enter your PIN or use fingerprint to add '
                                'money to your available balance.',
                          );
                          if (!widget.hostContext.mounted ||
                              authorized != true) {
                            return;
                          }

                          setState(() => _isSaving = true);
                          widget.onBusyChanged(true);
                          try {
                            await budget.addMoney(amount);
                            if (context.mounted) Navigator.pop(context);
                            if (!widget.hostContext.mounted) return;
                            ScaffoldMessenger.of(widget.hostContext)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${AllocationConfirmDialog.formatMoney(widget.hostContext, amount)} '
                                    'added to your available balance.',
                                  ),
                                ),
                              );
                          } catch (error) {
                            if (mounted) setState(() => _isSaving = false);
                            if (isFinanceRateLimitError(error)) return;
                            if (!widget.hostContext.mounted) return;
                            ScaffoldMessenger.of(widget.hostContext)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    budget.errorMessage ??
                                        'Unable to add money. Please try again.',
                                  ),
                                ),
                              );
                          } finally {
                            widget.onBusyChanged(false);
                          }
                        },
                  child: const Text(
                    'Add',
                    style: TextStyle(
                      color: Color(0xFF121212),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
