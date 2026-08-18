import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/financial_entry.dart';
import '../../models/loan_entry.dart';
import '../../providers/budget_provider.dart';
import '../../providers/loan_provider.dart';
import '../../services/finance_api_service.dart';
import '../../widgets/barrier_blur.dart';
import '../../widgets/sensitive_action_auth.dart';
import 'paid_loan_transactions_page.dart';

class TotalLoanPage extends StatefulWidget {
  const TotalLoanPage({super.key});

  @override
  State<TotalLoanPage> createState() => _TotalLoanPageState();
}

class _TotalLoanPageState extends State<TotalLoanPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      // Force reload so installment fields are always re-parsed from storage.
      context.read<LoanProvider>().loadForUser(uid);
    });
  }

  Future<void> _showAddLoanDialog() async {
    final result = await showDialog<_AddLoanDialogResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (_) => withBarrierBlur(const _AddLoanDialog()),
    );

    if (result == null || !mounted) return;

    if (result.finalPaymentDate.isBefore(result.monthlyDueDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Final payment must be on or after the monthly due.'),
        ),
      );
      return;
    }

    await context.read<LoanProvider>().addLoan(
      name: result.name,
      amount: result.amount,
      monthlyDueDate: result.monthlyDueDate,
      finalPaymentDate: result.finalPaymentDate,
    );
  }

  Future<bool> _confirmDeleteLoan(LoanEntry loan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (dialogContext) {
        return withBarrierBlur(
          Center(
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Delete loan?',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF121212),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Remove "${loan.name}" and its payment schedule? This cannot be undone.',
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF6B7280),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF121212),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              child: const Text(
                                'Delete',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return false;

    final authorized = await showSensitiveActionAuth(
      context: context,
      title: 'Confirm delete',
      description:
          'Enter your PIN or use fingerprint to delete "${loan.name}".',
    );
    if (!authorized || !mounted) return false;

    // Deletion happens in onDismissed so the Dismissible leaves the tree correctly.
    return true;
  }

  Future<void> _showLoanScheduleDialog(String loanId) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (_) => withBarrierBlur(_LoanScheduleDialog(loanId: loanId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loans = context.watch<LoanProvider>();
    final totalLabel = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: loans.totalLoan % 1 == 0 ? 0 : 2,
    ).format(loans.totalLoan);

    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, topInset + 4, 8, 36),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Loan transactions',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  const PaidLoanTransactionsPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.history, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    totalLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Total Loan',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                  ),
                  child: loans.activeLoans.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(24, 56, 24, 24),
                            child: Text(
                              'No active loans.\nTap + to add one.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 15,
                                height: 1.4,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 56, 20, 28),
                          itemCount: loans.activeLoans.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 14),
                          itemBuilder: (context, index) {
                            final loan = loans.activeLoans[index];
                            return _LoanCard(
                              loan: loan,
                              onOpen: () => _showLoanScheduleDialog(loan.id),
                              onConfirmDelete: () => _confirmDeleteLoan(loan),
                              onDismissed: () => loans.deleteLoan(loan.id),
                            );
                          },
                        ),
                ),
                Positioned(
                  top: -28,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _showAddLoanDialog,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.add,
                            size: 30,
                            color: Colors.black,
                            weight: 800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddLoanDialogResult {
  const _AddLoanDialogResult({
    required this.name,
    required this.amount,
    required this.monthlyDueDate,
    required this.finalPaymentDate,
  });

  final String name;
  final double amount;
  final DateTime monthlyDueDate;
  final DateTime finalPaymentDate;
}

class _AddLoanDialog extends StatefulWidget {
  const _AddLoanDialog();

  @override
  State<_AddLoanDialog> createState() => _AddLoanDialogState();
}

class _AddLoanDialogState extends State<_AddLoanDialog> {
  static final _dateFormat = DateFormat('MM/dd/yyyy');

  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _monthlyController;
  late final TextEditingController _finalController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _amountController = TextEditingController();
    _monthlyController = TextEditingController();
    _finalController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _monthlyController.dispose();
    _finalController.dispose();
    super.dispose();
  }

  DateTime? _parseDate(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    try {
      return _dateFormat.parseStrict(text);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickDate({
    required TextEditingController controller,
    DateTime? firstDate,
  }) async {
    final existing = _parseDate(controller.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: existing ?? firstDate ?? DateTime.now(),
      firstDate: firstDate ?? DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return withBarrierBlur(
          Theme(
            data: ThemeData(
              useMaterial3: true,
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF121212),
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Colors.black,
                secondary: Color(0xFF121212),
                onSecondary: Colors.white,
              ),
              datePickerTheme: DatePickerThemeData(
                backgroundColor: Colors.white,
                headerBackgroundColor: const Color(0xFF121212),
                headerForegroundColor: Colors.white,
                dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.white;
                  }
                  if (states.contains(WidgetState.disabled)) {
                    return Colors.black38;
                  }
                  return Colors.black;
                }),
                dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return const Color(0xFF121212);
                  }
                  return Colors.transparent;
                }),
                todayForegroundColor: const WidgetStatePropertyAll(Colors.black),
                todayBackgroundColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                todayBorder: const BorderSide(color: Color(0xFF121212)),
                confirmButtonStyle: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF121212),
                ),
                cancelButtonStyle: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                ),
              ),
            ),
            child: child!,
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      controller.text = _dateFormat.format(picked);
    });
  }

  void _confirm() {
    final name = _nameController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());
    final monthly = _parseDate(_monthlyController.text);
    final finalDate = _parseDate(_finalController.text);

    if (name.isEmpty ||
        amount == null ||
        amount <= 0 ||
        monthly == null ||
        finalDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter name, amount, and both dates as MM/DD/YYYY.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      _AddLoanDialogResult(
        name: name,
        amount: amount,
        monthlyDueDate: monthly,
        finalPaymentDate: finalDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Add Loan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 28),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Name',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _RecessedField(
                child: TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.black,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Amount',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _RecessedField(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.black,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'When is your monthly payment due?',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _DateInputField(
                controller: _monthlyController,
                onPick: () => _pickDate(controller: _monthlyController),
              ),
              const SizedBox(height: 22),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'When is your final loan payment?',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _DateInputField(
                controller: _finalController,
                onPick: () => _pickDate(
                  controller: _finalController,
                  firstDate: _parseDate(_monthlyController.text),
                ),
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: _confirm,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: const Text(
                  'Confirm',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF9CA3AF),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateInputField extends StatelessWidget {
  const _DateInputField({
    required this.controller,
    required this.onPick,
  });

  final TextEditingController controller;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return _RecessedField(
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.datetime,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
                LengthLimitingTextInputFormatter(10),
              ],
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Colors.black,
              ),
              decoration: const InputDecoration(
                hintText: 'MM/DD/YYY',
                hintStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Colors.black,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onPick,
            icon: const Icon(
              Icons.calendar_today_outlined,
              size: 20,
              color: Colors.black,
            ),
            tooltip: 'Pick date',
          ),
        ],
      ),
    );
  }
}

