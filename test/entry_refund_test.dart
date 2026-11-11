import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/financial_entry.dart';
import 'package:just_budget/models/loan_entry.dart';
import 'package:just_budget/providers/budget_provider.dart';
import 'package:just_budget/providers/wallet_cards_provider.dart';
import 'package:just_budget/providers/wallet_cash_provider.dart';
import 'package:just_budget/screens/home/daily_spending_page.dart';
import 'package:just_budget/services/finance_api_service.dart';
import 'package:just_budget/services/firestore_finance_service.dart';
import 'package:just_budget/services/funding_source_adjuster.dart';
import 'package:just_budget/services/wallet_firestore_service.dart';
import 'package:just_budget/services/wallet_repository.dart';

const _mari = 'assets/images/bank/maribank.png';

class _StubService implements FirestoreFinanceService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubApi implements FinanceApiService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeleteCall {
  const _DeleteCall(this.entryId, this.refund, this.awaitRemote);

  final String entryId;
  final bool refund;
  final bool awaitRemote;
}

/// Mirrors BudgetProvider.deleteEntry: a refund marks the row refunded and
/// restores Available Balance; a plain delete removes the row only.
class _FakeBudget extends BudgetProvider {
  _FakeBudget() : super(_StubService(), financeApi: _StubApi());

  final Map<FinancialCategory, List<FinancialEntry>> rows = {
    for (final category in FinancialCategory.values) category: [],
  };
  final List<_DeleteCall> calls = [];
  bool failNext = false;
  Completer<void>? gate;

  @override
  List<FinancialEntry> entriesFor(FinancialCategory category) =>
      List.unmodifiable(rows[category]!);

  @override
  Future<Map<String, dynamic>?> deleteEntry(
    FinancialCategory category,
    FinancialEntry entry, {
    bool refund = true,
    bool awaitRemote = false,
  }) async {
    calls.add(_DeleteCall(entry.id, refund, awaitRemote));
    if (gate != null) await gate!.future;
    if (failNext) {
      failNext = false;
      throw StateError('worker down');
    }
    final list = rows[category]!;
    final index = list.indexWhere((item) => item.id == entry.id);
    if (index < 0) return null;
    if (refund && !entry.isRefund) {
      list[index] = entry.copyWith(isRefund: true);
      availableBalance += entry.amount;
    } else {
      list.removeAt(index);
    }
    notifyListeners();
    return null;
  }
}

class _MemoryWallet implements WalletDataSource {
  _MemoryWallet({required this.cash, required this.cards});

  double cash;
  List<WalletCardModel> cards;
  bool failWrites = false;
  final _controller = StreamController<WalletSnapshot>.broadcast();

  @override
  Future<WalletDocument> load(String uid, {bool serverOnly = false}) async {
    return WalletDocument(
      cashAmount: cash,
      currencyCode: 'PHP',
      cards: cards,
      loans: const <LoanEntry>[],
    );
  }

  @override
  Stream<WalletSnapshot> watch(String uid) => _controller.stream;

  @override
  Future<void> saveCashAmount(String uid, double cashAmount) async {
    if (failWrites) throw StateError('write failed');
    cash = cashAmount;
  }

  @override
  Future<void> saveCards(String uid, List<WalletCardModel> next) async {
    if (failWrites) throw StateError('write failed');
    cards = next;
  }

  @override
  Future<void> saveCurrency(String uid, String currencyCode) async {}

  @override
  Future<void> saveLoans(String uid, List<LoanEntry> loans) async {}

  Future<void> close() => _controller.close();
}

class _Harness {
  _Harness._(this.store, this.repository, this.wallet, this.cards, this.budget);

  final _MemoryWallet store;
  final WalletRepository repository;
  final WalletCashProvider wallet;
  final WalletCardsProvider cards;
  final _FakeBudget budget;
  final service = EntryRefundService();

  static Future<_Harness> create({
    double cash = 500,
    List<WalletCardModel>? cards,
  }) async {
    final store = _MemoryWallet(
      cash: cash,
      cards:
          cards ??
          [
            WalletCardModel(
              id: 'mari-1',
              iconAsset: _mari,
              amount: 1000,
              nickname: 'My MariBank',
            ),
            WalletCardModel(
              id: 'mari-2',
              iconAsset: _mari,
              amount: 2000,
              nickname: "Wife's MariBank",
            ),
          ],
    );
    final repository = WalletRepository(store);
    await repository.loadForUser('user-1');
    final harness = _Harness._(
      store,
      repository,
      WalletCashProvider(repository),
      WalletCardsProvider(repository),
      _FakeBudget(),
    );
    harness.budget.availableBalance = harness.cards.combinedTotal(
      harness.wallet.amount,
    );
    return harness;
  }

