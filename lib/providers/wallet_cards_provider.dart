import 'package:flutter/foundation.dart';

import '../services/wallet_repository.dart';

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

  WalletCardModel copyWith({String? id, String? iconAsset, double? amount}) {
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

/// Bank-card amounts, synced across devices via the user's wallet document
/// (`users/{uid}/wallet/data`). Independent of wallet cash.
///
/// Available Balance = wallet cash + sum of selected card amounts.
class WalletCardsProvider extends ChangeNotifier {
  WalletCardsProvider(this._repository) {
    _repository.addListener(_syncFromRepository);
    _syncFromRepository();
  }

  final WalletRepository _repository;

  String? _uid;
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

  /// Loads cards for [uid] from Firestore and subscribes to realtime updates.
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
    _cards = _repository.wallet.cards;
    _loaded = _repository.isLoaded;
    notifyListeners();
  }

  bool hasIcon(String iconAsset) => _cards.any((c) => c.iconAsset == iconAsset);

  Future<bool> addCard({required String iconAsset}) =>
      addCardVerified(iconAsset: iconAsset);

  Future<bool> addCardVerified({required String iconAsset}) async {
    if (hasIcon(iconAsset)) return true;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final previous = _cards;
    _cards = [
      ..._cards,
      WalletCardModel(id: id, iconAsset: iconAsset, amount: 0),
    ];
    notifyListeners();
    final saved = await _persist(previous);
    return saved && hasIcon(iconAsset);
  }

  Future<bool> removeByIconAsset(String iconAsset) async {
    final next = _cards.where((c) => c.iconAsset != iconAsset).toList();
    if (next.length == _cards.length) return true;
    final previous = _cards;
    _cards = next;
    notifyListeners();
    return _persist(previous);
  }

  Future<bool> setCardAmount({
    required String cardId,
    required double amount,
  }) async {
    return setCardAmounts({cardId: amount});
  }

  Future<bool> setCardAmounts(Map<String, double> amountsById) =>
      setCardAmountsVerified(amountsById);

  Future<bool> setCardAmountsVerified(Map<String, double> amountsById) async {
    if (amountsById.isEmpty) return true;
    final previous = _cards;
    _cards = _cards
        .map((c) {
          final next = amountsById[c.id];
          if (next == null) return c;
          return c.copyWith(amount: next < 0 ? 0.0 : next);
        })
        .toList(growable: false);
    notifyListeners();
    final saved = await _persist(previous);
    if (!saved) return false;
    return amountsById.entries.every((entry) {
      final card = cardById(entry.key);
      final expected = entry.value < 0 ? 0.0 : entry.value;
      return card != null && (card.amount - expected).abs() < 0.001;
    });
  }

  Future<bool> _persist(List<WalletCardModel> previous) async {
    if (_uid == null) return false;
    final saved = await _repository.saveCards(_cards);
    if (!saved) {
      _cards = previous;
      notifyListeners();
      return false;
    }
    return true;
  }

  /// Resets to the signed-out state and stops listening.
  Future<void> clear() async {
    _uid = null;
    _cards = [];
    _loaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _repository.removeListener(_syncFromRepository);
    super.dispose();
  }
}
