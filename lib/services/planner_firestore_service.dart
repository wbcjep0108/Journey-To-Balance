import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/budget_plan.dart';

class PlannerSnapshot {
  const PlannerSnapshot({required this.plan, required this.hasPendingWrites});

  final BudgetPlan? plan;
  final bool hasPendingWrites;
}

/// Every Budget Planner field stored in users/{uid}.planner.
const plannerPlanFields = [
  'id',
  'period',
  'startAt',
  'endAt',
  'endDate',
  'billsEnabled',
  'billsAmount',
  'savingsEnabled',
  'savingsAmount',
  'personalEnabled',
  'personalAmount',
  'total',
  'createdAt',
  'alertEligible',
];

/// The update that deletes the saved plan. When the planner map also holds a
/// legacy 13th Month Pay copy (planner.thirteenthMonth, from older app
/// versions), only the plan fields are removed so that calculator data is
/// kept exactly as stored. Otherwise the whole planner field is removed.
@visibleForTesting
Map<String, Object?> plannerDeleteUpdate(Object? planner) {
  if (planner is Map && planner.containsKey('thirteenthMonth')) {
    return {
      for (final field in plannerPlanFields)
        'planner.$field': FieldValue.delete(),
    };
  }
  return {'planner': FieldValue.delete()};
}

/// Budget Planner storage: the users/{uid}.planner map. It reads and writes
/// only plan fields. 13th Month Pay inputs are stored separately by
/// ThirteenthMonthFirestoreService.
class PlannerFirestoreService {
  PlannerFirestoreService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _firestore.collection('users').doc(uid);

  BudgetPlan? _parse(Map<String, dynamic>? data) {
    final planner = data?['planner'];
    if (planner is! Map) return null;
    if (planner['id'] is! String) return null;
    try {
      return BudgetPlan.fromFirestore(Map<String, dynamic>.from(planner));
    } catch (_) {
      return null;
    }
  }

  Future<BudgetPlan?> load(String uid) async {
    final snapshot = await _user(uid).get();
    return _parse(snapshot.data());
  }

  Stream<PlannerSnapshot> watch(String uid) {
    return _user(uid).snapshots().map(
      (snapshot) => PlannerSnapshot(
        plan: _parse(snapshot.data()),
        hasPendingWrites: snapshot.metadata.hasPendingWrites,
      ),
    );
  }

  String createPlanId(String uid) => _user(uid).collection('_ids').doc().id;

  /// Merges the plan fields into users/{uid}.planner. Every plan field is
  /// written, and nothing else in the document is touched.
  Future<void> save(String uid, BudgetPlan plan) {
    return _user(
      uid,
    ).set({'planner': plan.toFirestore()}, SetOptions(merge: true));
  }

  Future<void> delete(String uid) {
    final reference = _user(uid);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      transaction.update(
        reference,
        plannerDeleteUpdate(snapshot.data()?['planner']),
      );
    });
  }
}
