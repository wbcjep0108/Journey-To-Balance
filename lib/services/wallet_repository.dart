import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/loan_entry.dart';
import '../providers/wallet_cards_provider.dart';
import 'wallet_firestore_service.dart';

/// Shared owner of the single wallet document read and realtime listener.
class WalletRepository extends ChangeNotifier {
  WalletRepository(this._service);

  final WalletDataSource _service;

  String? _uid;
  WalletDocument _wallet = WalletDocument.empty;
  bool _isLoaded = false;
  bool _lastLoadSucceeded = false;
  StreamSubscription<WalletSnapshot>? _subscription;
  Future<bool>? _activeLoad;

  WalletDocument get wallet => _wallet;
  bool get isLoaded => _isLoaded;
  String? get uid => _uid;

  Future<bool> loadForUser(String? uid) {
    if (uid == null || uid.isEmpty) return clear().then((_) => true);
    if (_uid == uid && _isLoaded && _lastLoadSucceeded) {
      return Future.value(true);
    }
    final active = _activeLoad;
    if (_uid == uid && active != null) return active;

    _uid = uid;
    _isLoaded = false;
    notifyListeners();

    late final Future<bool> operation;
    operation = _load(uid).whenComplete(() {
      if (identical(_activeLoad, operation)) _activeLoad = null;
    });
    _activeLoad = operation;
    return operation;
  }

  Future<bool> _load(String uid) async {
    await _subscription?.cancel();
    try {
      _wallet = await _service.load(uid);
    } catch (_) {
      if (_uid == uid) {
        _wallet = WalletDocument.empty;
        _isLoaded = true;
        _lastLoadSucceeded = false;
        notifyListeners();
      }
      return false;
    }
    if (_uid != uid) return false;

    _isLoaded = true;
    _lastLoadSucceeded = true;
    notifyListeners();
    _subscription = _service.watch(uid).listen((snapshot) {
      if (_uid != uid || snapshot.hasPendingWrites) return;
      _wallet = snapshot.wallet;
      notifyListeners();
    }, onError: (_) {});
    return true;
  }

  Future<bool> saveCashAmount(double amount) =>
      _write((uid) => _service.saveCashAmount(uid, amount));

  Future<bool> saveCurrency(String code) =>
      _write((uid) => _service.saveCurrency(uid, code));

  Future<bool> saveCards(List<WalletCardModel> cards) =>
      _write((uid) => _service.saveCards(uid, cards));

  Future<bool> saveLoans(List<LoanEntry> loans) =>
      _write((uid) => _service.saveLoans(uid, loans));

  Future<bool> _write(Future<void> Function(String uid) write) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await write(uid);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    await _subscription?.cancel();
    _subscription = null;
    _activeLoad = null;
    _uid = null;
    _wallet = WalletDocument.empty;
    _isLoaded = true;
    _lastLoadSucceeded = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
