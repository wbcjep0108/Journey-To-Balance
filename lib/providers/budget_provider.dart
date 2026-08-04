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
        _applyBudget(
          income: 0,
          billsPercentage: 50,
          savingsPercentage: 20,
          personalPercentage: 30,
        );
      } else {
        monthlySalary = budget['monthlySalary']!;
        _applyForfeited(budget);
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

  Future<void> deleteEntry(
    FinancialCategory category,
    FinancialEntry entry,
  ) async {
    final uid = _requireUid();
    final list = _entries[category]!;
    final index = list.indexWhere((item) => item.id == entry.id);
    if (index < 0) return;

    final previousForfeited = _forfeited[category]!;
    list.removeAt(index);
    // Keep the spend deducted from balances even after the row is removed.
    _forfeited[category] = previousForfeited + entry.amount;
    errorMessage = null;
    notifyListeners();
    try {
      await Future.wait([
        _service.deleteEntry(uid, category, entry.id),
        _saveCurrentBudget(uid),
      ]);
    } catch (_) {
      list.insert(index, entry);
      _forfeited[category] = previousForfeited;
      errorMessage = 'The entry could not be deleted.';
      notifyListeners();
      rethrow;
    }
  }

  void reset() {
    _cancelRealtimeSync();
    _uid = null;
    isLoading = false;
    isRefreshing = false;
    _refreshOperation = null;
    errorMessage = null;
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

  void _applyForfeited(Map<String, double> budget) {
    _forfeited[FinancialCategory.bills] = budget['forfeitedBills'] ?? 0;
    _forfeited[FinancialCategory.savings] = budget['forfeitedSavings'] ?? 0;
    _forfeited[FinancialCategory.personal] = budget['forfeitedPersonal'] ?? 0;
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
      _service.watchBudget(uid).listen((budget) {
        if (_uid != uid || budget == null) return;
        monthlySalary = budget['monthlySalary']!;
        _applyForfeited(budget);
        _applyBudget(
          income: budget['income']!,
          billsPercentage: budget['billsPercentage']!,
          savingsPercentage: budget['savingsPercentage']!,
          personalPercentage: budget['personalPercentage']!,
        );
        notifyListeners();
      }, onError: (_) => _handleRealtimeError(uid)),
    );

    for (final category in FinancialCategory.values) {
      _realtimeSubscriptions.add(
        _service.watchEntries(uid, category).listen((entries) {
          if (_uid != uid) return;
          _entries[category] = entries;
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
