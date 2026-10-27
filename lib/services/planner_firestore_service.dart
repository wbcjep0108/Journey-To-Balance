import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/budget_plan.dart';

class PlannerSnapshot {
  const PlannerSnapshot({required this.plan, required this.hasPendingWrites});

  final BudgetPlan? plan;
  final bool hasPendingWrites;
}

class PlannerFirestoreService {
  PlannerFirestoreService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _firestore.collection('users').doc(uid);

  BudgetPlan? _parse(Map<String, dynamic>? data) {
    final planner = data?['planner'];
    if (planner is! Map) return null;
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

  Future<void> save(String uid, BudgetPlan plan) {
    return _user(
      uid,
    ).set({'planner': plan.toFirestore()}, SetOptions(merge: true));
  }

  Future<void> delete(String uid) {
    return _user(uid).update({'planner': FieldValue.delete()});
  }
}
