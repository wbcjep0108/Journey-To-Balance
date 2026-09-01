import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/wallet_firestore_service.dart';

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

/// Bank-card amounts, synced across devices via the user's wallet document
/// (`users/{uid}/wallet/data`). Independent of wallet cash.
///
/// Available Balance = wallet cash + sum of selected card amounts.
class WalletCardsProvider extends ChangeNotifier {
  WalletCardsProvider({WalletFirestoreService? service})
    : _service = service ?? WalletFirestoreService();

  final WalletFirestoreService _service;

  String? _uid;
  bool _loaded = false;
  List<WalletCardModel> _cards = [];
  StreamSubscription<WalletSnapshot>? _sub;

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
      clear();
      return;
    }

    _uid = uid;
    _loaded = false;
    notifyListeners();

    try {
      final wallet = await _service.load(uid);
      _cards = wallet.cards;
    } catch (_) {
      _cards = [];
    }

    _loaded = true;
    notifyListeners();

    _subscribe(uid);
  }

  void _subscribe(String uid) {
    _sub?.cancel();
    _sub = _service.watch(uid).listen((snapshot) {
      if (snapshot.hasPendingWrites) return;
      _cards = snapshot.wallet.cards;
      notifyListeners();
    });
  }

  bool hasIcon(String iconAsset) => _cards.any((c) => c.iconAsset == iconAsset);

  Future<void> addCard({required String iconAsset}) async {
    if (hasIcon(iconAsset)) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final previous = _cards;
    _cards = [
      ..._cards,
      WalletCardModel(id: id, iconAsset: iconAsset, amount: 0),
    ];
    notifyListeners();
    await _persist(previous);
  }

  Future<void> removeByIconAsset(String iconAsset) async {
    final next = _cards.where((c) => c.iconAsset != iconAsset).toList();
    if (next.length == _cards.length) return;
    final previous = _cards;
    _cards = next;
    notifyListeners();
    await _persist(previous);
  }

  Future<void> setCardAmount({
    required String cardId,
    required double amount,
  }) async {
    await setCardAmounts({cardId: amount});
  }

  Future<void> setCardAmounts(Map<String, double> amountsById) async {
    if (amountsById.isEmpty) return;
    final previous = _cards;
    _cards = _cards
        .map((c) {
          final next = amountsById[c.id];
          if (next == null) return c;
          return c.copyWith(amount: next < 0 ? 0.0 : next);
        })
        .toList(growable: false);
    notifyListeners();
    await _persist(previous);
  }

  Future<void> _persist(List<WalletCardModel> previous) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _service.saveCards(uid, _cards);
    } catch (_) {
      _cards = previous;
      notifyListeners();
    }
  }

  /// Resets to the signed-out state and stops listening.
  void clear() {
    _sub?.cancel();
    _sub = null;
    _uid = null;
    _cards = [];
    _loaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
