import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/wallet_firestore_service.dart';

/// Cash-on-hand amount, synced across devices via the user's wallet document
/// (`users/{uid}/wallet/data`). Independent of Available Balance.
class WalletCashProvider extends ChangeNotifier {
  WalletCashProvider({WalletFirestoreService? service})
    : _service = service ?? WalletFirestoreService();

  final WalletFirestoreService _service;

  String? _uid;
  double _amount = 0;
  bool _loaded = false;
  StreamSubscription<WalletSnapshot>? _sub;

  double get amount => _amount;
  bool get isLoaded => _loaded;

  /// Loads the cash amount for [uid] from Firestore and subscribes to realtime
  /// updates so changes made on another device appear here automatically.
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
      _amount = wallet.cashAmount;
    } catch (_) {
      _amount = 0;
    }

    _loaded = true;
    notifyListeners();

    _subscribe(uid);
  }

  void _subscribe(String uid) {
    _sub?.cancel();
    _sub = _service.watch(uid).listen((snapshot) {
      // Ignore local pending writes so our own optimistic value isn't clobbered
      // by an intermediate echo before the server value settles.
      if (snapshot.hasPendingWrites) return;
      final next = snapshot.wallet.cashAmount;
      if (next == _amount) return;
      _amount = next;
      notifyListeners();
    });
  }

  Future<void> setAmount(double amount) async {
    final next = amount < 0 ? 0.0 : amount;
    final previous = _amount;
    _amount = next;
    notifyListeners();

    final uid = _uid;
    if (uid == null) return;
    try {
      await _service.saveCashAmount(uid, next);
    } catch (_) {
      _amount = previous;
      notifyListeners();
    }
  }

  /// Resets to the signed-out state and stops listening.
  void clear() {
    _sub?.cancel();
    _sub = null;
    _uid = null;
    _amount = 0;
    _loaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
