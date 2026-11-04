import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/loan_entry.dart';
import '../services/notification_service.dart';
import '../services/wallet_repository.dart';

/// Loans, synced across devices via the user's wallet document
/// (`users/{uid}/wallet/data`).
class LoanProvider extends ChangeNotifier {
  LoanProvider(this._repository) {
    _repository.addListener(_syncFromRepository);
    _syncFromRepository();
  }

  final WalletRepository _repository;

  String? _uid;
  List<LoanEntry> _loans = [];
  bool _loaded = false;

  List<LoanEntry> get loans => List.unmodifiable(_loans);
  bool get isLoaded => _loaded;

  /// Loans still being paid (not all installments marked paid).
  List<LoanEntry> get activeLoans =>
      List.unmodifiable(_loans.where((loan) => !loan.isFullyPaid));

  /// Fully paid loans (final installment completed), newest completion first.
  List<LoanEntry> get paidLoans {
    final paid = _loans.where((loan) => loan.isFullyPaid).toList()
      ..sort((a, b) {
        final aDone = a.installmentDates.isEmpty
            ? a.finalPaymentDate
            : a.installmentDates.last;
        final bDone = b.installmentDates.isEmpty
            ? b.finalPaymentDate
            : b.installmentDates.last;
        return bDone.compareTo(aDone);
      });
    return List.unmodifiable(paid);
  }

  double get totalLoan {
    var sum = 0.0;
    for (final loan in _loans) {
      sum += loan.remainingBalance;
    }
    return sum;
  }

  Future<void> loadForUser(String? uid) async {
    if (uid == null || uid.isEmpty) {
      await clear();
      return;
    }

    _uid = uid;
    _loaded = false;
    notifyListeners();

    await _repository.loadForUser(uid);
    _syncFromRepository();
  }

  void _syncFromRepository() {
    _uid = _repository.uid;
    _loans = _sorted(_repository.wallet.loans);
    _loaded = _repository.isLoaded;
    notifyListeners();
    unawaited(NotificationService.instance.syncLoans(_loans));
  }

  List<LoanEntry> _sorted(List<LoanEntry> loans) {
    final next = [...loans]
      ..sort((a, b) => a.monthlyDueDate.compareTo(b.monthlyDueDate));
    return next;
  }

  Future<bool> addLoan({
    required String name,
    required double amount,
    required DateTime monthlyDueDate,
    required DateTime finalPaymentDate,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || amount <= 0 || _uid == null) return false;

    final loan = LoanEntry(
      id: 'loan_${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed,
      amount: amount,
      monthlyDueDate: DateTime(
        monthlyDueDate.year,
        monthlyDueDate.month,
        monthlyDueDate.day,
      ),
      finalPaymentDate: DateTime(
        finalPaymentDate.year,
        finalPaymentDate.month,
        finalPaymentDate.day,
      ),
    );
    final previous = _loans;
    _loans = _sorted([..._loans, loan]);
    notifyListeners();
    return _persist(previous);
  }

  Future<bool> markInstallmentPaid({
    required String loanId,
    required DateTime dueDate,
    required bool paid,
  }) async {
    final index = _loans.indexWhere((loan) => loan.id == loanId);
    if (index < 0) return false;
    final current = _loans[index];
    final previous = _loans;
    _loans = [
      for (var i = 0; i < _loans.length; i++)
        if (i == index)
          current.withInstallmentPaid(dueDate, paid: paid)
        else
          _loans[i],
    ];
    notifyListeners();
    return _persist(previous);
  }

  Future<bool> deleteLoan(String id) async {
    final previous = _loans;
    _loans = _loans.where((loan) => loan.id != id).toList();
    notifyListeners();
    return _persist(previous);
  }

  Future<bool> _persist(List<LoanEntry> previous) async {
    if (_uid == null) return false;
    final saved = await _repository.saveLoans(_loans);
    if (!saved) {
      _loans = previous;
      notifyListeners();
      unawaited(NotificationService.instance.syncLoans(_loans));
      return false;
    }
    unawaited(NotificationService.instance.syncLoans(_loans));
    return true;
  }

  /// Resets to the signed-out state and stops listening.
  Future<void> clear() async {
    _uid = null;
    _loans = [];
    _loaded = true;
    notifyListeners();
    unawaited(NotificationService.instance.syncLoans(const []));
  }

  @override
  void dispose() {
    _repository.removeListener(_syncFromRepository);
    super.dispose();
  }
}
