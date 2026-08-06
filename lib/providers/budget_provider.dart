import 'dart:async';

import 'package:flutter/material.dart';

import '../models/financial_entry.dart';
import '../services/firestore_finance_service.dart';

class BudgetProvider extends ChangeNotifier {
  BudgetProvider(this._service);

  final FirestoreFinanceService _service;

  double income = 0;
  double monthlySalary = 0;
  double billsPercentage = 50;
  double savingsPercentage = 20;
  double personalPercentage = 30;
  double billsAmount = 0;
  double savingsAmount = 0;
  double personalAmount = 0;
  double remainingAmount = 0;
  double savingsGoalTarget = 10000;
  double savingsGoalCurrent = 0;
  DateTime savingsGoalTargetDate = DateTime(2028, 12, 31);

  static const savingsGoalEntryTitle = 'Savings Goal';

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

  void _lockForfeited(FinancialCategory category) {
    _lockedForfeited[category] = _forfeited[category];
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

  double allocationFor(FinancialCategory category) {
    return switch (category) {
      FinancialCategory.bills => billsAmount,
      FinancialCategory.savings => savingsAmount,
      FinancialCategory.personal => personalAmount,
    };
  }

  double remainingFor(FinancialCategory category) {
    return allocationFor(category) - totalUsedFor(category);
  }

  double get totalRemainingBalance {
    return FinancialCategory.values.fold(
      0,
      (total, category) => total + remainingFor(category),
    );
  }

  double get availableBalance => totalRemainingBalance;

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
        _applyForfeited(budget);
        _applySavingsGoal(budget);
        _applyBudget(
          income: budget['income']!,
          billsPercentage: budget['billsPercentage']!,
          savingsPercentage: budget['savingsPercentage']!,
          personalPercentage: budget['personalPercentage']!,
        );
      }

