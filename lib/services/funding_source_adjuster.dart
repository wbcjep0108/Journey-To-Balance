import '../models/financial_entry.dart';
import '../providers/budget_provider.dart';
import '../providers/wallet_cards_provider.dart';
import '../providers/wallet_cash_provider.dart';

/// What happened when a wallet or card balance was adjusted for an entry.
enum FundingAdjustmentOutcome {
  /// The balance was changed on the original wallet or card.
  applied,

  /// The original card no longer exists, so Wallet was credited instead.
  appliedToWalletFallback,

  /// The entry has no payment source, so nothing was changed.
  noSource,

  /// The original card no longer exists and no fallback was allowed.
  cardMissing,

  /// The source does not hold enough money for the charge.
  insufficient,

  /// The balance write failed or could not be verified.
  failed,
}

class FundingAdjustmentResult {
  const FundingAdjustmentResult(this.outcome, {this.targetCard});

  final FundingAdjustmentOutcome outcome;

  /// The card that was (or would have been) adjusted. Null for Wallet.
  final WalletCardModel? targetCard;

  bool get changedBalance =>
      outcome == FundingAdjustmentOutcome.applied ||
      outcome == FundingAdjustmentOutcome.appliedToWalletFallback;
}

/// Adds [delta] to the wallet or card identified by [sourceId]. A positive
/// [delta] credits money back; a negative one charges more.
///
/// The write uses the providers' verified setters, so a failed or unconfirmed
/// write is reported as [FundingAdjustmentOutcome.failed] instead of being
/// swallowed. Amounts are combined in centavos to avoid rounding drift.
/// When the card is gone, Wallet is credited if [fallbackToWallet] is true.
/// A charge never falls back to Wallet and never takes a balance below zero.
Future<FundingAdjustmentResult> adjustFundingSource({
  required WalletCashProvider wallet,
  required WalletCardsProvider cards,
  required String? sourceId,
  required double delta,
  bool fallbackToWallet = true,
}) async {
  final id = sourceId?.trim();
  if (id == null || id.isEmpty) {
    return const FundingAdjustmentResult(FundingAdjustmentOutcome.noSource);
  }
  final deltaCents = moneyToCents(delta);

  Future<FundingAdjustmentResult> applyToWallet(
    FundingAdjustmentOutcome success,
  ) async {
    final nextCents = moneyToCents(wallet.amount) + deltaCents;
    if (nextCents < 0) {
      return const FundingAdjustmentResult(
        FundingAdjustmentOutcome.insufficient,
      );
    }
    if (deltaCents == 0) return FundingAdjustmentResult(success);
    try {
      final saved = await wallet.setAmountVerified(centsToMoney(nextCents));
      return FundingAdjustmentResult(
        saved ? success : FundingAdjustmentOutcome.failed,
      );
    } catch (_) {
      return const FundingAdjustmentResult(FundingAdjustmentOutcome.failed);
    }
  }

  if (id == 'wallet') {
    return applyToWallet(FundingAdjustmentOutcome.applied);
  }

  final card = cards.cardById(id);
  if (card == null) {
    if (fallbackToWallet && deltaCents > 0) {
      return applyToWallet(FundingAdjustmentOutcome.appliedToWalletFallback);
    }
    return const FundingAdjustmentResult(FundingAdjustmentOutcome.cardMissing);
  }

  final nextCents = moneyToCents(card.amount) + deltaCents;
  if (nextCents < 0) {
    return FundingAdjustmentResult(
      FundingAdjustmentOutcome.insufficient,
      targetCard: card,
    );
  }
  if (deltaCents == 0) {
    return FundingAdjustmentResult(
      FundingAdjustmentOutcome.applied,
      targetCard: card,
    );
  }
  try {
    final saved = await cards.setCardAmountsVerified({
      card.id: centsToMoney(nextCents),
    });
    return FundingAdjustmentResult(
      saved ? FundingAdjustmentOutcome.applied : FundingAdjustmentOutcome.failed,
      targetCard: card,
    );
  } catch (_) {
    return FundingAdjustmentResult(
      FundingAdjustmentOutcome.failed,
      targetCard: card,
    );
  }
}

/// Whether [entry] is a savings-goal contribution. Those keep their own undo
/// flow (Worker reversal or the savings page restore) and are never credited
/// by the ordinary refund or edit logic below.
bool isSavingsGoalEntry(FinancialEntry entry) =>
    entry.title == BudgetProvider.savingsGoalEntryTitle ||
    entry.savingsSources.isNotEmpty ||
    entry.savingsDestinations.isNotEmpty;

/// Charges or credits the difference after an expense amount is edited from
/// [previousAmount] to [newAmount]. An increase takes more from the source,
/// a decrease gives the difference back. Entries without a source, or
/// savings-goal entries, are left alone. A missing card is not replaced by
/// Wallet, because the user did not pay from Wallet.
Future<FundingAdjustmentResult> applyEditToFundingSource({
  required WalletCashProvider wallet,
  required WalletCardsProvider cards,
  required FinancialEntry entry,
  required double previousAmount,
  required double newAmount,
}) {
  if (isSavingsGoalEntry(entry)) {
    return Future.value(
      const FundingAdjustmentResult(FundingAdjustmentOutcome.noSource),
    );
  }
  return adjustFundingSource(
    wallet: wallet,
    cards: cards,
    sourceId: entry.fundingSourceId,
    delta: centsToMoney(moneyToCents(previousAmount) - moneyToCents(newAmount)),
    fallbackToWallet: false,
  );
}

