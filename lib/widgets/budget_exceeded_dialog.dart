import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/planner_provider.dart';
import '../services/notification_router.dart';
import 'barrier_blur.dart';

class BudgetExceededDialog extends StatefulWidget {
  const BudgetExceededDialog({
    super.key,
    required this.planLabel,
    required this.budgetAmount,
    required this.spentAmount,
    required this.overAmount,
  });

  final String planLabel;
  final String budgetAmount;
  final String spentAmount;
  final String overAmount;

  @override
  State<BudgetExceededDialog> createState() => _BudgetExceededDialogState();
}

class _BudgetExceededDialogState extends State<BudgetExceededDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HapticFeedback.lightImpact();
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = Semantics(
      label: 'Budget exceeded by ${widget.overAmount}',
      child: PopScope(
        canPop: false,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFEE2E2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.trending_up_rounded,
                      size: 28,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FittedBox(
                    child: const Text(
                      'You went over budget',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF121212),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    child: Text(
                      widget.planLabel,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF737983),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SummaryBlock(
                    budgetAmount: widget.budgetAmount,
                    spentAmount: widget.spentAmount,
                    overAmount: widget.overAmount,
                  ),
                  const SizedBox(height: 14),
                  const SizedBox(
                    width: double.infinity,
                    height: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFFDC2626),
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.pressed)
                              ? const Color(0xFF333333)
                              : const Color(0xFF121212),
                        ),
                        foregroundColor: const WidgetStatePropertyAll(
                          Colors.white,
                        ),
                        shape: const WidgetStatePropertyAll(StadiumBorder()),
                      ),
                      child: const Text(
                        'Got it',
                        style: TextStyle(
                          fontFamily: 'Inter',
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

    if (MediaQuery.disableAnimationsOf(context)) return content;
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      tween: Tween(begin: 0.96, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: ((value - 0.96) / 0.04).clamp(0.0, 1.0),
        child: Transform.scale(scale: value, child: child),
      ),
      child: content,
    );
  }
}

class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({
    required this.budgetAmount,
    required this.spentAmount,
    required this.overAmount,
  });

  final String budgetAmount;
  final String spentAmount;
  final String overAmount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _SummaryRow(label: 'Budget', value: budgetAmount),
          const SizedBox(height: 10),
          _SummaryRow(label: 'Spent', value: spentAmount),
          const SizedBox(height: 10),
          _SummaryRow(label: 'Over by', value: overAmount, isOverage: true),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.isOverage = false,
  });

  final String label;
  final String value;
  final bool isOverage;

  @override
  Widget build(BuildContext context) {
    final color = isOverage ? const Color(0xFFDC2626) : const Color(0xFF25282D);
    return Row(
      children: [
        Expanded(
          child: FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: isOverage ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: FittedBox(
            alignment: Alignment.centerRight,
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: isOverage ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PlannerAlertListener extends StatefulWidget {
  const PlannerAlertListener({super.key, required this.child});

  final Widget child;

  @override
  State<PlannerAlertListener> createState() => _PlannerAlertListenerState();
}

class _PlannerAlertListenerState extends State<PlannerAlertListener> {
  PlannerProvider? _planner;
  bool _showing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final planner = context.read<PlannerProvider>();
    if (identical(_planner, planner)) return;
    _planner?.removeListener(_onPlannerChanged);
    _planner = planner;
    planner.addListener(_onPlannerChanged);
    _onPlannerChanged();
  }

  void _onPlannerChanged() {
    if (!mounted || _showing) return;
    final event = _planner?.pendingExceededEvent;
    if (event == null) return;
    _showing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final navigatorContext =
          NotificationRouter.navigatorKey.currentContext ?? context;
      await showDialog<void>(
        context: navigatorContext,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (_) => withBarrierBlur(
          BudgetExceededDialog(
            planLabel: event.planLabel,
            budgetAmount: event.budgetAmount,
            spentAmount: event.spentAmount,
            overAmount: event.overAmount,
          ),
        ),
      );
      _planner?.consumeExceededEvent();
      _showing = false;
    });
  }

  @override
  void dispose() {
    _planner?.removeListener(_onPlannerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
