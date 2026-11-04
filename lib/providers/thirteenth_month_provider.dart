import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/thirteenth_month_result.dart';
import '../services/planner_firestore_service.dart';
import '../services/thirteenth_month_calculator.dart';
import 'budget_provider.dart';

class ThirteenthMonthProvider extends ChangeNotifier {
  ThirteenthMonthProvider(this._plannerService, this._budget);

  final PlannerFirestoreService _plannerService;
  final BudgetProvider _budget;

  String? _uid;
  List<double> _monthlySalaries = List<double>.filled(12, 0);
  List<double> _savedSalaryHistory = List<double>.filled(12, 0);
  double _otherBenefits = 0;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isReceiving = false;
  String? _errorMessage;
  Timer? _saveTimer;

  UnmodifiableListView<double> get monthlySalaries =>
      UnmodifiableListView(_monthlySalaries);
  UnmodifiableListView<double> get savedSalaryHistory =>
      UnmodifiableListView(_savedSalaryHistory);
  double get otherBenefits => _otherBenefits;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isReceiving => _isReceiving;
  String? get errorMessage => _errorMessage;
  ThirteenthMonthResult get result => ThirteenthMonthCalculator.calculate(
    _monthlySalaries,
    otherBenefits: _otherBenefits,
  );

  Future<void> loadForUser(String uid) async {
    if (_uid == uid && !_isLoading) return;
    _saveTimer?.cancel();
    _uid = uid;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final saved = await _plannerService.loadThirteenthMonthInputs(uid);
      if (_uid != uid) return;
      _monthlySalaries = saved?.monthlySalaries ?? List<double>.filled(12, 0);
      _savedSalaryHistory = List<double>.from(_monthlySalaries);
      _otherBenefits = saved?.otherBenefits ?? 0;
    } catch (_) {
      if (_uid == uid) {
        _errorMessage = 'Saved salary inputs could not be loaded.';
      }
      rethrow;
    } finally {
      if (_uid == uid) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void setMonthlySalary(int monthIndex, double amount) {
    if (monthIndex < 0 || monthIndex >= 12 || amount < 0 || !amount.isFinite) {
      return;
    }
    if (_monthlySalaries[monthIndex] == amount) return;
    _monthlySalaries[monthIndex] = amount;
    _errorMessage = null;
    notifyListeners();
    _queueSave();
  }

  void fillAllMonths(double amount) {
    if (amount < 0 || !amount.isFinite) return;
    _monthlySalaries = List<double>.filled(12, amount);
    _errorMessage = null;
    notifyListeners();
    _queueSave();
  }

  void setOtherBenefits(double amount) {
    if (amount < 0 || !amount.isFinite || amount == _otherBenefits) return;
    _otherBenefits = amount;
    _errorMessage = null;
    notifyListeners();
    _queueSave();
  }

  Future<void> saveNow() async {
    final uid = _uid;
    if (uid == null) return;
    if (_isSaving) {
      _queueSave();
      return;
    }
    _saveTimer?.cancel();
    final salaries = List<double>.from(_monthlySalaries);
    final otherBenefits = _otherBenefits;
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _plannerService.saveThirteenthMonthInputs(
        uid,
        monthlySalaries: salaries,
        otherBenefits: otherBenefits,
      );
      if (_uid == uid) {
        _savedSalaryHistory = salaries;
        if (!listEquals(_monthlySalaries, salaries) ||
            _otherBenefits != otherBenefits) {
          _queueSave();
        }
      }
    } catch (_) {
      if (_uid == uid) {
        _errorMessage = 'Salary inputs could not be saved.';
      }
      rethrow;
    } finally {
      if (_uid == uid) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  Future<void> receiveAsIncome() async {
    final amount = result.gross;
    if (amount <= 0 || _isReceiving) return;
    _isReceiving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _budget.receiveSalary(
        amount: amount,
        title: 'Received 13th month pay',
      );
    } catch (_) {
      _errorMessage = 'The 13th month payout could not be received.';
      rethrow;
    } finally {
      _isReceiving = false;
      notifyListeners();
    }
  }

  Future<void> clear() async {
    _saveTimer?.cancel();
    _uid = null;
    _monthlySalaries = List<double>.filled(12, 0);
    _savedSalaryHistory = List<double>.filled(12, 0);
    _otherBenefits = 0;
    _isLoading = false;
    _isSaving = false;
    _isReceiving = false;
    _errorMessage = null;
    notifyListeners();
  }

  void _queueSave() {
    if (_uid == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      saveNow().catchError((_) {});
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
