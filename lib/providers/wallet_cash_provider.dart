import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local cash-on-hand amount, independent of Available Balance.
class WalletCashProvider extends ChangeNotifier {
  WalletCashProvider({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'wallet_cash_amount';

  final FlutterSecureStorage _storage;
  double _amount = 0;
  bool _loaded = false;

  double get amount => _amount;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    try {
      final saved = await _storage.read(key: _storageKey);
      _amount = double.tryParse(saved ?? '') ?? 0;
    } catch (_) {
      _amount = 0;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setAmount(double amount) async {
    final next = amount < 0 ? 0.0 : amount;
    _amount = next;
    notifyListeners();
    try {
      await _storage.write(key: _storageKey, value: next.toString());
    } catch (_) {}
  }
}
