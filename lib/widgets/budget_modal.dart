import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/financial_entry.dart';
import '../models/spend_category_option.dart';
import '../providers/currency_provider.dart';
import '../providers/wallet_cards_provider.dart';
import '../providers/wallet_cash_provider.dart';
import 'barrier_blur.dart';
import 'category_icon_badge.dart';
import 'rate_limit_dialog.dart';

/// The account a spend is paid from. Either the cash wallet, or a specific
/// bank card identified by [cardId].
class PaymentSource {
  const PaymentSource.wallet()
      : isWallet = true,
        cardId = null;

  const PaymentSource.card(String this.cardId) : isWallet = false;

  final bool isWallet;
  final String? cardId;
}

typedef BudgetModalSave =
    Future<void> Function(
      String name,
      double amount,
      String? iconAsset,
      PaymentSource? source,
    );

class BudgetModal extends StatefulWidget {
  const BudgetModal({
    super.key,
    required this.category,
    required this.title,
    required this.availableBalance,
    required this.onSave,
    this.initialEntry,
    this.quickSelectOptions,
  });

  final FinancialCategory category;
  final String title;
  final double availableBalance;
  final BudgetModalSave onSave;
  final FinancialEntry? initialEntry;

  /// Optional override. Defaults to [SpendCategoryPresets.forCategory].
  final List<SpendCategoryOption>? quickSelectOptions;

  static Future<void> show({
    required BuildContext context,
    required FinancialCategory category,
    required String title,
    required double availableBalance,
    required BudgetModalSave onSave,
    FinancialEntry? initialEntry,
    List<SpendCategoryOption>? quickSelectOptions,
    VoidCallback? onClose,
  }) async {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close $title dialog',
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => withBarrierBlur(
        BudgetModal(
          category: category,
          title: title,
          availableBalance: availableBalance,
          initialEntry: initialEntry,
          quickSelectOptions: quickSelectOptions,
          onSave: onSave,
        ),
      ),
      transitionBuilder: (_, animation, _, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.035),
              end: Offset.zero,
            ).animate(curve),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1).animate(curve),
              child: child,
            ),
          ),
        );
      },
    );
    onClose?.call();
  }

  @override
  State<BudgetModal> createState() => _BudgetModalState();
}

