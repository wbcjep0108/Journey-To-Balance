import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/app_currency.dart';
import 'package:just_budget/models/loan_entry.dart';
import 'package:just_budget/providers/currency_provider.dart';
import 'package:just_budget/providers/wallet_cards_provider.dart';
import 'package:just_budget/providers/wallet_cash_provider.dart';
import 'package:just_budget/services/wallet_firestore_service.dart';
import 'package:just_budget/services/wallet_repository.dart';

void main() {
  test('concurrent consumers share one wallet load and one listener', () async {
    final source = _FakeWalletDataSource();
    final repository = WalletRepository(source);

    final results = await Future.wait([
      repository.loadForUser('user-1'),
      repository.loadForUser('user-1'),
      repository.loadForUser('user-1'),
      repository.loadForUser('user-1'),
    ]);

    expect(results, everyElement(isTrue));
    expect(source.loadCalls, 1);
    expect(source.watchCalls, 1);
    expect(repository.wallet.cashAmount, 25);

    await repository.clear();
    await source.close();
  });

  test('wallet writes report failure', () async {
    final source = _FakeWalletDataSource(failWrites: true);
    final repository = WalletRepository(source);
    await repository.loadForUser('user-1');

    expect(await repository.saveCashAmount(10), isFalse);
    expect(await repository.saveCurrency('USD'), isFalse);
    expect(await repository.saveCards(const []), isFalse);
    expect(await repository.saveLoans(const []), isFalse);

    await repository.clear();
    await source.close();
  });

  test('wallet-facing providers return false when persistence fails', () async {
    final source = _FakeWalletDataSource(failWrites: true);
    final repository = WalletRepository(source);
    await repository.loadForUser('user-1');
    final cash = WalletCashProvider(repository);
    final cards = WalletCardsProvider(repository);
    final currency = CurrencyProvider(repository);

    expect(await cash.setAmount(50), isFalse);
    expect(await cards.addCard(iconAsset: 'assets/card.png'), isFalse);
    expect(await currency.setCurrency(AppCurrency.all[1]), isFalse);

    cash.dispose();
    cards.dispose();
    currency.dispose();
    await repository.clear();
    await source.close();
  });
}

class _FakeWalletDataSource implements WalletDataSource {
  _FakeWalletDataSource({this.failWrites = false});

  final bool failWrites;
  final _controller = StreamController<WalletSnapshot>.broadcast();
  int loadCalls = 0;
  int watchCalls = 0;

  @override
  Future<WalletDocument> load(String uid, {bool serverOnly = false}) async {
    loadCalls++;
    await Future<void>.delayed(Duration.zero);
    return const WalletDocument(
      cashAmount: 25,
      currencyCode: 'PHP',
      cards: <WalletCardModel>[],
      loans: <LoanEntry>[],
    );
  }

  @override
  Stream<WalletSnapshot> watch(String uid) {
    watchCalls++;
    return _controller.stream;
  }

  Future<void> _write() async {
    if (failWrites) throw StateError('write failed');
  }

  @override
  Future<void> saveCards(String uid, List<WalletCardModel> cards) => _write();

  @override
  Future<void> saveCashAmount(String uid, double cashAmount) => _write();

  @override
  Future<void> saveCurrency(String uid, String currencyCode) => _write();

  @override
  Future<void> saveLoans(String uid, List<LoanEntry> loans) => _write();

  Future<void> close() => _controller.close();
}
