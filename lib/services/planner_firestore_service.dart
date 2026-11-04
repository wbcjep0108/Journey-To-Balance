import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/budget_plan.dart';

class PlannerSnapshot {
  const PlannerSnapshot({required this.plan, required this.hasPendingWrites});

  final BudgetPlan? plan;
  final bool hasPendingWrites;
}

class ThirteenthMonthInputs {
  const ThirteenthMonthInputs({
    required this.monthlySalaries,
    required this.otherBenefits,
  });

  final List<double> monthlySalaries;
  final double otherBenefits;
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

  Future<ThirteenthMonthInputs?> loadThirteenthMonthInputs(String uid) async {
    final snapshot = await _user(uid).get();
    final planner = snapshot.data()?['planner'];
    if (planner is! Map) return null;
    final saved = planner['thirteenthMonth'];
    if (saved is! Map) return null;
    final rawSalaries = saved['monthlyBasicSalaries'];
    if (rawSalaries is! List || rawSalaries.length != 12) return null;
    return ThirteenthMonthInputs(
      monthlySalaries: rawSalaries
          .map((value) => (value as num?)?.toDouble() ?? 0)
          .toList(growable: false),
      otherBenefits: (saved['otherBenefits'] as num?)?.toDouble() ?? 0,
    );
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

  Future<void> saveThirteenthMonthInputs(
    String uid, {
    required List<double> monthlySalaries,
    required double otherBenefits,
  }) {
    if (monthlySalaries.length != 12) {
      throw ArgumentError('Exactly 12 monthly salaries are required.');
    }
    return _user(uid).set({
      'planner': {
        'thirteenthMonth': {
          'year': DateTime.now().year,
          'monthlyBasicSalaries': monthlySalaries,
          'otherBenefits': otherBenefits,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      },
    }, SetOptions(merge: true));
  }

  Future<void> delete(String uid) {
    final reference = _user(uid);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final planner = snapshot.data()?['planner'];
      final thirteenthMonth = planner is Map
          ? planner['thirteenthMonth']
          : null;
      if (thirteenthMonth is Map) {
        transaction.update(reference, {
          'planner': {'thirteenthMonth': thirteenthMonth},
        });
      } else {
        transaction.update(reference, {'planner': FieldValue.delete()});
      }
    });
  }
}
