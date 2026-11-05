import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/loan_entry.dart';
import 'package:just_budget/providers/wallet_cards_provider.dart';
import 'package:just_budget/providers/wallet_cash_provider.dart';
import 'package:just_budget/services/wallet_firestore_service.dart';
import 'package:just_budget/services/wallet_repository.dart';

const _mari = 'assets/images/bank/maribank.png';
const _bdo = 'assets/images/bank/bdo.png';

void main() {
  group('WalletCardModel nickname', () {
    test('displayName falls back to bank label, trims and caps nickname', () {
      final plain = WalletCardModel(id: '1', iconAsset: _mari, amount: 0);
      expect(plain.displayName, 'MariBank');
      expect(plain.nickname, isNull);

      final named = WalletCardModel(
        id: '2',
        iconAsset: _mari,
        amount: 0,
        nickname: "  Wife's MariBank  ",
      );
      expect(named.nickname, "Wife's MariBank");
      expect(named.displayName, "Wife's MariBank");

      final tooLong = WalletCardModel(
        id: '3',
        iconAsset: _mari,
        amount: 0,
        nickname: 'x' * 40,
      );
      expect(tooLong.nickname!.length, kWalletCardNicknameMaxLength);

      final whitespace = WalletCardModel(
        id: '4',
        iconAsset: _mari,
        amount: 0,
        nickname: '   ',
      );
      expect(whitespace.nickname, isNull);
      expect(whitespace.displayName, 'MariBank');
    });

    test('nickname round-trips through json; absent nickname omitted', () {
      final named = WalletCardModel(
        id: '2',
        iconAsset: _mari,
        amount: 10,
        nickname: 'Mine',
      );
      final json = named.toJson();
      expect(json['nickname'], 'Mine');
      final restored = WalletCardModel.fromJson(
        Map<String, dynamic>.from(json),
      );
      expect(restored.nickname, 'Mine');
      expect(restored.displayName, 'Mine');

      final plain = WalletCardModel(id: '1', iconAsset: _mari, amount: 0);
      expect(plain.toJson().containsKey('nickname'), isFalse);
    });
  });

  group('walletCardDisplayLabels', () {
    test('adds (n) suffix only when labels collide', () {
      final cards = [
        WalletCardModel(id: 'a', iconAsset: _mari, amount: 0),
        WalletCardModel(id: 'b', iconAsset: _mari, amount: 0),
        WalletCardModel(id: 'c', iconAsset: _bdo, amount: 0),
      ];
      final labels = walletCardDisplayLabels(cards);
      expect(labels['a'], 'MariBank (1)');
      expect(labels['b'], 'MariBank (2)');
      expect(labels['c'], 'BDO');
    });
  });

  group('WalletCardsProvider multi-card', () {
    test('two cards of the same bank get distinct ids and persist', () async {
      final source = _FakeWalletDataSource();
      final repository = WalletRepository(source);
      await repository.loadForUser('user-1');
      final cards = WalletCardsProvider(repository);

      final id1 = await cards.addCardReturningId(iconAsset: _mari);
      // microsecond ids can collide in a tight loop; force monotonic time.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final id2 = await cards.addCardReturningId(
        iconAsset: _mari,
        nickname: "Wife's MariBank",
      );

      expect(id1, isNotNull);
      expect(id2, isNotNull);
      expect(id1, isNot(id2));
      expect(cards.cards.length, 2);

      // Independent balances.
      await cards.setCardAmount(cardId: id1!, amount: 100);
      await cards.setCardAmount(cardId: id2!, amount: 250);
      expect(cards.cardById(id1)!.amount, 100);
      expect(cards.cardById(id2)!.amount, 250);

      // Persisted shape survives a reload from the same backing store.
      final reloaded = WalletRepository(source);
      await reloaded.loadForUser('user-1');
      final reloadedCards = reloaded.wallet.cards;
      expect(reloadedCards.length, 2);
      expect(reloadedCards.firstWhere((c) => c.id == id2).nickname,
          "Wife's MariBank");
      expect(reloadedCards.firstWhere((c) => c.id == id1).amount, 100);
      expect(reloadedCards.firstWhere((c) => c.id == id2).amount, 250);

      cards.dispose();
      await repository.clear();
      await reloaded.clear();
      await source.close();
    });

    test('suggestedNicknameFor numbers duplicates', () async {
      final source = _FakeWalletDataSource();
      final repository = WalletRepository(source);
      await repository.loadForUser('user-1');
      final cards = WalletCardsProvider(repository);

      expect(cards.suggestedNicknameFor(_mari), isNull);
      await cards.addCardReturningId(iconAsset: _mari);
      expect(cards.suggestedNicknameFor(_mari), 'MariBank 2');

      cards.dispose();
      await repository.clear();
      await source.close();
    });

    test('renameCard updates and clears nickname', () async {
      final source = _FakeWalletDataSource();
      final repository = WalletRepository(source);
      await repository.loadForUser('user-1');
      final cards = WalletCardsProvider(repository);
      final id = (await cards.addCardReturningId(iconAsset: _mari))!;

      expect(await cards.renameCard(cardId: id, nickname: 'Travel'), isTrue);
      expect(cards.cardById(id)!.displayName, 'Travel');

      expect(await cards.renameCard(cardId: id, nickname: '   '), isTrue);
      expect(cards.cardById(id)!.nickname, isNull);
      expect(cards.cardById(id)!.displayName, 'MariBank');

      cards.dispose();
      await repository.clear();
      await source.close();
    });

    test('removeById deletes only the targeted card', () async {
      final source = _FakeWalletDataSource();
      final repository = WalletRepository(source);
      await repository.loadForUser('user-1');
      final cards = WalletCardsProvider(repository);
      final id1 = (await cards.addCardReturningId(iconAsset: _mari))!;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final id2 = (await cards.addCardReturningId(iconAsset: _mari))!;

      expect(cards.cards.length, 2);
      await cards.removeById(id1);
      expect(cards.cards.length, 1);
      expect(cards.cardById(id1), isNull);
      expect(cards.cardById(id2), isNotNull);

      cards.dispose();
      await repository.clear();
      await source.close();
    });

    test('enforces the card cap', () async {
      final source = _FakeWalletDataSource();
      final repository = WalletRepository(source);
      await repository.loadForUser('user-1');
      final cards = WalletCardsProvider(repository);
      for (var i = 0; i < kWalletMaxCards; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        await cards.addCardReturningId(iconAsset: _mari);
      }
      expect(cards.canAddCard, isFalse);
      expect(await cards.addCardReturningId(iconAsset: _bdo), isNull);
      expect(cards.cards.length, kWalletMaxCards);

      cards.dispose();
      await repository.clear();
      await source.close();
    });
  });

  group('in-memory optimistic updates do not persist', () {
    test('applyInMemoryCardAmounts never calls saveCards', () async {
      final source = _FakeWalletDataSource(seedCards: [
        WalletCardModel(id: 'c1', iconAsset: _mari, amount: 100),
      ]);
      final repository = WalletRepository(source);
      await repository.loadForUser('user-1');
      final cards = WalletCardsProvider(repository);
      source.saveCardsCalls = 0;

      cards.applyInMemoryCardAmounts({'c1': 40});
      expect(cards.cardById('c1')!.amount, 40);
      expect(source.saveCardsCalls, 0);

      cards.restoreInMemoryCards([
        WalletCardModel(id: 'c1', iconAsset: _mari, amount: 100),
      ]);
      expect(cards.cardById('c1')!.amount, 100);
      expect(source.saveCardsCalls, 0);

      cards.dispose();
      await repository.clear();
      await source.close();
    });

    test('applyInMemoryAmount never calls saveCashAmount', () async {
      final source = _FakeWalletDataSource(seedCash: 500);
      final repository = WalletRepository(source);
      await repository.loadForUser('user-1');
      final cash = WalletCashProvider(repository);
      source.saveCashCalls = 0;

      final previous = cash.applyInMemoryAmount(300);
      expect(previous, 500);
      expect(cash.amount, 300);
      expect(source.saveCashCalls, 0);

      cash.restoreInMemoryAmount(previous);
      expect(cash.amount, 500);
      expect(source.saveCashCalls, 0);

      cash.dispose();
      await repository.clear();
      await source.close();
    });
  });
}

