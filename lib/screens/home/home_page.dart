import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/budget_plan.dart';
import '../../providers/budget_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/planner_provider.dart';
import '../../providers/wallet_cards_provider.dart';
import '../../providers/wallet_cash_provider.dart';
import '../../widgets/allocation_confirm_dialog.dart';
import '../../widgets/app_refresh_indicator.dart';
import '../../widgets/barrier_blur.dart';
import '../../widgets/rate_limit_dialog.dart';
import '../../widgets/sensitive_action_auth.dart';
import '../../widgets/foreign_exchange_card.dart';
import '../../widgets/planner_progress_bar.dart';
import '../../widgets/weekly_spending_card.dart';
import '../loans/total_loan_page.dart';
import '../savings/savings_goal_page.dart';
import 'budget_planner_page.dart';
import 'home_money_dialogs.dart';
import 'monthly_spending_dashboard_page.dart';
import 'thirteenth_month_screen.dart';
import 'wallet_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.onProfileTap,
    this.showFinishSetup = false,
    this.onFinishSetup,
  });

  final VoidCallback? onProfileTap;
  final bool showFinishSetup;
  final VoidCallback? onFinishSetup;

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
      builder: (_) => withBarrierBlur(
        SalarySetupDialog(
          hostContext: context,
          onSaved: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  void _showBalanceDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => withBarrierBlur(
        BalanceEditDialog(
          hostContext: context,
          onSaved: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> _receiveSalary() async {
    if (_isReceivingSalary) return;

    final budget = context.read<BudgetProvider>();
    if (budget.monthlySalary <= 0) return;
    final salary = budget.monthlySalary;

    setState(() => _isReceivingSalary = true);
    final source = await showDialog<MoneyDepositSource>(
      context: context,
      builder: (_) => withBarrierBlur(
        MoneyDepositSourceDialog(
          hostContext: context,
          title: 'Where should the salary go?',
          description: 'Choose the wallet or card that received your salary.',
        ),
      ),
    );
    if (!mounted) return;
    if (source == null) {
      setState(() => _isReceivingSalary = false);
      return;
    }

    final confirmed = await AllocationConfirmDialog.showNewMoneyConfirm(
      context: context,
      kind: AllocationConfirmKind.receiveSalary,
      amount: salary,
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
      if (source.isWallet) {
        final wallet = context.read<WalletCashProvider>();
        await wallet.setAmount(wallet.amount + salary);
      } else {
        final cards = context.read<WalletCardsProvider>();
        final card = cards.cardById(source.cardId!);
        if (card != null) {
          await cards.setCardAmount(
            cardId: card.id,
            amount: card.amount + salary,
          );
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Monthly salary added to ${source.label} and your available balance.',
            ),
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
      builder: (_) => withBarrierBlur(
        AddMoneyDialog(
          hostContext: context,
          onBusyChanged: (busy) {
            if (mounted) setState(() => _isAddingMoney = busy);
          },
        ),
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
                        Expanded(
                          child: Semantics(
                            button: true,
                            label: 'Open account profile',
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: widget.onProfileTap,
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 6,
                                  ),
                                  child: Row(
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
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Wallet',
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const WalletPage(),
                              ),
                            );
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                          icon: const Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 22,
                            color: Colors.white,
                          ),
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
                                              color: Color(0xFF121212),
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
                              onPressed: _isAddingMoney
                                  ? null
                                  : _showAddMoneyDialog,
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
                                        color: Color(0xFF121212),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.add_circle_outline,
                                      size: 18,
                                    ),
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
              if (widget.showFinishSetup)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: FinishSetupCard(onTap: widget.onFinishSetup),
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
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _HomePlannerCard(),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: WeeklySpendingCard(),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(0, 10, 0, 8),
                child: QuickActionRow(),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: ForeignExchangeCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FinishSetupCard extends StatelessWidget {
  const FinishSetupCard({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF1F2F4),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white,
                child: Icon(Icons.tune_rounded, color: Color(0xFF121212)),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Finish setup',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Add your income, starting money, and reminders.',
                      style: TextStyle(color: Color(0xFF737983)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomePlannerCard extends StatelessWidget {
  const _HomePlannerCard();

  @override
  Widget build(BuildContext context) {
    final planner = context.watch<PlannerProvider>();
    final currency = context.watch<CurrencyProvider>();
    final plan = planner.plan;
    final progress = planner.progress;

    return Semantics(
      button: true,
      label: 'Open Budget Planner',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BudgetPlannerPage(),
              ),
            );
          },
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE8EAED)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.event_note_outlined, size: 21),
                    SizedBox(width: 9),
                    Text(
                      'Budget Planner',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF121212),
                      ),
                    ),
                    Spacer(),
                    Icon(Icons.chevron_right_rounded, size: 22),
                  ],
                ),
                const SizedBox(height: 10),
                if (plan == null)
                  const Text(
                    'Set a budget plan',
                    style: TextStyle(fontSize: 13, color: Color(0xFF747C89)),
                  )
                else ...[
                  Text(
                    plannerPeriodSummary(plan),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF747C89),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    DateTime.now().isBefore(plan.localStart)
                        ? plannerStatusLabel(plan, planner.spent)
                        : '${currency.formatAmount(planner.spent)} of '
                              '${currency.formatAmount(plan.total)} spent',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF121212),
                    ),
                  ),
                  const SizedBox(height: 12),
                  PlannerProgressBar(
                    progress: progress,
                    height: 6,
                    trackColor: const Color(0xFFE1E4E8),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QuickActionRow extends StatelessWidget {
  const QuickActionRow({super.key, this.buttonSize = 64});

  final double buttonSize;

  @override
  Widget build(BuildContext context) {
    final planner = context.watch<PlannerProvider>();
    final actions = <Widget>[
      _SavingsProgressAction(size: buttonSize),
      _FilledIconAction(
        size: buttonSize,
        icon: Icons.account_balance_outlined,
        label: 'Loan',
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TotalLoanPage()),
          );
        },
      ),
      _FilledIconAction(
        size: buttonSize,
        icon: Icons.calendar_month_outlined,
        label: 'Calendar',
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const MonthlySpendingDashboardPage(),
            ),
          );
        },
      ),
      _PlannerAction(
        size: buttonSize,
        progress: planner.progress,
        hasPlan: planner.hasPlan,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const BudgetPlannerPage()),
          );
        },
      ),
      _FilledIconAction(
        size: buttonSize,
        icon: Icons.card_giftcard_rounded,
        label: '13th Month Pay Calculator',
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ThirteenthMonthScreen(),
            ),
          );
        },
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final count = actions.length;
        final fits =
            count * buttonSize + (count - 1) * 12 + 2 * 20 <=
            constraints.maxWidth;

        // Progress rings and button shadows paint slightly outside their
        // nominal size. Keep them away from the horizontal viewport's clip
        // edge so they remain intact while the row is being dragged.
        return SizedBox(
          height: buttonSize + 20,
          child: fits
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: actions,
                    ),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  itemCount: actions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, index) => actions[index],
                ),
        );
      },
    );
  }
}

