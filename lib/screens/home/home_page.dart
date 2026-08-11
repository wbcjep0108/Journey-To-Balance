import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/budget_provider.dart';
import '../../widgets/allocation_confirm_dialog.dart';
import '../../widgets/app_refresh_indicator.dart';
import '../../widgets/rate_limit_dialog.dart';
import '../../widgets/sensitive_action_auth.dart';
import '../../widgets/weekly_spending_card.dart';
import '../savings/savings_goal_page.dart';
import 'home_money_dialogs.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isReceivingSalary = false;
  bool _isAddingMoney = false;
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

  void _onBudgetChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _budget?.removeListener(_onBudgetChanged);
    super.dispose();
  }

  void _showEditDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SalarySetupDialog(
        hostContext: context,
        onSaved: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  void _showBalanceDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => BalanceEditDialog(
        hostContext: context,
        onSaved: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Future<void> _receiveSalary() async {
    if (_isReceivingSalary) return;

    final budget = context.read<BudgetProvider>();
    if (budget.monthlySalary <= 0) return;

    setState(() => _isReceivingSalary = true);
    final confirmed = await AllocationConfirmDialog.showNewMoneyConfirm(
      context: context,
      kind: AllocationConfirmKind.receiveSalary,
      amount: budget.monthlySalary,
      billsPercentage: budget.billsPercentage,
      savingsPercentage: budget.savingsPercentage,
      personalPercentage: budget.personalPercentage,
    );

    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _isReceivingSalary = false);
      return;
    }

    final authorized = await showSensitiveActionAuth(
      context: context,
      title: 'Confirm receive salary',
      description:
          'Enter your PIN or use fingerprint to add your salary '
          'to available balance.',
    );
    if (!mounted) return;
    if (authorized != true) {
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
    } catch (error) {
      if (!mounted) return;
      if (isFinanceRateLimitError(error)) return;
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
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddMoneyDialog(
        hostContext: context,
        onBusyChanged: (busy) {
          if (mounted) setState(() => _isAddingMoney = busy);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final budget = _budget ?? context.watch<BudgetProvider>();
    final media = MediaQuery.of(context);
    final screenHeight = media.size.height;
    final headerHeight = screenHeight * 0.38;
    // Floating bottom nav (~72) + gap (24) + home-indicator safe area + buffer.
    final bottomScrollPadding = media.padding.bottom + 168;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      body: AppRefreshIndicator(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: bottomScrollPadding),
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
                  vertical: 16,
                ),
                child: _CategoryCardsRow(
                  billsAmount: NumberFormat(
                    '#,##0.##',
                  ).format(budget.billsAmount),
                  savingsAmount: NumberFormat(
                    '#,##0.##',
                  ).format(budget.savingsAmount),
                  personalAmount: NumberFormat(
                    '#,##0.##',
                  ).format(budget.personalAmount),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: WeeklySpendingCard(),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(28, 16, 28, 8),
                child: _QuickActionsRow(),
              ),
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

class _SavingsProgressAction extends StatefulWidget {
  const _SavingsProgressAction();

  @override
  State<_SavingsProgressAction> createState() => _SavingsProgressActionState();
}

class _SavingsProgressActionState extends State<_SavingsProgressAction> {
  @override
  Widget build(BuildContext context) {
    final budget = context.watch<BudgetProvider>();
    final progress = budget.savingsGoalProgress;

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
            ).then((_) {
              if (mounted) setState(() {});
            });
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

class _CategoryCardsRow extends StatelessWidget {
  const _CategoryCardsRow({
    required this.billsAmount,
    required this.savingsAmount,
    required this.personalAmount,
  });

  final String billsAmount;
  final String savingsAmount;
  final String personalAmount;

  static const _gradient = [Color(0xFF333333), Color(0xFF000000)];

  @override
  Widget build(BuildContext context) {
    final cards = [
      (amount: billsAmount, label: 'BILLS'),
      (amount: savingsAmount, label: 'SAVINGS'),
      (amount: personalAmount, label: 'PERSONAL'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        // Keep all 3 cards on one row; tighten gaps on narrow phones.
        final gap = available < 340 ? 6.0 : (available < 380 ? 8.0 : 10.0);
        final cardWidth = (available - gap * 2) / 3;
        final cardHeight = (cardWidth * 1.45).clamp(120.0, 160.0);
        final horizontalPad = (cardWidth * 0.08).clamp(4.0, 10.0);
        final amountFontSize = (cardWidth * 0.18).clamp(12.0, 20.0);
        final labelFontSize = (cardWidth * 0.095).clamp(8.5, 12.0);
        final letterSpacing = available < 360 ? 0.4 : 1.0;

        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(
                child: _BuildGridCard(
                  amount: cards[i].amount,
                  label: cards[i].label,
                  height: cardHeight,
                  horizontalPadding: horizontalPad,
                  amountFontSize: amountFontSize,
                  labelFontSize: labelFontSize,
                  letterSpacing: letterSpacing,
                  gradientColors: _gradient,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _BuildGridCard extends StatelessWidget {
  final String amount;
  final String label;
  final double height;
  final double horizontalPadding;
  final double amountFontSize;
  final double labelFontSize;
  final double letterSpacing;
  final List<Color> gradientColors;

  const _BuildGridCard({
    required this.amount,
    required this.label,
    required this.height,
    required this.horizontalPadding,
    required this.amountFontSize,
    required this.labelFontSize,
    required this.letterSpacing,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                amount,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: amountFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: labelFontSize,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: letterSpacing,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
