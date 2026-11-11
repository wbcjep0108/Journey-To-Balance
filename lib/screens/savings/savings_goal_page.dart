import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/financial_entry.dart';
import '../../models/spend_category_option.dart';
import '../../providers/budget_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/wallet_cards_provider.dart';
import '../../providers/wallet_cash_provider.dart';
import '../../services/funding_source_adjuster.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/barrier_blur.dart';
import '../../widgets/category_icon_badge.dart';
import '../../widgets/outlined_confirm_button.dart';
import '../../widgets/rate_limit_dialog.dart';
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
    final preferred = context.watch<CurrencyProvider>();
    final current = budget.savingsGoalCurrent;
    final target = budget.savingsGoalTarget;
    final progress = budget.savingsGoalProgress;
    final currency = NumberFormat.currency(
      locale: preferred.currency.locale,
      symbol: '${preferred.symbol} ',
      decimalDigits: current % 1 == 0 ? 0 : 2,
    );
    final goalCurrency = NumberFormat.currency(
      locale: preferred.currency.locale,
      symbol: '${preferred.symbol} ',
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
        return withBarrierBlur(
          Dialog(
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
                      } catch (error) {
                        if (isFinanceRateLimitError(error)) return;
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
        return withBarrierBlur(
          Dialog(
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
                  _TextField(
                    label: 'What are you saving for?',
                    controller: controller,
                  ),
                  const SizedBox(height: 24),
                  _ConfirmButton(
                    label: 'Confirm',
                    onPressed: () async {
                      final title = controller.text.trim();
                      if (title.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter a goal title.')),
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
                      } catch (error) {
                        if (isFinanceRateLimitError(error)) return;
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
      builder: appDatePickerBuilder,
    );
    if (picked == null || !context.mounted) return;

    try {
      await budget.updateSavingsGoalSettings(
        target: budget.savingsGoalTarget,
        targetDate: picked,
      );
    } catch (error) {
      if (isFinanceRateLimitError(error)) return;
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
        return withBarrierBlur(
          Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 28,
              vertical: 24,
            ),
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
                    'The Savings Goal is completely up to you. You choose which '
                    'wallet or cards the money comes from and where it is saved.\n\n'
                    'When you add to your goal, the app moves the amount between '
                    'those balances: it is deducted from the places you take it '
                    'from and added to the places you save it into. Undoing a '
                    'contribution reverses those balance changes.',
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
      return withBarrierBlur(SavingsContributionModal(category: category));
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

String _savingsConfirmSummary({
  required CurrencyProvider currency,
  required double total,
  required SavingsTransferValidation validation,
  required String sourceNames,
  required String destinationNames,
  required String effect,
}) {
  if (total <= 0) return 'Enter a contribution amount';
  if (validation.sourceCents == 0) return 'Select where money comes from';
  if (!validation.sourcesWithinBalance) {
    return 'Fix insufficient source balance';
  }
  final totalCents = moneyToCents(total);
  if (validation.sourceCents < totalCents) {
    return 'Assign ${currency.formatAmount(centsToMoney(totalCents - validation.sourceCents))} in Take from';
  }
  if (validation.sourceCents > totalCents) {
    return 'Reduce Take from by ${currency.formatAmount(centsToMoney(validation.sourceCents - totalCents))}';
  }
  if (validation.destinationCents == 0 || destinationNames.isEmpty) {
    return 'Select where to save';
  }
  if (!validation.destinationsMatch) return 'Select where to save';
  return effect;
}

/// Builds the net per-location balance effect line, e.g.
/// "Wallet -PHP 1,000.00, BDO +PHP 1,000.00". A location that appears on both
/// sides nets out and is omitted.
String savingsBalanceEffectSummary({
  required CurrencyProvider currency,
  required List<SavingsTransferPart> sources,
  required List<SavingsTransferPart> destinations,
}) {
  final order = <String>[];
  final names = <String, String>{};
  final deltaCents = <String, int>{};
  void add(SavingsTransferPart part, int sign) {
    final id = part.locationId;
    if (!deltaCents.containsKey(id)) {
      order.add(id);
      names[id] = part.displayName;
    }
    deltaCents[id] = (deltaCents[id] ?? 0) + sign * moneyToCents(part.amount);
  }

  for (final part in sources) {
    add(part, -1);
  }
  for (final part in destinations) {
    add(part, 1);
  }

  final pieces = <String>[];
  for (final id in order) {
    final cents = deltaCents[id] ?? 0;
    if (cents == 0) continue;
    final sign = cents > 0 ? '+' : '-';
    pieces.add(
      '${names[id]} $sign${currency.formatAmount(centsToMoney(cents.abs()))}',
    );
  }
  return pieces.join(', ');
}

class SavingsContributionModal extends StatefulWidget {
  const SavingsContributionModal({super.key, required this.category});

  final FinancialCategory category;

  @override
  State<SavingsContributionModal> createState() =>
      _SavingsContributionModalState();
}

class _SavingsContributionModalState extends State<SavingsContributionModal> {
  static const _walletId = 'wallet';

  final _totalController = TextEditingController();
  final _sourceControllers = <String, TextEditingController>{};
  final _destinationControllers = <String, TextEditingController>{};
  final Set<String> _sourceIds = {};
  final Set<String> _destinationIds = {};
  bool _defaultsInitialized = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _sourceControllers[_walletId] = TextEditingController();
    _totalController.addListener(_handleTotalChanged);
  }

  void _ensureDefaults(List<WalletCardModel> cards, double walletAmount) {
    if (_defaultsInitialized) return;
    _defaultsInitialized = true;
    final positiveCard = cards.where((card) => card.amount > 0).firstOrNull;
    final sourceId = walletAmount > 0 ? _walletId : positiveCard?.id;
    if (sourceId != null) {
      _sourceIds.add(sourceId);
      _sourceControllers[sourceId] = TextEditingController();
    }
    final destinationId = cards
        .where((card) => card.id != sourceId)
        .firstOrNull
        ?.id;
    if (destinationId != null) {
      _destinationIds.add(destinationId);
      _destinationControllers[destinationId] = TextEditingController();
    } else if (sourceId != _walletId) {
      _destinationIds.add(_walletId);
      _destinationControllers[_walletId] = TextEditingController();
    }
  }

  void _handleTotalChanged() {
    _autoFill(_sourceIds, _sourceControllers);
    _autoFill(_destinationIds, _destinationControllers);
    if (mounted) setState(() {});
  }

  void _autoFill(
    Set<String> selectedIds,
    Map<String, TextEditingController> controllers,
  ) {
    final total = double.tryParse(_totalController.text) ?? 0;
    final parts = splitSavingsAmount(total, selectedIds.length);
    for (var index = 0; index < selectedIds.length; index++) {
      final id = selectedIds.elementAt(index);
      controllers.putIfAbsent(id, TextEditingController.new).text =
          parts.isEmpty ? '' : parts[index].toStringAsFixed(2);
    }
  }

  void _toggleLocation({
    required bool isSource,
    required String id,
    required bool selected,
  }) {
    final ids = isSource ? _sourceIds : _destinationIds;
    final oppositeIds = isSource ? _destinationIds : _sourceIds;
    final controllers = isSource ? _sourceControllers : _destinationControllers;
    if (selected && oppositeIds.contains(id)) return;
    setState(() {
      if (selected) {
        ids.add(id);
        controllers.putIfAbsent(id, TextEditingController.new);
      } else {
        ids.remove(id);
      }
      _autoFill(ids, controllers);
    });
  }

  void _useFullSourceAmount(String id) {
    final total = double.tryParse(_totalController.text) ?? 0;
    setState(() {
      _sourceControllers.putIfAbsent(id, TextEditingController.new).text =
          total > 0 ? total.toStringAsFixed(2) : '';
    });
  }

  List<SavingsTransferPart> _parts(
    Set<String> selectedIds,
    Map<String, TextEditingController> controllers,
    List<WalletCardModel> cards,
  ) {
    return [
      if (selectedIds.contains(_walletId))
        SavingsTransferPart(
          locationType: 'wallet',
          cardName: 'Wallet',
          amount: double.tryParse(controllers[_walletId]?.text ?? '') ?? 0,
        ),
      for (final card in cards)
        if (selectedIds.contains(card.id))
          SavingsTransferPart(
            locationType: 'card',
            cardId: card.id,
            cardName: _cardLabels(cards)[card.id] ?? card.displayName,
            amount: double.tryParse(controllers[card.id]?.text ?? '') ?? 0,
          ),
    ];
  }

  /// Disambiguated display labels for [cards], keyed by id.
  Map<String, String> _cardLabels(List<WalletCardModel> cards) =>
      walletCardDisplayLabels(cards);

  @override
  void dispose() {
    _totalController
      ..removeListener(_handleTotalChanged)
      ..dispose();
    for (final controller in {
      ..._sourceControllers.values,
      ..._destinationControllers.values,
    }) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_saving) return;
    final budget = context.read<BudgetProvider>();
    final walletAmount = context.read<WalletCashProvider>().amount;
    final cards = context.read<WalletCardsProvider>().cards;
    final amount = centsToMoney(
      moneyToCents(double.tryParse(_totalController.text) ?? 0),
    );
    final sources = _parts(_sourceIds, _sourceControllers, cards);
    final destinations = _parts(
      _destinationIds,
      _destinationControllers,
      cards,
    );
    final validation = validateSavingsTransfer(
      total: amount,
      sources: sources,
      destinations: destinations,
      balancesByLocationId: {
        _walletId: walletAmount,
        for (final card in cards) card.id: card.amount,
      },
    );
    if (!validation.canConfirm) return;
    if (amount > budget.remainingFor(widget.category) + 0.001) {
      final symbol = context.read<CurrencyProvider>().symbol;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Only $symbol${NumberFormat('#,##0.##').format(budget.remainingFor(widget.category))} '
            'left in ${SavingsGoalPage.categoryLabel(widget.category)}.',
          ),
        ),
      );
      return;
    }

    // Reject up front if a selected TO card vanished since the modal opened
    // (e.g. deleted on another device). The Worker also enforces this.
    final cardIds = {for (final card in cards) card.id};
    SavingsTransferPart? missingDestination;
    for (final part in destinations) {
      if (!part.isWallet && !cardIds.contains(part.cardId)) {
        missingDestination = part;
        break;
      }
    }
    if (missingDestination != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${missingDestination.cardName} is no longer available. '
            'Choose a different card to save into.',
          ),
        ),
      );
      return;
    }

    final category = widget.category;
    final messenger = ScaffoldMessenger.of(context);
    final symbol = context.read<CurrencyProvider>().symbol;
    final walletCashProvider = context.read<WalletCashProvider>();
    final walletCardsProvider = context.read<WalletCardsProvider>();
    final previousCurrent = budget.savingsGoalCurrent;
    final goalTarget = budget.savingsGoalTarget;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);

    // Snapshot wallet/card balances so we can restore them if the write fails.
    final previousWalletCash = walletCashProvider.amount;
    final previousCards = walletCardsProvider.cards;
    _applyBalanceDeltasInMemory(
      walletCash: walletCashProvider,
      walletCards: walletCardsProvider,
      sources: sources,
      destinations: destinations,
    );

    try {
      // Optimistic update BEFORE closing so the page already shows new totals.
      await budget.contributeToSavingsGoal(
        source: category,
        fundingSourceId: sources.length == 1
            ? sources.first.locationId
            : 'multiple',
        fundingSourceLabel: sources.length == 1
            ? sources.first.displayName
            : '${sources.first.displayName} + ${sources.length - 1} more',
        savingsSources: sources,
        savingsDestinations: destinations,
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
                '$symbol${NumberFormat('#,##0.##').format(amount)} added to your savings goal.',
              ),
            ),
          );
      }
    } catch (error) {
      // Roll back the in-memory optimistic balance changes (not persisted).
      walletCashProvider.restoreInMemoryAmount(previousWalletCash);
      walletCardsProvider.restoreInMemoryCards(previousCards);
      if (mounted) setState(() => _saving = false);
      if (isFinanceRateLimitError(error)) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not add to savings goal.')),
      );
    }
  }

  /// Applies FROM debits and TO credits to the wallet/card providers in memory
  /// only (no Firestore write). The Worker performs the authoritative wallet
  /// write with a version precondition; the realtime snapshot then replaces
  /// this local state. Persisting here would double-write and conflict.
  static void _applyBalanceDeltasInMemory({
    required WalletCashProvider walletCash,
    required WalletCardsProvider walletCards,
    required List<SavingsTransferPart> sources,
    required List<SavingsTransferPart> destinations,
  }) {
    final cardDeltaCents = <String, int>{};
    var walletDeltaCents = 0;
    for (final part in sources) {
      if (part.isWallet) {
        walletDeltaCents -= moneyToCents(part.amount);
      } else {
        cardDeltaCents[part.cardId!] =
            (cardDeltaCents[part.cardId!] ?? 0) - moneyToCents(part.amount);
      }
    }
    for (final part in destinations) {
      if (part.isWallet) {
        walletDeltaCents += moneyToCents(part.amount);
      } else {
        cardDeltaCents[part.cardId!] =
            (cardDeltaCents[part.cardId!] ?? 0) + moneyToCents(part.amount);
      }
    }

    if (walletDeltaCents != 0) {
      walletCash.applyInMemoryAmount(
        centsToMoney(moneyToCents(walletCash.amount) + walletDeltaCents),
      );
    }
    if (cardDeltaCents.isNotEmpty) {
      final nextAmounts = <String, double>{};
      for (final card in walletCards.cards) {
        final delta = cardDeltaCents[card.id];
        if (delta == null) continue;
        nextAmounts[card.id] = centsToMoney(
          moneyToCents(card.amount) + delta,
        );
      }
      if (nextAmounts.isNotEmpty) {
        walletCards.applyInMemoryCardAmounts(nextAmounts);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final budget = context.watch<BudgetProvider>();
    final preferred = context.watch<CurrencyProvider>();
    final walletAmount = context.watch<WalletCashProvider>().amount;
    final cards = context.watch<WalletCardsProvider>().cards;
    _ensureDefaults(cards, walletAmount);
    final availableIds = {_walletId, ...cards.map((card) => card.id)};
    _sourceIds.removeWhere((id) => !availableIds.contains(id));
    _destinationIds.removeWhere((id) => !availableIds.contains(id));
    _sourceControllers.putIfAbsent(_walletId, TextEditingController.new);
    final total = centsToMoney(
      moneyToCents(double.tryParse(_totalController.text) ?? 0),
    );
    final sources = _parts(_sourceIds, _sourceControllers, cards);
    final destinations = _parts(
      _destinationIds,
      _destinationControllers,
      cards,
    );
    final validation = validateSavingsTransfer(
      total: total,
      sources: sources,
      destinations: destinations,
      balancesByLocationId: {
        _walletId: walletAmount,
        for (final card in cards) card.id: card.amount,
      },
    );
    final sourceAssigned = centsToMoney(validation.sourceCents);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomInset = keyboardInset > 0 ? keyboardInset + 8 : 16.0;
    final maxModalHeight = MediaQuery.sizeOf(context).height - bottomInset - 16;
    final modalHeight = maxModalHeight.clamp(280.0, 692.0).toDouble();
    final title = budget.savingsGoalTitle.trim().isEmpty
        ? 'Savings Goal'
        : budget.savingsGoalTitle.trim();
    final remaining = budget.remainingFor(widget.category);
    final remainingLabel = NumberFormat.currency(
      locale: preferred.currency.locale,
      symbol: preferred.symbol,
      decimalDigits: remaining % 1 == 0 ? 0 : 2,
    ).format(remaining);
    final categoryLabel = SavingsGoalPage.categoryLabel(widget.category);
    final remainingAfter = (remaining - total)
        .clamp(0, double.infinity)
        .toDouble();
    final categoryChange =
        '$categoryLabel: ${preferred.formatAmount(remaining)} to '
        '${preferred.formatAmount(remainingAfter)}';
    final sourceNames = sources.map((part) => part.displayName).join(' + ');
    final destinationNames = destinations
        .map((part) => part.displayName)
        .join(' + ');
    final canConfirm = validation.canConfirm && !_saving;
    final balanceEffect = savingsBalanceEffectSummary(
      currency: preferred,
      sources: sources,
      destinations: destinations,
    );
    final footerText = _savingsConfirmSummary(
      currency: preferred,
      total: total,
      validation: validation,
      sourceNames: sourceNames,
      destinationNames: destinationNames,
      effect: balanceEffect,
    );

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
              padding: EdgeInsets.fromLTRB(12, 16, 12, bottomInset),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 400,
                  maxHeight: modalHeight,
                ),
                child: Container(
                  height: modalHeight,
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
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
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 30,
                                  ),
                                  child: Text(
                                    'Add to "$title"',
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF121212),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: IconButton(
                                    key: const ValueKey(
                                      'close-contribution-modal',
                                    ),
                                    onPressed: _saving
                                        ? null
                                        : () => Navigator.pop(context),
                                    visualDensity: VisualDensity.compact,
                                    iconSize: 19,
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '$remainingLabel available in $categoryLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              categoryChange,
                              key: const ValueKey('budget-category-change'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF3F444C),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _AmountField(
                                label: 'Total contribution',
                                controller: _totalController,
                                enabled: !_saving,
                              ),
                              const SizedBox(height: 8),
                              SavingsTransferSection(
                                title: 'Take from',
                                selectedIds: _sourceIds,
                                oppositeSelectedIds: _destinationIds,
                                controllers: _sourceControllers,
                                walletAmount: walletAmount,
                                cards: cards,
                                enabled: !_saving,
                                assignedAmount: sourceAssigned,
                                totalAmount: total,
                                sumMatches: validation.sourcesMatch,
                                showBalances: true,
                                onToggle: (id, selected) => _toggleLocation(
                                  isSource: true,
                                  id: id,
                                  selected: selected,
                                ),
                                onUseFullAmount: _useFullSourceAmount,
                                onAmountChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(
                                height: 20,
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 20,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                              SavingsTransferSection(
                                title: 'Save into',
                                selectedIds: _destinationIds,
                                oppositeSelectedIds: _sourceIds,
                                controllers: _destinationControllers,
                                walletAmount: walletAmount,
                                cards: cards,
                                enabled: !_saving,
                                assignedAmount: centsToMoney(
                                  validation.destinationCents,
                                ),
                                totalAmount: total,
                                sumMatches: validation.destinationsMatch,
                                showBalances: false,
                                amountEditable: false,
                                onToggle: (id, selected) => _toggleLocation(
                                  isSource: false,
                                  id: id,
                                  selected: selected,
                                ),
                                onAmountChanged: (_) => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        key: const ValueKey('pinned-confirm-bar'),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(24),
                          ),
                          border: Border(
                            top: BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              footerText,
                              key: const ValueKey('confirm-summary'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF3F444C),
                              ),
                            ),
                            const SizedBox(height: 6),
                            _ConfirmButton(
                              key: const ValueKey('contribution-confirm'),
                              label: 'Confirm',
                              isLoading: _saving,
                              onPressed: canConfirm ? _confirm : null,
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
              child: const Icon(
                Icons.savings_outlined,
                size: 230,
                color: Color(0xFF9CA3AF),
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
            icon: Icons.receipt_long_outlined,
            label: 'Bills',
            onTap: () => onCategoryTap(FinancialCategory.bills),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionCard(
            icon: Icons.savings_outlined,
            label: 'Savings',
            onTap: () => onCategoryTap(FinancialCategory.savings),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionCard(
            icon: Icons.person_outline,
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
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
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
                  Icon(icon, size: 30, color: const Color(0xFF121212)),
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

  Future<String?> _restoreFundingSource(
    BuildContext context,
    FinancialEntry entry,
  ) async {
    // New transfers are reversed atomically by the Worker. The legacy
    // restoration below remains for entries created by older app versions
    // that deducted one funding account on the client.
    if (entry.savingsSources.isNotEmpty &&
        entry.savingsDestinations.isNotEmpty) {
      return null;
    }
    // Shared with ordinary refunds. A removed card returns the money to
    // Wallet, as before.
    final result = await adjustFundingSource(
      wallet: context.read<WalletCashProvider>(),
      cards: context.read<WalletCardsProvider>(),
      sourceId: entry.fundingSourceId,
      delta: entry.amount,
    );
    if (result.outcome == FundingAdjustmentOutcome.noSource) return null;
    return result.targetCard?.bankLabel ?? 'Wallet';
  }

  Future<bool> _confirmDelete(BuildContext context, DayTransaction item) async {
    final authorized = await showSensitiveActionAuth(
      context: context,
      title: 'Undo contribution',
      description:
          'Enter your PIN or use fingerprint to return '
          '${context.read<CurrencyProvider>().formatAmount(item.entry.amount)} '
          'to ${SavingsGoalPage.categoryLabel(item.category)}.',
    );
    if (!authorized || !context.mounted) return false;

    final entry = item.entry;
    final isAtomicTransfer =
        entry.savingsSources.isNotEmpty &&
        entry.savingsDestinations.isNotEmpty;
    final walletCashProvider = context.read<WalletCashProvider>();
    final walletCardsProvider = context.read<WalletCardsProvider>();

    // For a new atomic transfer, optimistically reverse the balances in memory
    // (credit FROM, debit TO) so the wallet screen updates immediately. The
    // Worker performs the authoritative reversal with a version precondition.
    final previousWalletCash = walletCashProvider.amount;
    final previousCards = walletCardsProvider.cards;
    if (isAtomicTransfer) {
      _SavingsContributionModalState._applyBalanceDeltasInMemory(
        walletCash: walletCashProvider,
        walletCards: walletCardsProvider,
        // Swap sides: undo credits the original FROM and debits the original TO.
        sources: entry.savingsDestinations,
        destinations: entry.savingsSources,
      );
    }

    try {
      final result = await context.read<BudgetProvider>().deleteEntry(
        item.category,
        entry,
      );
      if (!context.mounted) return false;
      // Legacy single-source entries still restore via persisting setters.
      final restoredAccount = isAtomicTransfer
          ? null
          : await _restoreFundingSource(context, entry);
      final rawFallbacks = result?['fallbacks'];
      final fallbacks = rawFallbacks is List
          ? rawFallbacks.map((item) => item.toString()).toList()
          : const <String>[];
      // A fallback means a TO card was deleted, so its reversal went to Wallet.
      final fallbackText = fallbacks.isNotEmpty ? ' ${fallbacks.join(' ')}' : '';
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                '${context.read<CurrencyProvider>().formatAmount(entry.amount)} '
                'returned to ${SavingsGoalPage.categoryLabel(item.category)}'
                '${restoredAccount == null ? '.' : ' and $restoredAccount.'}'
                '$fallbackText',
              ),
            ),
          );
      }
      return true;
    } catch (error) {
      // Roll back the in-memory optimistic reversal (not persisted).
      if (isAtomicTransfer) {
        walletCashProvider.restoreInMemoryAmount(previousWalletCash);
        walletCardsProvider.restoreInMemoryCards(previousCards);
      }
      if (isFinanceRateLimitError(error)) return false;
      if (context.mounted) {
        final message = isFinanceConflictError(error)
            ? 'Could not undo this contribution. A destination may no longer '
                  'have enough balance to reverse it.'
            : 'Could not undo this contribution.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
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
              confirmDismiss: (_) async {
                // _confirmDelete updates the provider and removes this row.
                // Keep Dismissible from attempting a second removal.
                await _confirmDelete(context, items[i]);
                return false;
              },
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
                    CategoryIconBadge(
                      iconAsset:
                          items[i].entry.iconAsset ??
                          SpendCategoryPresets.defaultIconAsset(
                            items[i].category,
                          ),
                      size: 36,
                      showBorder: false,
                    ),
                    const SizedBox(width: 12),
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
                          if (items[i].entry.savingsSources.isNotEmpty &&
                              items[i]
                                  .entry
                                  .savingsDestinations
                                  .isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              savingsTransferSummary(context, items[i].entry),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      '+${context.watch<CurrencyProvider>().formatAmount(items[i].entry.amount)}',
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

enum SavingsAssignmentStatus { empty, partial, matched, over }

SavingsAssignmentStatus savingsAssignmentStatus({
  required double assignedAmount,
  required double totalAmount,
}) {
  final assigned = moneyToCents(assignedAmount);
  final total = moneyToCents(totalAmount);
  if (assigned <= 0 || total <= 0) return SavingsAssignmentStatus.empty;
  if (assigned == total) return SavingsAssignmentStatus.matched;
  return assigned < total
      ? SavingsAssignmentStatus.partial
      : SavingsAssignmentStatus.over;
}

class SavingsTransferSection extends StatefulWidget {
  const SavingsTransferSection({
    super.key,
    required this.title,
    required this.selectedIds,
    required this.controllers,
    required this.walletAmount,
    required this.cards,
    required this.enabled,
    required this.assignedAmount,
    required this.totalAmount,
    required this.sumMatches,
    required this.showBalances,
    this.amountEditable = true,
    this.oppositeSelectedIds = const <String>{},
    required this.onToggle,
    required this.onAmountChanged,
    this.onUseFullAmount,
  });

  final String title;
  final Set<String> selectedIds;
  final Map<String, TextEditingController> controllers;
  final double walletAmount;
  final List<WalletCardModel> cards;
  final bool enabled;
  final double assignedAmount;
  final double totalAmount;
  final bool sumMatches;
  final bool showBalances;
  final bool amountEditable;
  final Set<String> oppositeSelectedIds;
  final void Function(String id, bool selected) onToggle;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String>? onUseFullAmount;

  @override
  State<SavingsTransferSection> createState() => _SavingsTransferSectionState();
}

class _SavingsTransferSectionState extends State<SavingsTransferSection> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<CurrencyProvider>();
    final isSource = widget.amountEditable;
    final locations = <_SavingsLocation>[
      _SavingsLocation(
        id: 'wallet',
        label: 'Wallet',
        balance: widget.walletAmount,
        icon: const Icon(Icons.account_balance_wallet_outlined, size: 20),
      ),
      for (final card in widget.cards)
        _SavingsLocation(
          id: card.id,
          label: walletCardDisplayLabels(widget.cards)[card.id] ??
              card.displayName,
          balance: card.amount,
          icon: Image.asset(
            card.iconAsset,
            width: 20,
            height: 20,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.credit_card_outlined, size: 20),
          ),
        ),
    ];
    final visible = _showAll || locations.length <= 4
        ? locations
        : <_SavingsLocation>[
            ...locations.take(3),
            ...locations
                .skip(3)
                .where((location) => widget.selectedIds.contains(location.id)),
          ];
    final uniqueVisible = <String, _SavingsLocation>{
      for (final location in visible) location.id: location,
    }.values.toList();
    final status = savingsAssignmentStatus(
      assignedAmount: widget.assignedAmount,
      totalAmount: widget.totalAmount,
    );

    return Container(
      decoration: BoxDecoration(
        color: isSource ? const Color(0xFFF3F4F6) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: isSource
            ? null
            : Border.all(color: const Color(0xFF121212), width: 1),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 1, 4, 5),
            child: Row(
              children: [
                Icon(
                  isSource
                      ? Icons.call_made_rounded
                      : Icons.call_received_rounded,
                  size: 18,
                  color: const Color(0xFF121212),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF121212),
                  ),
                ),
                const SizedBox(width: 8),
                if (isSource)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _SourceAssignmentStatus(
                        status: status,
                        assignedAmount: widget.assignedAmount,
                        totalAmount: widget.totalAmount,
                      ),
                    ),
                  )
                else if (widget.selectedIds.length > 1)
                  Expanded(
                    child: Text(
                      'Split equally - ${currency.formatAmount(_firstSelectedAmount())} each',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  )
                else
                  const Spacer(),
              ],
            ),
          ),
          for (var index = 0; index < uniqueVisible.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _SavingsTransferLocationTile(
              sectionTitle: widget.title,
              id: uniqueVisible[index].id,
              icon: uniqueVisible[index].icon,
              label: uniqueVisible[index].label,
              balance: uniqueVisible[index].balance,
              isSource: isSource,
              oppositeUsed: widget.oppositeSelectedIds.contains(
                uniqueVisible[index].id,
              ),
              selected: widget.selectedIds.contains(uniqueVisible[index].id),
              controller: widget.controllers[uniqueVisible[index].id],
              enabled: widget.enabled,
              onToggle: widget.onToggle,
              onAmountChanged: widget.onAmountChanged,
              onUseFullAmount: widget.onUseFullAmount,
            ),
          ],
          if (!_showAll && locations.length > 4) ...[
            const SizedBox(height: 6),
            InkWell(
              key: ValueKey('show-all-${widget.title}'),
              onTap: () => setState(() => _showAll = true),
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 34,
                child: Center(
                  child: Text(
                    'Show all (${locations.length})',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3F444C),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _firstSelectedAmount() {
    if (widget.selectedIds.isEmpty) return 0;
    return double.tryParse(
          widget.controllers[widget.selectedIds.first]?.text ?? '',
        ) ??
        0;
  }
}

class _SavingsLocation {
  const _SavingsLocation({
    required this.id,
    required this.label,
    required this.balance,
    required this.icon,
  });

  final String id;
  final String label;
  final double balance;
  final Widget icon;
}

class _SourceAssignmentStatus extends StatelessWidget {
  const _SourceAssignmentStatus({
    required this.status,
    required this.assignedAmount,
    required this.totalAmount,
  });

  final SavingsAssignmentStatus status;
  final double assignedAmount;
  final double totalAmount;

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<CurrencyProvider>();
    final difference = centsToMoney(
      (moneyToCents(totalAmount) - moneyToCents(assignedAmount)).abs(),
    );
    final (text, color) = switch (status) {
      SavingsAssignmentStatus.empty => (
        '${currency.formatAmount(totalAmount)} left',
        const Color(0xFF9CA3AF),
      ),
      SavingsAssignmentStatus.partial => (
        '${currency.formatAmount(difference)} left',
        const Color(0xFFF59E0B),
      ),
      SavingsAssignmentStatus.matched => (
        currency.formatAmount(totalAmount),
        const Color(0xFF121212),
      ),
      SavingsAssignmentStatus.over => (
        '${currency.formatAmount(difference)} over',
        const Color(0xFFDC2626),
      ),
    };
    return Row(
      key: ValueKey('source-status-${status.name}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status == SavingsAssignmentStatus.matched) ...[
          const Icon(Icons.check_rounded, size: 15, color: Color(0xFF121212)),
          const SizedBox(width: 2),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

String savingsTransferSummary(BuildContext context, FinancialEntry entry) {
  final currency = context.read<CurrencyProvider>();
  String side(List<SavingsTransferPart> parts) => parts
      .map(
        (part) => '${part.displayName} ${currency.formatAmount(part.amount)}',
      )
      .join(' + ');
  return 'From ${side(entry.savingsSources)} to ${side(entry.savingsDestinations)}';
}

class _SavingsTransferLocationTile extends StatelessWidget {
  const _SavingsTransferLocationTile({
    required this.sectionTitle,
    required this.id,
    required this.icon,
    required this.label,
    required this.balance,
    required this.isSource,
    required this.oppositeUsed,
    required this.selected,
    required this.controller,
    required this.enabled,
    required this.onToggle,
    required this.onAmountChanged,
    required this.onUseFullAmount,
  });

  final String sectionTitle;
  final String id;
  final Widget icon;
  final String label;
  final double balance;
  final bool isSource;
  final bool oppositeUsed;
  final bool selected;
  final TextEditingController? controller;
  final bool enabled;
  final void Function(String id, bool selected) onToggle;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String>? onUseFullAmount;

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<CurrencyProvider>();
    final enteredAmount = double.tryParse(controller?.text ?? '') ?? 0;
    final insufficient = isSource && selected && enteredAmount > balance;
    final zeroBalance = isSource && balance <= 0;
    final canToggle = enabled && !oppositeUsed && (!zeroBalance || selected);
    final dimmed = oppositeUsed || zeroBalance || insufficient || !selected;
    final oppositeLabel = isSource ? 'Used as destination' : 'Used as source';

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: dimmed ? 0.58 : 1,
      child: Column(
        children: [
          AnimatedContainer(
            key: ValueKey('transfer-row-$sectionTitle-$id'),
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: selected
                  ? Border.all(color: const Color(0xFF121212))
                  : null,
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: canToggle ? () => onToggle(id, !selected) : null,
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Checkbox(
                            key: ValueKey(
                              'transfer-checkbox-$sectionTitle-$id',
                            ),
                            value: selected,
                            onChanged: canToggle
                                ? (value) => onToggle(id, value ?? false)
                                : null,
                            activeColor: const Color(0xFF121212),
                            checkColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Center(child: icon),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            oppositeUsed
                                ? oppositeLabel
                                : insufficient
                                ? '${currency.formatAmount(balance)} - Insufficient'
                                : isSource
                                ? currency.formatAmount(balance)
                                : selected && controller != null
                                ? currency.formatAmount(enteredAmount)
                                : '',
                            key: insufficient
                                ? ValueKey('insufficient-$id')
                                : null,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: insufficient
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
                if (selected && isSource && controller != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(40, 0, 8, 7),
                    child: Row(
                      children: [
                        TextButton(
                          key: ValueKey('use-full-$id'),
                          onPressed: enabled
                              ? () => onUseFullAmount?.call(id)
                              : null,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF3F444C),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: const Size(0, 32),
                          ),
                          child: const Text(
                            'Use full amount',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: SizedBox(
                            height: 36,
                            child: TextField(
                              controller: controller,
                              enabled: enabled,
                              onChanged: onAmountChanged,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}'),
                                ),
                              ],
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                              decoration: InputDecoration(
                                prefixText: '${currency.symbol} ',
                                hintText: 'Amount',
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF121212),
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
          ),
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
        const SizedBox(height: 5),
        SizedBox(
          height: 48,
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF121212),
            ),
            decoration: InputDecoration(
              prefixText: '${context.watch<CurrencyProvider>().symbol} ',
              hintText: '0.00',
              prefixStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF121212),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF9CA3AF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF121212)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({required this.label, required this.controller});

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

/// Shared outlined confirm button (also used by the Add Loan dialog).
typedef _ConfirmButton = OutlinedConfirmButton;

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
