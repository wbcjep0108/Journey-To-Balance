import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/financial_entry.dart';
import '../../providers/budget_provider.dart';
import '../../widgets/savings_goal_complete_dialog.dart';
import '../../widgets/sensitive_action_auth.dart';

class SavingsGoalPage extends StatefulWidget {
  const SavingsGoalPage({super.key});

  static String categoryLabel(FinancialCategory category) {
    return switch (category) {
      FinancialCategory.bills => 'Bills',
      FinancialCategory.savings => 'Savings',
      FinancialCategory.personal => 'Personal',
    };
  }

  @override
  State<SavingsGoalPage> createState() => _SavingsGoalPageState();
}

class _SavingsGoalPageState extends State<SavingsGoalPage> {
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
    final current = budget.savingsGoalCurrent;
    final target = budget.savingsGoalTarget;
    final progress = budget.savingsGoalProgress;
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱ ',
      decimalDigits: current % 1 == 0 ? 0 : 2,
    );
    final goalCurrency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱ ',
      decimalDigits: target % 1 == 0 ? 0 : 2,
    );
    final targetDateLabel = DateFormat(
      'MMMM d, yyyy',
    ).format(budget.savingsGoalTargetDate);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F7F8),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text(
          'Savings Goal',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _SavingsGoalInfoButton(
              onPressed: () => _showSavingsGoalInfo(context),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _GoalHeader(
              currentLabel: currency.format(current),
              goalLabel: goalCurrency.format(target),
              progress: progress,
              goalTitle: budget.savingsGoalTitle,
              targetDateLabel: targetDateLabel,
              onEditGoal: () => _editGoal(context, budget),
              onEditTitle: () => _editTitle(context, budget),
              onEditDate: () => _editDate(context, budget),
            ),
            const SizedBox(height: 28),
            _QuickActionCardsRow(
              onCategoryTap: (category) =>
                  _showContributeModal(context, category),
            ),
            const SizedBox(height: 32),
            const Text(
              'Recent Activity:',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF121212),
              ),
            ),
            const SizedBox(height: 14),
            _RecentActivityList(items: budget.savingsGoalActivity),
          ],
        ),
      ),
    );
  }

  Future<void> _editGoal(BuildContext context, BudgetProvider budget) async {
    final controller = TextEditingController(
      text: budget.savingsGoalTarget.toStringAsFixed(0),
    );

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Edit Goal Savings',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF121212),
                  ),
                ),
                const SizedBox(height: 22),
                _AmountField(label: 'Goal Amount', controller: controller),
                const SizedBox(height: 24),
                _ConfirmButton(
                  label: 'Confirm',
                  onPressed: () async {
                    final amount = double.tryParse(controller.text) ?? 0;
                    if (amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Enter a goal greater than zero.'),
                        ),
                      );
                      return;
                    }
                    // Apply optimistic update before closing the dialog.
                    try {
                      await budget.updateSavingsGoalSettings(
                        target: amount,
                        targetDate: budget.savingsGoalTargetDate,
                      );
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not update savings goal.'),
                          ),
                        );
                      }
                    }
                  },
                ),
                _CancelButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(controller.dispose);

    if (saved != true) return;
  }

  Future<void> _editTitle(BuildContext context, BudgetProvider budget) async {
    final controller = TextEditingController(text: budget.savingsGoalTitle);

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Edit Goal Title',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF121212),
                  ),
                ),
                const SizedBox(height: 22),
                _TextField(label: 'What are you saving for?', controller: controller),
                const SizedBox(height: 24),
                _ConfirmButton(
                  label: 'Confirm',
                  onPressed: () async {
                    final title = controller.text.trim();
                    if (title.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Enter a goal title.'),
                        ),
                      );
                      return;
                    }
                    try {
                      await budget.updateSavingsGoalSettings(
                        target: budget.savingsGoalTarget,
                        targetDate: budget.savingsGoalTargetDate,
                        title: title,
                      );
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not update goal title.'),
                          ),
                        );
                      }
                    }
                  },
                ),
                _CancelButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(controller.dispose);

    if (saved != true) return;
  }

  Future<void> _editDate(BuildContext context, BudgetProvider budget) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: budget.savingsGoalTargetDate,
      firstDate: DateTime(DateTime.now().year, DateTime.now().month, 1),
      lastDate: DateTime(DateTime.now().year + 30),
      helpText: 'Select target date',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF121212),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF121212),
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Colors.white,
            ),
            datePickerTheme: const DatePickerThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              headerBackgroundColor: Colors.white,
              headerForegroundColor: Color(0xFF121212),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !context.mounted) return;

    try {
      await budget.updateSavingsGoalSettings(
        target: budget.savingsGoalTarget,
        targetDate: picked,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update target date.')),
      );
    }
  }

  Future<void> _showContributeModal(
    BuildContext context,
    FinancialCategory category,
  ) async {
    final completed = await showContributeToGoalModal(
      context: context,
      category: category,
    );
    if (completed != true || !context.mounted) return;

    final budget = context.read<BudgetProvider>();
    await SavingsGoalCompleteDialog.show(
      context: context,
      goalTitle: budget.savingsGoalTitle,
      targetAmount: budget.savingsGoalTarget,
    );
  }

  Future<void> _showSavingsGoalInfo(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'About Savings Goal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF121212),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'The Savings Goal is completely up to you. You can save the money '
                  'wherever you prefer, such as your wallet, bank account, e-wallet, '
                  'or any other place you use to keep your savings.\n\n'
                  'This feature only helps you set a goal and track your savings '
                  'progress. It does not store or transfer your money.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                    color: Color(0xFF4B5563),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext),
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
                      'Got it',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SavingsGoalInfoButton extends StatelessWidget {
  const _SavingsGoalInfoButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'About Savings Goal',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Ink(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF9CA3AF), width: 1.5),
            ),
            child: const Center(
              child: Text(
                '?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Returns `true` when the contribution just completed the savings goal.
Future<bool?> showContributeToGoalModal({
  required BuildContext context,
  required FinancialCategory category,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _ContributeToGoalModal(category: category);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _ContributeToGoalModal extends StatefulWidget {
  const _ContributeToGoalModal({required this.category});

  final FinancialCategory category;

  @override
  State<_ContributeToGoalModal> createState() => _ContributeToGoalModalState();
}

class _ContributeToGoalModalState extends State<_ContributeToGoalModal> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_saving) return;
    final budget = context.read<BudgetProvider>();
    final amount = double.tryParse(_controller.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount greater than zero.')),
      );
      return;
    }
    if (amount > budget.remainingFor(widget.category) + 0.001) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Only ₱${NumberFormat('#,##0.##').format(budget.remainingFor(widget.category))} '
            'left in ${SavingsGoalPage.categoryLabel(widget.category)}.',
          ),
        ),
      );
      return;
    }

    final category = widget.category;
    final messenger = ScaffoldMessenger.of(context);
    final previousCurrent = budget.savingsGoalCurrent;
    final goalTarget = budget.savingsGoalTarget;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);

    try {
      // Optimistic update BEFORE closing so the page already shows new totals.
      await budget.contributeToSavingsGoal(
        source: category,
        amount: amount,
      );
      final justCompleted =
          previousCurrent < goalTarget - 0.001 &&
          budget.savingsGoalCurrent >= goalTarget - 0.001;
      if (mounted) Navigator.pop(context, justCompleted);
      if (!justCompleted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                '₱${NumberFormat('#,##0.##').format(amount)} added to your savings goal.',
              ),
            ),
          );
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not add to savings goal.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final budget = context.watch<BudgetProvider>();
    final remaining = budget.remainingFor(widget.category);
    final remainingLabel = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: remaining % 1 == 0 ? 0 : 2,
    ).format(remaining);
    final title = 'From ${SavingsGoalPage.categoryLabel(widget.category)}';

    return Center(
      child: Material(
        color: Colors.transparent,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (!_saving) Navigator.pop(context);
            },
          },
          child: Focus(
            autofocus: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
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
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF121212),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        remainingLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF121212),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Available in ${SavingsGoalPage.categoryLabel(widget.category)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'How much would you like to save today?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF121212),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _AmountField(
                        label: 'Amount',
                        controller: _controller,
                        enabled: !_saving,
                      ),
                      const SizedBox(height: 28),
                      _ConfirmButton(
                        label: 'Confirm',
                        isLoading: _saving,
                        onPressed: _confirm,
                      ),
                      _CancelButton(
                        onPressed: _saving ? null : () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalHeader extends StatelessWidget {
  const _GoalHeader({
    required this.currentLabel,
    required this.goalLabel,
    required this.progress,
    required this.goalTitle,
    required this.targetDateLabel,
    required this.onEditGoal,
    required this.onEditTitle,
    required this.onEditDate,
  });

  final String currentLabel;
  final String goalLabel;
  final double progress;
  final String goalTitle;
  final String targetDateLabel;
  final VoidCallback onEditGoal;
  final VoidCallback onEditTitle;
  final VoidCallback onEditDate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Opacity(
              opacity: 0.10,
              child: Image.asset(
                'assets/images/icons/piggybank.png',
                width: 230,
                height: 230,
                color: const Color(0xFF9CA3AF),
                colorBlendMode: BlendMode.srcIn,
              ),
            ),
          ),
          Column(
            children: [
              SizedBox(
                width: 190,
                height: 190,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 190,
                      height: 190,
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(progress.toStringAsFixed(6)),
                        tween: Tween<double>(begin: 0, end: progress),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) {
                          return CircularProgressIndicator(
                            value: value <= 0 ? 0.001 : value,
                            strokeWidth: 14,
                            strokeCap: StrokeCap.round,
                            backgroundColor: const Color(0xFF121212),
                            color: const Color(0xFFD6C4A3),
                          );
                        },
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currentLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF121212),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Saved',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              InkWell(
                onTap: onEditGoal,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        goalLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF121212),
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit,
                          size: 16,
                          color: Color(0xFF121212),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: onEditTitle,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    goalTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF121212),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: onEditDate,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    'Target date: $targetDateLabel',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionCardsRow extends StatelessWidget {
  const _QuickActionCardsRow({required this.onCategoryTap});

  final ValueChanged<FinancialCategory> onCategoryTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionCard(
            assetPath: 'assets/images/icons/bills.png',
            label: 'Bills',
            onTap: () => onCategoryTap(FinancialCategory.bills),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionCard(
            assetPath: 'assets/images/icons/savings.png',
            label: 'Savings',
            onTap: () => onCategoryTap(FinancialCategory.savings),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionCard(
            assetPath: 'assets/images/icons/personal.png',
            label: 'Personal',
            onTap: () => onCategoryTap(FinancialCategory.personal),
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.assetPath,
    required this.label,
    required this.onTap,
  });

  final String assetPath;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 18,
              offset: const Offset(0, 8),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 88,
              width: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    assetPath,
                    width: 30,
                    height: 30,
                    color: const Color(0xFF121212),
                    colorBlendMode: BlendMode.srcIn,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF3F444C),
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

class _RecentActivityList extends StatelessWidget {
  const _RecentActivityList({required this.items});

  final List<DayTransaction> items;

  Future<bool> _confirmDelete(
    BuildContext context,
    DayTransaction item,
  ) async {
    final authorized = await showSensitiveActionAuth(
      context: context,
      title: 'Undo contribution',
      description:
          'Enter your PIN or use fingerprint to return '
          '₱${NumberFormat('#,##0.##').format(item.entry.amount)} '
          'to ${SavingsGoalPage.categoryLabel(item.category)}.',
    );
    if (!authorized || !context.mounted) return false;

    try {
      await context.read<BudgetProvider>().deleteEntry(
        item.category,
        item.entry,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                '₱${NumberFormat('#,##0.##').format(item.entry.amount)} '
                'returned to ${SavingsGoalPage.categoryLabel(item.category)}.',
              ),
            ),
          );
      }
      return true;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not undo this contribution.')),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          'No savings activity yet.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade500,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            Dismissible(
              key: ValueKey(items[i].entry.id),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) => _confirmDelete(context, items[i]),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE11D48),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Delete',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'From ${SavingsGoalPage.categoryLabel(items[i].category)}',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF121212),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat(
                              'MMM d, yyyy',
                            ).format(items[i].entry.createdAt.toLocal()),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '+₱${NumberFormat('#,##0.##').format(items[i].entry.amount)}',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF5CB450),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i < items.length - 1)
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
          ],
        ],
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.label,
    required this.controller,
    this.enabled = true,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
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
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
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
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF121212),
            ),
            decoration: const InputDecoration(
              prefixText: '₱ ',
              prefixStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF121212),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.label,
    required this.controller,
  });

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
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
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
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
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF121212),
            ),
            decoration: const InputDecoration(
              counterText: '',
              hintText: 'e.g. Baguio trip',
              hintStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF9CA3AF),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _ConfirmButton extends StatefulWidget {
  const _ConfirmButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  State<_ConfirmButton> createState() => _ConfirmButtonState();
}

class _ConfirmButtonState extends State<_ConfirmButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed?.call();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.5,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: double.infinity,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black, width: 1.3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _pressed ? 0.04 : 0.08),
                  blurRadius: _pressed ? 8 : 14,
                  offset: Offset(0, _pressed ? 2 : 5),
                ),
              ],
            ),
            child: widget.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : Text(
                    widget.label,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: const Color(0xFF8A8F98)),
      child: const Text(
        'Cancel',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
