import 'dart:async';

import 'package:flutter/material.dart';

import '../models/financial_entry.dart';
import '../models/rate_limit_info.dart';
import '../services/finance_api_service.dart';
import '../services/firestore_finance_service.dart';

class BudgetProvider extends ChangeNotifier {
  BudgetProvider(this._service, {FinanceApiService? financeApi})
    : _api = financeApi ?? FinanceApiService();

  final FirestoreFinanceService _service;
  final FinanceApiService _api;

  /// Single source of truth for total cash on hand.
  double availableBalance = 0;
  double monthlySalary = 0;
  double billsPercentage = 50;
  double savingsPercentage = 20;
  double personalPercentage = 30;

  /// Independent envelope remainings (not live AB × %).
  double _billsRemaining = 0;
  double _savingsRemaining = 0;
  double _personalRemaining = 0;

  double savingsGoalTarget = 10000;
  double savingsGoalCurrent = 0;
  DateTime savingsGoalTargetDate = DateTime(2028, 12, 31);
  String savingsGoalTitle = BudgetDocument.defaultSavingsGoalTitle;

  /// 1–2 = legacy AB×% models. 3 = independent category remainings.
  int budgetSchemaVersion = 1;

  static const savingsGoalEntryTitle = 'Savings Goal';
  static const currentBudgetSchemaVersion = 3;

  String? _uid;
  bool isLoading = false;
  bool isRefreshing = false;
  String? errorMessage;

  /// Set when a Worker finance mutation returns HTTP 429 / rate-limit-exceeded.
  /// Consumed by [RateLimitListener] — do not convert into [errorMessage].
  RateLimitInfo? pendingRateLimit;

  Future<void>? _refreshOperation;

  final Map<FinancialCategory, List<FinancialEntry>> _entries = {
    for (final category in FinancialCategory.values) category: [],
  };
  final Map<FinancialCategory, double> _forfeited = {
    for (final category in FinancialCategory.values) category: 0,
  };
  final List<StreamSubscription<Object?>> _realtimeSubscriptions = [];

  /// Local writes in flight — remote snapshots must not clobber these.
  final Set<String> _pendingUpsertKeys = {};
  final Set<String> _pendingDeleteKeys = {};

  /// In-flight budget field mutations (add money, salary, AB, percentages).
  /// Prevents realtime snapshots from clobbering rollback mid-request.
  int _budgetMutationDepth = 0;
  double? _lockedSavingsGoalCurrent;
  double? _lockedSavingsGoalTarget;
  DateTime? _lockedSavingsGoalTargetDate;
  String? _lockedSavingsGoalTitle;
  final Map<FinancialCategory, double?> _lockedForfeited = {
    for (final category in FinancialCategory.values) category: null,
  };

  String _entryKey(FinancialCategory category, String id) =>
      '${category.name}|$id';

  void _lockSavingsGoal() {
    _lockedSavingsGoalCurrent = savingsGoalCurrent;
    _lockedSavingsGoalTarget = savingsGoalTarget;
    _lockedSavingsGoalTargetDate = savingsGoalTargetDate;
    _lockedSavingsGoalTitle = savingsGoalTitle;
  }

  List<FinancialEntry> _mergeEntriesWithPending(
    FinancialCategory category,
    List<FinancialEntry> remote, {
    required bool confirmPending,
  }) {
    final previous = _entries[category]!;
    final pendingLocals = previous
        .where(
          (entry) =>
              _pendingUpsertKeys.contains(_entryKey(category, entry.id)),
        )
        .where((entry) => !remote.any((item) => item.id == entry.id))
        .toList();
    final filteredRemote = remote
        .where(
          (entry) =>
              !_pendingDeleteKeys.contains(_entryKey(category, entry.id)),
        )
        .toList();

    // Only clear pending markers after backend ack (not local pending writes).
    if (confirmPending) {
      for (final entry in remote) {
        _pendingUpsertKeys.remove(_entryKey(category, entry.id));
      }
      _pendingDeleteKeys.removeWhere((key) {
        if (!key.startsWith('${category.name}|')) return false;
        final id = key.substring(category.name.length + 1);
        return !remote.any((entry) => entry.id == id);
      });
    }

    final merged = [...pendingLocals, ...filteredRemote];
    merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged;
  }

  List<FinancialEntry> entriesFor(FinancialCategory category) {
    return List.unmodifiable(_entries[category]!);
  }

  double totalUsedFor(FinancialCategory category) {
    final active = _entries[category]!
        .where((entry) => !entry.isRefund)
        .fold<double>(0, (total, entry) => total + entry.amount);
    return active + _forfeited[category]!;
  }

  double get billsAmount => _billsRemaining;
  double get savingsAmount => _savingsRemaining;
  double get personalAmount => _personalRemaining;

  /// Category remaining envelope balance.
  double allocationFor(FinancialCategory category) {
    return switch (category) {
      FinancialCategory.bills => _billsRemaining,
      FinancialCategory.savings => _savingsRemaining,
      FinancialCategory.personal => _personalRemaining,
    };
  }

  /// Spendable in a category (independent remaining).
  double remainingFor(FinancialCategory category) => allocationFor(category);

  double get totalRemainingBalance =>
      _billsRemaining + _savingsRemaining + _personalRemaining;

  double get spendableBalance => availableBalance;

