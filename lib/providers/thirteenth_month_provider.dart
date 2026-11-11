import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/thirteenth_month_result.dart';
import '../services/thirteenth_month_calculator.dart';
import '../services/thirteenth_month_firestore_service.dart';
import 'budget_provider.dart';

/// Loads the calculator during session start without letting a failure stop
/// the session. The error stays on [calculator] (see
/// [ThirteenthMonthProvider.loadFailed]) for the 13th Month Pay screen, and
/// edits and saves remain blocked until a later load succeeds.
Future<void> loadCalculatorWithoutBlocking(
  ThirteenthMonthProvider calculator,
  String uid,
) async {
  try {
    await calculator.loadForUser(uid);
  } catch (error) {
    debugPrint('13th Month Pay load failed: $error');
  }
}

class ThirteenthMonthProvider extends ChangeNotifier {
  ThirteenthMonthProvider(this._service, this._budget);

  /// Calculator storage only. The Budget Planner is never read or written.
  final ThirteenthMonthFirestoreService _service;
  final BudgetProvider _budget;

  static const loadErrorMessage = 'Saved salary inputs could not be loaded.';
  static const saveErrorMessage = 'Salary inputs could not be saved.';

  String? _uid;
  List<double> _monthlySalaries = List<double>.filled(12, 0);
  List<double> _savedSalaryHistory = List<double>.filled(12, 0);
  double _otherBenefits = 0;

  /// True once saved inputs were read for the current user. Edits and saves
  /// stay blocked until then, so a failed or offline load can never replace
  /// the stored calculator data with placeholder zeros.
  bool _hasLoaded = false;
  bool _loadFailed = false;
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
  bool get hasLoaded => _hasLoaded;
  bool get loadFailed => _loadFailed;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isReceiving => _isReceiving;
  String? get errorMessage => _errorMessage;
  ThirteenthMonthResult get result => ThirteenthMonthCalculator.calculate(
    _monthlySalaries,
    otherBenefits: _otherBenefits,
  );

  /// Loads saved inputs for [uid]. A user whose data already loaded is not
  /// reloaded; after a failed load, calling this again retries. Errors are
  /// rethrown for the caller and also kept in [errorMessage] for the screen.
  Future<void> loadForUser(String uid) async {
    if (_uid == uid && (_hasLoaded || _isLoading)) return;
    _saveTimer?.cancel();
    if (_uid != uid) {
      // A different user: never show the previous user's numbers.
      _monthlySalaries = List<double>.filled(12, 0);
      _savedSalaryHistory = List<double>.filled(12, 0);
      _otherBenefits = 0;
    }
    _uid = uid;
    _hasLoaded = false;
    _loadFailed = false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final saved = await _service.load(uid);
      if (_uid != uid) return;
      // Keep an own, editable copy: the loaded list may be read-only.
      _monthlySalaries = List<double>.from(
        saved?.monthlySalaries ?? List<double>.filled(12, 0),
      );
      _savedSalaryHistory = List<double>.from(_monthlySalaries);
      _otherBenefits = saved?.otherBenefits ?? 0;
      _hasLoaded = true;
    } catch (_) {
      if (_uid == uid) {
        _loadFailed = true;
        _errorMessage = loadErrorMessage;
      }
      rethrow;
    } finally {
      if (_uid == uid) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Retries a failed load for the current user. Returns true when the saved
  /// inputs are now available.
  Future<bool> retryLoad() async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await loadForUser(uid);
    } catch (_) {
      return false;
    }
    return _hasLoaded;
  }

  void setMonthlySalary(int monthIndex, double amount) {
    if (!_hasLoaded) return;
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
    if (!_hasLoaded) return;
    if (amount < 0 || !amount.isFinite) return;
    _monthlySalaries = List<double>.filled(12, amount);
    _errorMessage = null;
    notifyListeners();
    _queueSave();
  }

  void setOtherBenefits(double amount) {
    if (!_hasLoaded) return;
    if (amount < 0 || !amount.isFinite || amount == _otherBenefits) return;
    _otherBenefits = amount;
    _errorMessage = null;
    notifyListeners();
    _queueSave();
  }

  Future<void> saveNow() async {
    final uid = _uid;
    // Never write before the saved inputs loaded: that would overwrite them.
    if (uid == null || !_hasLoaded) return;
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
      await _service.save(
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
        _errorMessage = saveErrorMessage;
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
    _hasLoaded = false;
    _loadFailed = false;
    _isLoading = false;
    _isSaving = false;
    _isReceiving = false;
    _errorMessage = null;
    notifyListeners();
  }

  void _queueSave() {
    if (_uid == null || !_hasLoaded) return;
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
