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

/// Maximum characters allowed in a user-chosen card nickname.
const int kWalletCardNicknameMaxLength = 24;

/// Trims a nickname and enforces the max length. Returns null when the result
/// is empty, so the card falls back to its [WalletCardModel.bankLabel].
String? normalizeCardNickname(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.length > kWalletCardNicknameMaxLength
      ? trimmed.substring(0, kWalletCardNicknameMaxLength)
      : trimmed;
}

class WalletCardModel {
  WalletCardModel({
    required this.id,
    required this.iconAsset,
    required this.amount,
    String? nickname,
  }) : nickname = normalizeCardNickname(nickname);

  final String id;
  final String iconAsset;
  final double amount;

  /// Optional user-chosen label. Null means "use the bank name".
  final String? nickname;

  /// The bank name derived from the card design asset.
  String get bankLabel => walletBankLabel(iconAsset);

  /// What to show the user: the nickname when set, otherwise the bank name.
  String get displayName => nickname ?? bankLabel;

  WalletCardModel copyWith({
    String? id,
    String? iconAsset,
    double? amount,
    String? nickname,
    bool clearNickname = false,
  }) {
    return WalletCardModel(
      id: id ?? this.id,
      iconAsset: iconAsset ?? this.iconAsset,
      amount: amount ?? this.amount,
      nickname: clearNickname ? null : (nickname ?? this.nickname),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'iconAsset': iconAsset,
    'amount': amount,
    if (nickname != null && nickname!.isNotEmpty) 'nickname': nickname,
  };

  static WalletCardModel fromJson(Map<String, dynamic> json) {
    final rawNickname = json['nickname'];
    return WalletCardModel(
      id: json['id'] as String,
      iconAsset: json['iconAsset'] as String,
      amount: (json['amount'] as num).toDouble(),
      nickname: rawNickname is String ? rawNickname : null,
    );
  }
}

/// Builds display labels for [cards], adding a short "(n)" suffix when two or
/// more cards would otherwise show the same label, so they stay distinct in
/// lists. Keyed by card id.
Map<String, String> walletCardDisplayLabels(List<WalletCardModel> cards) {
  final counts = <String, int>{};
  for (final card in cards) {
    counts[card.displayName] = (counts[card.displayName] ?? 0) + 1;
  }
  final seen = <String, int>{};
  final labels = <String, String>{};
  for (final card in cards) {
    final base = card.displayName;
    if ((counts[base] ?? 0) <= 1) {
      labels[card.id] = base;
      continue;
    }
    final occurrence = (seen[base] ?? 0) + 1;
    seen[base] = occurrence;
    labels[card.id] = '$base ($occurrence)';
  }
  return labels;
}

/// Maximum number of cards a single user may hold.
const int kWalletMaxCards = 20;

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

  /// Whether another card can be added without exceeding [kWalletMaxCards].
  bool get canAddCard => _cards.length < kWalletMaxCards;

  /// Display labels keyed by card id, disambiguated with a "(n)" suffix when
  /// two cards would otherwise share the same label.
  Map<String, String> get displayLabels => walletCardDisplayLabels(_cards);

  /// The disambiguated label for a single card id (falls back to 'Card').
  String displayLabelFor(String id) => displayLabels[id] ?? 'Card';

  /// Generates a nickname suggestion for a new card of [iconAsset], e.g.
  /// "MariBank 2" when one MariBank card already exists. Returns null for the
  /// first card of a bank so it keeps the plain bank name as its default.
  String? suggestedNicknameFor(String iconAsset) {
    final bankLabel = walletBankLabel(iconAsset);
    final sameBank = _cards.where((c) => c.iconAsset == iconAsset).length;
    if (sameBank == 0) return null;
    return '$bankLabel ${sameBank + 1}';
  }

  /// Adds a card, returning the generated id, or null when the cap is hit or
  /// the write fails. Each call creates a NEW card (duplicates allowed).
  Future<String?> addCardReturningId({
    required String iconAsset,
    String? nickname,
  }) async {
    if (!canAddCard) return null;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final previous = _cards;
    final card = WalletCardModel(
      id: id,
      iconAsset: iconAsset,
      amount: 0,
      nickname: nickname,
    );
    _cards = [..._cards, card];
    notifyListeners();
    final saved = await _persist(previous);
    return saved ? id : null;
  }

  Future<bool> addCard({required String iconAsset}) async =>
      (await addCardReturningId(iconAsset: iconAsset)) != null;

  /// Backward-compatible add used by onboarding. Unlike before, this no longer
  /// dedupes by icon — onboarding guards duplicates itself.
  Future<bool> addCardVerified({required String iconAsset}) =>
      addCard(iconAsset: iconAsset);

  /// Renames a card by id. An empty/whitespace nickname clears it so the card
  /// falls back to its bank name.
  Future<bool> renameCard({
    required String cardId,
    required String? nickname,
  }) async {
    final index = _cards.indexWhere((c) => c.id == cardId);
    if (index < 0) return false;
    final normalized = normalizeCardNickname(nickname);
    if (_cards[index].nickname == normalized) return true;
    final previous = _cards;
    _cards = [
      for (final card in _cards)
        card.id == cardId
            ? card.copyWith(nickname: normalized, clearNickname: normalized == null)
            : card,
    ];
    notifyListeners();
    return _persist(previous);
  }

  /// Deletes a single card by id (never by icon).
  Future<bool> removeById(String cardId) async {
    final next = _cards.where((c) => c.id != cardId).toList();
    if (next.length == _cards.length) return true;
    final previous = _cards;
    _cards = next;
    notifyListeners();
    return _persist(previous);
  }

  /// Deletes every card matching [iconAsset]. Retained for the legacy
  /// onboarding/clear paths; UI deletion is id-based via [removeById].
  Future<bool> removeByIconAsset(String iconAsset) async {
    final next = _cards.where((c) => c.iconAsset != iconAsset).toList();
    if (next.length == _cards.length) return true;
    final previous = _cards;
    _cards = next;
    notifyListeners();
    return _persist(previous);
  }

  /// Replaces local card state in memory only, without persisting. Used by the
  /// savings flow's optimistic updates — the Worker writes the wallet document
  /// (with a version precondition) and the realtime snapshot then replaces this
  /// local state. Persisting here would double-write and conflict.
  void applyInMemoryCardAmounts(Map<String, double> amountsById) {
    if (amountsById.isEmpty) return;
    _cards = _cards
        .map((c) {
          final next = amountsById[c.id];
          if (next == null) return c;
          return c.copyWith(amount: next < 0 ? 0.0 : next);
        })
        .toList(growable: false);
    notifyListeners();
  }

  /// Restores a previously captured card list in memory only (error rollback
  /// companion to [applyInMemoryCardAmounts]).
  void restoreInMemoryCards(List<WalletCardModel> cards) {
    _cards = List<WalletCardModel>.from(cards);
    notifyListeners();
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
