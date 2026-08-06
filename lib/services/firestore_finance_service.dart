import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/financial_entry.dart';

class FirestoreFinanceService {
  FirestoreFinanceService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _user(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  CollectionReference<Map<String, dynamic>> _entries(
    String uid,
    FinancialCategory category,
  ) {
    return _user(uid).collection(category.collection);
  }

  Map<String, double> _parseBudget(Map budget) {
    return {
      'availableBalance':
          (budget['availableBalance'] as num?)?.toDouble() ??
          (budget['income'] as num?)?.toDouble() ??
          0,
      'monthlySalary':
          (budget['monthlySalary'] as num?)?.toDouble() ??
          (budget['availableBalance'] as num?)?.toDouble() ??
          (budget['income'] as num?)?.toDouble() ??
          0,
      'billsPercentage': (budget['billsPercentage'] as num?)?.toDouble() ?? 50,
      'savingsPercentage':
          (budget['savingsPercentage'] as num?)?.toDouble() ?? 20,
      'personalPercentage':
          (budget['personalPercentage'] as num?)?.toDouble() ?? 30,
      if (budget['billsRemaining'] != null)
        'billsRemaining': (budget['billsRemaining'] as num).toDouble(),
      if (budget['savingsRemaining'] != null)
        'savingsRemaining': (budget['savingsRemaining'] as num).toDouble(),
      if (budget['personalRemaining'] != null)
        'personalRemaining': (budget['personalRemaining'] as num).toDouble(),
      'forfeitedBills': (budget['forfeitedBills'] as num?)?.toDouble() ?? 0,
      'forfeitedSavings': (budget['forfeitedSavings'] as num?)?.toDouble() ?? 0,
      'forfeitedPersonal':
          (budget['forfeitedPersonal'] as num?)?.toDouble() ?? 0,
      'savingsGoalTarget':
          (budget['savingsGoalTarget'] as num?)?.toDouble() ?? 10000,
      'savingsGoalCurrent':
          (budget['savingsGoalCurrent'] as num?)?.toDouble() ?? 0,
      'savingsGoalTargetDateMs':
          (budget['savingsGoalTargetDateMs'] as num?)?.toDouble() ??
          DateTime(2028, 12, 31).millisecondsSinceEpoch.toDouble(),
      'schemaVersion': (budget['schemaVersion'] as num?)?.toDouble() ?? 1,
    };
  }

  Map<String, dynamic> _budgetPayload({
    required double availableBalance,
    required double monthlySalary,
    required double billsPercentage,
    required double savingsPercentage,
    required double personalPercentage,
    required double billsRemaining,
    required double savingsRemaining,
    required double personalRemaining,
    double forfeitedBills = 0,
    double forfeitedSavings = 0,
    double forfeitedPersonal = 0,
    double savingsGoalTarget = 10000,
    double savingsGoalCurrent = 0,
    double? savingsGoalTargetDateMs,
    double schemaVersion = 3,
  }) {
    return {
      // Keep `income` for backward compatibility with older app builds.
      'income': availableBalance,
      'availableBalance': availableBalance,
      'monthlySalary': monthlySalary,
      'billsPercentage': billsPercentage,
      'savingsPercentage': savingsPercentage,
      'personalPercentage': personalPercentage,
      'billsRemaining': billsRemaining,
      'savingsRemaining': savingsRemaining,
      'personalRemaining': personalRemaining,
      'forfeitedBills': forfeitedBills,
      'forfeitedSavings': forfeitedSavings,
      'forfeitedPersonal': forfeitedPersonal,
      'savingsGoalTarget': savingsGoalTarget,
      'savingsGoalCurrent': savingsGoalCurrent,
      'savingsGoalTargetDateMs':
          savingsGoalTargetDateMs ??
          DateTime(2028, 12, 31).millisecondsSinceEpoch.toDouble(),
      'schemaVersion': schemaVersion,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<Map<String, double>?> loadBudget(
    String uid, {
    bool serverOnly = false,
  }) async {
    final snapshot = serverOnly
        ? await _user(uid).get(const GetOptions(source: Source.server))
        : await _user(uid).get();
    final budget = snapshot.data()?['budget'];
    if (budget is! Map) return null;
    return _parseBudget(budget);
  }

  Stream<BudgetSnapshot> watchBudget(String uid) {
    return _user(uid).snapshots().map((snapshot) {
      final budget = snapshot.data()?['budget'];
      if (budget is! Map) {
        return BudgetSnapshot(
          budget: null,
          hasPendingWrites: snapshot.metadata.hasPendingWrites,
          isFromCache: snapshot.metadata.isFromCache,
        );
      }

      return BudgetSnapshot(
        hasPendingWrites: snapshot.metadata.hasPendingWrites,
        isFromCache: snapshot.metadata.isFromCache,
        budget: _parseBudget(budget),
      );
    });
  }

  Future<void> saveBudget(
    String uid, {
    required double availableBalance,
    required double monthlySalary,
    required double billsPercentage,
    required double savingsPercentage,
    required double personalPercentage,
    required double billsRemaining,
    required double savingsRemaining,
    required double personalRemaining,
    double forfeitedBills = 0,
    double forfeitedSavings = 0,
    double forfeitedPersonal = 0,
    double savingsGoalTarget = 10000,
    double savingsGoalCurrent = 0,
    double? savingsGoalTargetDateMs,
    double schemaVersion = 3,
  }) {
    return _user(uid).set({
      'budget': _budgetPayload(
        availableBalance: availableBalance,
        monthlySalary: monthlySalary,
        billsPercentage: billsPercentage,
        savingsPercentage: savingsPercentage,
        personalPercentage: personalPercentage,
        billsRemaining: billsRemaining,
        savingsRemaining: savingsRemaining,
        personalRemaining: personalRemaining,
        forfeitedBills: forfeitedBills,
        forfeitedSavings: forfeitedSavings,
        forfeitedPersonal: forfeitedPersonal,
        savingsGoalTarget: savingsGoalTarget,
        savingsGoalCurrent: savingsGoalCurrent,
        savingsGoalTargetDateMs: savingsGoalTargetDateMs,
        schemaVersion: schemaVersion,
      ),
    }, SetOptions(merge: true));
  }

  Future<List<FinancialEntry>> loadEntries(
    String uid,
    FinancialCategory category, {
    bool serverOnly = false,
  }) async {
    final query = _entries(
      uid,
      category,
    ).orderBy('createdAt', descending: true);
    final snapshot = serverOnly
        ? await query.get(const GetOptions(source: Source.server))
        : await query.get();
    return snapshot.docs.map(FinancialEntry.fromFirestore).toList();
  }

  Stream<EntriesSnapshot> watchEntries(
    String uid,
    FinancialCategory category,
  ) {
    return _entries(uid, category)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => EntriesSnapshot(
            entries: snapshot.docs.map(FinancialEntry.fromFirestore).toList(),
            hasPendingWrites: snapshot.metadata.hasPendingWrites,
            isFromCache: snapshot.metadata.isFromCache,
          ),
        );
  }

  String createEntryId(String uid, FinancialCategory category) {
    return _entries(uid, category).doc().id;
  }

  Future<void> saveEntry(
    String uid,
    FinancialCategory category,
    FinancialEntry entry,
  ) {
    return _entries(uid, category).doc(entry.id).set(entry.toFirestore());
  }

  Future<void> deleteEntry(
    String uid,
    FinancialCategory category,
    String entryId,
  ) {
    return _entries(uid, category).doc(entryId).delete();
  }

  /// Atomically save a category entry and budget fields together.
  Future<void> saveEntryAndBudget(
    String uid, {
    required FinancialCategory category,
    required FinancialEntry entry,
    required double availableBalance,
    required double monthlySalary,
    required double billsPercentage,
    required double savingsPercentage,
    required double personalPercentage,
    required double billsRemaining,
    required double savingsRemaining,
    required double personalRemaining,
    double forfeitedBills = 0,
    double forfeitedSavings = 0,
    double forfeitedPersonal = 0,
    double savingsGoalTarget = 10000,
    double savingsGoalCurrent = 0,
    double? savingsGoalTargetDateMs,
    double schemaVersion = 3,
  }) {
    final batch = _firestore.batch();
    batch.set(_entries(uid, category).doc(entry.id), entry.toFirestore());
    batch.set(_user(uid), {
      'budget': _budgetPayload(
        availableBalance: availableBalance,
        monthlySalary: monthlySalary,
        billsPercentage: billsPercentage,
        savingsPercentage: savingsPercentage,
        personalPercentage: personalPercentage,
        billsRemaining: billsRemaining,
        savingsRemaining: savingsRemaining,
        personalRemaining: personalRemaining,
        forfeitedBills: forfeitedBills,
        forfeitedSavings: forfeitedSavings,
        forfeitedPersonal: forfeitedPersonal,
        savingsGoalTarget: savingsGoalTarget,
        savingsGoalCurrent: savingsGoalCurrent,
        savingsGoalTargetDateMs: savingsGoalTargetDateMs,
        schemaVersion: schemaVersion,
      ),
    }, SetOptions(merge: true));
    return batch.commit();
  }

  /// Atomically delete a category entry and update budget fields together.
  Future<void> deleteEntryAndBudget(
    String uid, {
    required FinancialCategory category,
    required String entryId,
    required double availableBalance,
    required double monthlySalary,
    required double billsPercentage,
    required double savingsPercentage,
    required double personalPercentage,
    required double billsRemaining,
    required double savingsRemaining,
    required double personalRemaining,
    double forfeitedBills = 0,
    double forfeitedSavings = 0,
    double forfeitedPersonal = 0,
    double savingsGoalTarget = 10000,
    double savingsGoalCurrent = 0,
    double? savingsGoalTargetDateMs,
    double schemaVersion = 3,
  }) {
    final batch = _firestore.batch();
    batch.delete(_entries(uid, category).doc(entryId));
    batch.set(_user(uid), {
      'budget': _budgetPayload(
        availableBalance: availableBalance,
        monthlySalary: monthlySalary,
        billsPercentage: billsPercentage,
        savingsPercentage: savingsPercentage,
        personalPercentage: personalPercentage,
        billsRemaining: billsRemaining,
        savingsRemaining: savingsRemaining,
        personalRemaining: personalRemaining,
        forfeitedBills: forfeitedBills,
        forfeitedSavings: forfeitedSavings,
        forfeitedPersonal: forfeitedPersonal,
        savingsGoalTarget: savingsGoalTarget,
        savingsGoalCurrent: savingsGoalCurrent,
        savingsGoalTargetDateMs: savingsGoalTargetDateMs,
        schemaVersion: schemaVersion,
      ),
    }, SetOptions(merge: true));
    return batch.commit();
  }
}

class BudgetSnapshot {
  const BudgetSnapshot({
    required this.budget,
    required this.hasPendingWrites,
    required this.isFromCache,
  });

  final Map<String, double>? budget;
  final bool hasPendingWrites;
  final bool isFromCache;
}

class EntriesSnapshot {
  const EntriesSnapshot({
    required this.entries,
    required this.hasPendingWrites,
    required this.isFromCache,
  });

  final List<FinancialEntry> entries;
  final bool hasPendingWrites;
  final bool isFromCache;
}