      for (var index = 0; index < FinancialCategory.values.length; index++) {
        _entries[FinancialCategory.values[index]] =
            results[index + 1] as List<FinancialEntry>;
      }
      _startRealtimeSync(uid);
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
          income: 0,
          billsPercentage: 50,
          savingsPercentage: 20,
          personalPercentage: 30,
        );
      } else {
        monthlySalary = budget['monthlySalary']!;
        _applyBudget(
          income: budget['income']!,
          billsPercentage: budget['billsPercentage']!,
          savingsPercentage: budget['savingsPercentage']!,
          personalPercentage: budget['personalPercentage']!,
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
    required double billsPercentage,
    required double savingsPercentage,
    required double personalPercentage,
  }) async {
    final uid = _requireUid();
    final total = billsPercentage + savingsPercentage + personalPercentage;
    if (monthlySalary < 0 || (total - 100).abs() > 0.001) {
      throw ArgumentError('Budget percentages must total 100.');
    }

    final previous = _budgetValues;
    this.monthlySalary = monthlySalary;
    _applyBudget(
      income: income,
      billsPercentage: billsPercentage,
      savingsPercentage: savingsPercentage,
      personalPercentage: personalPercentage,
    );
    errorMessage = null;
    notifyListeners();

    try {
      await _saveCurrentBudget(uid);
    } catch (_) {
      this.monthlySalary = previous['monthlySalary']!;
      _applyBudget(
        income: previous['income']!,
        billsPercentage: previous['billsPercentage']!,
        savingsPercentage: previous['savingsPercentage']!,
        personalPercentage: previous['personalPercentage']!,
      );
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

    final previousIncome = income;
    _applyBudget(
      income: income + monthlySalary,
      billsPercentage: billsPercentage,
      savingsPercentage: savingsPercentage,
      personalPercentage: personalPercentage,
    );
    errorMessage = null;
    notifyListeners();

    try {
      await _saveCurrentBudget(uid);
    } catch (_) {
      _applyBudget(
        income: previousIncome,
        billsPercentage: billsPercentage,
        savingsPercentage: savingsPercentage,
        personalPercentage: personalPercentage,
      );
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

    final previousIncome = income;
    _applyBudget(
      income: income + amount,
      billsPercentage: billsPercentage,
      savingsPercentage: savingsPercentage,
      personalPercentage: personalPercentage,
    );
    errorMessage = null;
    notifyListeners();

    try {
      await _saveCurrentBudget(uid);
    } catch (_) {
      _applyBudget(
        income: previousIncome,
        billsPercentage: billsPercentage,
        savingsPercentage: savingsPercentage,
        personalPercentage: personalPercentage,
      );
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

    final previousIncome = income;
    final totalDeductions = FinancialCategory.values.fold<double>(
      0,
      (total, category) => total + totalUsedFor(category),
    );
    _applyBudget(
      income: newBalance + totalDeductions,
      billsPercentage: billsPercentage,
      savingsPercentage: savingsPercentage,
      personalPercentage: personalPercentage,
    );
    errorMessage = null;
    notifyListeners();

    try {
      await _saveCurrentBudget(uid);
    } catch (_) {
      _applyBudget(
        income: previousIncome,
        billsPercentage: billsPercentage,
        savingsPercentage: savingsPercentage,
        personalPercentage: personalPercentage,
      );
      errorMessage = 'Available balance could not be updated.';
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

    _entries[category]!.insert(0, entry);
    errorMessage = null;
    notifyListeners();
    try {
      await _service.saveEntry(uid, category, entry);
    } catch (_) {
      _entries[category]!.removeWhere((item) => item.id == entry.id);
      errorMessage = 'The entry could not be saved.';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateEntry(
    FinancialCategory category,
    FinancialEntry updated,
  ) async {
    final uid = _requireUid();
    final list = _entries[category]!;
    final index = list.indexWhere((item) => item.id == updated.id);
    if (index < 0) return;

    final previous = list[index];
    final availableForEdit = remainingFor(category) + previous.amount;
    if (updated.amount <= 0 || updated.amount > availableForEdit + 0.001) {
      throw ArgumentError('Amount exceeds the available category balance.');
    }
    list[index] = updated;
    errorMessage = null;
    notifyListeners();
    try {
      await _service.saveEntry(uid, category, updated);
    } catch (_) {
      list[index] = previous;
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
    final entry = FinancialEntry(
      id: _service.createEntryId(uid, source),
      title: savingsGoalEntryTitle,
      amount: amount,
      createdAt: DateTime.now(),
    );
    final key = _entryKey(source, entry.id);

    _entries[source]!.insert(0, entry);
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
          income: income,
          monthlySalary: monthlySalary,
          billsPercentage: billsPercentage,
          savingsPercentage: savingsPercentage,
          personalPercentage: personalPercentage,
          forfeitedBills: _forfeited[FinancialCategory.bills]!,
          forfeitedSavings: _forfeited[FinancialCategory.savings]!,
          forfeitedPersonal: _forfeited[FinancialCategory.personal]!,
          savingsGoalTarget: savingsGoalTarget,
          savingsGoalCurrent: savingsGoalCurrent,
          savingsGoalTargetDateMs: savingsGoalTargetDate.millisecondsSinceEpoch
              .toDouble(),
        );
      } catch (_) {
        _entries[source]!.removeWhere((item) => item.id == entry.id);
        _pendingUpsertKeys.remove(key);
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

    final previousForfeited = _forfeited[category]!;
    final previousGoalCurrent = savingsGoalCurrent;
    final isGoalContribution = entry.title == savingsGoalEntryTitle;
    final key = _entryKey(category, entry.id);

    list.removeAt(index);
    if (isGoalContribution) {
      // Return the amount to the source category (do not forfeit).
      savingsGoalCurrent = (previousGoalCurrent - entry.amount).clamp(
        0,
        double.infinity,
      );
      _lockSavingsGoal();
    } else {
      // Keep normal spend deducted from balances after the row is removed.
      _forfeited[category] = previousForfeited + entry.amount;
      _lockForfeited(category);
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
          income: income,
          monthlySalary: monthlySalary,
          billsPercentage: billsPercentage,
          savingsPercentage: savingsPercentage,
          personalPercentage: personalPercentage,
          forfeitedBills: _forfeited[FinancialCategory.bills]!,
          forfeitedSavings: _forfeited[FinancialCategory.savings]!,
          forfeitedPersonal: _forfeited[FinancialCategory.personal]!,
          savingsGoalTarget: savingsGoalTarget,
          savingsGoalCurrent: savingsGoalCurrent,
          savingsGoalTargetDateMs: savingsGoalTargetDate.millisecondsSinceEpoch
              .toDouble(),
        );
      } catch (_) {
        list.insert(index, entry);
        _forfeited[category] = previousForfeited;
        savingsGoalCurrent = previousGoalCurrent;
        _pendingDeleteKeys.remove(key);
        if (isGoalContribution) {
          _lockSavingsGoal();
        } else {
          _lockedForfeited[category] = null;
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

  Map<String, double> get _budgetValues => {
    'income': income,
    'monthlySalary': monthlySalary,
    'billsPercentage': billsPercentage,
    'savingsPercentage': savingsPercentage,
    'personalPercentage': personalPercentage,
  };

  void _setDefaults() {
    monthlySalary = 0;
    _clearForfeited();
    _resetSavingsGoal();
    _applyBudget(
      income: 0,
      billsPercentage: 50,
      savingsPercentage: 20,
      personalPercentage: 30,
    );
    for (final entries in _entries.values) {
      entries.clear();
    }
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
      income: income,
      monthlySalary: monthlySalary,
      billsPercentage: billsPercentage,
      savingsPercentage: savingsPercentage,
      personalPercentage: personalPercentage,
      forfeitedBills: _forfeited[FinancialCategory.bills]!,
      forfeitedSavings: _forfeited[FinancialCategory.savings]!,
      forfeitedPersonal: _forfeited[FinancialCategory.personal]!,
      savingsGoalTarget: savingsGoalTarget,
      savingsGoalCurrent: savingsGoalCurrent,
      savingsGoalTargetDateMs: savingsGoalTargetDate.millisecondsSinceEpoch
          .toDouble(),
    );
  }

  void _applyBudget({
    required double income,
    required double billsPercentage,
    required double savingsPercentage,
    required double personalPercentage,
  }) {
    this.income = income;
    this.billsPercentage = billsPercentage;
    this.savingsPercentage = savingsPercentage;
    this.personalPercentage = personalPercentage;
    billsAmount = income * (billsPercentage / 100);
    savingsAmount = income * (savingsPercentage / 100);
    personalAmount = income * (personalPercentage / 100);
    remainingAmount = income - billsAmount - savingsAmount - personalAmount;
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
        _applyBudget(
          income: budget['income']!,
          billsPercentage: budget['billsPercentage']!,
          savingsPercentage: budget['savingsPercentage']!,
          personalPercentage: budget['personalPercentage']!,
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
