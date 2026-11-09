import 'dart:async';

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
import '../../widgets/app_date_picker.dart';
import '../../widgets/barrier_blur.dart';
import '../../widgets/category_icon_badge.dart';
import '../../widgets/financial_hero_card.dart';
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

  /// Last day of a multi-day Day plan. Null means one day (Until equals the
  /// start date). Always null for Week and Month.
  DateTime? _until;
  bool _initialized = false;
  Map<FinancialCategory, List<FinancialEntry>> _draftEntries = {
    for (final category in FinancialCategory.values) category: [],
  };
  int _draftLoadGeneration = 0;

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
    if (plan != null) {
      _period = plan.period;
      _start = plan.start;
      _until = plan.period == PlannerPeriod.day ? plan.localEndDate : null;
      _enabled.addAll(plan.enabledCategories);
      for (final entry in plan.amounts.entries) {
        _controllers[entry.key]!.text = _editableAmount(entry.value);
      }
    }
    unawaited(_refreshDraftEntries());
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

  DateTime get _startDay => DateUtils.dateOnly(_start);

  /// The end date that applies to the current period: only Day plans have one.
  DateTime? get _endDate => _period == PlannerPeriod.day ? _until : null;

  /// Days covered by the Day range (1 when there is no Until date).
  int get _dayLength {
    final end = _endDate;
    return end == null ? 1 : plannerRangeDays(_startDay, end);
  }

  void _applyDayLength(int days) {
    _until = days <= 1 ? null : plannerDayRangeEnd(_startDay, days);
  }

  bool get _canSave {
    final today = DateUtils.dateOnly(DateTime.now());
    return !_start.isBefore(today) &&
        isPlannerDayRangeValid(_startDay, _endDate) &&
        isPlannerDraftValid(_enabled, _amounts) &&
        !context.read<PlannerProvider>().isSaving;
  }

  BudgetPlan get _draftPlan => BudgetPlan(
    id: 'draft',
    period: _period,
    start: _startDay,
    endExclusive: plannerEndExclusive(_period, _startDay, _endDate),
    amounts: {for (final category in _enabled) category: _amounts[category]!},
    createdAt: DateTime.now(),
    alertEligible: true,
    endDate: _endDate,
  );

  double _draftSpent() {
    return plannerSpent(_draftPlan, _draftEntries);
  }

  Future<void> _refreshDraftEntries() async {
    final generation = ++_draftLoadGeneration;
    final plan = _draftPlan;
    try {
      final entries = await context.read<BudgetProvider>().loadEntriesInRange(
        startInclusive: plan.localStart,
        endExclusive: plan.localEndExclusive,
      );
      if (!mounted || generation != _draftLoadGeneration) return;
      setState(() => _draftEntries = entries);
    } catch (_) {}
  }

  void _setPeriod(PlannerPeriod period) {
    if (period == _period) return;
    // Week and Month have no Until date, and Day always starts at one day.
    setState(() {
      _period = period;
      _until = null;
    });
    unawaited(_refreshDraftEntries());
  }

  void _setDayLength(int days) {
    setState(() => _applyDayLength(days));
    unawaited(_refreshDraftEntries());
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
      builder: appDatePickerBuilder,
    );
    if (picked != null && mounted) {
      // Moving the start date keeps the Day range the same length.
      final length = _dayLength;
      setState(() {
        _start = DateUtils.dateOnly(picked);
        _applyDayLength(length);
      });
      unawaited(_refreshDraftEntries());
    }
  }

  Future<void> _pickUntil() async {
    final first = _startDay;
    final last = plannerDayRangeEnd(first, kPlannerMaxDayRange);
    final picked = await showDatePicker(
      context: context,
      initialDate: _until ?? first,
      firstDate: first,
      lastDate: last,
      helpText: 'Choose plan end date',
      builder: appDatePickerBuilder,
    );
    if (picked != null && mounted) {
      final day = DateUtils.dateOnly(picked);
      setState(() => _until = day.isAfter(first) ? day : null);
      unawaited(_refreshDraftEntries());
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
        endDate: _endDate,
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
        _until = null;
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
    final planner = context.watch<PlannerProvider>();
    final currency = context.watch<CurrencyProvider>();
    final budget = context.watch<BudgetProvider>();
    final draftPlan = _draftPlan;
    final total = _total;
    final spent = _draftSpent();
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
                perDayLabel: plannerPerDayAmount(draftPlan) == null
                    ? null
                    : 'About ${currency.formatAmount(plannerPerDayAmount(draftPlan)!)} per day',
                isPreview: hasUnsavedDraft,
                isEmpty: _enabled.isEmpty,
              ),
              const SizedBox(height: 16),
              _SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const _SectionTitle('Period'),
                        const SizedBox(width: 2),
                        Semantics(
                          button: true,
                          label: 'About budget periods',
                          excludeSemantics: true,
                          onTap: () => _showPeriodInfo(context),
                          child: IconButton(
                            key: const ValueKey('planner-period-info'),
                            tooltip: 'About budget periods',
                            onPressed: () => _showPeriodInfo(context),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            icon: const Icon(
                              Icons.info_outline_rounded,
                              size: 20,
                              color: Color(0xFF737983),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (final period in PlannerPeriod.values) ...[
                          if (period.index > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _ChipButton(
                              label: period.label,
                              selected: _period == period,
                              onTap: () => _setPeriod(period),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _periodHelp[_period]!,
                      key: const ValueKey('planner-period-help'),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF737983),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _DatePill(
                      key: const ValueKey('planner-start-date'),
                      text: plannerFriendlyDate(_start),
                      semanticsLabel:
                          'Start date, ${plannerFriendlyDate(_start)}. '
                          'Double tap to change.',
                      onTap: _pickDate,
                    ),
                    AnimatedSize(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: _period == PlannerPeriod.day
                          ? _buildUntilSection()
                          : const SizedBox(width: double.infinity),
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
                        availableLabel: currency.formatAmount(
                          budget.remainingFor(category),
                        ),
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
                    // Scale the amount down instead of overflowing at large
                    // text sizes on narrow screens.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          currency.formatAmount(total),
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF121212),
                          ),
                        ),
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
                            color: Color(0xFF121212),
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

  /// Quick day counts shown under the Until field.
  static const _quickDayOptions = [1, 2, 3, 5];

  Widget _buildUntilSection() {
    final until = _until ?? _startDay;
    final length = _dayLength;
    return Column(
      key: const ValueKey('planner-until-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        _DatePill(
          key: const ValueKey('planner-until-date'),
          text: 'Until ${plannerFriendlyDate(until)}',
          semanticsLabel:
              'Until date, ${plannerFriendlyDate(until)}. '
              'Double tap to change.',
          onTap: _pickUntil,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < _quickDayOptions.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _ChipButton(
                  key: ValueKey('planner-days-${_quickDayOptions[i]}'),
                  label: _quickDayOptions[i] == 1
                      ? '1 day'
                      : '${_quickDayOptions[i]} days',
                  semanticsLabel:
                      'Cover ${_quickDayOptions[i]} '
                      '${_quickDayOptions[i] == 1 ? 'day' : 'days'}',
                  selected: length == _quickDayOptions[i],
                  onTap: () => _setDayLength(_quickDayOptions[i]),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

const _periodHelp = <PlannerPeriod, String>{
  PlannerPeriod.day:
      'One budget for the days you choose. Pick an end date to cover up to 6 days.',
  PlannerPeriod.week: 'One budget for 7 days from your start date.',
  PlannerPeriod.month:
      'One budget from your start date to the day before the same date next month.',
};

const _periodExample = <PlannerPeriod, String>{
  PlannerPeriod.day:
      'Example: Oct 28 to Oct 30 is one budget that covers 3 days.',
  PlannerPeriod.week: 'Example: starting Oct 28 covers Oct 28 to Nov 3.',
  PlannerPeriod.month: 'Example: starting Oct 28 covers Oct 28 to Nov 27.',
};

Future<void> _showPeriodInfo(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => withBarrierBlur(
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Budget periods',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF121212),
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final period in PlannerPeriod.values) ...[
                          if (period.index > 0) const SizedBox(height: 16),
                          Text(
                            period.label,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF121212),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _periodHelp[period]!,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF737983),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _periodExample[period]!,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF121212),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF121212),
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
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

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.plan,
    required this.total,
    required this.spent,
    required this.progress,
    required this.totalLabel,
    required this.isPreview,
    required this.isEmpty,
    this.perDayLabel,
  });

  final BudgetPlan plan;
  final double total;
  final double spent;
  final double progress;
  final String totalLabel;
  final bool isPreview;
  final bool isEmpty;

  /// "About X per day", shown under the total for multi-day plans.
  final String? perDayLabel;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final status = isEmpty
        ? 'Turn on a category to set a budget'
        : plannerStatusLabel(plan, spent, now: now);
    final heading = plan.isMultiDay
        ? 'BUDGET PLAN'
        : plannerFriendlyDate(plan.start).startsWith('Tomorrow')
        ? 'BUDGET FOR TOMORROW'
        : plannerFriendlyDate(plan.start) == 'Today'
        ? 'BUDGET FOR TODAY'
        : 'BUDGET PLAN';

    return FinancialHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FinancialHeroLabel(heading),
          const SizedBox(height: 8),
          FinancialHeroAmount(totalLabel),
          if (perDayLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              perDayLabel!,
              key: const ValueKey('planner-per-day'),
              style: const TextStyle(
                color: Color(0xFFD7DCE5),
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
          FinancialHeroSubtitle(status),
          // Before a multi-day plan starts the status reads "Starts Oct 28",
          // so show the range on its own line as well.
          if (plan.isMultiDay && status != plannerPeriodSummary(plan)) ...[
            const SizedBox(height: 4),
            Text(
              plannerPeriodSummary(plan),
              key: const ValueKey('planner-range-summary'),
              style: const TextStyle(
                color: Color(0xFFD7DCE5),
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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

/// Selectable chip used for the period (Day, Week, Month) and the quick day
/// counts. The label scales down instead of overflowing at large text sizes.
class _ChipButton extends StatelessWidget {
  const _ChipButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.semanticsLabel,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: SizedBox(
        height: 46,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: selected
                ? const Color(0xFF121212)
                : const Color(0xFF7A8290),
            backgroundColor: selected ? Colors.white : const Color(0xFFF1F3F6),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: Size.zero,
            side: BorderSide(
              color: selected ? const Color(0xFF121212) : Colors.transparent,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill-shaped date field with a calendar icon, used for Start and Until.
class _DatePill extends StatelessWidget {
  const _DatePill({
    super.key,
    required this.text,
    required this.semanticsLabel,
    required this.onTap,
  });

  final String text;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
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
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF121212),
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

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.enabled,
    required this.controller,
    required this.focusNode,
    required this.currencySymbol,
    required this.availableLabel,
    required this.onChanged,
  });

  final FinancialCategory category;
  final bool enabled;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String currencySymbol;

  /// Formatted money currently left in this category, shown under the label.
  final String availableLabel;
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
            child: Semantics(
              label: '$label, $availableLabel available',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF121212),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      availableLabel,
                      key: ValueKey('planner_available_${category.name}'),
                      maxLines: 1,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF737983),
                      ),
                    ),
                  ),
                ],
              ),
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
