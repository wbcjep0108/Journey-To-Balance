import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/app_currency.dart';
import '../services/wallet_repository.dart';

/// Preferred display currency, synced across devices via the user's wallet
/// document (`users/{uid}/wallet/data`).
class CurrencyProvider extends ChangeNotifier {
  CurrencyProvider(this._repository) {
    _repository.addListener(_syncFromRepository);
    _syncFromRepository();
  }

  final WalletRepository _repository;

  String? _uid;
  AppCurrency _currency = AppCurrency.php;
  bool _loaded = false;

  AppCurrency get currency => _currency;
  String get symbol => _currency.symbol;
  String get code => _currency.code;
  bool get isLoaded => _loaded;

  /// Loads the preferred currency for [uid] and subscribes to realtime updates.
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
    final next = AppCurrency.byCode(_repository.wallet.currencyCode);
    final loaded = _repository.isLoaded;
    if (next.code == _currency.code && loaded == _loaded) return;
    _currency = next;
    _loaded = loaded;
    notifyListeners();
  }

  Future<bool> setCurrency(AppCurrency currency) =>
      setCurrencyVerified(currency);

  Future<bool> setCurrencyVerified(AppCurrency currency) async {
    if (_currency.code == currency.code) return true;
    final previous = _currency;
    _currency = currency;
    notifyListeners();

    if (_uid == null) return false;
    final saved = await _repository.saveCurrency(currency.code);
    if (!saved) {
      _currency = previous;
      notifyListeners();
      return false;
    }
    return _currency.code == currency.code;
  }

  /// Resets to the signed-out state and stops listening.
  Future<void> clear() async {
    _uid = null;
    _currency = AppCurrency.php;
    _loaded = true;
    notifyListeners();
  }

  String format(double amount, {int? decimalDigits}) {
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
    _repository.removeListener(_syncFromRepository);
    super.dispose();
  }
}
