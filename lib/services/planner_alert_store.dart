import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/budget_plan.dart';

abstract interface class PlannerAlertStore {
  Future<bool> wasShown(String uid, String planId);

  Future<void> markShown(String uid, String planId);

  Future<void> clear(String uid, String planId);
}

class SecurePlannerAlertStore implements PlannerAlertStore {
  SecurePlannerAlertStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String uid, String planId) => 'planner_alert_${uid}_$planId';

  @override
  Future<bool> wasShown(String uid, String planId) async {
    return await _storage.read(key: _key(uid, planId)) == '1';
  }

  @override
  Future<void> markShown(String uid, String planId) {
    return _storage.write(key: _key(uid, planId), value: '1');
  }

  @override
  Future<void> clear(String uid, String planId) {
    return _storage.delete(key: _key(uid, planId));
  }
}

class PlannerAlertTracker {
  PlannerAlertTracker(this.store);

  final PlannerAlertStore store;

  String? _planId;
  double? _previousSpent;

  Future<bool> evaluate({
    required String uid,
    required BudgetPlan plan,
    required double spent,
  }) async {
    if (_planId != plan.id) {
      _planId = plan.id;
      _previousSpent = spent;
      return false;
    }

    final previous = _previousSpent ?? spent;
    _previousSpent = spent;
    final crossed = previous <= plan.total && spent > plan.total;
    if (!plan.alertEligible || !crossed) return false;
    if (await store.wasShown(uid, plan.id)) return false;
    await store.markShown(uid, plan.id);
    return true;
  }

  void reset() {
    _planId = null;
    _previousSpent = null;
  }
}
