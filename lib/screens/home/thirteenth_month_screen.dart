import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/budget_provider.dart';
import '../../providers/thirteenth_month_provider.dart';
import '../../providers/wallet_cards_provider.dart';
import '../../providers/wallet_cash_provider.dart';
import '../../widgets/allocation_confirm_dialog.dart';
import '../../widgets/barrier_blur.dart';
import '../../widgets/sensitive_action_auth.dart';
import 'home_money_dialogs.dart';

class ThirteenthMonthScreen extends StatefulWidget {
  const ThirteenthMonthScreen({super.key});

  @override
  State<ThirteenthMonthScreen> createState() => _ThirteenthMonthScreenState();
}

class _ThirteenthMonthScreenState extends State<ThirteenthMonthScreen> {
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  late final List<TextEditingController> _monthControllers;
  late final TextEditingController _fillAllController;
  late final TextEditingController _otherBenefitsController;

  @override
  void initState() {
    super.initState();
    final calculator = context.read<ThirteenthMonthProvider>();
    _monthControllers = calculator.monthlySalaries
        .map((amount) => TextEditingController(text: _editableAmount(amount)))
        .toList(growable: false);
    _fillAllController = TextEditingController();
    _otherBenefitsController = TextEditingController(
      text: _editableAmount(calculator.otherBenefits),
    );
  }

  @override
  void dispose() {
    for (final controller in _monthControllers) {
      controller.dispose();
    }
    _fillAllController.dispose();
    _otherBenefitsController.dispose();
    super.dispose();
  }

  double _amountOf(String value) => double.tryParse(value.trim()) ?? 0;

  static String _editableAmount(double amount) {
    if (amount == 0) return '';
    return amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }

  String _money(double amount) => NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  ).format(amount);

  /// Retries a failed load, then shows the loaded inputs in the fields.
  Future<void> _retryLoad() async {
    final calculator = context.read<ThirteenthMonthProvider>();
    final loaded = await calculator.retryLoad();
    if (!mounted || !loaded) return;
    _syncFieldsFromProvider(calculator);
  }

  void _syncFieldsFromProvider(ThirteenthMonthProvider calculator) {
    for (var i = 0; i < _monthControllers.length; i++) {
      _monthControllers[i].text = _editableAmount(calculator.monthlySalaries[i]);
    }
    _otherBenefitsController.text = _editableAmount(calculator.otherBenefits);
  }

  void _fillAll() {
    final calculator = context.read<ThirteenthMonthProvider>();
    if (!calculator.hasLoaded) return;
    final amount = _amountOf(_fillAllController.text);
    context.read<ThirteenthMonthProvider>().fillAllMonths(amount);
    for (final controller in _monthControllers) {
      controller.text = _editableAmount(amount);
    }
    FocusScope.of(context).unfocus();
  }

  Future<void> _receiveAsIncome() async {
    final calculator = context.read<ThirteenthMonthProvider>();
    final budget = context.read<BudgetProvider>();
    final result = calculator.result;
    if (result.gross <= 0) return;
    final payout = result.gross;

    final source = await showDialog<MoneyDepositSource>(
      context: context,
      builder: (_) => withBarrierBlur(
        MoneyDepositSourceDialog(
          hostContext: context,
          title: 'Where should the pay go?',
          description:
              'Choose the wallet or card that will receive your 13th month pay.',
        ),
      ),
    );
    if (!mounted || source == null) return;

    final confirmed = await AllocationConfirmDialog.showNewMoneyConfirm(
      context: context,
      kind: AllocationConfirmKind.receiveSalary,
      amount: payout,
      billsPercentage: budget.billsPercentage,
      savingsPercentage: budget.savingsPercentage,
      personalPercentage: budget.personalPercentage,
    );
    if (!mounted || !confirmed) return;

    final authorized = await showSensitiveActionAuth(
      context: context,
      title: 'Receive 13th month pay',
      description:
          'Enter your PIN or use fingerprint to add this payout to your '
          'available balance.',
    );
    if (!mounted || authorized != true) return;

    try {
      await calculator.receiveAsIncome();
      if (source.isWallet) {
        if (!mounted) return;
        final wallet = context.read<WalletCashProvider>();
        await wallet.setAmount(wallet.amount + payout);
      } else {
        if (!mounted) return;
        final cards = context.read<WalletCardsProvider>();
        final card = cards.cardById(source.cardId!);
        if (card != null) {
          await cards.setCardAmount(
            cardId: card.id,
            amount: card.amount + payout,
          );
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '13th month pay added to ${source.label} and your available balance.',
            ),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              calculator.errorMessage ??
                  'Unable to receive the payout. Please try again.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final calculator = context.watch<ThirteenthMonthProvider>();
    final budget = context.watch<BudgetProvider>();
    final result = calculator.result;
    // Inputs stay read-only until saved data loads, so nothing typed here can
    // be saved over it.
    final editable = calculator.hasLoaded;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F5),
        surfaceTintColor: Colors.transparent,
        title: const Text(
          '13th Month Pay',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: const Color(0xFF121212),
            ),
          ),
          child: Builder(
            builder: (context) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        const Text(
                          'Enter the basic salary actually earned in each month. Exclude '
                          'allowances, overtime, holiday pay, and other benefits.',
                          style: TextStyle(
                            color: Color(0xFF121212),
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Fill all months',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF121212),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _MoneyField(
                                      controller: _fillAllController,
                                      label: 'Monthly basic salary',
                                      enabled: editable,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed: editable ? _fillAll : null,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF121212),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                      ),
                                      child: const Text(
                                        'Fill',
                                        style: TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Monthly basic salary',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF121212),
                                      ),
                                    ),
                                  ),
                                  if (calculator.isSaving)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF121212),
                                      ),
                                    )
                                  else
                                    const Text(
                                      'Saved automatically',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF121212),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: 12,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 2.3,
                                    ),
                                itemBuilder: (context, index) => _MoneyField(
                                  controller: _monthControllers[index],
                                  label: _months[index],
                                  enabled: editable,
                                  onChanged: (value) =>
                                      calculator.setMonthlySalary(index, _amountOf(value)),
                                  onClear: () {
                                    _monthControllers[index].clear();
                                    calculator.setMonthlySalary(index, 0);
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                              _MoneyField(
                                controller: _otherBenefitsController,
                                label: 'Other benefits (optional)',
                                enabled: editable,
                                helperText:
                                    'Counts toward the combined ₱90,000 exemption',
                                onChanged: (value) =>
                                    calculator.setOtherBenefits(_amountOf(value)),
                              ),
                              if (calculator.errorMessage != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  calculator.errorMessage!,
                                  key: const ValueKey('thirteenth-month-error'),
                                  style: const TextStyle(
                                    color: Color(0xFFB42318),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              if (calculator.loadFailed ||
                                  (calculator.isLoading &&
                                      !calculator.hasLoaded)) ...[
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    key: const ValueKey('thirteenth-month-retry'),
                                    onPressed: calculator.isLoading
                                        ? null
                                        : _retryLoad,
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF121212),
                                    ),
                                    icon: calculator.isLoading
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFF121212),
                                            ),
                                          )
                                        : const Icon(Icons.refresh_rounded),
                                    label: const Text(
                                      'Retry',
                                      style: TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Estimated result',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF121212),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _ResultRow(
                                label: 'Gross 13th month pay',
                                value: _money(result.gross),
                                prominent: true,
                              ),
                              if (result.otherBenefits > 0) ...[
                                const SizedBox(height: 12),
                                _ResultRow(
                                  label: 'Other benefits',
                                  value: _money(result.otherBenefits),
                                ),
                                const SizedBox(height: 12),
                                _ResultRow(
                                  label: 'Total combined benefits',
                                  value: _money(result.totalBenefits),
                                ),
                              ],
                              const Divider(height: 24),
                              _ResultRow(
                                label: 'Tax-exempt portion (max ₱90,000)',
                                value: _money(result.taxExempt),
                              ),
                              const SizedBox(height: 12),
                              _ResultRow(
                                label: 'Taxable excess',
                                value: _money(result.taxableExcess),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Estimate only. Not legal or tax advice.',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF121212),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Allocation preview',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF121212),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'If received as income, the payout uses your current budget percentages.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF121212),
                                ),
                              ),
                              const SizedBox(height: 14),
                              _AllocationRow(
                                label: 'Bills',
                                percentage: budget.billsPercentage,
                                amount: result.gross * budget.billsPercentage / 100,
                                formatter: _money,
                              ),
                              _AllocationRow(
                                label: 'Savings',
                                percentage: budget.savingsPercentage,
                                amount: result.gross * budget.savingsPercentage / 100,
                                formatter: _money,
                              ),
                              _AllocationRow(
                                label: 'Personal',
                                percentage: budget.personalPercentage,
                                amount: result.gross * budget.personalPercentage / 100,
                                formatter: _money,
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      result.gross <= 0 || calculator.isReceiving
                                          ? null
                                          : _receiveAsIncome,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF121212),
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor:
                                        const Color(0xFFD5D7DA),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  icon: calculator.isReceiving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.account_balance_wallet_rounded,
                                        ),
                                  label: const Text(
                                    'Receive as income',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8EAED)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    this.helperText,
    this.onChanged,
    this.onClear,
    this.enabled = true,
  });

  /// False while saved inputs are not loaded, so nothing can be edited or
  /// saved over them.
  final bool enabled;

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final ValueChanged<String>? onChanged;

  /// When set, a delete icon appears while the field has a value.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    if (onClear == null || !enabled) return _buildField(showClear: false);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) =>
          _buildField(showClear: value.text.isNotEmpty),
    );
  }

  Widget _buildField({required bool showClear}) {
    return TextField(
      controller: controller,
      enabled: enabled,
      style: const TextStyle(
        color: Color(0xFF121212),
        fontWeight: FontWeight.w600,
      ),
      cursorColor: const Color(0xFF121212),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF121212)),
        floatingLabelStyle: const TextStyle(
          color: Color(0xFF121212),
          fontWeight: FontWeight.w700,
        ),
        helperText: helperText,
        helperStyle: const TextStyle(color: Color(0xFF121212)),
        helperMaxLines: 2,
        prefixText: '₱ ',
        prefixStyle: const TextStyle(
          color: Color(0xFF121212),
          fontWeight: FontWeight.w600,
        ),
        suffixIcon: showClear
            ? IconButton(
                tooltip: 'Clear $label',
                onPressed: onClear,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: Color(0xFF6B7280),
                ),
              )
            : null,
        filled: true,
        fillColor: const Color(0xFFF7F7F8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF121212), width: 1.5),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.value,
    this.prominent = false,
  });

  final String label;
  final String value;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: prominent ? 15 : 14,
              fontWeight: prominent ? FontWeight.w700 : FontWeight.w500,
              color: const Color(0xFF121212),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: prominent ? 22 : 16,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF121212),
          ),
        ),
      ],
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({
    required this.label,
    required this.percentage,
    required this.amount,
    required this.formatter,
  });

  final String label;
  final double percentage;
  final double amount;
  final String Function(double) formatter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF121212),
              ),
            ),
          ),
          Text(
            '${percentage.toStringAsFixed(percentage % 1 == 0 ? 0 : 1)}%',
            style: const TextStyle(
              color: Color(0xFF121212),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 110,
            child: Text(
              formatter(amount),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF121212),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
