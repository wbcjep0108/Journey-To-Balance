import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/financial_entry.dart';
import 'rate_limit_dialog.dart';

typedef BudgetModalSave = Future<void> Function(String name, double amount);

class BudgetModal extends StatefulWidget {
  const BudgetModal({
    super.key,
    required this.category,
    required this.title,
    required this.availableBalance,
    required this.onSave,
    this.initialEntry,
  });

  final FinancialCategory category;
  final String title;
  final double availableBalance;
  final BudgetModalSave onSave;
  final FinancialEntry? initialEntry;

  static Future<void> show({
    required BuildContext context,
    required FinancialCategory category,
    required String title,
    required double availableBalance,
    required BudgetModalSave onSave,
    FinancialEntry? initialEntry,
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
      pageBuilder: (_, _, _) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: Center(
          child: BudgetModal(
            category: category,
            title: title,
            availableBalance: availableBalance,
            initialEntry: initialEntry,
            onSave: onSave,
          ),
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

  bool _nameTouched = false;
  bool _amountTouched = false;
  bool _isSaving = false;
  String? _submissionError;

  String get _name => _nameController.text.trim();
  double? get _amount => double.tryParse(_amountController.text);

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

  bool get _isValid => _nameError == null && _amountError == null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialEntry?.title ?? '',
    );
    _amountController = TextEditingController(
      text: widget.initialEntry?.amount.toStringAsFixed(2) ?? '',
    );
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
    _nameTouched = true;
    _refresh();
  }

  void _onAmountChanged() {
    _amountTouched = true;
    _refresh();
  }

  void _refresh() {
    if (mounted) setState(() => _submissionError = null);
  }

  Future<void> _submit() async {
    _nameTouched = true;
    _amountTouched = true;
    if (!_isValid) {
      setState(() {});
      _shakeController.forward(from: 0);
      return;
    }

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final saveOperation = widget.onSave(_name, _amount!);
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
                        'Available: ₱${NumberFormat('#,##0.00').format(widget.availableBalance)}',
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
                    ),
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
                      prefixText: '₱ ',
                      inputFormatters: [_CurrencyInputFormatter()],
                      onSubmitted: (_) {
                        if (_isValid && !_isSaving) _submit();
                      },
                      errorText: _amountTouched ? _amountError : null,
                    ),
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
                          onPressed: _isValid && !_isSaving ? _submit : null,
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
              borderRadius: BorderRadius.circular(28),
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
              decoration: InputDecoration(
                hintText: hint,
                prefixText: prefixText,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 17,
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
