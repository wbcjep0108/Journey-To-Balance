import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

String walletBankLabel(String iconAsset) {
  final name = iconAsset.split('/').last.replaceAll('.png', '');
  const labels = <String, String>{
    'gcash': 'GCash',
    'maribank': 'MariBank',
    'gotyme': 'GoTyme',
    'landbank': 'Landbank',
    'metrobank': 'Metrobank',
    'unionbank': 'UnionBank',
    'maya': 'Maya',
    'bdo': 'BDO',
    'bpi': 'BPI',
    'pnb': 'PNB',
  };
  return labels[name] ?? name.toUpperCase();
}

class WalletCardModel {
  WalletCardModel({
    required this.id,
    required this.iconAsset,
    required this.amount,
  });

  final String id;
  final String iconAsset;
  final double amount;

  String get bankLabel => walletBankLabel(iconAsset);

  WalletCardModel copyWith({
    String? id,
    String? iconAsset,
    double? amount,
  }) {
    return WalletCardModel(
      id: id ?? this.id,
      iconAsset: iconAsset ?? this.iconAsset,
      amount: amount ?? this.amount,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'iconAsset': iconAsset,
        'amount': amount,
      };

  static WalletCardModel fromJson(Map<String, dynamic> json) {
    return WalletCardModel(
      id: json['id'] as String,
      iconAsset: json['iconAsset'] as String,
      amount: (json['amount'] as num).toDouble(),
    );
  }
}

/// Local bank-card amounts. Independent of wallet cash.
///
/// Available Balance = wallet cash + sum of selected card amounts.
class WalletCardsProvider extends ChangeNotifier {
  WalletCardsProvider({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'wallet_cards_v1';

  final FlutterSecureStorage _storage;
  bool _loaded = false;
  List<WalletCardModel> _cards = [];

  bool get isLoaded => _loaded;
  List<WalletCardModel> get cards => List.unmodifiable(_cards);

  WalletCardModel? cardById(String id) {
    for (final c in _cards) {
      if (c.id == id) return c;
    }
    return null;
  }

  double get totalAmount =>
      _cards.fold<double>(0, (sum, card) => sum + card.amount);

  double combinedTotal(double walletCash) => walletCash + totalAmount;

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null || raw.trim().isEmpty) {
        _cards = [];
      } else {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _cards = decoded
              .whereType<Map<String, dynamic>>()
              .map(WalletCardModel.fromJson)
              .toList();
        } else {
          _cards = [];
        }
      }
    } catch (_) {
      _cards = [];
    }

    _loaded = true;
    notifyListeners();
  }

  bool hasIcon(String iconAsset) =>
      _cards.any((c) => c.iconAsset == iconAsset);

  Future<void> addCard({required String iconAsset}) async {
    if (hasIcon(iconAsset)) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _cards = [
      ..._cards,
      WalletCardModel(id: id, iconAsset: iconAsset, amount: 0),
    ];
    notifyListeners();
    await _persist();
  }

  Future<void> removeByIconAsset(String iconAsset) async {
    final next = _cards.where((c) => c.iconAsset != iconAsset).toList();
    if (next.length == _cards.length) return;
    _cards = next;
    notifyListeners();
    await _persist();
  }

  Future<void> setCardAmount({
    required String cardId,
    required double amount,
  }) async {
    await setCardAmounts({cardId: amount});
  }

  Future<void> setCardAmounts(Map<String, double> amountsById) async {
    if (amountsById.isEmpty) return;
    _cards = _cards
        .map((c) {
          final next = amountsById[c.id];
          if (next == null) return c;
          return c.copyWith(amount: next < 0 ? 0.0 : next);
        })
        .toList(growable: false);
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final json = jsonEncode(_cards.map((c) => c.toJson()).toList());
    try {
      await _storage.write(key: _storageKey, value: json);
    } catch (_) {}
  }
}
