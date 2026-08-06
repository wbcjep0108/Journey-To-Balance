import 'dart:async';

import 'package:flutter/material.dart';

import '../models/financial_entry.dart';
import '../services/firestore_finance_service.dart';

class BudgetProvider extends ChangeNotifier {
  BudgetProvider(this._service);

  final FirestoreFinanceService _service;

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

  /// 1–2 = legacy AB×% models. 3 = independent category remainings.
  int budgetSchemaVersion = 1;

  static const savingsGoalEntryTitle = 'Savings Goal';
  static const currentBudgetSchemaVersion = 3;

  String? _uid;
  bool isLoading = false;
  bool isRefreshing = false;
  String? errorMessage;
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
  double? _lockedSavingsGoalCurrent;
  double? _lockedSavingsGoalTarget;
  DateTime? _lockedSavingsGoalTargetDate;
  final Map<FinancialCategory, double?> _lockedForfeited = {
    for (final category in FinancialCategory.values) category: null,
  };

  String _entryKey(FinancialCategory category, String id) =>
      '${category.name}|$id';

  void _lockSavingsGoal() {
    _lockedSavingsGoalCurrent = savingsGoalCurrent;
    _lockedSavingsGoalTarget = savingsGoalTarget;
    _lockedSavingsGoalTargetDate = savingsGoalTargetDate;
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
    final active = _entries[category]!.fold<double>(
      0,
      (total, entry) => total + entry.amount,
    );
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
  void _distributeAddedFunds(double amount) {
    if (amount == 0) return;
    _billsRemaining += amount * (billsPercentage / 100);
    _savingsRemaining += amount * (savingsPercentage / 100);
    _personalRemaining += amount * (personalPercentage / 100);
  }

  /// Reset envelopes to match current Available Balance × percentages.
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
        if (entry.title == savingsGoalEntryTitle) {
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

  Future<void> loadForUser(String uid) async {
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

      final budget = results[0] as Map<String, double>?;
      if (budget != null) {
        monthlySalary = budget['monthlySalary']!;
        budgetSchemaVersion =
            (budget['schemaVersion'] ?? 1).round().clamp(1, currentBudgetSchemaVersion);
        _applyForfeited(budget);
        _applySavingsGoal(budget);
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
        unawaited(_saveCurrentBudget(uid));
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

      final budget = results[0] as Map<String, double>?;
      if (budget == null) {
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
          _applySavingsGoal(budget);
        } else {
          savingsGoalCurrent = _lockedSavingsGoalCurrent!;
          savingsGoalTarget = _lockedSavingsGoalTarget!;
          savingsGoalTargetDate = _lockedSavingsGoalTargetDate!;
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
    final uid = _requireUid();
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
    this.billsPercentage = nextBills;
    this.savingsPercentage = nextSavings;
    this.personalPercentage = nextPersonal;
    if ((nextBills - previousPct.bills).abs() > 0.001 ||
        (nextSavings - previousPct.savings).abs() > 0.001 ||
        (nextPersonal - previousPct.personal).abs() > 0.001) {
      _reallocateAllFromAvailableBalance();
    }
    errorMessage = null;
    notifyListeners();

    try {
      await _saveCurrentBudget(uid);
    } catch (_) {
      this.monthlySalary = previousSalary;
      this.billsPercentage = previousPct.bills;
      this.savingsPercentage = previousPct.savings;
      this.personalPercentage = previousPct.personal;
      _restoreRemainings(previous);
      errorMessage = 'Budget changes could not be saved.';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> receiveSalary() async {
    final uid = _requireUid();
    if (monthlySalary <= 0) {
      throw StateError('Set a monthly salary before receiving it.');
    }

    final previous = _remainingSnapshot();
    availableBalance += monthlySalary;
    _distributeAddedFunds(monthlySalary);
    errorMessage = null;
    notifyListeners();

    try {
      await _saveCurrentBudget(uid);
    } catch (_) {
      _restoreRemainings(previous);
      errorMessage = 'Salary could not be received. Please try again.';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> addMoney(double amount) async {
    final uid = _requireUid();
    if (amount <= 0) {
      throw ArgumentError('Amount must be greater than zero.');
    }

    final previous = _remainingSnapshot();
    availableBalance += amount;
    _distributeAddedFunds(amount);
    errorMessage = null;
    notifyListeners();

    try {
      await _saveCurrentBudget(uid);
    } catch (_) {
      _restoreRemainings(previous);
      errorMessage = 'Money could not be added. Please try again.';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateAvailableBalance(double newBalance) async {
    final uid = _requireUid();
    if (newBalance < 0) {
      throw ArgumentError('Available balance cannot be negative.');
    }

    final previous = _remainingSnapshot();
    final delta = newBalance - availableBalance;
    availableBalance = newBalance;
    if (delta > 0) {
      _distributeAddedFunds(delta);
    } else if (delta < 0) {
      _reallocateAllFromAvailableBalance();
    }
    errorMessage = null;
    notifyListeners();

    try {
      await _saveCurrentBudget(uid);
    } catch (_) {
      _restoreRemainings(previous);
      errorMessage = 'Available balance could not be updated.';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updatePercentages({
    required double billsPercentage,
    required double savingsPercentage,
    required double personalPercentage,
  }) async {
    final uid = _requireUid();
    final total = billsPercentage + savingsPercentage + personalPercentage;
    if ((total - 100).abs() > 0.001) {
      throw ArgumentError('Budget percentages must total 100.');
    }

    final previous = _remainingSnapshot();
    final previousPct = (
      bills: this.billsPercentage,
      savings: this.savingsPercentage,
      personal: this.personalPercentage,
    );
    this.billsPercentage = billsPercentage;
    this.savingsPercentage = savingsPercentage;
    this.personalPercentage = personalPercentage;
    _reallocateAllFromAvailableBalance();
    errorMessage = null;
    notifyListeners();

    try {
      await _saveCurrentBudget(uid);
    } catch (_) {
      billsPercentage = previousPct.bills;
      savingsPercentage = previousPct.savings;
      personalPercentage = previousPct.personal;
      _restoreRemainings(previous);
      errorMessage = 'Percentages could not be updated.';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateMonthlySalary(double monthlySalary) async {
    final uid = _requireUid();
    if (monthlySalary < 0) {
      throw ArgumentError('Monthly salary cannot be negative.');
    }

    final previousSalary = this.monthlySalary;
    this.monthlySalary = monthlySalary;
    errorMessage = null;
    notifyListeners();

    try {
      await _saveCurrentBudget(uid);
    } catch (_) {
      this.monthlySalary = previousSalary;
      errorMessage = 'Monthly salary could not be updated.';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> addEntry(
    FinancialCategory category, {
    required String title,
    required double amount,
  }) async {
    final uid = _requireUid();
    if (amount <= 0 || amount > remainingFor(category) + 0.001) {
      throw ArgumentError('Amount exceeds the available category balance.');
    }
    final entry = FinancialEntry(
      id: _service.createEntryId(uid, category),
      title: title.trim(),
      amount: amount,
      createdAt: DateTime.now(),
    );
    final key = _entryKey(category, entry.id);
    final previous = _remainingSnapshot();

    _entries[category]!.insert(0, entry);
    availableBalance = (previous['availableBalance']! - amount).clamp(
      0,
      double.infinity,
    );
    _adjustRemaining(category, -amount);
    _pendingUpsertKeys.add(key);
    errorMessage = null;
    notifyListeners();

    unawaited(() async {
      try {
        await _service.saveEntryAndBudget(
          uid,
          category: category,
          entry: entry,
          availableBalance: availableBalance,
          monthlySalary: monthlySalary,
          billsPercentage: billsPercentage,
          savingsPercentage: savingsPercentage,
          personalPercentage: personalPercentage,
          billsRemaining: _billsRemaining,
          savingsRemaining: _savingsRemaining,
          personalRemaining: _personalRemaining,
          forfeitedBills: _forfeited[FinancialCategory.bills]!,
          forfeitedSavings: _forfeited[FinancialCategory.savings]!,
          forfeitedPersonal: _forfeited[FinancialCategory.personal]!,
          savingsGoalTarget: savingsGoalTarget,
          savingsGoalCurrent: savingsGoalCurrent,
          savingsGoalTargetDateMs: savingsGoalTargetDate.millisecondsSinceEpoch
              .toDouble(),
          schemaVersion: budgetSchemaVersion.toDouble(),
        );
      } catch (_) {
        _entries[category]!.removeWhere((item) => item.id == entry.id);
        _pendingUpsertKeys.remove(key);
        _restoreRemainings(previous);
        errorMessage = 'The entry could not be saved.';
        notifyListeners();
      }
    }());
  }

  Future<void> updateEntry(
    FinancialCategory category,
    FinancialEntry updated,
  ) async {
    final uid = _requireUid();
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
      await _service.saveEntryAndBudget(
        uid,
        category: category,
        entry: updated,
        availableBalance: availableBalance,
        monthlySalary: monthlySalary,
        billsPercentage: billsPercentage,
        savingsPercentage: savingsPercentage,
        personalPercentage: personalPercentage,
        billsRemaining: _billsRemaining,
        savingsRemaining: _savingsRemaining,
        personalRemaining: _personalRemaining,
        forfeitedBills: _forfeited[FinancialCategory.bills]!,
        forfeitedSavings: _forfeited[FinancialCategory.savings]!,
        forfeitedPersonal: _forfeited[FinancialCategory.personal]!,
        savingsGoalTarget: savingsGoalTarget,
        savingsGoalCurrent: savingsGoalCurrent,
        savingsGoalTargetDateMs: savingsGoalTargetDate.millisecondsSinceEpoch
            .toDouble(),
        schemaVersion: budgetSchemaVersion.toDouble(),
      );
    } catch (_) {
      list[index] = previousEntry;
      _restoreRemainings(previous);
      errorMessage = 'The entry could not be updated.';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateSavingsGoalSettings({
    required double target,
    required DateTime targetDate,
  }) async {
    final uid = _requireUid();
    if (target <= 0) {
      throw ArgumentError('Goal amount must be greater than zero.');
    }

    final previousTarget = savingsGoalTarget;
    final previousDate = savingsGoalTargetDate;
    savingsGoalTarget = target;
    savingsGoalTargetDate = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );
    errorMessage = null;
    _lockSavingsGoal();
    notifyListeners();

    // Persist in background so the edit UI is not blocked on network.
    unawaited(() async {
      try {
        await _saveCurrentBudget(uid);
      } catch (_) {
        savingsGoalTarget = previousTarget;
        savingsGoalTargetDate = previousDate;
        _lockSavingsGoal();
        errorMessage = 'Savings goal could not be updated.';
        notifyListeners();
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
        await _service.saveEntryAndBudget(
          uid,
          category: source,
          entry: entry,
          availableBalance: availableBalance,
          monthlySalary: monthlySalary,
          billsPercentage: billsPercentage,
          savingsPercentage: savingsPercentage,
          personalPercentage: personalPercentage,
          billsRemaining: _billsRemaining,
          savingsRemaining: _savingsRemaining,
          personalRemaining: _personalRemaining,
          forfeitedBills: _forfeited[FinancialCategory.bills]!,
          forfeitedSavings: _forfeited[FinancialCategory.savings]!,
          forfeitedPersonal: _forfeited[FinancialCategory.personal]!,
          savingsGoalTarget: savingsGoalTarget,
          savingsGoalCurrent: savingsGoalCurrent,
          savingsGoalTargetDateMs: savingsGoalTargetDate.millisecondsSinceEpoch
              .toDouble(),
          schemaVersion: budgetSchemaVersion.toDouble(),
        );
      } catch (_) {
        _entries[source]!.removeWhere((item) => item.id == entry.id);
        _pendingUpsertKeys.remove(key);
        _restoreRemainings(previous);
        savingsGoalCurrent = previousCurrent;
        _lockSavingsGoal();
        errorMessage = 'Could not add to your savings goal.';
        notifyListeners();
      }
    }());
  }

  Future<void> deleteEntry(
    FinancialCategory category,
    FinancialEntry entry,
  ) async {
    final uid = _requireUid();
    final list = _entries[category]!;
    final index = list.indexWhere((item) => item.id == entry.id);
    if (index < 0) return;

    final previousGoalCurrent = savingsGoalCurrent;
    final previous = _remainingSnapshot();
    final isGoalContribution = entry.title == savingsGoalEntryTitle;
    final key = _entryKey(category, entry.id);

    list.removeAt(index);
    if (isGoalContribution) {
      // Refund only to the original source category.
      availableBalance = previous['availableBalance']! + entry.amount;
      _adjustRemaining(category, entry.amount);
      savingsGoalCurrent = (previousGoalCurrent - entry.amount).clamp(
        0,
        double.infinity,
      );
      _lockSavingsGoal();
    } else {
      availableBalance = previous['availableBalance']! + entry.amount;
      _adjustRemaining(category, entry.amount);
    }
    _pendingDeleteKeys.add(key);
    errorMessage = null;
    notifyListeners();

    // Persist in background so swipe-delete / confirmDismiss is not blocked.
    unawaited(() async {
      try {
        await _service.deleteEntryAndBudget(
          uid,
          category: category,
          entryId: entry.id,
          availableBalance: availableBalance,
          monthlySalary: monthlySalary,
          billsPercentage: billsPercentage,
          savingsPercentage: savingsPercentage,
          personalPercentage: personalPercentage,
          billsRemaining: _billsRemaining,
          savingsRemaining: _savingsRemaining,
          personalRemaining: _personalRemaining,
          forfeitedBills: _forfeited[FinancialCategory.bills]!,
          forfeitedSavings: _forfeited[FinancialCategory.savings]!,
          forfeitedPersonal: _forfeited[FinancialCategory.personal]!,
          savingsGoalTarget: savingsGoalTarget,
          savingsGoalCurrent: savingsGoalCurrent,
          savingsGoalTargetDateMs: savingsGoalTargetDate.millisecondsSinceEpoch
              .toDouble(),
          schemaVersion: budgetSchemaVersion.toDouble(),
        );
      } catch (_) {
        list.insert(index, entry);
        _restoreRemainings(previous);
        savingsGoalCurrent = previousGoalCurrent;
        _pendingDeleteKeys.remove(key);
        if (isGoalContribution) {
          _lockSavingsGoal();
        }
        errorMessage = 'The entry could not be deleted.';
        notifyListeners();
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
    _pendingUpsertKeys.clear();
    _pendingDeleteKeys.clear();
    _lockedSavingsGoalCurrent = null;
    _lockedSavingsGoalTarget = null;
    _lockedSavingsGoalTargetDate = null;
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
  }

  void _applyForfeited(Map<String, double> budget) {
    _forfeited[FinancialCategory.bills] = budget['forfeitedBills'] ?? 0;
    _forfeited[FinancialCategory.savings] = budget['forfeitedSavings'] ?? 0;
    _forfeited[FinancialCategory.personal] = budget['forfeitedPersonal'] ?? 0;
  }

  void _applySavingsGoal(Map<String, double> budget) {
    savingsGoalTarget = budget['savingsGoalTarget'] ?? 10000;
    savingsGoalCurrent = budget['savingsGoalCurrent'] ?? 0;
    final ms = budget['savingsGoalTargetDateMs'];
    savingsGoalTargetDate = ms == null
        ? DateTime(2028, 12, 31)
        : DateTime.fromMillisecondsSinceEpoch(ms.round());
  }

  Future<void> _saveCurrentBudget(String uid) {
    return _service.saveBudget(
      uid,
      availableBalance: availableBalance,
      monthlySalary: monthlySalary,
      billsPercentage: billsPercentage,
      savingsPercentage: savingsPercentage,
      personalPercentage: personalPercentage,
      billsRemaining: _billsRemaining,
      savingsRemaining: _savingsRemaining,
      personalRemaining: _personalRemaining,
      forfeitedBills: _forfeited[FinancialCategory.bills]!,
      forfeitedSavings: _forfeited[FinancialCategory.savings]!,
      forfeitedPersonal: _forfeited[FinancialCategory.personal]!,
      savingsGoalTarget: savingsGoalTarget,
      savingsGoalCurrent: savingsGoalCurrent,
      savingsGoalTargetDateMs: savingsGoalTargetDate.millisecondsSinceEpoch
          .toDouble(),
      schemaVersion: budgetSchemaVersion.toDouble(),
    );
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
        final budget = snapshot.budget!;

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
            _pendingUpsertKeys.isNotEmpty || _pendingDeleteKeys.isNotEmpty;
        if (!hasPendingLocalBudget) {
          _applyBudget(
            availableBalance: budget['availableBalance']!,
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
          _applySavingsGoal(budget);
        } else {
          savingsGoalCurrent = _lockedSavingsGoalCurrent!;
          savingsGoalTarget = _lockedSavingsGoalTarget!;
          savingsGoalTargetDate = _lockedSavingsGoalTargetDate!;
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