class _FakeWalletDataSource implements WalletDataSource {
  _FakeWalletDataSource({
    this.seedCards = const <WalletCardModel>[],
    this.seedCash = 0,
  });

  final List<WalletCardModel> seedCards;
  final double seedCash;
  final _controller = StreamController<WalletSnapshot>.broadcast();

  // Mutable backing store so saves are visible on the next load.
  List<WalletCardModel>? _stored;
  double? _storedCash;

  int saveCardsCalls = 0;
  int saveCashCalls = 0;

  @override
  Future<WalletDocument> load(String uid, {bool serverOnly = false}) async {
    await Future<void>.delayed(Duration.zero);
    return WalletDocument(
      cashAmount: _storedCash ?? seedCash,
      currencyCode: 'PHP',
      cards: _stored ?? seedCards,
      loans: const <LoanEntry>[],
    );
  }

  @override
  Stream<WalletSnapshot> watch(String uid) => _controller.stream;

  @override
  Future<void> saveCards(String uid, List<WalletCardModel> cards) async {
    saveCardsCalls++;
    _stored = List<WalletCardModel>.from(cards);
  }

  @override
  Future<void> saveCashAmount(String uid, double cashAmount) async {
    saveCashCalls++;
    _storedCash = cashAmount;
  }

  @override
  Future<void> saveCurrency(String uid, String currencyCode) async {}

  @override
  Future<void> saveLoans(String uid, List<LoanEntry> loans) async {}

  Future<void> close() => _controller.close();
}