class _BudgetModalState extends State<BudgetModal>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final FocusNode _nameFocus;
  late final FocusNode _amountFocus;
  late final AnimationController _shakeController;
  late final List<SpendCategoryOption> _quickSelectOptions;
  SpendCategoryOption? _selectedOption;

  /// Selected payment source (Wallet or a specific card). Only shown for new
  /// spends; editing an existing entry does not re-charge a source.
  PaymentSource _paymentSource = const PaymentSource.wallet();
  String? _selectedCardId;

  bool _nameTouched = false;
  bool _amountTouched = false;
  bool _iconTouched = false;
  bool _isSaving = false;
  String? _submissionError;

  /// Payment source is only relevant when recording a new spend.
  bool get _showPaymentSource => widget.initialEntry == null;

  String get _name => _nameController.text.trim();
  double? get _amount => double.tryParse(_amountController.text);

  bool get _iconRequired => _quickSelectOptions.isNotEmpty;

  String? get _nameError {
    if (_name.isEmpty) return 'Name is required.';
    return null;
  }

  String? get _amountError {
    if (_amountController.text.isEmpty) return 'Amount is required.';
    final amount = _amount;
    if (amount == null) return 'Enter a valid amount.';
    if (amount <= 0) return 'Amount must be greater than zero.';
    if (amount > widget.availableBalance + 0.001) {
      return 'Amount cannot exceed the available balance.';
    }
    return null;
  }

  String? get _iconError {
    if (_iconRequired && _selectedOption == null) {
      return 'Icon is required. Select one.';
    }
    return null;
  }

  bool get _isValid =>
      _nameError == null && _amountError == null && _iconError == null;

  @override
  void initState() {
    super.initState();
    _quickSelectOptions =
        widget.quickSelectOptions ??
        SpendCategoryPresets.forCategory(widget.category);
    _nameController = TextEditingController(
      text: widget.initialEntry?.title ?? '',
    );
    _amountController = TextEditingController(
      text: widget.initialEntry?.amount.toStringAsFixed(2) ?? '',
    );
    final initialTitle = widget.initialEntry?.title.trim().toLowerCase() ?? '';
    final initialIcon = widget.initialEntry?.iconAsset?.trim();
    if (initialIcon != null && initialIcon.isNotEmpty) {
      SpendCategoryOption? match;
      for (final option in _quickSelectOptions) {
        if (option.assetPath == initialIcon) {
          match = option;
          break;
        }
      }
      _selectedOption =
          match ??
          SpendCategoryOption(
            label: widget.initialEntry?.title ?? '',
            assetPath: initialIcon,
          );
    } else if (initialTitle.isNotEmpty) {
      for (final option in _quickSelectOptions) {
        if (option.label.toLowerCase() == initialTitle) {
          _selectedOption = option;
          break;
        }
      }
    }
    _nameFocus = FocusNode(debugLabel: 'Budget item name');
    _amountFocus = FocusNode(debugLabel: 'Budget item amount');
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _nameController.addListener(_onNameChanged);
    _amountController.addListener(_onAmountChanged);
    _nameFocus.addListener(_refresh);
    _amountFocus.addListener(_refresh);
  }

  void _onNameChanged() {
    _refresh();
  }

  void _onAmountChanged() {
    _refresh();
  }

  void _refresh() {
    if (mounted) setState(() => _submissionError = null);
  }

  void _selectQuickOption(SpendCategoryOption option) {
    setState(() {
      _selectedOption = option;
    });
    // Prefill name from the chip; user can still edit freely (e.g. "Meralco").
    if (_nameController.text.trim().isEmpty ||
        _quickSelectOptions.any(
          (o) =>
              o.label.toLowerCase() == _nameController.text.trim().toLowerCase(),
        )) {
      _nameController
        ..text = option.label
        ..selection = TextSelection.collapsed(offset: option.label.length);
    }
    _refresh();
    _amountFocus.requestFocus();
  }

  /// Resolves the chosen payment source and confirms it can cover [_amount].
  /// Returns null when the selection is invalid or has insufficient balance.
  PaymentSource? _resolvePaymentSource() {
    final amount = _amount;
    if (amount == null) return null;

    if (_paymentSource.isWallet) {
      final cash = context.read<WalletCashProvider>().amount;
      if (amount > cash + 0.001) return null;
      return const PaymentSource.wallet();
    }

    final cardId = _selectedCardId;
    if (cardId == null) return null;
    final card = context.read<WalletCardsProvider>().cardById(cardId);
    if (card == null || amount > card.amount + 0.001) return null;
    return PaymentSource.card(cardId);
  }

  Future<void> _submit() async {
    _nameTouched = true;
    _amountTouched = true;
    _iconTouched = true;
    if (!_isValid) {
      setState(() {});
      _shakeController.forward(from: 0);
      return;
    }

    PaymentSource? source;
    if (_showPaymentSource) {
      final resolved = _resolvePaymentSource();
      if (resolved == null) {
        setState(
          () => _submissionError =
              'Select a payment method that can cover this amount.',
        );
        _shakeController.forward(from: 0);
        return;
      }
      source = resolved;
    }

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final saveOperation = widget.onSave(
        _name,
        _amount!,
        _selectedOption?.assetPath,
        source,
      );
      if (mounted) Navigator.pop(context);
      await saveOperation;
    } catch (error) {
      if (isFinanceRateLimitError(error)) return;
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to save. Check your connection and retry.'),
          ),
        );
    }
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_onNameChanged)
      ..dispose();
    _amountController
      ..removeListener(_onAmountChanged)
      ..dispose();
    _nameFocus
      ..removeListener(_refresh)
      ..dispose();
    _amountFocus
      ..removeListener(_refresh)
      ..dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalMargin = width < 600 ? width * 0.05 : 24.0;
    final symbol = context.watch<CurrencyProvider>().symbol;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_isSaving) Navigator.maybePop(context);
        },
      },
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Material(
          color: Colors.transparent,
          child: AnimatedBuilder(
            animation: _shakeController,
            builder: (context, child) {
              final progress = _shakeController.value;
              final offset =
                  math.sin(progress * math.pi * 6) * 7 * (1 - progress);
              return Transform.translate(
                offset: Offset(offset, 0),
                child: child,
              );
            },
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 460),
              margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
              padding: const EdgeInsets.fromLTRB(26, 28, 26, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 36,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF17191D),
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Available: $symbol${NumberFormat('#,##0.00').format(widget.availableBalance)}',
                        style: const TextStyle(
                          color: Color(0xFF737983),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    _PremiumField(
                      label: 'Name',
                      hint: 'Enter item name',
                      controller: _nameController,
                      focusNode: _nameFocus,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _amountFocus.requestFocus(),
                      errorText: _nameTouched ? _nameError : null,
                      leadingIconAsset: _selectedOption?.assetPath,
                    ),
                    if (_quickSelectOptions.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _IconSelectSection(
                        options: _quickSelectOptions,
                        selectedOption: _selectedOption,
                        showError: _iconTouched && _iconError != null,
                        errorText: _iconError,
                        onSelected: _selectQuickOption,
                      ),
                    ],
                    const SizedBox(height: 20),
                    _PremiumField(
                      label: 'Amount',
                      hint: 'Enter amount',
                      controller: _amountController,
                      focusNode: _amountFocus,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.done,
                      prefixText: '$symbol ',
                      inputFormatters: [_CurrencyInputFormatter()],
                      onSubmitted: (_) {
                        if (_isValid && !_isSaving) _submit();
                      },
                      errorText: _amountTouched ? _amountError : null,
                    ),
                    if (_showPaymentSource) ...[
                      const SizedBox(height: 20),
                      _PaymentSourceSection(
                        walletSelected: _paymentSource.isWallet,
                        selectedCardId: _selectedCardId,
                        onSelectWallet: () {
                          setState(() {
                            _paymentSource = const PaymentSource.wallet();
                            _selectedCardId = null;
                            _submissionError = null;
                          });
                        },
                        onSelectCard: (cardId) {
                          setState(() {
                            _paymentSource = PaymentSource.card(cardId);
                            _selectedCardId = cardId;
                            _submissionError = null;
                          });
                        },
                      ),
                    ],
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _submissionError == null
                          ? const SizedBox(height: 10)
                          : Padding(
                              key: ValueKey(_submissionError),
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                _submissionError!,
                                style: const TextStyle(
                                  color: Color(0xFFB3261E),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF777C85),
                          ),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _isSaving ? null : _submit,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black,
                            disabledForegroundColor: const Color(0xFFB5B8BE),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconSelectSection extends StatelessWidget {
  const _IconSelectSection({
    required this.options,
    required this.selectedOption,
    required this.showError,
    required this.errorText,
    required this.onSelected,
  });

  final List<SpendCategoryOption> options;
  final SpendCategoryOption? selectedOption;
  final bool showError;
  final String? errorText;
  final ValueChanged<SpendCategoryOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Icon',
          style: TextStyle(
            color: Color(0xFF25282D),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: showError
                  ? const Color(0xFFB3261E)
                  : Colors.transparent,
              width: showError ? 1.4 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _QuickSelectChips(
            options: options,
            selectedOption: selectedOption,
            onSelected: onSelected,
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: showError
              ? Padding(
                  key: ValueKey(errorText ?? 'icon-error'),
                  padding: const EdgeInsets.only(top: 7, left: 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Color(0xFFB3261E),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          errorText ?? 'Icon is required. Select one.',
                          style: const TextStyle(
                            color: Color(0xFFB3261E),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('icon-ok')),
        ),
      ],
    );
  }
}

class _QuickSelectChips extends StatelessWidget {
  const _QuickSelectChips({
    required this.options,
    required this.selectedOption,
    required this.onSelected,
  });

  final List<SpendCategoryOption> options;
  final SpendCategoryOption? selectedOption;
  final ValueChanged<SpendCategoryOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final option in options)
          _CategoryChip(
            option: option,
            selected: identical(selectedOption, option) ||
                selectedOption?.assetPath == option.assetPath,
            onTap: () => onSelected(option),
          ),
      ],
    );
  }
}

