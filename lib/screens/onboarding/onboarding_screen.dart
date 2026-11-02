import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/app_currency.dart';
import '../../models/onboarding_state.dart';
import '../../providers/budget_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/loan_provider.dart';
import '../../providers/notification_prefs_provider.dart';
import '../../providers/wallet_cards_provider.dart';
import '../../providers/wallet_cash_provider.dart';
import '../../services/notification_service.dart';
import '../../services/onboarding_service.dart';
import '../../services/onboarding_save_runner.dart';
import '../../widgets/bank_card_picker.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.uid,
    required this.onClosed,
    this.existingStatus,
    this.isRerun = false,
  });

  final String uid;
  final OnboardingStatus? existingStatus;
  final bool isRerun;
  final ValueChanged<OnboardingStatus?> onClosed;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _slideCount = 6;
  static const _currencyStep = 'currency';
  static const _budgetStep = 'budget';
  static const _walletStep = 'wallet';
  static const _balanceStep = 'balance';

  final _pageController = PageController();
  final _incomeController = TextEditingController();
  final _cashController = TextEditingController();
  final _percentageControllers = List.generate(
    3,
    (_) => TextEditingController(),
  );
  final _percentageInputsValid = <bool>[true, true, true];
  final Map<String, TextEditingController> _cardControllers = {};
  final OnboardingSaveRunner _saveRunner = OnboardingSaveRunner();

  OnboardingDraft? _draft;
  Future<void> _draftWrite = Future<void>.value();
  bool _loading = true;
  bool _saving = false;
  bool _permissionDenied = false;
  bool _closed = false;
  OnboardingService? _service;

  OnboardingDraft get draft => _draft!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _pageController.dispose();
    _incomeController.dispose();
    _cashController.dispose();
    for (final controller in _percentageControllers) {
      controller.dispose();
    }
    for (final controller in _cardControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final service = context.read<OnboardingService>();
    _service = service;
    final saved = await service.loadDraft(widget.uid);
    if (!mounted) return;
    final budget = context.read<BudgetProvider>();
    final currency = context.read<CurrencyProvider>();
    final cash = context.read<WalletCashProvider>();
    final cards = context.read<WalletCardsProvider>();
    final prefs = context.read<NotificationPrefsProvider>();
    final initial =
        saved ??
        OnboardingDraft(
          currencyCode: currency.code,
          monthlyIncome: budget.monthlySalary,
          billsPercentage: budget.billsPercentage.round(),
          savingsPercentage: budget.savingsPercentage.round(),
          personalPercentage: budget.personalPercentage.round(),
          walletCash: cash.amount,
          selectedCards: cards.cards.map((card) => card.iconAsset).toSet(),
          cardAmounts: {
            for (final card in cards.cards) card.iconAsset: card.amount,
          },
          dailyReminder: prefs.dailyEnabled,
          loanReminders: prefs.loanEnabled,
          budgetAlerts: prefs.plannerEnabled,
        );
    initial.slide = initial.slide.clamp(0, _slideCount - 1);
    _draft = initial;
    _incomeController.text =
        initial.monthlyIncome == null || initial.monthlyIncome == 0
        ? ''
        : _plainAmount(initial.monthlyIncome!);
    _cashController.text = initial.walletCash == null || initial.walletCash == 0
        ? ''
        : _plainAmount(initial.walletCash!);
    _syncPercentageControllers();
    for (final icon in initial.selectedCards) {
      _cardController(icon).text = _plainAmount(initial.cardAmounts[icon] ?? 0);
    }
    setState(() => _loading = false);
    if (initial.slide > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(initial.slide);
        }
      });
    }
  }

  String _plainAmount(double amount) {
    return amount % 1 == 0
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }

  TextEditingController _cardController(String icon) {
    return _cardControllers.putIfAbsent(icon, TextEditingController.new);
  }

  void _queueDraftSave() {
    if (_draft == null) return;
    final snapshot = OnboardingDraft.decode(draft.encode());
    final service = _service;
    if (service == null) return;
    _draftWrite = _draftWrite
        .catchError((_) {})
        .then((_) => service.saveDraft(widget.uid, snapshot));
  }

  void _setStateAndSave(VoidCallback change) {
    setState(change);
    _queueDraftSave();
  }

  Future<void> _goTo(int page) async {
    if (_saving || page < 0 || page >= _slideCount) return;
    draft.slide = page;
    _queueDraftSave();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _pageController.jumpToPage(page);
    } else {
      await _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _next() async {
    if (draft.slide == 1 && !draft.incomeEntered) {
      _showMessage(
        'Enter a positive monthly income or choose No regular income.',
      );
      return;
    }
    if (draft.slide == 2 && !_percentageSplitIsValid) {
      await _showPercentageTotalError();
      return;
    }
    if (draft.slide == _slideCount - 1) {
      await _finish();
      return;
    }
    await _goTo(draft.slide + 1);
  }

  Future<void> _back() async {
    if (_saving) return;
    if (draft.slide > 0) {
      await _goTo(draft.slide - 1);
    } else {
      await _skip();
    }
  }

  Future<void> _skip() async {
    if (_saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Skip setup?'),
        content: const Text('You can finish it anytime from Home.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF121212),
            ),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final service = context.read<OnboardingService>();
      OnboardingStatus? result;
      if (widget.isRerun &&
          widget.existingStatus == OnboardingStatus.completed) {
        await service.clearDraft(widget.uid);
        result = OnboardingStatus.completed;
      } else {
        await service.dismiss(widget.uid, step: draft.slide);
        result = OnboardingStatus.dismissed;
      }
      _close(result);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _showMessage(
          'Setup could not be skipped. Check your connection and try again.',
        );
      }
    }
  }

  void _close(OnboardingStatus? status) {
    if (_closed) return;
    _closed = true;
    widget.onClosed(status);
    if (widget.isRerun && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    await _draftWrite.catchError((_) {});
    try {
      await _runSaveSteps();
      if (!mounted) return;
      await context.read<OnboardingService>().complete(
        widget.uid,
        step: _slideCount - 1,
      );
      await _requestCompletionPermission();
      _close(OnboardingStatus.completed);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      await _showSaveFailure();
    }
  }

  Future<void> _runSaveSteps() async {
    final steps = <String>[
      if (draft.currencyTouched) _currencyStep,
      if (draft.incomeEntered || draft.splitTouched) _budgetStep,
      if (draft.cashEntered || draft.cardsTouched) ...[
        _walletStep,
        _balanceStep,
      ],
    ];
    await _saveRunner.run(
      steps: steps,
      completedSteps: draft.completedSaveSteps,
      saveStep: (step) => switch (step) {
        _currencyStep => _saveCurrency(),
        _budgetStep => _saveBudget(),
        _walletStep => _saveWallet(),
        _balanceStep => _saveBalance(),
        _ => throw StateError('Unknown onboarding save step.'),
      },
      markComplete: _markStepComplete,
    );
  }

  Future<void> _saveCurrency() async {
    final saved = await context.read<CurrencyProvider>().setCurrencyVerified(
      AppCurrency.byCode(draft.currencyCode),
    );
    if (!saved) throw StateError('currency-save-failed');
  }

  Future<void> _saveBudget() async {
    final budget = context.read<BudgetProvider>();
    draft.salaryRequestId ??= budget.newRequestId();
    draft.percentagesRequestId ??= budget.newRequestId();
    _queueDraftSave();
    await _draftWrite;
    await budget.updateBudget(
      monthlySalary: draft.incomeEntered
          ? (draft.monthlyIncome ?? 0)
          : budget.monthlySalary,
      billsPercentage: draft.splitTouched
          ? draft.billsPercentage.toDouble()
          : budget.billsPercentage,
      savingsPercentage: draft.splitTouched
          ? draft.savingsPercentage.toDouble()
          : budget.savingsPercentage,
      personalPercentage: draft.splitTouched
          ? draft.personalPercentage.toDouble()
          : budget.personalPercentage,
      salaryRequestId: draft.salaryRequestId,
      percentagesRequestId: draft.percentagesRequestId,
    );
  }

  Future<void> _saveWallet() async {
    final cashProvider = context.read<WalletCashProvider>();
    final cardsProvider = context.read<WalletCardsProvider>();
    if (draft.cashEntered) {
      final saved = await cashProvider.setAmountVerified(draft.walletCash ?? 0);
      if (!saved) throw StateError('cash-save-failed');
    }
    for (final icon in draft.selectedCards) {
      if (!cardsProvider.hasIcon(icon)) {
        final saved = await cardsProvider.addCardVerified(iconAsset: icon);
        if (!saved) throw StateError('card-save-failed');
      }
    }
    final amountsById = <String, double>{};
    for (final icon in draft.selectedCards) {
      final card = cardsProvider.cards
          .where((item) => item.iconAsset == icon)
          .firstOrNull;
      if (card != null && draft.cardAmounts.containsKey(icon)) {
        amountsById[card.id] = draft.cardAmounts[icon] ?? 0;
      }
    }
    final saved = await cardsProvider.setCardAmountsVerified(amountsById);
    if (!saved) throw StateError('card-amount-save-failed');
  }

  Future<void> _saveBalance() async {
    final budget = context.read<BudgetProvider>();
    final cashProvider = context.read<WalletCashProvider>();
    final cardsProvider = context.read<WalletCardsProvider>();
    draft.balanceRequestId ??= budget.newRequestId();
    _queueDraftSave();
    await _draftWrite;
    final total = cardsProvider.combinedTotal(cashProvider.amount);
    await budget.updateAvailableBalance(
      total,
      requestId: draft.balanceRequestId,
    );
  }

  Future<void> _markStepComplete(String step) async {
    draft.completedSaveSteps.add(step);
    _queueDraftSave();
    await _draftWrite;
  }

  Future<void> _showSaveFailure() async {
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Setup was not fully saved'),
        content: const Text(
          'Check your connection and try again. Your progress is safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'continue'),
            child: const Text('Continue anyway'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'retry'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF121212),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'retry') {
      await _finish();
    } else if (choice == 'continue') {
      setState(() => _saving = true);
      try {
        await context.read<OnboardingService>().dismiss(
          widget.uid,
          step: draft.slide,
        );
        await _requestCompletionPermission();
        _close(OnboardingStatus.dismissed);
      } catch (_) {
        if (mounted) {
          setState(() => _saving = false);
          _showMessage('Setup could not be closed. Please try again.');
        }
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _onIncomeChanged(String raw) {
    final value = double.tryParse(raw);
    _setStateAndSave(() {
      draft.monthlyIncome = value;
      draft.noRegularIncome = false;
      draft.incomeEntered = value != null && value > 0;
    });
  }

  void _setNoIncome(bool selected) {
    if (!selected) return;
    _incomeController.clear();
    _setStateAndSave(() {
      draft.monthlyIncome = 0;
      draft.noRegularIncome = true;
      draft.incomeEntered = true;
    });
  }

  void _changePercentage(int index, double raw) {
    final result = rebalancePercentages(
      changedIndex: index,
      value: raw.round(),
      bills: draft.billsPercentage,
      savings: draft.savingsPercentage,
      personal: draft.personalPercentage,
    );
    _setStateAndSave(() {
      draft.billsPercentage = result.bills;
      draft.savingsPercentage = result.savings;
      draft.personalPercentage = result.personal;
      draft.splitTouched = true;
    });
    _percentageInputsValid.fillRange(0, 3, true);
    _syncPercentageControllers();
  }

  void _resetSplit() {
    _setStateAndSave(() {
      draft.billsPercentage = 50;
      draft.savingsPercentage = 20;
      draft.personalPercentage = 30;
      draft.splitTouched = true;
    });
    _percentageInputsValid.fillRange(0, 3, true);
    _syncPercentageControllers();
  }

  bool get _percentageSplitIsValid {
    return _percentageInputsValid.every((valid) => valid) &&
        isValidPercentageSplit(
          bills: draft.billsPercentage,
          savings: draft.savingsPercentage,
          personal: draft.personalPercentage,
        );
  }

  void _syncPercentageControllers() {
    final values = [
      draft.billsPercentage,
      draft.savingsPercentage,
      draft.personalPercentage,
    ];
    for (var index = 0; index < values.length; index++) {
      final text = '${values[index]}';
      final controller = _percentageControllers[index];
      if (controller.text == text) continue;
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void _typePercentage(int index, String raw) {
    final value = int.tryParse(raw);
    final valid = value != null && value >= 0 && value <= 100;
    setState(() {
      _percentageInputsValid[index] = valid;
      if (!valid) return;
      if (index == 0) draft.billsPercentage = value;
      if (index == 1) draft.savingsPercentage = value;
      if (index == 2) draft.personalPercentage = value;
      draft.splitTouched = true;
    });
    if (valid) _queueDraftSave();
  }

  Future<void> _showPercentageTotalError() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Check your budget split',
          style: TextStyle(color: Color(0xFF121212)),
        ),
        content: const Text(
          'Bills, Savings, and Personal must total 100%.',
          style: TextStyle(color: Color(0xFF737983)),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF121212),
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _toggleCard(String icon) {
    final isExisting = context.read<WalletCardsProvider>().cards.any(
      (card) => card.iconAsset == icon,
    );
    if (isExisting) return;
    _setStateAndSave(() {
      if (!draft.selectedCards.add(icon)) {
        draft.selectedCards.remove(icon);
        draft.cardAmounts.remove(icon);
      } else {
        draft.cardAmounts.putIfAbsent(icon, () => 0);
      }
      draft.cardsTouched = true;
    });
  }

  Future<void> _setReminder(String type, bool value) async {
    final prefs = context.read<NotificationPrefsProvider>();
    final previousValue = switch (type) {
      'daily' => draft.dailyReminder,
      'loan' => draft.loanReminders,
      _ => draft.budgetAlerts,
    };
    _setStateAndSave(() {
      if (type == 'daily') draft.dailyReminder = value;
      if (type == 'loan') draft.loanReminders = value;
      if (type == 'planner') draft.budgetAlerts = value;
      draft.remindersTouched = true;
      _permissionDenied = false;
    });
    if (type == 'daily') await prefs.setDailyEnabled(value);
    if (type == 'loan') await prefs.setLoanEnabled(value);
    if (type == 'planner') await prefs.setPlannerEnabled(value);
    if (!shouldRequestOnboardingNotificationPermission(
          previousValue: previousValue,
          nextValue: value,
        ) ||
        !mounted) {
      return;
    }
    if (prefs.permissionDecision == NotificationPermissionDecision.denied) {
      setState(() => _permissionDenied = true);
      return;
    }
    if (prefs.permissionDecision == NotificationPermissionDecision.granted) {
      await NotificationService.instance.syncAll(
        loans: context.read<LoanProvider>().loans,
      );
      return;
    }
    final granted = await NotificationService.instance.requestPermission();
    if (!mounted) return;
    await prefs.setPermissionDecision(
      granted
          ? NotificationPermissionDecision.granted
          : NotificationPermissionDecision.denied,
    );
    if (!mounted) return;
    if (!granted) {
      setState(() => _permissionDenied = true);
      return;
    }
    await NotificationService.instance.syncAll(
      loans: context.read<LoanProvider>().loans,
    );
  }

  Future<void> _requestCompletionPermission() async {
    if (!mounted) return;
    final prefs = context.read<NotificationPrefsProvider>();
    await requestOnboardingCompletionPermissionIfNeeded(
      anyReminderEnabled:
          prefs.dailyEnabled || prefs.loanEnabled || prefs.plannerEnabled,
      decision: prefs.permissionDecision,
      requestPermission: NotificationService.instance.requestPermission,
      saveDecision: prefs.setPermissionDecision,
    );
    if (!mounted ||
        prefs.permissionDecision != NotificationPermissionDecision.granted) {
      return;
    }
    await NotificationService.instance.syncAll(
      loans: context.read<LoanProvider>().loans,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF121212)),
        ),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => _back(),
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                child: Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: _saving ? null : _skip,
                      child: const Text(
                        'Skip',
                        style: TextStyle(color: Color(0xFF737983)),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _welcomeSlide(),
                    _incomeSlide(),
                    _splitSlide(),
                    _startingMoneySlide(),
                    _remindersSlide(),
                    _reviewSlide(),
                  ],
                ),
              ),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _welcomeSlide() {
    return _SlideShell(
      icon: Icons.waving_hand_outlined,
      title: "Let's set up your account",
      description:
          'Income is what you earn regularly. Your balance is the money you have right now.',
      child: Padding(
        padding: const EdgeInsets.only(top: 34),
        child: _BlackButton(
          label: 'Get started',
          onPressed: _saving ? null : _next,
        ),
      ),
    );
  }

  Widget _incomeSlide() {
    final currency = AppCurrency.byCode(draft.currencyCode);
    return _SlideShell(
      icon: Icons.payments_outlined,
      title: 'Income and currency',
      description:
          'Choose how amounts appear and add what you earn each month.',
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: draft.currencyCode,
            decoration: _fieldDecoration('Currency'),
            borderRadius: BorderRadius.circular(24),
            dropdownColor: Colors.white,
            iconEnabledColor: const Color(0xFF121212),
            iconDisabledColor: const Color(0xFF737983),
            style: const TextStyle(
              color: Color(0xFF121212),
              fontWeight: FontWeight.w600,
            ),
            items: [
              for (final item in AppCurrency.all)
                DropdownMenuItem(
                  value: item.code,
                  child: Text(
                    '${item.code}  ${item.name}',
                    style: const TextStyle(color: Color(0xFF121212)),
                  ),
                ),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value == null) return;
                    _setStateAndSave(() {
                      draft.currencyCode = value;
                      draft.currencyTouched = true;
                    });
                  },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _incomeController,
            enabled: !_saving && !draft.noRegularIncome,
            cursorColor: const Color(0xFF121212),
            style: const TextStyle(color: Color(0xFF121212)),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_amountFormatter],
            decoration: _fieldDecoration(
              'Monthly income',
              prefix: currency.symbol,
            ),
            onChanged: _onIncomeChanged,
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: draft.noRegularIncome,
            checkColor: Colors.white,
            fillColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? const Color(0xFF121212)
                  : Colors.transparent;
            }),
            side: const BorderSide(color: Color(0xFF737983)),
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'No regular income',
              style: TextStyle(
                color: Color(0xFF121212),
                fontWeight: FontWeight.w600,
              ),
            ),
            onChanged: _saving ? null : (value) => _setNoIncome(value ?? false),
          ),
        ],
      ),
    );
  }

  Widget _splitSlide() {
    final income = draft.monthlyIncome ?? 0;
    return _SlideShell(
      icon: Icons.pie_chart_outline_rounded,
      title: 'Plan your split',
      description:
          'Set how new money should be divided. The three parts always total 100%.',
      child: Column(
        children: [
          _PercentageSlider(
            label: 'Bills',
            value: draft.billsPercentage,
            amount: income * draft.billsPercentage / 100,
            symbol: AppCurrency.byCode(draft.currencyCode).symbol,
            controller: _percentageControllers[0],
            inputValid: _percentageInputsValid[0],
            enabled: !_saving,
            onChanged: (value) => _changePercentage(0, value),
            onTextChanged: (value) => _typePercentage(0, value),
          ),
          _PercentageSlider(
            label: 'Savings',
            value: draft.savingsPercentage,
            amount: income * draft.savingsPercentage / 100,
            symbol: AppCurrency.byCode(draft.currencyCode).symbol,
            controller: _percentageControllers[1],
            inputValid: _percentageInputsValid[1],
            enabled: !_saving,
            onChanged: (value) => _changePercentage(1, value),
            onTextChanged: (value) => _typePercentage(1, value),
          ),
          _PercentageSlider(
            label: 'Personal',
            value: draft.personalPercentage,
            amount: income * draft.personalPercentage / 100,
            symbol: AppCurrency.byCode(draft.currencyCode).symbol,
            controller: _percentageControllers[2],
            inputValid: _percentageInputsValid[2],
            enabled: !_saving,
            onChanged: (value) => _changePercentage(2, value),
            onTextChanged: (value) => _typePercentage(2, value),
          ),
          TextButton(
            onPressed: _saving ? null : _resetSplit,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF121212),
              disabledForegroundColor: const Color(0xFF737983),
            ),
            child: const Text('Reset to 50 / 20 / 30'),
          ),
        ],
      ),
    );
  }

  Widget _startingMoneySlide() {
    final currency = AppCurrency.byCode(draft.currencyCode);
    return _SlideShell(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Starting money',
      description:
          'Add cash or accounts now, or leave this optional step for later.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _cashController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_amountFormatter],
            decoration: _fieldDecoration(
              'Wallet cash',
              prefix: currency.symbol,
            ),
            onChanged: (raw) {
              _setStateAndSave(() {
                draft.walletCash = double.tryParse(raw) ?? 0;
                draft.cashEntered = raw.trim().isNotEmpty;
              });
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'Bank cards and wallets',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'We never ask for card numbers or CVV.',
            style: TextStyle(color: Color(0xFF737983)),
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.5,
            children: [
              for (final icon in bankCardIconAssets)
                BankCardPickerTile(
                  iconAsset: icon,
                  selected: draft.selectedCards.contains(icon),
                  alreadyAdded: context.read<WalletCardsProvider>().hasIcon(
                    icon,
                  ),
                  onTap: _saving ? () {} : () => _toggleCard(icon),
                ),
            ],
          ),
          for (final icon in draft.selectedCards) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _cardController(icon),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [_amountFormatter],
              decoration: _fieldDecoration(
                '${walletBankLabel(icon)} starting amount',
                prefix: currency.symbol,
              ),
              onChanged: (raw) {
                _setStateAndSave(() {
                  draft.cardAmounts[icon] = double.tryParse(raw) ?? 0;
                  draft.cardsTouched = true;
                });
              },
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Total starting balance: ${currency.symbol}${_startingTotal().toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _remindersSlide() {
    return _SlideShell(
      icon: Icons.notifications_none_rounded,
      title: 'Helpful reminders',
      description:
          'Stay on top of daily tracking, due loans, and budget limits.',
      child: Column(
        children: [
          _ReminderSwitch(
            label: 'Daily reminder',
            value: draft.dailyReminder,
            onChanged: (value) => _setReminder('daily', value),
          ),
          _ReminderSwitch(
            label: 'Loan reminders',
            value: draft.loanReminders,
            onChanged: (value) => _setReminder('loan', value),
          ),
          _ReminderSwitch(
            label: 'Budget alerts',
            value: draft.budgetAlerts,
            onChanged: (value) => _setReminder('planner', value),
          ),
          if (_permissionDenied)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Notifications are not allowed. You can enable them later in device settings.',
                style: TextStyle(
                  color: Color(0xFF737983),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _reviewSlide() {
    final currency = AppCurrency.byCode(draft.currencyCode);
    return _SlideShell(
      icon: Icons.checklist_rounded,
      title: 'Review your setup',
      description: 'Check the choices you made before saving them.',
      child: Column(
        children: [
          _ReviewRow(label: 'Currency', value: currency.code),
          _ReviewRow(
            label: 'Monthly income',
            value: draft.incomeEntered
                ? '${currency.symbol}${(draft.monthlyIncome ?? 0).toStringAsFixed(2)}'
                : 'Not changed',
          ),
          _ReviewRow(
            label: 'Split',
            value: draft.splitTouched
                ? '${draft.billsPercentage}% / ${draft.savingsPercentage}% / ${draft.personalPercentage}%'
                : 'Not changed',
          ),
          _ReviewRow(
            label: 'Starting balance',
            value: draft.cashEntered || draft.cardsTouched
                ? '${currency.symbol}${_startingTotal().toStringAsFixed(2)}'
                : 'Not added',
          ),
          _ReviewRow(
            label: 'Accounts',
            value: '${draft.selectedCards.length} selected',
          ),
          _ReviewRow(
            label: 'Reminders',
            value:
                [
                  if (draft.dailyReminder) 'Daily',
                  if (draft.loanReminders) 'Loans',
                  if (draft.budgetAlerts) 'Budget',
                ].join(', ').isEmpty
                ? 'Off'
                : [
                    if (draft.dailyReminder) 'Daily',
                    if (draft.loanReminders) 'Loans',
                    if (draft.budgetAlerts) 'Budget',
                  ].join(', '),
          ),
        ],
      ),
    );
  }

  double _startingTotal() {
    final cash = draft.cashEntered
        ? (draft.walletCash ?? 0)
        : context.read<WalletCashProvider>().amount;
    return cash +
        draft.selectedCards.fold<double>(
          0,
          (sum, icon) => sum + (draft.cardAmounts[icon] ?? 0),
        );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_slideCount, (index) {
              final active = index == draft.slide;
              return AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                width: active ? 22 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF121212)
                      : const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(99),
                ),
              );
            }),
          ),
          if (draft.slide > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _back,
                    style: _outlineButtonStyle,
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BlackButton(
                    label: draft.slide == _slideCount - 1 ? 'Finish' : 'Next',
                    loading: _saving,
                    onPressed: _saving ? null : _next,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

final _amountFormatter = FilteringTextInputFormatter.allow(
  RegExp(r'^\d*\.?\d{0,2}'),
);

InputDecoration _fieldDecoration(String label, {String? prefix}) {
  return InputDecoration(
    labelText: label,
    prefixText: prefix,
    labelStyle: const TextStyle(color: Color(0xFF737983)),
    floatingLabelStyle: const TextStyle(color: Color(0xFF121212)),
    prefixStyle: const TextStyle(color: Color(0xFF121212)),
    hintStyle: const TextStyle(color: Color(0xFF737983)),
    filled: true,
    fillColor: const Color(0xFFF1F2F4),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(30),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(30),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(30),
      borderSide: const BorderSide(color: Color(0xFF121212)),
    ),
  );
}

final _outlineButtonStyle = OutlinedButton.styleFrom(
  foregroundColor: const Color(0xFF121212),
  minimumSize: const Size.fromHeight(52),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
);

class _SlideShell extends StatelessWidget {
  const _SlideShell({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF121212)),
                ),
                child: Icon(icon, color: const Color(0xFF121212)),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF121212),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF737983),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _BlackButton extends StatelessWidget {
  const _BlackButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF121212),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _PercentageSlider extends StatelessWidget {
  const _PercentageSlider({
    required this.label,
    required this.value,
    required this.amount,
    required this.symbol,
    required this.controller,
    required this.inputValid,
    required this.enabled,
    required this.onChanged,
    required this.onTextChanged,
  });

  final String label;
  final int value;
  final double amount;
  final String symbol;
  final TextEditingController controller;
  final bool inputValid;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<String> onTextChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '$symbol${amount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: '$label percentage',
                  value: '$value percent',
                  child: SizedBox(
                    height: 48,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF121212),
                        inactiveTrackColor: const Color(0xFFE5E7EB),
                        thumbColor: const Color(0xFF121212),
                        overlayColor: const Color(0x1A121212),
                      ),
                      child: Slider(
                        value: value.toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 100,
                        onChanged: enabled ? onChanged : null,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 76,
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  cursorColor: const Color(0xFF121212),
                  style: const TextStyle(
                    color: Color(0xFF121212),
                    fontWeight: FontWeight.w700,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: InputDecoration(
                    suffixText: '%',
                    suffixStyle: const TextStyle(color: Color(0xFF121212)),
                    filled: true,
                    fillColor: const Color(0xFFF1F2F4),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: inputValid
                            ? Colors.transparent
                            : const Color(0xFF121212),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFF121212)),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: onTextChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReminderSwitch extends StatelessWidget {
  const _ReminderSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      value: value,
      activeTrackColor: const Color(0xFF121212),
      onChanged: onChanged,
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F2F4),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF737983),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
