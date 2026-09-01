import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/app_currency.dart';
import '../services/wallet_firestore_service.dart';

/// Preferred display currency, synced across devices via the user's wallet
/// document (`users/{uid}/wallet/data`).
class CurrencyProvider extends ChangeNotifier {
  CurrencyProvider({WalletFirestoreService? service})
    : _service = service ?? WalletFirestoreService();

  final WalletFirestoreService _service;

  String? _uid;
  AppCurrency _currency = AppCurrency.php;
  bool _loaded = false;
  StreamSubscription<WalletSnapshot>? _sub;

  AppCurrency get currency => _currency;
  String get symbol => _currency.symbol;
  String get code => _currency.code;
  bool get isLoaded => _loaded;

  /// Loads the preferred currency for [uid] and subscribes to realtime updates.
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
      _currency = AppCurrency.byCode(wallet.currencyCode);
    } catch (_) {
      _currency = AppCurrency.php;
    }

    _loaded = true;
    notifyListeners();

    _subscribe(uid);
  }

  void _subscribe(String uid) {
    _sub?.cancel();
    _sub = _service.watch(uid).listen((snapshot) {
      if (snapshot.hasPendingWrites) return;
      final next = AppCurrency.byCode(snapshot.wallet.currencyCode);
      if (next.code == _currency.code) return;
      _currency = next;
      notifyListeners();
    });
  }

  Future<void> setCurrency(AppCurrency currency) async {
    if (_currency.code == currency.code) return;
    final previous = _currency;
    _currency = currency;
    notifyListeners();

    final uid = _uid;
    if (uid == null) return;
    try {
      await _service.saveCurrency(uid, currency.code);
    } catch (_) {
      _currency = previous;
      notifyListeners();
    }
  }

  /// Resets to the signed-out state and stops listening.
  void clear() {
    _sub?.cancel();
    _sub = null;
    _uid = null;
    _currency = AppCurrency.php;
    _loaded = true;
    notifyListeners();
  }

  String format(
    double amount, {
    int? decimalDigits,
  }) {
    final digits = decimalDigits ?? (amount % 1 == 0 ? 0 : 2);
    return NumberFormat.currency(
      locale: _currency.locale,
      symbol: _currency.symbol,
      decimalDigits: digits,
    ).format(amount);
  }

  /// Prefix format used across most UI surfaces.
  String formatAmount(double amount, {String pattern = '#,##0.##'}) {
    return '${_currency.symbol}${NumberFormat(pattern).format(amount)}';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
