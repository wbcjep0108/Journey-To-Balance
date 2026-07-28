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

  Future<Map<String, double>?> loadBudget(
    String uid, {
    bool serverOnly = false,
  }) async {
    final snapshot = serverOnly
        ? await _user(uid).get(const GetOptions(source: Source.server))
        : await _user(uid).get();
    final budget = snapshot.data()?['budget'];
    if (budget is! Map) return null;

    return {
      'income': (budget['income'] as num?)?.toDouble() ?? 0,
      'billsPercentage': (budget['billsPercentage'] as num?)?.toDouble() ?? 50,
      'savingsPercentage':
          (budget['savingsPercentage'] as num?)?.toDouble() ?? 20,
      'personalPercentage':
          (budget['personalPercentage'] as num?)?.toDouble() ?? 30,
    };
  }

  Stream<Map<String, double>?> watchBudget(String uid) {
    return _user(uid).snapshots().map((snapshot) {
      final budget = snapshot.data()?['budget'];
      if (budget is! Map) return null;

      return {
        'income': (budget['income'] as num?)?.toDouble() ?? 0,
        'billsPercentage':
            (budget['billsPercentage'] as num?)?.toDouble() ?? 50,
        'savingsPercentage':
            (budget['savingsPercentage'] as num?)?.toDouble() ?? 20,
        'personalPercentage':
            (budget['personalPercentage'] as num?)?.toDouble() ?? 30,
      };
    });
  }

  Future<void> saveBudget(
    String uid, {
    required double income,
    required double billsPercentage,
    required double savingsPercentage,
    required double personalPercentage,
  }) {
    return _user(uid).set({
      'budget': {
        'income': income,
        'billsPercentage': billsPercentage,
        'savingsPercentage': savingsPercentage,
        'personalPercentage': personalPercentage,
        'updatedAt': FieldValue.serverTimestamp(),
      },
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

  Stream<List<FinancialEntry>> watchEntries(
    String uid,
    FinancialCategory category,
  ) {
    return _entries(uid, category)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(FinancialEntry.fromFirestore).toList(),
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
}