  void _setRemaining(FinancialCategory category, double value) {
    final next = value < 0 ? 0.0 : value;
    switch (category) {
      case FinancialCategory.bills:
        _billsRemaining = next;
      case FinancialCategory.savings:
        _savingsRemaining = next;
      case FinancialCategory.personal:
        _personalRemaining = next;
    }
  }

  void _adjustRemaining(FinancialCategory category, double delta) {
    _setRemaining(category, allocationFor(category) + delta);
  }

  /// Add funds into envelopes by percentage (salary / add money / AB increase).
  /// Applies percentages ONLY to [amount], never to the full Available Balance.
  void _distributeAddedFunds(double amount) {
    if (amount == 0) return;
    _billsRemaining += amount * (billsPercentage / 100);
    _savingsRemaining += amount * (savingsPercentage / 100);
    _personalRemaining += amount * (personalPercentage / 100);
  }

  /// Recalculate all envelopes from the current Available Balance × user %.
  /// Used for manual Available Balance edits and one-time schema migration.
  /// Do NOT use for spending or receive/add money.
  void _reallocateAllFromAvailableBalance() {
    _billsRemaining = availableBalance * (billsPercentage / 100);
    _savingsRemaining = availableBalance * (savingsPercentage / 100);
    _personalRemaining = availableBalance * (personalPercentage / 100);
  }

  Map<String, double> _remainingSnapshot() => {
    'bills': _billsRemaining,
    'savings': _savingsRemaining,
    'personal': _personalRemaining,
    'availableBalance': availableBalance,
  };

  void _restoreRemainings(Map<String, double> snapshot) {
    availableBalance = snapshot['availableBalance']!;
    _billsRemaining = snapshot['bills']!;
    _savingsRemaining = snapshot['savings']!;
    _personalRemaining = snapshot['personal']!;
  }

  double get savingsGoalProgress {
    if (savingsGoalTarget <= 0) return 0;
    return (savingsGoalCurrent / savingsGoalTarget).clamp(0.0, 1.0);
  }


  /// Contributions to the savings goal from Bills / Savings / Personal.
  List<DayTransaction> get savingsGoalActivity {
    final results = <DayTransaction>[];
    for (final category in FinancialCategory.values) {
      for (final entry in _entries[category]!) {
        if (entry.title == savingsGoalEntryTitle && !entry.isRefund) {
          results.add(DayTransaction(category: category, entry: entry));
        }
      }
    }
    results.sort((a, b) => b.entry.createdAt.compareTo(a.entry.createdAt));
    return results;
  }

