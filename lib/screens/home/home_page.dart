import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/financial_entry.dart';
import '../../providers/budget_provider.dart';
import '../../widgets/app_refresh_indicator.dart';
import '../../widgets/weekly_spending_card.dart';
import '../savings/savings_goal_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late TextEditingController salaryController;
  late TextEditingController balanceController;
  late TextEditingController addMoneyController;
  late TextEditingController billsController;
  late TextEditingController savingsController;
  late TextEditingController personalController;
  bool _isReceivingSalary = false;
  bool _isAddingMoney = false;
  BudgetProvider? _budget;

  @override
  void initState() {
    super.initState();

    salaryController = TextEditingController();
    balanceController = TextEditingController();
    addMoneyController = TextEditingController();
    billsController = TextEditingController();
    savingsController = TextEditingController();
    personalController = TextEditingController();
  }

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

  void _onBudgetChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _budget?.removeListener(_onBudgetChanged);
    salaryController.dispose();
    balanceController.dispose();
    addMoneyController.dispose();
    billsController.dispose();
    savingsController.dispose();
    personalController.dispose();
    super.dispose();
  }

  void _showEditDialog() {
    final budget = context.read<BudgetProvider>();
    salaryController.text = budget.monthlySalary.toStringAsFixed(0);
    billsController.text = budget.billsPercentage.toStringAsFixed(0);
    savingsController.text = budget.savingsPercentage.toStringAsFixed(0);
    personalController.text = budget.personalPercentage.toStringAsFixed(0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
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
                _buildField(
                  label: 'Monthly Salary/Income',
                  controller: salaryController,
                  prefixText: '₱ ',
                ),
                const SizedBox(height: 16),
                _buildField(
                  label: 'Bills %',
                  controller: billsController,
                  suffixText: '%',
                ),
                const SizedBox(height: 16),
                _buildField(
                  label: 'Savings %',
                  controller: savingsController,
                  suffixText: '%',
                ),
                const SizedBox(height: 16),
                _buildField(
                  label: 'Personal %',
                  controller: personalController,
                  suffixText: '%',
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
                            double.tryParse(salaryController.text) ?? -1;
                        final billsPercentage =
                            double.tryParse(billsController.text) ?? 0;
                        final savingsPercentage =
                            double.tryParse(savingsController.text) ?? 0;
                        final personalPercentage =
                            double.tryParse(personalController.text) ?? 0;
                        final totalPercentage =
                            billsPercentage +
                            savingsPercentage +
                            personalPercentage;

                        if (monthlySalary < 0 ||
                            (totalPercentage - 100).abs() > 0.001) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Enter a valid salary and percentages totaling 100%',
                              ),
                            ),
                          );
                          return;
                        }

                        try {
                          await context.read<BudgetProvider>().updateBudget(
                            monthlySalary: monthlySalary,
                            billsPercentage: billsPercentage,
                            savingsPercentage: savingsPercentage,
                            personalPercentage: personalPercentage,
                          );
                          if (context.mounted) Navigator.pop(context);
                          if (mounted) setState(() {});
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
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
      ),
    );
  }

  void _showBalanceDialog() {
    final budget = context.read<BudgetProvider>();
    balanceController.text = budget.availableBalance.toStringAsFixed(0);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Edit Available Balance',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF121212),
                ),
              ),
              const SizedBox(height: 24),
              _buildField(
                label: 'Available Balance',
                controller: balanceController,
                prefixText: '₱ ',
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
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
                      final balance =
                          double.tryParse(balanceController.text) ?? -1;
                      if (balance < 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter a valid available balance.'),
                          ),
                        );
                        return;
                      }

                      try {
                        await budget.updateAvailableBalance(balance);
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        if (mounted) setState(() {});
                      } catch (_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Available balance could not be updated.',
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

  Future<void> _receiveSalary() async {
    if (_isReceivingSalary) return;

    final budget = context.read<BudgetProvider>();
    if (budget.monthlySalary <= 0) return;

    setState(() => _isReceivingSalary = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Receive monthly salary?'),
        content: Text(
          'Add ₱${NumberFormat('#,##0').format(budget.monthlySalary)} '
          'to your available balance?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Receive',
              style: TextStyle(
                color: Color(0xFF121212),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _isReceivingSalary = false);
      return;
    }

    try {
      await budget.receiveSalary();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Monthly salary added to your available balance.'),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Unable to receive salary. Please try again.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _isReceivingSalary = false);
    }
  }

  void _showAddMoneyDialog() {
    final budget = context.read<BudgetProvider>();
    addMoneyController.clear();
    var isSaving = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
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
                _buildField(
                  label: 'Amount',
                  controller: addMoneyController,
                  prefixText: '₱ ',
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: isSaving
                          ? null
                          : () => Navigator.pop(dialogContext),
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
                      onPressed: isSaving
                          ? null
                          : () async {
                              final amount =
                                  double.tryParse(addMoneyController.text) ??
                                  0;
                              if (amount <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Enter an amount greater than zero.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              setDialogState(() => isSaving = true);
                              if (mounted) {
                                setState(() => _isAddingMoney = true);
                              }
                              try {
                                await budget.addMoney(amount);
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                                if (!mounted) return;
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '₱${NumberFormat('#,##0').format(amount)} '
                                        'added to your available balance.',
                                      ),
                                    ),
                                  );
                              } catch (_) {
                                if (dialogContext.mounted) {
                                  setDialogState(() => isSaving = false);
                                }
                                if (!mounted) return;
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Unable to add money. Please try again.',
                                      ),
                                    ),
                                  );
                              } finally {
                                if (mounted) {
                                  setState(() => _isAddingMoney = false);
                                }
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
        ),
      ),
    );
  }

  Widget _buildField({
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
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixText: prefixText,
                suffixText: suffixText,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final budget = _budget ?? context.watch<BudgetProvider>();
    final screenHeight = MediaQuery.of(context).size.height;
    final headerHeight = screenHeight * 0.38;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      body: AppRefreshIndicator(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              Container(
                height: headerHeight,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [Color(0xFF262626), Color(0xFF000000)],
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.grey[700],
                          backgroundImage: user?.photoURL != null
                              ? NetworkImage(user!.photoURL!)
                              : null,
                          child: user?.photoURL == null
                              ? Icon(
                                  Icons.person,
                                  size: 32,
                                  color: Colors.grey[300],
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName ?? 'User',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user?.email ?? 'No email',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[400],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ),
                    Center(
                      child: SizedBox(
                        height: 120,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    'Income',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.grey[400],
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Flexible(
                                        child: _AnimatedCurrencyAmount(
                                          amount: budget.monthlySalary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: _showEditDialog,
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[700],
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.edit,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 30,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Container(
                                    width: 1.5,
                                    height: 100,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    'Available Balance',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.grey[400],
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Flexible(
                                        child: _AnimatedCurrencyAmount(
                                          amount: budget.availableBalance,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: _showBalanceDialog,
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[700],
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.edit,
                                            size: 16,
                                            color: Colors.white,
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
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: budget.monthlySalary <= 0
                              ? TextButton(
                                  onPressed: _showEditDialog,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                  ),
                                  child: const Text(
                                    'Set monthly salary',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 13),
                                  ),
                                )
                              : SizedBox(
                                  height: 42,
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _isReceivingSalary
                                        ? null
                                        : _receiveSalary,
                                    style: ElevatedButton.styleFrom(
                                      foregroundColor: Colors.black,
                                      backgroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          Colors.grey.shade300,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                    ),
                                    icon: _isReceivingSalary
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.black,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.account_balance_wallet,
                                            size: 18,
                                          ),
                                    label: const Text(
                                      'Receive Salary',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 30),
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed:
                                  _isAddingMoney ? null : _showAddMoneyDialog,
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.black,
                                backgroundColor: Colors.white,
                                disabledBackgroundColor: Colors.grey.shade300,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                              ),
                              icon: _isAddingMoney
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                  : const Icon(Icons.add_circle_outline, size: 18),
                              label: const Text(
                                'Add Money',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _BuildGridCard(
                        amount: NumberFormat(
                          '#,##0.##',
                        ).format(budget.remainingFor(FinancialCategory.bills)),
                        label: 'BILLS',
                        gradientColors: const [
                          Color(0xFF333333),
                          Color(0xFF000000),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _BuildGridCard(
                        amount: NumberFormat('#,##0.##').format(
                          budget.remainingFor(FinancialCategory.savings),
                        ),
                        label: 'SAVINGS',
                        gradientColors: const [
                          Color(0xFF333333),
                          Color(0xFF000000),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _BuildGridCard(
                        amount: NumberFormat('#,##0.##').format(
                          budget.remainingFor(FinancialCategory.personal),
                        ),
                        label: 'PERSONAL',
                        gradientColors: const [
                          Color(0xFF333333),
                          Color(0xFF000000),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: WeeklySpendingCard(),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(28, 8, 28, 8),
                child: _QuickActionsRow(),
              ),
              // Clear the floating bottom navigation bar.
              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _SavingsProgressAction(),
        _FilledIconAction(
          assetPath: 'assets/images/icons/loan.png',
          label: 'Loan',
        ),
        _FilledIconAction(
          assetPath: 'assets/images/icons/calendar.png',
          label: 'Calendar',
        ),
      ],
    );
  }
}

class _SavingsProgressAction extends StatelessWidget {
  const _SavingsProgressAction();

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<BudgetProvider>().savingsGoalProgress;

    return Semantics(
      button: true,
      label: 'Savings Goal',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SavingsGoalPage(),
              ),
            );
          },
          child: SizedBox(
            width: 74,
            height: 74,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 74,
                  height: 74,
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(progress.toStringAsFixed(4)),
                    tween: Tween<double>(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) {
                      return CircularProgressIndicator(
                        value: value <= 0 ? 0.001 : value,
                        strokeWidth: 10.5,
                        strokeCap: StrokeCap.round,
                        backgroundColor: const Color(0xFF121212),
                        color: const Color(0xFFD6C4A3),
                      );
                    },
                  ),
                ),
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Image.asset(
                    'assets/images/icons/piggybank.png',
                    fit: BoxFit.contain,
                    color: const Color(0xFF121212),
                    colorBlendMode: BlendMode.srcIn,
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

class _FilledIconAction extends StatelessWidget {
  const _FilledIconAction({
    required this.assetPath,
    required this.label,
  });

  final String assetPath;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(15),
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          alignment: Alignment.center,
        ),
      ),
    );
  }
}

class _AnimatedCurrencyAmount extends StatelessWidget {
  const _AnimatedCurrencyAmount({required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: amount),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '₱${NumberFormat('#,##0').format(value)}',
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _BuildGridCard extends StatelessWidget {
  final String amount;
  final String label;
  final List<Color> gradientColors;

  const _BuildGridCard({
    required this.amount,
    required this.label,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              amount,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