/// Result of [EntryRefundService.refund].
enum EntryRefundOutcome {
  /// Another refund of this entry is already running.
  inFlight,

  /// The entry is missing or was already refunded, so nothing happened.
  alreadyRefunded,

  /// The user did not confirm.
  cancelled,

  /// The refund call failed. No balance was changed.
  failed,

  /// The refund succeeded and the original wallet or card was credited.
  credited,

  /// The refund succeeded and Wallet was credited because the card is gone.
  creditedWalletFallback,

  /// The refund succeeded, but the entry has no payment source.
  noSource,

  /// The refund succeeded, but the wallet or card write failed.
  creditFailed,

  /// A savings-goal entry was refunded through its own existing flow.
  savingsGoal,
}

class EntryRefundResult {
  const EntryRefundResult(this.outcome, {this.entry, this.targetCard});

  final EntryRefundOutcome outcome;

  /// The entry as it was before the refund.
  final FinancialEntry? entry;

  /// The card that was credited, when the source was a card.
  final WalletCardModel? targetCard;
}

/// Refunds an entry and returns the money to its payment source exactly once.
///
/// Keep one instance per screen. It blocks a second refund of the same entry
/// while one is running, re-reads the entry from [BudgetProvider] before and
/// after confirmation, waits for the Worker before crediting anything, and
/// reports a failed wallet or card write instead of retrying it.
class EntryRefundService {
  final Set<String> _inFlight = {};

  bool isInFlight(String entryId) => _inFlight.contains(entryId);

  Future<EntryRefundResult> refund({
    required BudgetProvider budget,
    required WalletCashProvider wallet,
    required WalletCardsProvider cards,
    required FinancialCategory category,
    required String entryId,
    required Future<bool> Function() authorize,
  }) async {
    if (!_inFlight.add(entryId)) {
      return const EntryRefundResult(EntryRefundOutcome.inFlight);
    }
    try {
      final before = _currentEntry(budget, category, entryId);
      if (before == null || before.isRefund) {
        return const EntryRefundResult(EntryRefundOutcome.alreadyRefunded);
      }
      if (!await authorize()) {
        return const EntryRefundResult(EntryRefundOutcome.cancelled);
      }

      // The entry may have changed on another device while the PIN sheet was
      // open, so check it again before refunding.
      final entry = _currentEntry(budget, category, entryId);
      if (entry == null || entry.isRefund) {
        return const EntryRefundResult(EntryRefundOutcome.alreadyRefunded);
      }

      final goal = isSavingsGoalEntry(entry);
      try {
        await budget.deleteEntry(
          category,
          entry,
          refund: true,
          awaitRemote: !goal,
        );
      } catch (_) {
        return EntryRefundResult(EntryRefundOutcome.failed, entry: entry);
      }
      if (goal) {
        return EntryRefundResult(EntryRefundOutcome.savingsGoal, entry: entry);
      }

      // Only credit when the entry is now recorded as refunded.
      final after = _currentEntry(budget, category, entryId);
      if (after == null || !after.isRefund) {
        return EntryRefundResult(EntryRefundOutcome.failed, entry: entry);
      }

      final credit = await adjustFundingSource(
        wallet: wallet,
        cards: cards,
        sourceId: entry.fundingSourceId,
        delta: entry.amount,
      );
      final outcome = switch (credit.outcome) {
        FundingAdjustmentOutcome.applied => EntryRefundOutcome.credited,
        FundingAdjustmentOutcome.appliedToWalletFallback =>
          EntryRefundOutcome.creditedWalletFallback,
        FundingAdjustmentOutcome.noSource => EntryRefundOutcome.noSource,
        FundingAdjustmentOutcome.cardMissing ||
        FundingAdjustmentOutcome.insufficient ||
        FundingAdjustmentOutcome.failed => EntryRefundOutcome.creditFailed,
      };
      return EntryRefundResult(
        outcome,
        entry: entry,
        targetCard: credit.targetCard,
      );
    } finally {
      _inFlight.remove(entryId);
    }
  }

  static FinancialEntry? _currentEntry(
    BudgetProvider budget,
    FinancialCategory category,
    String entryId,
  ) {
    for (final entry in budget.entriesFor(category)) {
      if (entry.id == entryId) return entry;
    }
    return null;
  }
}

/// User-facing message for a refund result, or null when nothing should be
/// shown. [categoryLabel] is the category title, [amountLabel] the formatted
/// amount, and [cardLabel] the credited card's display label.
String? entryRefundMessage(
  EntryRefundResult result, {
  required String categoryLabel,
  required String amountLabel,
  String? cardLabel,
}) {
  return switch (result.outcome) {
    EntryRefundOutcome.inFlight ||
    EntryRefundOutcome.alreadyRefunded ||
    EntryRefundOutcome.cancelled ||
    EntryRefundOutcome.failed => null,
    EntryRefundOutcome.credited =>
      '$amountLabel returned to $categoryLabel and ${cardLabel ?? 'Wallet'}.',
    EntryRefundOutcome.creditedWalletFallback =>
      'The original card was removed, so the refund went to Wallet.',
    EntryRefundOutcome.noSource =>
      'This older entry has no payment source, so only your budget was '
          'refunded.',
    EntryRefundOutcome.creditFailed =>
      'Refund recorded, but your wallet or card could not be updated. '
          'Please adjust it manually.',
    EntryRefundOutcome.savingsGoal => '$amountLabel returned to $categoryLabel.',
  };
}
