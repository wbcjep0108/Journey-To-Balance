import 'package:flutter/foundation.dart';

import '../services/wallet_repository.dart';

/// Cash-on-hand amount, synced across devices via the user's wallet document
/// (`users/{uid}/wallet/data`). Independent of Available Balance.
class WalletCashProvider extends ChangeNotifier {
  WalletCashProvider(this._repository) {
    _repository.addListener(_syncFromRepository);
    _syncFromRepository();
  }

  final WalletRepository _repository;

  String? _uid;
  double _amount = 0;
  bool _loaded = false;

  double get amount => _amount;
  bool get isLoaded => _loaded;

  /// Loads the cash amount for [uid] from Firestore and subscribes to realtime
  /// updates so changes made on another device appear here automatically.
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
    final next = _repository.wallet.cashAmount;
    final loaded = _repository.isLoaded;
    if (next == _amount && loaded == _loaded) return;
    _amount = next;
    _loaded = loaded;
    notifyListeners();
  }

  Future<bool> setAmount(double amount) => setAmountVerified(amount);

  Future<bool> setAmountVerified(double amount) async {
    final next = amount < 0 ? 0.0 : amount;
    final previous = _amount;
    _amount = next;
    notifyListeners();

    if (_uid == null) return false;
    final saved = await _repository.saveCashAmount(next);
    if (!saved) {
      _amount = previous;
      notifyListeners();
      return false;
    }
    return (_amount - next).abs() < 0.001;
  }

  /// Resets to the signed-out state and stops listening.
  Future<void> clear() async {
    _uid = null;
    _amount = 0;
    _loaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _repository.removeListener(_syncFromRepository);
    super.dispose();
  }
}
