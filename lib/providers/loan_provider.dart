import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/loan_entry.dart';
import '../services/notification_service.dart';
import '../services/wallet_firestore_service.dart';

/// Loans, synced across devices via the user's wallet document
/// (`users/{uid}/wallet/data`).
class LoanProvider extends ChangeNotifier {
  LoanProvider({WalletFirestoreService? service})
    : _service = service ?? WalletFirestoreService();

  final WalletFirestoreService _service;

  String? _uid;
  List<LoanEntry> _loans = [];
  bool _loaded = false;
  StreamSubscription<WalletSnapshot>? _sub;

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
      clear();
      return;
    }

    _uid = uid;
    _loaded = false;
    notifyListeners();

    try {
      final wallet = await _service.load(uid);
      _loans = _sorted(wallet.loans);
    } catch (_) {
      _loans = [];
    }

    _loaded = true;
    notifyListeners();
    unawaited(NotificationService.instance.syncLoans(_loans));

    _subscribe(uid);
  }

  void _subscribe(String uid) {
    _sub?.cancel();
    _sub = _service.watch(uid).listen((snapshot) {
      if (snapshot.hasPendingWrites) return;
      _loans = _sorted(snapshot.wallet.loans);
      notifyListeners();
      unawaited(NotificationService.instance.syncLoans(_loans));
    });
  }

  List<LoanEntry> _sorted(List<LoanEntry> loans) {
    final next = [...loans]
      ..sort((a, b) => a.monthlyDueDate.compareTo(b.monthlyDueDate));
    return next;
  }

  Future<void> addLoan({
    required String name,
    required double amount,
    required DateTime monthlyDueDate,
    required DateTime finalPaymentDate,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || amount <= 0 || _uid == null) return;

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
    await _persist(previous);
  }

  Future<void> markInstallmentPaid({
    required String loanId,
    required DateTime dueDate,
    required bool paid,
  }) async {
    final index = _loans.indexWhere((loan) => loan.id == loanId);
    if (index < 0) return;
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
    await _persist(previous);
  }

  Future<void> deleteLoan(String id) async {
    final previous = _loans;
    _loans = _loans.where((loan) => loan.id != id).toList();
    notifyListeners();
    await _persist(previous);
  }

  Future<void> _persist(List<LoanEntry> previous) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _service.saveLoans(uid, _loans);
    } catch (_) {
      _loans = previous;
      notifyListeners();
      unawaited(NotificationService.instance.syncLoans(_loans));
      return;
    }
    unawaited(NotificationService.instance.syncLoans(_loans));
  }

  /// Resets to the signed-out state and stops listening.
  void clear() {
    _sub?.cancel();
    _sub = null;
    _uid = null;
    _loans = [];
    _loaded = true;
    notifyListeners();
    unawaited(NotificationService.instance.syncLoans(const []));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
