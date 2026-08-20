import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/loan_entry.dart';
import '../services/notification_service.dart';

class LoanProvider extends ChangeNotifier {
  LoanProvider({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

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

  String _storageKey(String uid) => 'loans_v2_$uid';

  Future<void> loadForUser(String? uid) async {
    if (uid == null || uid.isEmpty) {
      _uid = null;
      _loans = [];
      _loaded = true;
      notifyListeners();
      unawaited(NotificationService.instance.syncLoans(const []));
      return;
    }

    // Always re-parse from storage so hot-reload can't leave null fields.
    _uid = uid;
    _loaded = false;
    notifyListeners();

    try {
      final raw = await _storage.read(key: _storageKey(uid));
      _loans = LoanEntry.listFromJsonString(raw);
      _loans.sort((a, b) => a.monthlyDueDate.compareTo(b.monthlyDueDate));
    } catch (_) {
      _loans = [];
    }

    _loaded = true;
    notifyListeners();
    unawaited(NotificationService.instance.syncLoans(_loans));
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
    _loans = [..._loans, loan]
      ..sort((a, b) => a.monthlyDueDate.compareTo(b.monthlyDueDate));
    notifyListeners();
    await _persist();
  }

  Future<void> markInstallmentPaid({
    required String loanId,
    required DateTime dueDate,
    required bool paid,
  }) async {
    final index = _loans.indexWhere((loan) => loan.id == loanId);
    if (index < 0) return;
    final current = _loans[index];
    _loans = [
      for (var i = 0; i < _loans.length; i++)
        if (i == index)
          current.withInstallmentPaid(dueDate, paid: paid)
        else
          _loans[i],
    ];
    notifyListeners();
    await _persist();
  }

  Future<void> deleteLoan(String id) async {
    _loans = _loans.where((loan) => loan.id != id).toList();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final uid = _uid;
    if (uid == null) return;
    await _storage.write(
      key: _storageKey(uid),
      value: LoanEntry.listToJsonString(_loans),
    );
    unawaited(NotificationService.instance.syncLoans(_loans));
  }
}
