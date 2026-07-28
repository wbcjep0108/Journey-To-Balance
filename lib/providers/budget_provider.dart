import 'package:flutter/material.dart';

import '../models/financial_entry.dart';
import '../services/firestore_finance_service.dart';

class BudgetProvider extends ChangeNotifier {
  BudgetProvider(this._service);

  final FirestoreFinanceService _service;

  double income = 0;
  double billsPercentage = 50;
  double savingsPercentage = 20;
  double personalPercentage = 30;
  double billsAmount = 0;
  double savingsAmount = 0;
  double personalAmount = 0;
  double remainingAmount = 0;

  String? _uid;
  bool isLoading = false;
  String? errorMessage;

  final Map<FinancialCategory, List<FinancialEntry>> _entries = {
    for (final category in FinancialCategory.values) category: [],
  };

  List<FinancialEntry> entriesFor(FinancialCategory category) {
    return List.unmodifiable(_entries[category]!);
  }

  Future<void> loadForUser(String uid) async {
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

  Future<void> updateBudget({
    required double income,
    required double billsPercentage,
    required double savingsPercentage,
    required double personalPercentage,
  }) async {
    final uid = _requireUid();
    final total = billsPercentage + savingsPercentage + personalPercentage;
    if ((total - 100).abs() > 0.001) {
      throw ArgumentError('Budget percentages must total 100.');
    }

    final previous = _budgetValues;
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
        billsPercentage: billsPercentage,
        savingsPercentage: savingsPercentage,
        personalPercentage: personalPercentage,
      );
    } catch (_) {
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

  Future<void> addEntry(
    FinancialCategory category, {
    required String title,
    required double amount,
  }) async {
    final uid = _requireUid();
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
    _uid = null;
    isLoading = false;
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
    'billsPercentage': billsPercentage,
    'savingsPercentage': savingsPercentage,
    'personalPercentage': personalPercentage,
  };

  void _setDefaults() {
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
}
