import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/budget_plan.dart';
import '../../models/financial_entry.dart';
import '../../models/spend_category_option.dart';
import '../../providers/budget_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/planner_provider.dart';
import '../../widgets/barrier_blur.dart';
import '../../widgets/category_icon_badge.dart';
import '../../widgets/planner_progress_bar.dart';

class BudgetPlannerPage extends StatefulWidget {
  const BudgetPlannerPage({super.key});

  @override
  State<BudgetPlannerPage> createState() => _BudgetPlannerPageState();
}

class _BudgetPlannerPageState extends State<BudgetPlannerPage> {
  final Map<FinancialCategory, TextEditingController> _controllers = {
    for (final category in FinancialCategory.values)
      category: TextEditingController(),
  };
  final Map<FinancialCategory, FocusNode> _focusNodes = {
    for (final category in FinancialCategory.values) category: FocusNode(),
  };
  final Set<FinancialCategory> _enabled = <FinancialCategory>{};

  PlannerPeriod _period = PlannerPeriod.day;
  late DateTime _start;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day + 1);
    for (final controller in _controllers.values) {
      controller.addListener(_onDraftChanged);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final plan = context.read<PlannerProvider>().plan;
    if (plan == null) return;
    _period = plan.period;
    _start = plan.start;
    _enabled.addAll(plan.enabledCategories);
    for (final entry in plan.amounts.entries) {
      _controllers[entry.key]!.text = _editableAmount(entry.value);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller
        ..removeListener(_onDraftChanged)
        ..dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  Map<FinancialCategory, double> get _amounts => {
    for (final entry in _controllers.entries)
      entry.key: double.tryParse(entry.value.text.replaceAll(',', '')) ?? 0,
  };

  double get _total => plannerTotal(_enabled, _amounts);

  bool get _canSave {
    final today = DateUtils.dateOnly(DateTime.now());
    return !_start.isBefore(today) &&
        isPlannerDraftValid(_enabled, _amounts) &&
        !context.read<PlannerProvider>().isSaving;
  }

  BudgetPlan get _draftPlan => BudgetPlan(
    id: 'draft',
    period: _period,
    start: DateUtils.dateOnly(_start),
    endExclusive: _period.endExclusive(_start),
    amounts: {for (final category in _enabled) category: _amounts[category]!},
    createdAt: DateTime.now(),
    alertEligible: true,
  );

  double _draftSpent(BudgetProvider budget) {
    return plannerSpent(_draftPlan, {
      for (final category in FinancialCategory.values)
        category: budget.entriesFor(category),
    });
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final initial = _start.isBefore(today) ? today : _start;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: DateTime(today.year + 10, 12, 31),
      helpText: 'Choose plan start date',
      builder: (context, child) {
        return withBarrierBlur(
          Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF121212),
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Color(0xFF121212),
              ),
              dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
              datePickerTheme: DatePickerThemeData(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                headerBackgroundColor: const Color(0xFF121212),
                headerForegroundColor: Colors.white,
                dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.white;
                  }
                  if (states.contains(WidgetState.disabled)) {
                    return Colors.black38;
                  }
                  return const Color(0xFF121212);
                }),
                dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return const Color(0xFF121212);
                  }
                  return Colors.transparent;
                }),
                todayForegroundColor: const WidgetStatePropertyAll(
                  Color(0xFF121212),
                ),
                todayBackgroundColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                todayBorder: const BorderSide(color: Color(0xFF121212)),
                confirmButtonStyle: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF121212),
                ),
                cancelButtonStyle: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF121212),
                ),
              ),
            ),
            child: child!,
          ),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _start = DateUtils.dateOnly(picked));
    }
  }

  void _toggle(FinancialCategory category, bool enabled) {
    setState(() {
      if (enabled) {
        _enabled.add(category);
      } else {
        _enabled.remove(category);
        _focusNodes[category]!.unfocus();
      }
    });
    if (enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNodes[category]!.requestFocus();
      });
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final planner = context.read<PlannerProvider>();
    if (planner.hasPlan) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (_) => withBarrierBlur(
          AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Text('Replace active plan?'),
            content: const Text(
              'Saving this plan will replace your current budget plan.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF121212),
                ),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF121212),
                ),
                child: const Text('Replace'),
              ),
            ],
          ),
        ),
      );
      if (replace != true || !mounted) return;
    }

    try {
      await planner.savePlan(
        period: _period,
        start: _start,
        enabled: Set.of(_enabled),
        amounts: _amounts,
      );
      if (!mounted) return;
      final startsLater = _start.isAfter(DateUtils.dateOnly(DateTime.now()));
      final message = startsLater
          ? 'Plan saved. Spending will be tracked starting '
                '${DateFormat('MMM d').format(_start)}.'
          : 'Budget plan saved.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not save the budget plan.')),
        );
    }
  }

  Future<void> _deletePlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => withBarrierBlur(
        AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Delete this plan?'),
          content: const Text(
            'Your budget plan will be removed from all your devices.',
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF121212),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await context.read<PlannerProvider>().deletePlan();
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _enabled.clear();
        _period = PlannerPeriod.day;
        _start = DateTime(now.year, now.month, now.day + 1);
        for (final controller in _controllers.values) {
          controller.clear();
        }
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Plan deleted')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not delete the plan.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final budget = context.watch<BudgetProvider>();
    final planner = context.watch<PlannerProvider>();
    final currency = context.watch<CurrencyProvider>();
    final draftPlan = _draftPlan;
    final total = _total;
    final spent = _draftSpent(budget);
    final now = DateTime.now();
    final progress = total <= 0 || now.isBefore(draftPlan.localStart)
        ? 0.0
        : spent / total;
    final hasUnsavedDraft = plannerDraftDiffers(draftPlan, planner.plan);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF121212),
        centerTitle: false,
        title: const Text(
          'Budget Planner',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            children: [
              _HeroCard(
                plan: draftPlan,
                total: total,
                spent: spent,
                progress: progress,
                totalLabel: currency.formatAmount(total),
                isPreview: hasUnsavedDraft,
                isEmpty: _enabled.isEmpty,
              ),
              const SizedBox(height: 16),
              _SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('Period'),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        for (final period in PlannerPeriod.values) ...[
                          if (period.index > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _PeriodButton(
                              period: period,
                              selected: _period == period,
                              onTap: () => setState(() => _period = period),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE1E4E8)),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined, size: 22),
                            const SizedBox(width: 14),
                            Text(
                              plannerFriendlyDate(_start),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF121212),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('Categories'),
                    const SizedBox(height: 8),
                    for (final category in FinancialCategory.values) ...[
                      if (category.index > 0)
                        const Divider(height: 1, color: Color(0xFFEBEDF0)),
                      _CategoryRow(
                        category: category,
                        enabled: _enabled.contains(category),
                        controller: _controllers[category]!,
                        focusNode: _focusNodes[category]!,
                        currencySymbol: currency.symbol,
                        onChanged: (value) => _toggle(category, value),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionTitle('Total budget'),
                          SizedBox(height: 6),
                          Text(
                            'This is the most you plan to spend. You will get an alert if you go over.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: Color(0xFF7A8290),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      currency.formatAmount(total),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF121212),
                      ),
                    ),
                  ],
                ),
              ),
              if (!planner.notificationsEnabled) ...[
                const SizedBox(height: 12),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notifications_off_outlined, size: 17),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Notifications are off. Budget alerts will still appear while the app is open.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _canSave ? _save : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF121212),
                    disabledBackgroundColor: const Color(0xFFD7DADF),
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                  ),
                  child: planner.isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save plan',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              if (planner.hasPlan) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: planner.isDeleting ? null : _deletePlan,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    textStyle: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: planner.isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFDC2626),
                          ),
                        )
                      : const Text('Delete plan'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _editableAmount(double value) {
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.plan,
    required this.total,
    required this.spent,
    required this.progress,
    required this.totalLabel,
    required this.isPreview,
    required this.isEmpty,
  });

  final BudgetPlan plan;
  final double total;
  final double spent;
  final double progress;
  final String totalLabel;
  final bool isPreview;
  final bool isEmpty;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final status = isEmpty
        ? 'Turn on a category to set a budget'
        : plannerStatusLabel(plan, spent, now: now);
    final heading = plannerFriendlyDate(plan.start).startsWith('Tomorrow')
        ? 'BUDGET FOR TOMORROW'
        : plannerFriendlyDate(plan.start) == 'Today'
        ? 'BUDGET FOR TODAY'
        : 'BUDGET PLAN';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF333333), Color(0xFF000000)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: const TextStyle(
              color: Color(0xFFD7DCE5),
              fontSize: 13,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            totalLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              height: 1.05,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (isPreview) ...[
            const Text(
              'Preview - not saved yet',
              style: TextStyle(
                color: Color(0xFFD7DCE5),
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            status,
            style: const TextStyle(color: Color(0xFFE2E6EC), fontSize: 16),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: PlannerProgressBar(
                  progress: progress,
                  height: 13,
                  trackColor: Colors.white.withValues(alpha: 0.32),
                  animate: true,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7E9ED)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Color(0xFF121212),
      ),
    );
  }
}

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
    required this.period,
    required this.selected,
    required this.onTap,
  });

  final PlannerPeriod period;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: selected
              ? const Color(0xFF121212)
              : const Color(0xFF7A8290),
          backgroundColor: selected ? Colors.white : const Color(0xFFF1F3F6),
          side: BorderSide(
            color: selected ? const Color(0xFF121212) : Colors.transparent,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          period.label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.enabled,
    required this.controller,
    required this.focusNode,
    required this.currencySymbol,
    required this.onChanged,
  });

  final FinancialCategory category;
  final bool enabled;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String currencySymbol;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = switch (category) {
      FinancialCategory.bills => 'Bills',
      FinancialCategory.savings => 'Savings',
      FinancialCategory.personal => 'Personal',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          CategoryIconBadge(
            iconAsset: SpendCategoryPresets.defaultIconAsset(category),
            size: 48,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, color: Color(0xFF121212)),
            ),
          ),
          Switch(
            value: enabled,
            onChanged: onChanged,
            activeTrackColor: const Color(0xFF121212),
            activeThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFD9DEE5),
            inactiveThumbColor: Colors.white,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            child: TextField(
              key: ValueKey('planner_amount_${category.name}'),
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: InputDecoration(
                prefixText: '$currencySymbol ',
                filled: true,
                fillColor: enabled ? Colors.white : const Color(0xFFF0F2F5),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: Color(0xFFDDE1E6)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(
                    color: Color(0xFF121212),
                    width: 1.4,
                  ),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: Color(0xFFE1E4E8)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
