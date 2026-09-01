import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/loan_entry.dart';
import '../providers/wallet_cards_provider.dart';

/// Immutable snapshot of the synced wallet document at `users/{uid}/wallet`.
///
/// Holds cash-on-hand, preferred currency code, bank cards, and loans — the
/// financial wallet data that now syncs across a user's devices. The security
/// PIN and biometric settings are intentionally NOT part of this document and
/// remain device-local via SecurityService.
class WalletDocument {
  const WalletDocument({
    required this.cashAmount,
    required this.currencyCode,
    required this.cards,
    required this.loans,
  });

  final double cashAmount;
  final String currencyCode;
  final List<WalletCardModel> cards;
  final List<LoanEntry> loans;

  /// Empty wallet used before the first sync / for brand-new users.
  static const empty = WalletDocument(
    cashAmount: 0,
    currencyCode: 'PHP',
    cards: <WalletCardModel>[],
    loans: <LoanEntry>[],
  );
}

/// Realtime snapshot wrapper mirroring the pattern used by
/// [BudgetSnapshot]/[EntriesSnapshot] in FirestoreFinanceService.
class WalletSnapshot {
  const WalletSnapshot({
    required this.wallet,
    required this.hasPendingWrites,
    required this.isFromCache,
    required this.exists,
  });

  final WalletDocument wallet;
  final bool hasPendingWrites;
  final bool isFromCache;

  /// Whether the wallet document exists yet in Firestore.
  final bool exists;
}

/// Reads, writes, and streams the single per-user wallet document.
///
/// Document path: `users/{uid}/wallet/data`
/// Fields: cashAmount, currency, cards[], loans[], updatedAt (serverTimestamp).
///
/// Unlike the budget (which mutates via a Cloudflare Worker), wallet data is
/// self-owned state written directly by the client, guarded by Firestore rules
/// that allow the owner to read/write only their own wallet document.
class WalletFirestoreService {
  WalletFirestoreService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _wallet(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('wallet')
        .doc('data');
  }

  WalletDocument _parse(Map<String, dynamic>? data) {
    if (data == null) return WalletDocument.empty;

    final cash = (data['cashAmount'] as num?)?.toDouble() ?? 0;
    final rawCurrency = (data['currency'] as String?)?.trim();
    final currency = (rawCurrency == null || rawCurrency.isEmpty)
        ? 'PHP'
        : rawCurrency;

    final cards = <WalletCardModel>[];
    final rawCards = data['cards'];
    if (rawCards is List) {
      for (final item in rawCards) {
        if (item is Map) {
          try {
            cards.add(WalletCardModel.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {
            // Skip malformed card entries rather than failing the whole load.
          }
        }
      }
    }

    final loans = <LoanEntry>[];
    final rawLoans = data['loans'];
    if (rawLoans is List) {
      for (final item in rawLoans) {
        if (item is Map) {
          try {
            final loan = LoanEntry.fromJson(Map<String, dynamic>.from(item));
            if (loan.id.isNotEmpty) loans.add(loan);
          } catch (_) {
            // Skip malformed loan entries.
          }
        }
      }
    }

    return WalletDocument(
      cashAmount: cash < 0 ? 0 : cash,
      currencyCode: currency,
      cards: cards,
      loans: loans,
    );
  }

  /// Whether the wallet document already exists in Firestore.
  ///
  /// Used by the one-time local→Firestore migration to treat Firestore as the
  /// source of truth. Reads from the server so a stale empty cache can't cause
  /// local data to overwrite existing remote data.
  Future<bool> exists(String uid, {bool serverOnly = true}) async {
    final snapshot = serverOnly
        ? await _wallet(uid).get(const GetOptions(source: Source.server))
        : await _wallet(uid).get();
    return snapshot.exists;
  }

  /// Creates the wallet document with the full set of fields, but ONLY if it
  /// does not already exist. Uses a transaction so a concurrent create on
  /// another device cannot be clobbered. Returns true when this call created
  /// the document, false when it already existed (left untouched).
  Future<bool> createIfAbsent(String uid, WalletDocument wallet) async {
    final ref = _wallet(uid);
    return _firestore.runTransaction<bool>((tx) async {
      final snapshot = await tx.get(ref);
      if (snapshot.exists) return false;
      tx.set(ref, {
        'cashAmount': wallet.cashAmount < 0 ? 0.0 : wallet.cashAmount,
        'currency': wallet.currencyCode,
        'cards': wallet.cards.map((c) => c.toJson()).toList(),
        'loans': wallet.loans.map((l) => l.toJson()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  /// One-shot load of the wallet document. Returns [WalletDocument.empty] when
  /// the user has no wallet document yet.
  Future<WalletDocument> load(String uid, {bool serverOnly = false}) async {
    final snapshot = serverOnly
        ? await _wallet(uid).get(const GetOptions(source: Source.server))
        : await _wallet(uid).get();
    return _parse(snapshot.data());
  }

  /// Realtime stream of the wallet document for cross-device sync.
  Stream<WalletSnapshot> watch(String uid) {
    return _wallet(uid).snapshots().map((snapshot) {
      return WalletSnapshot(
        wallet: _parse(snapshot.data()),
        hasPendingWrites: snapshot.metadata.hasPendingWrites,
        isFromCache: snapshot.metadata.isFromCache,
        exists: snapshot.exists,
      );
    });
  }

  Map<String, Object?> _cardsPayload(List<WalletCardModel> cards) {
    return {
      'cards': cards.map((c) => c.toJson()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, Object?> _loansPayload(List<LoanEntry> loans) {
    return {
      'loans': loans.map((l) => l.toJson()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Merge-write only the cash amount. Never overwrites cards/loans/currency.
  Future<void> saveCashAmount(String uid, double cashAmount) {
    final next = cashAmount < 0 ? 0.0 : cashAmount;
    return _wallet(uid).set({
      'cashAmount': next,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Merge-write only the preferred currency code.
  Future<void> saveCurrency(String uid, String currencyCode) {
    return _wallet(uid).set({
      'currency': currencyCode,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Merge-write the full cards list (add/edit/delete happen in the provider).
  Future<void> saveCards(String uid, List<WalletCardModel> cards) {
    return _wallet(uid).set(_cardsPayload(cards), SetOptions(merge: true));
  }

  /// Merge-write the full loans list (add/edit/delete happen in the provider).
  Future<void> saveLoans(String uid, List<LoanEntry> loans) {
    return _wallet(uid).set(_loansPayload(loans), SetOptions(merge: true));
  }
}