class _PaymentSourceSection extends StatelessWidget {
  const _PaymentSourceSection({
    required this.walletSelected,
    required this.selectedCardId,
    required this.onSelectWallet,
    required this.onSelectCard,
  });

  final bool walletSelected;
  final String? selectedCardId;
  final VoidCallback onSelectWallet;
  final ValueChanged<String> onSelectCard;

  @override
  Widget build(BuildContext context) {
    final symbol = context.watch<CurrencyProvider>().symbol;
    final cash = context.watch<WalletCashProvider>().amount;
    final cards = context.watch<WalletCardsProvider>().cards;

    String money(double value) =>
        '$symbol${NumberFormat('#,##0.00').format(value)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment method',
          style: TextStyle(
            color: Color(0xFF25282D),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PaymentSourceChip(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Wallet',
                subtitle: money(cash),
                selected: walletSelected,
                onTap: onSelectWallet,
              ),
              for (final card in cards)
                _PaymentSourceChip(
                  iconAsset: card.iconAsset,
                  label: card.bankLabel,
                  subtitle: money(card.amount),
                  selected: !walletSelected && selectedCardId == card.id,
                  onTap: () => onSelectCard(card.id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaymentSourceChip extends StatelessWidget {
  const _PaymentSourceChip({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.icon,
    this.iconAsset,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final String? iconAsset;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: selected ? const Color(0xFF25282D) : Colors.transparent,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: selected ? 0.12 : 0.07),
                blurRadius: selected ? 14 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (iconAsset != null)
                Image.asset(
                  iconAsset!,
                  width: 22,
                  height: 22,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.credit_card,
                    size: 20,
                    color: Color(0xFF737983),
                  ),
                )
              else
                Icon(
                  icon ?? Icons.credit_card,
                  size: 22,
                  color: const Color(0xFF25282D),
                ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: const Color(0xFF25282D),
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF737983),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SpendCategoryOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: selected
                  ? const Color(0xFF25282D)
                  : Colors.transparent,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: selected ? 0.12 : 0.07),
                blurRadius: selected ? 14 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (option.usesMaterialIcon)
                Icon(
                  option.materialIcon,
                  size: 22,
                  color: const Color(0xFF25282D),
                )
              else
                Image.asset(
                  option.assetPath,
                  width: 22,
                  height: 22,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.category_outlined,
                    size: 20,
                    color: Color(0xFF737983),
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                option.label,
                style: TextStyle(
                  color: const Color(0xFF25282D),
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumField extends StatelessWidget {
  const _PremiumField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.focusNode,
    required this.errorText,
    this.autofocus = false,
    this.keyboardType,
    this.textInputAction,
    this.prefixText,
    this.leadingIconAsset,
    this.inputFormatters,
    this.onSubmitted,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? errorText;
  final bool autofocus;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? prefixText;
  final String? leadingIconAsset;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF25282D),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: errorText != null
                    ? const Color(0xFFB3261E)
                    : focusNode.hasFocus
                    ? const Color(0xFF25282D)
                    : Colors.transparent,
              ),
              boxShadow: [
                BoxShadow(
                  color: focusNode.hasFocus
                      ? Colors.black.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.07),
                  blurRadius: focusNode.hasFocus ? 18 : 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              inputFormatters: inputFormatters,
              onSubmitted: onSubmitted,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(
                color: Color(0xFF17191D),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: Color(0xFF9AA0A8),
                  fontWeight: FontWeight.w500,
                ),
                prefixIcon: leadingIconAsset == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(left: 10, right: 6),
                        child: CategoryIconBadge(
                          iconAsset: leadingIconAsset!,
                          size: 34,
                        ),
                      ),
                prefixIconConstraints: leadingIconAsset == null
                    ? null
                    : const BoxConstraints(minWidth: 50, minHeight: 34),
                prefixText: prefixText,
                prefixStyle: const TextStyle(
                  color: Color(0xFF17191D),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(
                  leadingIconAsset == null ? 20 : 4,
                  17,
                  20,
                  17,
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: errorText == null
                ? const SizedBox.shrink()
                : Padding(
                    key: ValueKey(errorText),
                    padding: const EdgeInsets.only(top: 7, left: 12),
                    child: Text(
                      errorText!,
                      style: const TextStyle(
                        color: Color(0xFFB3261E),
                        fontSize: 12,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CurrencyInputFormatter extends TextInputFormatter {
  static final _pattern = RegExp(r'^\d{0,10}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return _pattern.hasMatch(newValue.text) ? newValue : oldValue;
  }
}
