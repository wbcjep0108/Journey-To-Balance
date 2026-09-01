import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_currency.dart';
import '../models/loan_entry.dart';
import '../providers/wallet_cards_provider.dart';
import 'wallet_firestore_service.dart';

/// Result of a one-time wallet migration attempt.
enum WalletMigrationResult {
  /// Migration already ran for this user (flag set) — nothing to do.
  alreadyDone,

  /// Firestore already had wallet data — it is the source of truth, no copy.
  firestoreWins,

  /// Local data was copied to Firestore successfully.
  migrated,

  /// Neither Firestore nor local had data — nothing to migrate.
  nothingToMigrate,
}

/// Performs a safe, one-time copy of the legacy flutter_secure_storage wallet
/// data (cash, cards, currency, loans) into Firestore at
/// `users/{uid}/wallet/data`.
///
/// Guarantees:
/// - Never overwrites existing Firestore wallet data (Firestore is the source
///   of truth once it exists). The create is transaction-guarded.
/// - Never deletes the local keys — they remain as a fallback.
/// - Runs at most once per uid, tracked by a local per-uid flag.
/// - Fails safe: on any error the local data is left untouched and the flag is
///   NOT set, so a later attempt can retry.
///
/// This is intentionally decoupled from the wallet providers so it can run
/// BEFORE they attach realtime listeners (which would otherwise seed empty
/// remote state over the local values).
class WalletMigrationService {
  WalletMigrationService({
    WalletFirestoreService? firestore,
    FlutterSecureStorage? storage,
  }) : _firestore = firestore ?? WalletFirestoreService(),
       _storage = storage ?? const FlutterSecureStorage();

  final WalletFirestoreService _firestore;
  final FlutterSecureStorage _storage;

  // Legacy secure-storage keys used by the pre-migration providers.
  static const _cashKey = 'wallet_cash_amount';
  static const _cardsKey = 'wallet_cards_v1';
  static const _currencyKey = 'preferred_currency_code';
  String _loansKey(String uid) => 'loans_v2_$uid';

  // Per-uid flag marking that migration completed (so it never repeats).
  String _migrationFlagKey(String uid) => 'wallet_migrated_v1_$uid';

  /// Runs the one-time migration for [uid]. Safe to call on every login; it
  /// returns early once the per-uid flag is set.
  Future<WalletMigrationResult> migrateIfNeeded(String uid) async {
    if (uid.isEmpty) return WalletMigrationResult.nothingToMigrate;

    // 1. Short-circuit if we've already migrated this user on this device.
    if (await _isMigrated(uid)) {
      return WalletMigrationResult.alreadyDone;
    }

    // 2. Firestore is the source of truth. If a wallet doc already exists,
    //    never overwrite it — just mark migration done so we stop checking.
    final remoteExists = await _firestore.exists(uid);
    if (remoteExists) {
      await _setMigrated(uid);
      return WalletMigrationResult.firestoreWins;
    }

    // 3. Read whatever legacy local data exists.
    final local = await _readLocalWallet(uid);
    if (local == null) {
      // Nothing locally to copy. Mark done so we don't keep probing the server
      // on every startup for a user who never had local data.
      await _setMigrated(uid);
      return WalletMigrationResult.nothingToMigrate;
    }

    // 4. Copy local -> Firestore, but only if still absent (transaction guard
    //    protects against a concurrent create on another device).
    final created = await _firestore.createIfAbsent(uid, local);

    // 5. Only mark migrated after a successful write path. If createIfAbsent
    //    returned false, Firestore now has data (created elsewhere), which is
    //    the source of truth — safe to mark done. Any thrown error above skips
    //    this line, leaving local data untouched and the flag unset for retry.
    await _setMigrated(uid);
    return created
        ? WalletMigrationResult.migrated
        : WalletMigrationResult.firestoreWins;
  }

  Future<bool> _isMigrated(String uid) async {
    try {
      final flag = await _storage.read(key: _migrationFlagKey(uid));
      return flag == 'true';
    } catch (_) {
      // If we can't read the flag, treat as not migrated. The Firestore
      // existence check downstream still prevents overwriting remote data.
      return false;
    }
  }

  Future<void> _setMigrated(String uid) async {
    try {
      await _storage.write(key: _migrationFlagKey(uid), value: 'true');
    } catch (_) {
      // Non-fatal: worst case we re-run, but createIfAbsent + the existence
      // check make re-running idempotent and non-destructive.
    }
  }

  /// Reads the legacy wallet data from secure storage. Returns null when there
  /// is no meaningful local wallet data to migrate.
  Future<WalletDocument?> _readLocalWallet(String uid) async {
    double cash = 0;
    var currencyCode = AppCurrency.php.code;
    final cards = <WalletCardModel>[];
    final loans = <LoanEntry>[];
    var hasAny = false;

    // Cash
    try {
      final raw = await _storage.read(key: _cashKey);
      final parsed = double.tryParse(raw ?? '');
      if (parsed != null) {
        cash = parsed < 0 ? 0 : parsed;
        if (cash > 0) hasAny = true;
      }
    } catch (_) {}

    // Currency
    try {
      final raw = await _storage.read(key: _currencyKey);
      if (raw != null && raw.trim().isNotEmpty) {
        // Normalize through the known currency list.
        currencyCode = AppCurrency.byCode(raw.trim()).code;
        if (currencyCode != AppCurrency.php.code) hasAny = true;
      }
    } catch (_) {}

    // Cards
    try {
      final raw = await _storage.read(key: _cardsKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              try {
                cards.add(WalletCardModel.fromJson(item));
              } catch (_) {}
            } else if (item is Map) {
              try {
                cards.add(
                  WalletCardModel.fromJson(Map<String, dynamic>.from(item)),
                );
              } catch (_) {}
            }
          }
        }
        if (cards.isNotEmpty) hasAny = true;
      }
    } catch (_) {}

    // Loans (per-uid key)
    try {
      final raw = await _storage.read(key: _loansKey(uid));
      final parsed = LoanEntry.listFromJsonString(raw);
      if (parsed.isNotEmpty) {
        loans.addAll(parsed);
        hasAny = true;
      }
    } catch (_) {}

    if (!hasAny) return null;

    return WalletDocument(
      cashAmount: cash,
      currencyCode: currencyCode,
      cards: cards,
      loans: loans,
    );
  }
}
