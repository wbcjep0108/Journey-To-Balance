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
  final List<StreamSubscription<Object?>> _realtimeSubscriptions = [];

  List<FinancialEntry> entriesFor(FinancialCategory category) {
    return List.unmodifiable(_entries[category]!);
  }

  double totalUsedFor(FinancialCategory category) {
    return _entries[category]!.fold(0, (total, entry) => total + entry.amount);
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
      await _service.saveBudget(
        uid,
        income: income,
        monthlySalary: monthlySalary,
        billsPercentage: billsPercentage,
        savingsPercentage: savingsPercentage,
        personalPercentage: personalPercentage,
      );
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
      await _service.saveBudget(
        uid,
        income: income,
        monthlySalary: monthlySalary,
        billsPercentage: billsPercentage,
        savingsPercentage: savingsPercentage,
        personalPercentage: personalPercentage,
      );
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
      await _service.saveBudget(
        uid,
        income: income,
        monthlySalary: monthlySalary,
        billsPercentage: billsPercentage,
        savingsPercentage: savingsPercentage,
        personalPercentage: personalPercentage,
      );
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
      await _service.saveBudget(
        uid,
        income: income,
        monthlySalary: monthlySalary,
        billsPercentage: billsPercentage,
        savingsPercentage: savingsPercentage,
        personalPercentage: personalPercentage,
      );
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

    list.removeAt(index);
    errorMessage = null;
    notifyListeners();
    try {
      await _service.deleteEntry(uid, category, entry.id);
    } catch (_) {
      list.insert(index, entry);
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