class _PlannerAction extends StatelessWidget {
  const _PlannerAction({
    required this.progress,
    required this.hasPlan,
    required this.onTap,
    this.size = 64,
  });

  final double progress;
  final bool hasPlan;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final statusColor = progress > 1
        ? const Color(0xFFDC2626)
        : progress >= 0.8
        ? const Color(0xFFF59E0B)
        : const Color(0xFF16A34A);
    final ringProgress = hasPlan
        ? (progress <= 0 ? 0.001 : progress.clamp(0.0, 1.0))
        : 0.0;

    return Tooltip(
      message: 'Budget Planner',
      child: Semantics(
        label: 'Budget Planner',
        button: true,
        child: SizedBox(
          width: size,
          height: size,
          child: InkResponse(
            onTap: onTap,
            radius: size / 2,
            customBorder: const CircleBorder(),
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: ringProgress,
                  strokeWidth: 8,
                  strokeCap: StrokeCap.round,
                  backgroundColor: const Color(0xFF121212),
                  color: statusColor,
                ),
                Center(
                  child: Container(
                    width: size - 16,
                    height: size - 16,
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
                    padding: const EdgeInsets.all(8),
                    child: const Icon(
                      Icons.event_note_outlined,
                      size: 26,
                      color: Color(0xFF121212),
                    ),
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

class _SavingsProgressAction extends StatefulWidget {
  const _SavingsProgressAction({this.size = 64});

  final double size;

  @override
  State<_SavingsProgressAction> createState() => _SavingsProgressActionState();
}

class _SavingsProgressActionState extends State<_SavingsProgressAction> {
  @override
  Widget build(BuildContext context) {
    final budget = context.watch<BudgetProvider>();
    final progress = budget.savingsGoalProgress;
    final size = widget.size;

    return Tooltip(
      message: 'Savings Goal',
      child: Semantics(
        button: true,
        label: 'Savings Goal',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SavingsGoalPage(),
                    ),
                  )
                  .then((_) {
                    if (mounted) setState(() {});
                  });
            },
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    key: ValueKey(progress.toStringAsFixed(4)),
                    tween: Tween<double>(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) {
                      return CircularProgressIndicator(
                        value: value <= 0 ? 0.001 : value,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor: const Color(0xFF121212),
                        color: const Color(0xFFD6C4A3),
                      );
                    },
                  ),
                  Center(
                    child: Container(
                      width: size - 16,
                      height: size - 16,
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
                      padding: const EdgeInsets.all(8),
                      child: const Icon(
                        Icons.savings_outlined,
                        size: 26,
                        color: Color(0xFF121212),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilledIconAction extends StatelessWidget {
  const _FilledIconAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.size = 64,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: size,
              height: size,
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
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
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
    final symbol = context.watch<CurrencyProvider>().symbol;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: amount),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$symbol${NumberFormat('#,##0').format(value)}',
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