class _RecessedField extends StatelessWidget {
  const _RecessedField({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 3),
            spreadRadius: -1,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({
    required this.loan,
    required this.onOpen,
    required this.onConfirmDelete,
    required this.onDismissed,
  });

  final LoanEntry loan;
  final VoidCallback onOpen;
  final Future<bool> Function() onConfirmDelete;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final amountLabel = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: loan.amount % 1 == 0 ? 0 : 2,
    ).format(loan.amount);
    final monthlyLabel = DateFormat('MMM d, yyyy').format(
      loan.nextActionableDue ?? loan.monthlyDueDate,
    );
    final status = loan.status;
    final statusColor = switch (status) {
      LoanStatus.pending => const Color(0xFF6B7280),
      LoanStatus.late => const Color(0xFFDC2626),
      LoanStatus.paid => const Color(0xFF16A34A),
    };

    return Dismissible(
      key: ValueKey(loan.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
      ),
      confirmDismiss: (_) => onConfirmDelete(),
      onDismissed: (_) => onDismissed(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        amountLabel,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: loan.isFullyPaid
                              ? const Color(0xFF9CA3AF)
                              : Colors.black,
                          decoration: loan.isFullyPaid
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        loan.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        loan.isFullyPaid
                            ? 'Fully paid'
                            : '$monthlyLabel - ${loan.statusLabel}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  loan.statusLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
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

class _LoanScheduleDialog extends StatefulWidget {
  const _LoanScheduleDialog({required this.loanId});

  final String loanId;

  @override
  State<_LoanScheduleDialog> createState() => _LoanScheduleDialogState();
}

class _LoanScheduleDialogState extends State<_LoanScheduleDialog> {
  bool _paying = false;
  late final PageController _pageController;
  int _focusedIndex = 0;
  bool _didJumpToActionable = false;

  static const _cardExtent = 108.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.38);
    _pageController.addListener(() {
      final page = _pageController.page;
      if (page == null) return;
      final next = page.round();
      if (next != _focusedIndex && mounted) {
        setState(() => _focusedIndex = next);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _payInstallment(LoanEntry loan, DateTime due) async {
    if (_paying) return;
    final budget = context.read<BudgetProvider>();
    final loans = context.read<LoanProvider>();
    final billsLeft = budget.remainingFor(FinancialCategory.bills);

    if (loan.amount > billsLeft + 0.001) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Not enough Bills balance. Need ₱${loan.amount.toStringAsFixed(loan.amount % 1 == 0 ? 0 : 2)}, '
            'have ₱${billsLeft.toStringAsFixed(billsLeft % 1 == 0 ? 0 : 2)}.',
          ),
        ),
      );
      return;
    }

    setState(() => _paying = true);
    try {
      await budget.addEntry(
        FinancialCategory.bills,
        title: 'Loan · ${loan.name}',
        amount: loan.amount,
        iconAsset: 'assets/images/icons_bills/loan.png',
        awaitRemote: true,
      );
      await loans.markInstallmentPaid(
        loanId: loan.id,
        dueDate: due,
        paid: true,
      );
      if (!mounted) return;
      await _animateToNextPending(loan.id);
    } catch (error) {
      if (!mounted) return;
      if (FinanceApiException.isRateLimitError(error)) {
        // Rate-limit dialog is shown by BudgetProvider.
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ArgumentError
                ? error.message?.toString() ??
                      'Could not pay this installment from Bills.'
                : 'Could not pay this installment from Bills.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _animateToNextPending(String loanId) async {
    final loans = context.read<LoanProvider>();
    LoanEntry? updated;
    for (final item in loans.loans) {
      if (item.id == loanId) {
        updated = item;
        break;
      }
    }
    if (updated == null) return;

    final nextDue = updated.nextActionableDue;
    if (nextDue == null) return;

    final index = updated.installmentDates.indexWhere(
      (d) => LoanEntry.dayKey(d) == LoanEntry.dayKey(nextDue),
    );
    if (index < 0 || !_pageController.hasClients) return;

    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
    if (mounted) setState(() => _focusedIndex = index);
  }

  void _jumpToActionableIfNeeded(LoanEntry loan) {
    if (_didJumpToActionable) return;
    final actionable = loan.nextActionableDue;
    if (actionable == null) {
      _didJumpToActionable = true;
      return;
    }
    final index = loan.installmentDates.indexWhere(
      (due) => LoanEntry.dayKey(due) == LoanEntry.dayKey(actionable),
    );
    if (index < 0) {
      _didJumpToActionable = true;
      return;
    }
    _didJumpToActionable = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_pageController.hasClients) return;
      _pageController.jumpToPage(index);
      if (mounted) setState(() => _focusedIndex = index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loans = context.watch<LoanProvider>();
    LoanEntry? loan;
    for (final item in loans.loans) {
      if (item.id == widget.loanId) {
        loan = item;
        break;
      }
    }

    if (loan == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const SizedBox.shrink();
    }

    final current = loan;
    _jumpToActionableIfNeeded(current);
    final actionable = current.nextActionableDue;
    final amountLabel = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: current.amount % 1 == 0 ? 0 : 2,
    ).format(current.amount);
    final dates = current.installmentDates;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(36),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: () {
                final maxH = MediaQuery.sizeOf(context).height * 0.58;
                const preferred = _cardExtent * 4.2;
                return maxH < preferred ? maxH : preferred;
              }(),
              child: PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: dates.length,
                physics: const BouncingScrollPhysics(),
                itemBuilder: (context, index) {
                  final due = dates[index];
                  final status = current.installmentStatus(due);
                  final isActionable =
                      actionable != null &&
                      LoanEntry.dayKey(due) == LoanEntry.dayKey(actionable);

                  return AnimatedBuilder(
                    animation: _pageController,
                    builder: (context, child) {
                      var page = index.toDouble();
                      if (_pageController.hasClients &&
                          _pageController.position.haveDimensions) {
                        page = _pageController.page ?? page;
                      } else {
                        page = _focusedIndex.toDouble();
                      }

                      final delta = (page - index).clamp(-2.5, 2.5);
                      final abs = delta.abs();
                      final scale = (1 - abs * 0.08).clamp(0.82, 1.0);
                      final opacity = (1 - abs * 0.22).clamp(0.45, 1.0);
                      final yOffset = delta * 10;
                      final blurSigma = (abs * 5.5).clamp(0.0, 9.0);

                      Widget card = child!;
                      if (blurSigma > 0.15) {
                        card = ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: blurSigma,
                            sigmaY: blurSigma,
                            tileMode: TileMode.decal,
                          ),
                          child: card,
                        );
                      }

                      return Align(
                        alignment: Alignment.center,
                        child: Opacity(
                          opacity: opacity,
                          child: Transform.translate(
                            offset: Offset(0, yOffset),
                            child: Transform.scale(
                              scale: scale,
                              alignment: Alignment.center,
                              child: card,
                            ),
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: SizedBox(
                        height: _cardExtent,
                        child: _InstallmentCard(
                          amountLabel: amountLabel,
                          name: current.name,
                          due: due,
                          status: status,
                          showCheck: isActionable,
                          paying: _paying && isActionable,
                          onCheck: isActionable && !_paying
                              ? () => _payInstallment(current, due)
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _paying ? null : () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF9CA3AF),
              ),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstallmentCard extends StatelessWidget {
  const _InstallmentCard({
    required this.amountLabel,
    required this.name,
    required this.due,
    required this.status,
    required this.showCheck,
    this.paying = false,
    this.onCheck,
  });

  final String amountLabel;
  final String name;
  final DateTime due;
  final LoanStatus status;
  final bool showCheck;
  final bool paying;
  final VoidCallback? onCheck;

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('MMM d, yyyy').format(due);
    final showDate = status != LoanStatus.paid || showCheck;
    final dateText = status == LoanStatus.late
        ? '$dateLabel - LATE'
        : dateLabel;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  amountLabel,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
                if (showDate) ...[
                  const SizedBox(height: 2),
                  Text(
                    dateText,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showCheck)
            Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onCheck,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: paying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(
                          Icons.check,
                          size: 22,
                          color: Colors.black,
                          weight: 800,
                        ),
                ),
              ),
            )
          else
            Text(
              switch (status) {
                LoanStatus.paid => 'PAID',
                LoanStatus.pending => 'PENDING',
                LoanStatus.late => 'LATE',
              },
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
        ],
      ),
    );
  }
}