  /// Monday–Sunday spending totals from Bills + Savings + Personal.
  List<WeeklyDaySpend> get weeklySpending {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));

    const shortLabels = ['M', 'T', 'W', 'Th', 'F', 'Sa', 'Su'];
    const fullLabels = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    final totals = List<double>.filled(7, 0);
    for (final category in FinancialCategory.values) {
      for (final entry in _entries[category]!) {
        if (entry.isRefund) continue;
        final local = entry.createdAt.toLocal();
        final day = DateTime(local.year, local.month, local.day);
        final offset = day.difference(monday).inDays;
        if (offset >= 0 && offset < 7) {
          totals[offset] += entry.amount;
        }
      }
    }

    return List<WeeklyDaySpend>.generate(7, (index) {
      final date = monday.add(Duration(days: index));
      return WeeklyDaySpend(
        shortLabel: shortLabels[index],
        fullLabel: fullLabels[index],
        date: date,
        amount: totals[index],
        isToday: date == today,
      );
    });
  }

  /// All Bills / Savings / Personal transactions for a local calendar day.
  List<DayTransaction> entriesForDay(DateTime day) {
    final target = DateTime(day.year, day.month, day.day);
    final results = <DayTransaction>[];

    for (final category in FinancialCategory.values) {
      for (final entry in _entries[category]!) {
        final local = entry.createdAt.toLocal();
        final entryDay = DateTime(local.year, local.month, local.day);
        if (entryDay == target) {
          results.add(DayTransaction(category: category, entry: entry));
        }
      }
    }

    results.sort((a, b) => b.entry.createdAt.compareTo(a.entry.createdAt));
    return results;
  }

  Future<void>? _activeLoad;
  String? _activeLoadUid;

  /// Loads budget + entries for [uid]. Concurrent calls for the same uid
  /// share one in-flight Future (avoids duplicate loads on rebuild).
  Future<void> loadForUser(String uid) {
    final existing = _activeLoad;
    if (existing != null && _activeLoadUid == uid) {
      return existing;
    }

    late final Future<void> operation;
    operation = _loadForUserBody(uid).whenComplete(() {
      if (identical(_activeLoad, operation)) {
        _activeLoad = null;
        _activeLoadUid = null;
      }
    });
    _activeLoad = operation;
    _activeLoadUid = uid;
    return operation;
  }

  Future<void> _loadForUserBody(String uid) async {
    _cancelRealtimeSync();
    _uid = uid;
    _setDefaults();
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait<Object?>([
        _service.loadBudget(uid),
        for (final category in FinancialCategory.values)
          _service.loadEntries(uid, category),
      ]);
      if (_uid != uid) return;

      final loaded = results[0] as BudgetDocument?;
      if (loaded != null) {
        final budget = loaded.values;
        monthlySalary = budget['monthlySalary']!;
        budgetSchemaVersion =
            (budget['schemaVersion'] ?? 1).round().clamp(1, currentBudgetSchemaVersion);
        _applyForfeited(budget);
        _applySavingsGoal(budget, title: loaded.savingsGoalTitle);
        _applyBudget(
          availableBalance: budget['availableBalance']!,
          billsPercentage: budget['billsPercentage']!,
          savingsPercentage: budget['savingsPercentage']!,
          personalPercentage: budget['personalPercentage']!,
          billsRemaining: budget['billsRemaining'],
          savingsRemaining: budget['savingsRemaining'],
          personalRemaining: budget['personalRemaining'],
        );
      }

      for (var index = 0; index < FinancialCategory.values.length; index++) {
        _entries[FinancialCategory.values[index]] =
            results[index + 1] as List<FinancialEntry>;
      }
      final migrated = _migrateBudgetSchemaIfNeeded();
      _startRealtimeSync(uid);
      if (migrated) {
        unawaited(() async {
          try {
            await _api.migrateBudgetSchema(
              requestId: _api.newRequestId(),
            );
          } catch (error) {
            // Keep local migrated view; next Worker mutation also migrates.
            // Still surface rate-limit UX when the Worker rejects the call.
            _publishRateLimit(error, actionLabel: 'Budget Migration');
          }
        }());
      }
    } catch (_) {
      if (_uid == uid) {
        errorMessage =
            'Saved data could not be loaded. Check your connection and retry.';
      }
    } finally {
      if (_uid == uid) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshAllData() {
    final activeRefresh = _refreshOperation;
    if (activeRefresh != null) return activeRefresh;

    late final Future<void> operation;
    operation = _performRefresh().whenComplete(() {
      if (identical(_refreshOperation, operation)) {
        _refreshOperation = null;
      }
    });
    _refreshOperation = operation;
    return operation;
  }

  Future<void> _performRefresh() async {
    final uid = _requireUid();
    isRefreshing = true;
    notifyListeners();

    try {
      final results = await Future.wait<Object?>([
        _service.loadBudget(uid, serverOnly: true),
        for (final category in FinancialCategory.values)
          _service.loadEntries(uid, category, serverOnly: true),
      ]);
      if (_uid != uid) return;

      final loaded = results[0] as BudgetDocument?;
      if (loaded == null) {
        monthlySalary = 0;
        _clearForfeited();
        _resetSavingsGoal();
        _applyBudget(
          availableBalance: 0,
          billsPercentage: 50,
          savingsPercentage: 20,
          personalPercentage: 30,
          billsRemaining: 0,
          savingsRemaining: 0,
          personalRemaining: 0,
        );
      } else {
        final budget = loaded.values;
        monthlySalary = budget['monthlySalary']!;
        budgetSchemaVersion =
            (budget['schemaVersion'] ?? 1).round().clamp(1, currentBudgetSchemaVersion);
        _applyBudget(
          availableBalance: budget['availableBalance']!,
          billsPercentage: budget['billsPercentage']!,
          savingsPercentage: budget['savingsPercentage']!,
          personalPercentage: budget['personalPercentage']!,
          billsRemaining: budget['billsRemaining'],
          savingsRemaining: budget['savingsRemaining'],
          personalRemaining: budget['personalRemaining'],
        );
        if (_lockedSavingsGoalCurrent == null) {
          _applySavingsGoal(budget, title: loaded.savingsGoalTitle);
        } else {
          savingsGoalCurrent = _lockedSavingsGoalCurrent!;
          savingsGoalTarget = _lockedSavingsGoalTarget!;
          savingsGoalTargetDate = _lockedSavingsGoalTargetDate!;
          savingsGoalTitle =
              _lockedSavingsGoalTitle ?? BudgetDocument.defaultSavingsGoalTitle;
        }
        if (_lockedForfeited.values.every((value) => value == null)) {
          _applyForfeited(budget);
        } else {
          for (final category in FinancialCategory.values) {
            final locked = _lockedForfeited[category];
            if (locked != null) {
              _forfeited[category] = locked;
            } else {
              _forfeited[category] = switch (category) {
                FinancialCategory.bills => budget['forfeitedBills'] ?? 0,
                FinancialCategory.savings => budget['forfeitedSavings'] ?? 0,
                FinancialCategory.personal => budget['forfeitedPersonal'] ?? 0,
              };
            }
          }
        }
        _migrateBudgetSchemaIfNeeded();
      }

      for (var index = 0; index < FinancialCategory.values.length; index++) {
        final category = FinancialCategory.values[index];
        final remote = results[index + 1] as List<FinancialEntry>;
        _entries[category] = _mergeEntriesWithPending(
          category,
          remote,
          confirmPending: true,
        );
      }
      errorMessage = null;
      notifyListeners();
    } catch (_) {
      if (_uid == uid) {
        errorMessage =
            'Could not refresh your data. Check your connection and retry.';
        notifyListeners();
      }
      rethrow;
    } finally {
      if (_uid == uid) {
        isRefreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> updateBudget({
    required double monthlySalary,
    double? billsPercentage,
    double? savingsPercentage,
    double? personalPercentage,
  }) async {
    _requireUid();
    final nextBills = billsPercentage ?? this.billsPercentage;
    final nextSavings = savingsPercentage ?? this.savingsPercentage;
    final nextPersonal = personalPercentage ?? this.personalPercentage;
    final total = nextBills + nextSavings + nextPersonal;
    if (monthlySalary < 0 || (total - 100).abs() > 0.001) {
      throw ArgumentError('Budget percentages must total 100.');
    }

    final previous = _remainingSnapshot();
    final previousSalary = this.monthlySalary;
    final previousPct = (
      bills: this.billsPercentage,
      savings: this.savingsPercentage,
      personal: this.personalPercentage,
    );
    this.monthlySalary = monthlySalary;
    // Percentages only affect future new money — never reset envelopes.
    this.billsPercentage = nextBills;
    this.savingsPercentage = nextSavings;
    this.personalPercentage = nextPersonal;
    errorMessage = null;
    notifyListeners();

    try {
      await _api.updateMonthlySalary(
        monthlySalary: monthlySalary,
        requestId: _api.newRequestId(),
      );
      await _api.updatePercentages(
        billsPercentage: nextBills,
        savingsPercentage: nextSavings,
        personalPercentage: nextPersonal,
        requestId: _api.newRequestId(),
      );
    } catch (error) {
      this.monthlySalary = previousSalary;
      this.billsPercentage = previousPct.bills;
      this.savingsPercentage = previousPct.savings;
      this.personalPercentage = previousPct.personal;
      _restoreRemainings(previous);
      _reportMutationFailure(
        error,
        fallback: 'Budget changes could not be saved.',
        rateLimitAction: 'Budget',
      );
      rethrow;
    }
  }

  Future<void> receiveSalary() async {
    _requireUid();
    if (monthlySalary <= 0) {
      throw StateError('Set a monthly salary before receiving it.');
    }

    final salary = monthlySalary;
    errorMessage = null;
    _budgetMutationDepth++;
    try {
      await _api.receiveSalary(requestId: _api.newRequestId());
      availableBalance += salary;
      _distributeAddedFunds(salary);
      notifyListeners();
    } catch (error) {
      _reportMutationFailure(
        error,
        fallback: 'Salary could not be received. Please try again.',
        rateLimitAction: 'Receive Salary',
      );
      rethrow;
    } finally {
      _budgetMutationDepth--;
    }
  }

  Future<void> addMoney(double amount) async {
    _requireUid();
    if (amount <= 0) {
      throw ArgumentError('Amount must be greater than zero.');
    }

    // Do not optimistically credit funds. A rejected/rate-limited Worker call
    // must leave balances unchanged (no flash-add, no listener races).
    errorMessage = null;
    _budgetMutationDepth++;
    try {
      await _api.addMoney(
        amount: amount,
        requestId: _api.newRequestId(),
      );
      availableBalance += amount;
      _distributeAddedFunds(amount);
      notifyListeners();
    } catch (error) {
      _reportMutationFailure(
        error,
        fallback: 'Money could not be added. Please try again.',
        rateLimitAction: 'Add Money',
      );
      rethrow;
    } finally {
      _budgetMutationDepth--;
    }
  }

  Future<void> updateAvailableBalance(double newBalance) async {
    _requireUid();
    if (newBalance < 0) {
      throw ArgumentError('Available balance cannot be negative.');
    }

    final previous = _remainingSnapshot();
    availableBalance = newBalance;
    // Manual AB edit: always recalculate all categories from the new total
    // using the user's current percentages (not incremental delta).
    _reallocateAllFromAvailableBalance();
    errorMessage = null;
    notifyListeners();

    try {
      await _api.updateAvailableBalance(
          availableBalance: newBalance,
          requestId: _api.newRequestId(),
        );
    } catch (error) {
      _restoreRemainings(previous);
      _reportMutationFailure(
        error,
        fallback: 'Available balance could not be updated.',
        rateLimitAction: 'Available Balance',
      );
      rethrow;
    }
  }

  Future<void> updatePercentages({
    required double billsPercentage,
    required double savingsPercentage,
    required double personalPercentage,
  }) async {
    _requireUid();
    final total = billsPercentage + savingsPercentage + personalPercentage;
    if ((total - 100).abs() > 0.001) {
      throw ArgumentError('Budget percentages must total 100.');
    }

    final previousPct = (
      bills: this.billsPercentage,
      savings: this.savingsPercentage,
      personal: this.personalPercentage,
    );
    // Only update rates for future new money — keep existing envelopes intact.
    this.billsPercentage = billsPercentage;
    this.savingsPercentage = savingsPercentage;
    this.personalPercentage = personalPercentage;
    errorMessage = null;
    notifyListeners();

    try {
      await _api.updatePercentages(
          billsPercentage: billsPercentage,
          savingsPercentage: savingsPercentage,
          personalPercentage: personalPercentage,
          requestId: _api.newRequestId(),
        );
    } catch (error) {
      this.billsPercentage = previousPct.bills;
      this.savingsPercentage = previousPct.savings;
      this.personalPercentage = previousPct.personal;
      _reportMutationFailure(
        error,
        fallback: 'Percentages could not be updated.',
        rateLimitAction: 'Budget Percentages',
      );
      rethrow;
    }
  }

  Future<void> updateMonthlySalary(double monthlySalary) async {
    _requireUid();
    if (monthlySalary < 0) {
      throw ArgumentError('Monthly salary cannot be negative.');
    }

    final previousSalary = this.monthlySalary;
    this.monthlySalary = monthlySalary;
    errorMessage = null;
    notifyListeners();

    try {
      await _api.updateMonthlySalary(
          monthlySalary: monthlySalary,
          requestId: _api.newRequestId(),
        );
    } catch (error) {
      this.monthlySalary = previousSalary;
      _reportMutationFailure(
        error,
        fallback: 'Monthly salary could not be updated.',
        rateLimitAction: 'Monthly Salary',
      );
      rethrow;
    }
  }

  Future<void> addEntry(
    FinancialCategory category, {
    required String title,
    required double amount,
    String? iconAsset,
    bool awaitRemote = false,
  }) async {
    final uid = _requireUid();
    if (amount <= 0 || amount > remainingFor(category) + 0.001) {
      throw ArgumentError('Amount exceeds the available category balance.');
    }
    final trimmedIcon = iconAsset?.trim();
    final entry = FinancialEntry(
      id: _service.createEntryId(uid, category),
      title: title.trim(),
      amount: amount,
      createdAt: DateTime.now(),
      iconAsset: (trimmedIcon != null && trimmedIcon.isNotEmpty)
          ? trimmedIcon
          : null,
    );
    final key = _entryKey(category, entry.id);
    final previous = _remainingSnapshot();
    final requestId = _api.newRequestId();

    _entries[category]!.insert(0, entry);
    availableBalance = (previous['availableBalance']! - amount).clamp(
      0,
      double.infinity,
    );
    _adjustRemaining(category, -amount);
    _pendingUpsertKeys.add(key);
    errorMessage = null;
    notifyListeners();

    Future<void> persist() async {
      try {
        await _api.addTransaction(
          category: category.collection,
          title: entry.title,
          amount: amount,
          entryId: entry.id,
          createdAtMs: entry.createdAt.millisecondsSinceEpoch,
          requestId: requestId,
          iconAsset: entry.iconAsset,
        );
      } catch (error) {
        _entries[category]!.removeWhere((item) => item.id == entry.id);
        _pendingUpsertKeys.remove(key);
        _restoreRemainings(previous);
        _reportMutationFailure(
          error,
          fallback: 'The entry could not be saved.',
          rateLimitAction: _categoryRateLimitLabel(category),
        );
        rethrow;
      }
    }

    if (awaitRemote) {
      await persist();
    } else {
      unawaited(persist());
    }
  }

  Future<void> updateEntry(
    FinancialCategory category,
    FinancialEntry updated,
  ) async {
    _requireUid();
    final list = _entries[category]!;
    final index = list.indexWhere((item) => item.id == updated.id);
    if (index < 0) return;

    final previousEntry = list[index];
    final delta = updated.amount - previousEntry.amount;
    final availableForEdit = remainingFor(category) + previousEntry.amount;
    if (updated.amount <= 0 || updated.amount > availableForEdit + 0.001) {
      throw ArgumentError('Amount exceeds the available category balance.');
    }

    final previous = _remainingSnapshot();
    list[index] = updated;
    availableBalance = (previous['availableBalance']! - delta).clamp(
      0,
      double.infinity,
    );
    _adjustRemaining(category, -delta);
    errorMessage = null;
    notifyListeners();

    try {
      await _api.updateTransaction(
          category: category.collection,
          entryId: updated.id,
          title: updated.title,
          amount: updated.amount,
          requestId: _api.newRequestId(),
          iconAsset: updated.iconAsset,
        );
    } catch (error) {
      list[index] = previousEntry;
      _restoreRemainings(previous);
      _reportMutationFailure(
        error,
        fallback: 'The entry could not be updated.',
        rateLimitAction: _categoryRateLimitLabel(category),
      );
      rethrow;
    }
  }

  Future<void> updateSavingsGoalSettings({
    required double target,
    required DateTime targetDate,
    String? title,
  }) async {
    _requireUid();
    if (target <= 0) {
      throw ArgumentError('Goal amount must be greater than zero.');
    }
    final nextTitle = (title ?? savingsGoalTitle).trim();
    if (nextTitle.isEmpty) {
      throw ArgumentError('Goal title cannot be empty.');
    }

    final previousTarget = savingsGoalTarget;
    final previousDate = savingsGoalTargetDate;
    final previousTitle = savingsGoalTitle;
    savingsGoalTarget = target;
    savingsGoalTargetDate = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );
    savingsGoalTitle = nextTitle;
    errorMessage = null;
    _lockSavingsGoal();
    notifyListeners();

    // Persist in background so the edit UI is not blocked on network.
    unawaited(() async {
      try {
        await _api.updateSavingsGoalSettings(
            target: target,
            targetDateMs: savingsGoalTargetDate.millisecondsSinceEpoch,
            title: nextTitle,
            requestId: _api.newRequestId(),
          );
      } catch (error) {
        savingsGoalTarget = previousTarget;
        savingsGoalTargetDate = previousDate;
        savingsGoalTitle = previousTitle;
        _lockSavingsGoal();
        _reportMutationFailure(
          error,
          fallback: 'Savings goal could not be updated.',
          rateLimitAction: 'Savings Goal',
        );
      }
    }());
  }

  Future<void> contributeToSavingsGoal({
    required FinancialCategory source,
    required double amount,
  }) async {
    final uid = _requireUid();
    if (amount <= 0) {
      throw ArgumentError('Amount must be greater than zero.');
    }
    if (amount > remainingFor(source) + 0.001) {
      throw ArgumentError('Amount exceeds the available category balance.');
    }

    final previousCurrent = savingsGoalCurrent;
    final previous = _remainingSnapshot();
    final entry = FinancialEntry(
      id: _service.createEntryId(uid, source),
      title: savingsGoalEntryTitle,
      amount: amount,
      createdAt: DateTime.now(),
    );
    final key = _entryKey(source, entry.id);
    final requestId = _api.newRequestId();

    _entries[source]!.insert(0, entry);
    availableBalance = (previous['availableBalance']! - amount).clamp(
      0,
      double.infinity,
    );
    _adjustRemaining(source, -amount);
    savingsGoalCurrent = previousCurrent + amount;
    _pendingUpsertKeys.add(key);
    _lockSavingsGoal();
    errorMessage = null;
    notifyListeners();

    // Persist in background so the contribute modal can close immediately.
    // Pending upsert/goal locks stay until remote snapshots confirm.
    unawaited(() async {
      try {
        await _api.contributeToSavingsGoal(
            source: source.collection,
            amount: amount,
            entryId: entry.id,
            createdAtMs: entry.createdAt.millisecondsSinceEpoch,
            requestId: requestId,
          );
      } catch (error) {
        _entries[source]!.removeWhere((item) => item.id == entry.id);
        _pendingUpsertKeys.remove(key);
        _restoreRemainings(previous);
        savingsGoalCurrent = previousCurrent;
        _lockSavingsGoal();
        _reportMutationFailure(
          error,
          fallback: 'Could not add to your savings goal.',
          rateLimitAction: 'Savings Goal',
        );
      }
    }());
  }

  /// Removes [entry], or converts it to a refund credit when [refund] is true.
  ///
  /// When [refund] is true, money returns to Available Balance and the source
  /// category (and Savings Goal decreases for goal contributions). The row
  /// stays in history as a green refund credit.
  /// When [refund] is false, only the transaction is removed — balances stay
  /// as they are.
  Future<void> deleteEntry(
    FinancialCategory category,
    FinancialEntry entry, {
    bool refund = true,
  }) async {
    _requireUid();
    final list = _entries[category]!;
    final index = list.indexWhere((item) => item.id == entry.id);
    if (index < 0) return;

    // Already-refunded rows can only be deleted from history.
    final shouldRefund = refund && !entry.isRefund;
    final previousGoalCurrent = savingsGoalCurrent;
    final previous = _remainingSnapshot();
    final previousEntry = entry;
    final isGoalContribution = entry.title == savingsGoalEntryTitle;
    final key = _entryKey(category, entry.id);
    final requestId = _api.newRequestId();

    if (shouldRefund) {
      final refunded = entry.copyWith(isRefund: true);
      list[index] = refunded;
      availableBalance = previous['availableBalance']! + entry.amount;
      _adjustRemaining(category, entry.amount);
      if (isGoalContribution) {
        savingsGoalCurrent = (previousGoalCurrent - entry.amount).clamp(
          0,
          double.infinity,
        );
        _lockSavingsGoal();
      }
      _pendingUpsertKeys.add(key);
      errorMessage = null;
      notifyListeners();

      unawaited(() async {
        try {
          await _api.deleteTransaction(
              category: category.collection,
              entryId: entry.id,
              refund: true,
              requestId: requestId,
            );
        } catch (error) {
          list[index] = previousEntry;
          _restoreRemainings(previous);
          savingsGoalCurrent = previousGoalCurrent;
          _pendingUpsertKeys.remove(key);
          if (isGoalContribution) {
            _lockSavingsGoal();
          }
          _reportMutationFailure(
            error,
            fallback: 'The entry could not be refunded.',
            rateLimitAction: isGoalContribution
                ? 'Savings Goal'
                : _categoryRateLimitLabel(category),
          );
        }
      }());
      return;
    }

    list.removeAt(index);
    _pendingDeleteKeys.add(key);
    errorMessage = null;
    notifyListeners();

    // Persist in background so swipe actions are not blocked on network.
    unawaited(() async {
      try {
        await _api.deleteTransaction(
            category: category.collection,
            entryId: entry.id,
            refund: false,
            requestId: requestId,
          );
      } catch (error) {
        list.insert(index, entry);
        _pendingDeleteKeys.remove(key);
        _reportMutationFailure(
          error,
          fallback: 'The entry could not be deleted.',
          rateLimitAction: _categoryRateLimitLabel(category),
        );
      }
    }());
  }

  void reset() {
    _cancelRealtimeSync();
    _uid = null;
    isLoading = false;
    isRefreshing = false;
    _refreshOperation = null;
    errorMessage = null;
    pendingRateLimit = null;
    _pendingUpsertKeys.clear();
    _pendingDeleteKeys.clear();
    _lockedSavingsGoalCurrent = null;
    _lockedSavingsGoalTarget = null;
    _lockedSavingsGoalTargetDate = null;
    _lockedSavingsGoalTitle = null;
    for (final category in FinancialCategory.values) {
      _lockedForfeited[category] = null;
    }
    _setDefaults();
    notifyListeners();
  }

  String _requireUid() {
    final uid = _uid;
    if (uid == null) throw StateError('No authenticated user is loaded.');
    return uid;
  }

  void _setDefaults() {
    monthlySalary = 0;
    budgetSchemaVersion = currentBudgetSchemaVersion;
    _clearForfeited();
    _resetSavingsGoal();
    _applyBudget(
      availableBalance: 0,
      billsPercentage: 50,
      savingsPercentage: 20,
      personalPercentage: 30,
      billsRemaining: 0,
      savingsRemaining: 0,
      personalRemaining: 0,
    );
    for (final entries in _entries.values) {
      entries.clear();
    }
  }

  /// Migrates to schema 3 independent envelopes.
  /// v1: pot − used → spendable AB, then seed envelopes.
  /// v2: AB×% live → seed stored remainings from AB × %.
  bool _migrateBudgetSchemaIfNeeded() {
    final missingRemainings =
        availableBalance > 0.001 && totalRemainingBalance < 0.001;
    if (budgetSchemaVersion >= currentBudgetSchemaVersion &&
        !missingRemainings) {
      return false;
    }

    if (budgetSchemaVersion < 2) {
      var legacySpendable = 0.0;
      for (final category in FinancialCategory.values) {
        final pct = switch (category) {
          FinancialCategory.bills => billsPercentage,
          FinancialCategory.savings => savingsPercentage,
          FinancialCategory.personal => personalPercentage,
        };
        final allocated = availableBalance * (pct / 100);
        legacySpendable += allocated - totalUsedFor(category);
      }
      availableBalance = legacySpendable.clamp(0, double.infinity);
      _clearForfeited();
    }

    _reallocateAllFromAvailableBalance();
    budgetSchemaVersion = currentBudgetSchemaVersion;
    return true;
  }

  void _clearForfeited() {
    for (final category in FinancialCategory.values) {
      _forfeited[category] = 0;
    }
  }

  void _resetSavingsGoal() {
    savingsGoalTarget = 10000;
    savingsGoalCurrent = 0;
    savingsGoalTargetDate = DateTime(2028, 12, 31);
    savingsGoalTitle = BudgetDocument.defaultSavingsGoalTitle;
  }

  void _applyForfeited(Map<String, double> budget) {
    _forfeited[FinancialCategory.bills] = budget['forfeitedBills'] ?? 0;
    _forfeited[FinancialCategory.savings] = budget['forfeitedSavings'] ?? 0;
    _forfeited[FinancialCategory.personal] = budget['forfeitedPersonal'] ?? 0;
  }

  void _applySavingsGoal(Map<String, double> budget, {String? title}) {
    savingsGoalTarget = budget['savingsGoalTarget'] ?? 10000;
    savingsGoalCurrent = budget['savingsGoalCurrent'] ?? 0;
    final ms = budget['savingsGoalTargetDateMs'];
    savingsGoalTargetDate = ms == null
        ? DateTime(2028, 12, 31)
        : DateTime.fromMillisecondsSinceEpoch(ms.round());
    if (title != null) {
      final trimmed = title.trim();
      savingsGoalTitle = trimmed.isEmpty
          ? BudgetDocument.defaultSavingsGoalTitle
          : trimmed;
    }
  }

  String _userFacingError(Object error, {required String fallback}) {
    if (error is FinanceApiException) {
      return error.message;
    }
    return fallback;
  }

  void clearPendingRateLimit() {
    if (pendingRateLimit == null) return;
    pendingRateLimit = null;
    notifyListeners();
  }

  /// Publishes a rate-limit event for the UI. Returns true when handled.
  bool _publishRateLimit(Object error, {String? actionLabel}) {
    if (!FinanceApiException.isRateLimitError(error)) return false;
    final apiError = error as FinanceApiException;
    pendingRateLimit = RateLimitInfo(
      code: apiError.code,
      statusCode: apiError.statusCode ?? 429,
      retryAfterSeconds: apiError.retryAfterSeconds,
      bucket: apiError.bucket,
      actionLabel: actionLabel ?? RateLimitInfo.labelForBucket(apiError.bucket),
    );
    errorMessage = null;
    notifyListeners();
    return true;
  }

  void _reportMutationFailure(
    Object error, {
    required String fallback,
    String? rateLimitAction,
  }) {
    if (_publishRateLimit(error, actionLabel: rateLimitAction)) return;
    errorMessage = _userFacingError(error, fallback: fallback);
    notifyListeners();
  }

  String _categoryRateLimitLabel(FinancialCategory category) {
    switch (category) {
      case FinancialCategory.bills:
        return 'Bills';
      case FinancialCategory.savings:
        return 'Savings';
      case FinancialCategory.personal:
        return 'Personal';
    }
  }


  void _applyBudget({
    required double availableBalance,
    required double billsPercentage,
    required double savingsPercentage,
    required double personalPercentage,
    double? billsRemaining,
    double? savingsRemaining,
    double? personalRemaining,
  }) {
    this.availableBalance = availableBalance;
    this.billsPercentage = billsPercentage;
    this.savingsPercentage = savingsPercentage;
    this.personalPercentage = personalPercentage;
    if (billsRemaining != null &&
        savingsRemaining != null &&
        personalRemaining != null) {
      _billsRemaining = billsRemaining < 0 ? 0 : billsRemaining;
      _savingsRemaining = savingsRemaining < 0 ? 0 : savingsRemaining;
      _personalRemaining = personalRemaining < 0 ? 0 : personalRemaining;
    }
  }

  void _startRealtimeSync(String uid) {
    _realtimeSubscriptions.add(
      _service.watchBudget(uid).listen((snapshot) {
        if (_uid != uid || snapshot.budget == null) return;
        final loaded = snapshot.budget!;
        final budget = loaded.values;

        final remoteGoal = budget['savingsGoalCurrent'] ?? 0;
        final remoteTarget = budget['savingsGoalTarget'] ?? 10000;
        final canConfirm = !snapshot.hasPendingWrites;

        if (canConfirm &&
            _lockedSavingsGoalCurrent != null &&
            (remoteGoal - _lockedSavingsGoalCurrent!).abs() < 0.001 &&
            (remoteTarget - _lockedSavingsGoalTarget!).abs() < 0.001) {
          _lockedSavingsGoalCurrent = null;
          _lockedSavingsGoalTarget = null;
          _lockedSavingsGoalTargetDate = null;
          _lockedSavingsGoalTitle = null;
        }

        if (canConfirm) {
          for (final category in FinancialCategory.values) {
            final locked = _lockedForfeited[category];
            if (locked == null) continue;
            final remoteForfeit = switch (category) {
              FinancialCategory.bills => budget['forfeitedBills'] ?? 0,
              FinancialCategory.savings => budget['forfeitedSavings'] ?? 0,
              FinancialCategory.personal => budget['forfeitedPersonal'] ?? 0,
            };
            if ((remoteForfeit - locked).abs() < 0.001) {
              _lockedForfeited[category] = null;
            }
          }
        }

        monthlySalary = budget['monthlySalary']!;
        budgetSchemaVersion =
            (budget['schemaVersion'] ?? budgetSchemaVersion.toDouble())
                .round()
                .clamp(1, currentBudgetSchemaVersion);

        final hasPendingLocalBudget =
            _pendingUpsertKeys.isNotEmpty ||
            _pendingDeleteKeys.isNotEmpty ||
            _budgetMutationDepth > 0;
        if (!hasPendingLocalBudget) {
          final remoteAb = budget['availableBalance']!;
          _applyBudget(
            availableBalance: remoteAb,
            billsPercentage: budget['billsPercentage']!,
            savingsPercentage: budget['savingsPercentage']!,
            personalPercentage: budget['personalPercentage']!,
            billsRemaining: budget['billsRemaining'],
            savingsRemaining: budget['savingsRemaining'],
            personalRemaining: budget['personalRemaining'],
          );
        } else {
          // Keep optimistic AB/envelopes; still sync percentage labels.
          billsPercentage = budget['billsPercentage']!;
          savingsPercentage = budget['savingsPercentage']!;
          personalPercentage = budget['personalPercentage']!;
        }

        if (_lockedSavingsGoalCurrent == null) {
          _applySavingsGoal(budget, title: loaded.savingsGoalTitle);
        } else {
          savingsGoalCurrent = _lockedSavingsGoalCurrent!;
          savingsGoalTarget = _lockedSavingsGoalTarget!;
          savingsGoalTargetDate = _lockedSavingsGoalTargetDate!;
          savingsGoalTitle =
              _lockedSavingsGoalTitle ?? BudgetDocument.defaultSavingsGoalTitle;
        }

        if (_lockedForfeited.values.every((value) => value == null)) {
          _applyForfeited(budget);
        } else {
          for (final category in FinancialCategory.values) {
            final locked = _lockedForfeited[category];
            if (locked != null) {
              _forfeited[category] = locked;
            } else {
              _forfeited[category] = switch (category) {
                FinancialCategory.bills => budget['forfeitedBills'] ?? 0,
                FinancialCategory.savings => budget['forfeitedSavings'] ?? 0,
                FinancialCategory.personal => budget['forfeitedPersonal'] ?? 0,
              };
            }
          }
        }

        notifyListeners();
      }, onError: (_) => _handleRealtimeError(uid)),
    );

    for (final category in FinancialCategory.values) {
      _realtimeSubscriptions.add(
        _service.watchEntries(uid, category).listen((snapshot) {
          if (_uid != uid) return;
          _entries[category] = _mergeEntriesWithPending(
            category,
            snapshot.entries,
            confirmPending: !snapshot.hasPendingWrites,
          );
          notifyListeners();
        }, onError: (_) => _handleRealtimeError(uid)),
      );
    }
  }

  void _handleRealtimeError(String uid) {
    if (_uid != uid) return;
    errorMessage = 'Live updates are temporarily unavailable.';
    notifyListeners();
  }

  void _cancelRealtimeSync() {
    for (final subscription in _realtimeSubscriptions) {
      subscription.cancel();
    }
    _realtimeSubscriptions.clear();
  }

  @override
  void dispose() {
    _cancelRealtimeSync();
    super.dispose();
  }
}

class WeeklyDaySpend {
  const WeeklyDaySpend({
    required this.shortLabel,
    required this.fullLabel,
    required this.date,
    required this.amount,
    required this.isToday,
  });

  final String shortLabel;
  final String fullLabel;
  final DateTime date;
  final double amount;
  final bool isToday;
}

class DayTransaction {
  const DayTransaction({required this.category, required this.entry});

  final FinancialCategory category;
  final FinancialEntry entry;
}