  FinancialEntry add(
    String id,
    double amount, {
    String? source,
    FinancialCategory category = FinancialCategory.personal,
    String title = 'Lunch',
  }) {
    final entry = FinancialEntry(
      id: id,
      title: title,
      amount: amount,
      createdAt: DateTime(2026, 11, 5, 12),
      fundingSourceId: source,
    );
    budget.rows[category]!.insert(0, entry);
    return entry;
  }

  Future<EntryRefundResult> refund(
    String id, {
    FinancialCategory category = FinancialCategory.personal,
    bool authorized = true,
  }) {
    return service.refund(
      budget: budget,
      wallet: wallet,
      cards: cards,
      category: category,
      entryId: id,
      authorize: () async => authorized,
    );
  }

  double card(String id) => cards.cardById(id)!.amount;

  String? message(EntryRefundResult result) => entryRefundMessage(
    result,
    categoryLabel: 'Personal',
    amountLabel: 'PHP 100',
    cardLabel: result.targetCard == null
        ? null
        : cards.displayLabelFor(result.targetCard!.id),
  );

  Future<void> dispose() async {
    wallet.dispose();
    cards.dispose();
    budget.dispose();
    await repository.clear();
    await store.close();
  }
}

void main() {
  group('refund returns money to the payment source', () {
    test('a cash entry increases wallet cash by the amount', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.add('e1', 100, source: 'wallet');

      final result = await h.refund('e1');

      expect(result.outcome, EntryRefundOutcome.credited);
      expect(h.wallet.amount, 600);
      expect(h.store.cash, 600);
      expect(h.message(result), 'PHP 100 returned to Personal and Wallet.');
      expect(h.budget.calls.single.refund, isTrue);
      expect(h.budget.calls.single.awaitRemote, isTrue);
    });

    test('a card entry increases that exact card by id', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.add('e1', 250, source: 'mari-2');

      final result = await h.refund('e1');

      expect(result.outcome, EntryRefundOutcome.credited);
      expect(h.card('mari-2'), 2250);
      expect(h.card('mari-1'), 1000);
      expect(h.wallet.amount, 500);
      expect(
        h.message(result),
        "PHP 100 returned to Personal and Wife's MariBank.",
      );
    });

    test('a removed card credits Wallet and says so', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.add('e1', 100, source: 'deleted-card');

      final result = await h.refund('e1');

      expect(result.outcome, EntryRefundOutcome.creditedWalletFallback);
      expect(h.wallet.amount, 600);
      expect(
        h.message(result),
        'The original card was removed, so the refund went to Wallet.',
      );
    });

    test('an entry with no source credits nothing and says so', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.add('e1', 100);

      final result = await h.refund('e1');

      expect(result.outcome, EntryRefundOutcome.noSource);
      expect(h.wallet.amount, 500);
      expect(h.card('mari-1'), 1000);
      expect(h.card('mari-2'), 2000);
      expect(
        h.message(result),
        'This older entry has no payment source, so only your budget was '
        'refunded.',
      );
    });

    test('a double tap credits once', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.add('e1', 100, source: 'wallet');
      h.budget.gate = Completer<void>();

      final first = h.refund('e1');
      final second = await h.refund('e1');
      expect(second.outcome, EntryRefundOutcome.inFlight);

      h.budget.gate!.complete();
      expect((await first).outcome, EntryRefundOutcome.credited);
      expect(h.wallet.amount, 600);
      expect(h.budget.calls, hasLength(1));
    });

    test('a second refund of an already refunded entry credits nothing', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.add('e1', 100, source: 'wallet');

      await h.refund('e1');
      final again = await h.refund('e1');

      expect(again.outcome, EntryRefundOutcome.alreadyRefunded);
      expect(h.message(again), isNull);
      expect(h.wallet.amount, 600);
      expect(h.budget.calls, hasLength(1));
    });

    test('a failed refund call credits nothing', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.add('e1', 100, source: 'wallet');
      h.budget.failNext = true;

      final result = await h.refund('e1');

      expect(result.outcome, EntryRefundOutcome.failed);
      expect(h.message(result), isNull);
      expect(h.wallet.amount, 500);
      expect(h.budget.entriesFor(FinancialCategory.personal).single.isRefund,
          isFalse);
    });

    test('a cancelled confirmation changes nothing', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.add('e1', 100, source: 'wallet');

      final result = await h.refund('e1', authorized: false);

      expect(result.outcome, EntryRefundOutcome.cancelled);
      expect(h.budget.calls, isEmpty);
      expect(h.wallet.amount, 500);
    });

    test('a wallet write failure is reported, not swallowed', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.add('e1', 100, source: 'wallet');
      h.store.failWrites = true;

      final result = await h.refund('e1');

      expect(result.outcome, EntryRefundOutcome.creditFailed);
      expect(h.wallet.amount, 500);
      expect(
        h.message(result),
        'Refund recorded, but your wallet or card could not be updated. '
        'Please adjust it manually.',
      );
      expect(h.budget.calls, hasLength(1));
    });

    test('a card write failure is reported, not swallowed', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.add('e1', 100, source: 'mari-1');
      h.store.failWrites = true;

      final result = await h.refund('e1');

      expect(result.outcome, EntryRefundOutcome.creditFailed);
      expect(h.card('mari-1'), 1000);
    });

    test('Available Balance still equals wallet plus cards after a refund', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      // Spend 300 from a card: the Worker lowers Available Balance and the app
      // lowers the card, so the two stay equal.
      h.add('e1', 300, source: 'mari-1');
      h.budget.availableBalance -= 300;
      await h.cards.setCardAmount(cardId: 'mari-1', amount: 700);
      expect(
        h.budget.availableBalance,
        h.cards.combinedTotal(h.wallet.amount),
      );

      await h.refund('e1');

      expect(h.budget.availableBalance, 3500);
      expect(
        h.budget.availableBalance,
        h.cards.combinedTotal(h.wallet.amount),
      );
    });

    test('savings-goal entries keep their own undo and are not credited', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.add(
        'goal',
        100,
        source: 'wallet',
        title: BudgetProvider.savingsGoalEntryTitle,
      );

      final result = await h.refund('goal');

      expect(result.outcome, EntryRefundOutcome.savingsGoal);
      expect(h.wallet.amount, 500);
      expect(h.budget.calls.single.awaitRemote, isFalse);
    });
  });

  group('Daily Spending Delete', () {
    test('does not refund the category or the source', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final entry = h.add('e1', 100, source: 'wallet');
      final before = h.budget.availableBalance;

      await deleteDayEntryWithoutRefund(
        h.budget,
        DayTransaction(category: FinancialCategory.personal, entry: entry),
      );

      expect(h.budget.calls.single.refund, isFalse);
      expect(h.budget.entriesFor(FinancialCategory.personal), isEmpty);
      expect(h.budget.availableBalance, before);
      expect(h.wallet.amount, 500);
    });
  });

  group('editing an expense amount', () {
    Future<FundingAdjustmentResult> edit(
      _Harness h,
      FinancialEntry entry,
      double from,
      double to,
    ) {
      return applyEditToFundingSource(
        wallet: h.wallet,
        cards: h.cards,
        entry: entry,
        previousAmount: from,
        newAmount: to,
      );
    }

    test('100 to 150 takes 50 more from the source', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final entry = h.add('e1', 100, source: 'mari-1');

      final result = await edit(h, entry, 100, 150);

      expect(result.outcome, FundingAdjustmentOutcome.applied);
      expect(h.card('mari-1'), 950);
    });

    test('150 to 100 gives 50 back to the source', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final entry = h.add('e1', 150, source: 'wallet');

      final result = await edit(h, entry, 150, 100);

      expect(result.outcome, FundingAdjustmentOutcome.applied);
      expect(h.wallet.amount, 550);
    });

    test('an entry without a source is skipped', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final entry = h.add('e1', 100);

      final result = await edit(h, entry, 100, 150);

      expect(result.outcome, FundingAdjustmentOutcome.noSource);
      expect(h.wallet.amount, 500);
    });

    test('an increase the source cannot cover is not applied', () async {
      final h = await _Harness.create(cash: 20);
      addTearDown(h.dispose);
      final entry = h.add('e1', 100, source: 'wallet');

      final result = await edit(h, entry, 100, 150);

      expect(result.outcome, FundingAdjustmentOutcome.insufficient);
      expect(h.wallet.amount, 20);
    });

    test('a removed card is not replaced by Wallet', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final entry = h.add('e1', 150, source: 'deleted-card');

      final result = await edit(h, entry, 150, 100);

      expect(result.outcome, FundingAdjustmentOutcome.cardMissing);
      expect(h.wallet.amount, 500);
    });

    test('a write failure is reported', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final entry = h.add('e1', 100, source: 'wallet');
      h.store.failWrites = true;

      final result = await edit(h, entry, 100, 150);

      expect(result.outcome, FundingAdjustmentOutcome.failed);
      expect(h.wallet.amount, 500);
    });
  });
}
