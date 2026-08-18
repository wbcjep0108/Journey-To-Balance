import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

import '../models/app_currency.dart';

class CurrencyProvider extends ChangeNotifier {
  CurrencyProvider({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage() {
    _load();
  }

  static const _storageKey = 'preferred_currency_code';

  final FlutterSecureStorage _storage;
  AppCurrency _currency = AppCurrency.php;
  bool _loaded = false;

  AppCurrency get currency => _currency;
  String get symbol => _currency.symbol;
  String get code => _currency.code;
  bool get isLoaded => _loaded;

  Future<void> _load() async {
    try {
      final saved = await _storage.read(key: _storageKey);
      _currency = AppCurrency.byCode(saved);
    } catch (_) {
      _currency = AppCurrency.php;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setCurrency(AppCurrency currency) async {
    if (_currency.code == currency.code) return;
    _currency = currency;
    notifyListeners();
    try {
      await _storage.write(key: _storageKey, value: currency.code);
    } catch (_) {}
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
}
