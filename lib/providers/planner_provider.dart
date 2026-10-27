import 'dart:async';

import 'package:flutter/material.dart';

import '../models/budget_plan.dart';
import '../models/financial_entry.dart';
import '../services/notification_service.dart';
import '../services/planner_alert_store.dart';
import '../services/planner_firestore_service.dart';
import 'budget_provider.dart';
import 'currency_provider.dart';
import 'notification_prefs_provider.dart';

class PlannerExceededEvent {
  const PlannerExceededEvent({
    required this.planId,
    required this.message,
    required this.planLabel,
    required this.budgetAmount,
    required this.spentAmount,
    required this.overAmount,
  });

  final String planId;
  final String message;
  final String planLabel;
  final String budgetAmount;
  final String spentAmount;
  final String overAmount;
}

class PlannerProvider extends ChangeNotifier {
  PlannerProvider(
    this._service,
    this._budget,
    this._currency,
    this._notificationPrefs, {
    PlannerAlertStore? alertStore,
    NotificationService? notifications,
  }) : _notifications = notifications ?? NotificationService.instance,
       _alertTracker = PlannerAlertTracker(
         alertStore ?? SecurePlannerAlertStore(),
       ) {
    _budget.addListener(_onBudgetChanged);
    _notificationPrefs.addListener(_onNotificationPrefsChanged);
  }

  final PlannerFirestoreService _service;
  final BudgetProvider _budget;
  final CurrencyProvider _currency;
  final NotificationService _notifications;
  final NotificationPrefsProvider _notificationPrefs;
  final PlannerAlertTracker _alertTracker;

  String? _uid;
  BudgetPlan? _plan;
  StreamSubscription<PlannerSnapshot>? _subscription;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _notificationPermissionGranted = true;
  bool _checkingAlert = false;
  bool _alertCheckPending = false;
  PlannerExceededEvent? _pendingExceededEvent;

  BudgetPlan? get plan => _plan;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isDeleting => _isDeleting;
  bool get notificationsEnabled => plannerNotificationsAllowed(
    settingEnabled: _notificationPrefs.plannerEnabled,
    permissionGranted: _notificationPermissionGranted,
  );
  bool get hasPlan => _plan != null;
  PlannerExceededEvent? get pendingExceededEvent => _pendingExceededEvent;

  double get spent {
    final current = _plan;
    return current == null ? 0 : _spentFor(current);
  }

  double get progress {
    final current = _plan;
    if (current == null || current.total <= 0) return 0;
    if (DateTime.now().isBefore(current.localStart)) return 0;
    return spent / current.total;
  }

  Future<void> loadForUser(String uid) async {
    if (_uid == uid && !_isLoading) return;
    await _subscription?.cancel();
    _uid = uid;
    _plan = null;
    _alertTracker.reset();
    _isLoading = true;
    notifyListeners();

    try {
      _plan = await _service.load(uid);
      await _evaluateAlert();
      _subscription = _service.watch(uid).listen((snapshot) {
        if (_uid != uid) return;
        _plan = snapshot.plan;
        notifyListeners();
        _queueAlertCheck();
      }, onError: (_) {});
      await refreshNotificationPermission();
    } finally {
      if (_uid == uid) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> savePlan({
    required PlannerPeriod period,
    required DateTime start,
    required Set<FinancialCategory> enabled,
    required Map<FinancialCategory, double> amounts,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Planner is not connected to a user.');
    if (!isPlannerDraftValid(enabled, amounts)) {
      throw ArgumentError('Every enabled category needs a positive amount.');
    }

    final normalizedStart = DateUtils.dateOnly(start);
    final selectedAmounts = <FinancialCategory, double>{
      for (final category in enabled) category: amounts[category]!,
    };
    final initial = BudgetPlan(
      id: _service.createPlanId(uid),
      period: period,
      start: normalizedStart,
      endExclusive: period.endExclusive(normalizedStart),
      amounts: selectedAmounts,
      createdAt: DateTime.now(),
      alertEligible: true,
    );
    final next = BudgetPlan(
      id: initial.id,
      period: initial.period,
      start: initial.start,
      endExclusive: initial.endExclusive,
      amounts: initial.amounts,
      createdAt: initial.createdAt,
      alertEligible: _spentFor(initial) <= initial.total,
    );

    final previous = _plan;
    _plan = next;
    _isSaving = true;
    _alertTracker.reset();
    await _evaluateAlert();
    notifyListeners();

    try {
      await _service.save(uid, next);
    } catch (_) {
      _plan = previous;
      _isSaving = false;
      notifyListeners();
      rethrow;
    }
    try {
      if (_notificationPrefs.plannerEnabled) {
        _notificationPermissionGranted = await _notifications
            .requestPermission();
      }
    } catch (_) {
      _notificationPermissionGranted = false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> deletePlan() async {
    final uid = _uid;
    final current = _plan;
    if (uid == null || current == null || _isDeleting) return;

    _isDeleting = true;
    _plan = null;
    _pendingExceededEvent = null;
    _alertTracker.reset();
    notifyListeners();

    try {
      await _service.delete(uid);
      await _alertTracker.store.clear(uid, current.id);
    } catch (_) {
      _plan = current;
      rethrow;
    } finally {
      _isDeleting = false;
      notifyListeners();
    }
  }

  void consumeExceededEvent() {
    if (_pendingExceededEvent == null) return;
    _pendingExceededEvent = null;
    notifyListeners();
  }

  Future<void> refreshNotificationPermission() async {
    try {
      _notificationPermissionGranted = await _notifications
          .areNotificationsEnabled();
    } catch (_) {
      _notificationPermissionGranted = false;
    }
    notifyListeners();
  }

  void clear() {
    _subscription?.cancel();
    _subscription = null;
    _uid = null;
    _plan = null;
    _pendingExceededEvent = null;
    _alertTracker.reset();
    _isLoading = false;
    _isSaving = false;
    _isDeleting = false;
    notifyListeners();
  }

  double _spentFor(BudgetPlan plan) {
    return plannerSpent(plan, {
      for (final category in FinancialCategory.values)
        category: _budget.entriesFor(category),
    });
  }

  void _onBudgetChanged() {
    if (_uid == null || _plan == null) return;
    notifyListeners();
    _queueAlertCheck();
  }

  void _onNotificationPrefsChanged() {
    notifyListeners();
  }

  void _queueAlertCheck() {
    if (_checkingAlert) {
      _alertCheckPending = true;
      return;
    }
    unawaited(_evaluateAlert());
  }

  Future<void> _evaluateAlert() async {
    final uid = _uid;
    final current = _plan;
    if (uid == null || current == null || _checkingAlert) return;
    _checkingAlert = true;
    try {
      final currentSpent = _spentFor(current);
      final shouldAlert = await _alertTracker.evaluate(
        uid: uid,
        plan: current,
        spent: currentSpent,
      );
      if (!shouldAlert || _plan?.id != current.id) return;
      final over = currentSpent - current.total;
      final message =
          'You went over your budget by ${_currency.formatAmount(over)}. '
          'Budget: ${_currency.formatAmount(current.total)}. '
          'Spent: ${_currency.formatAmount(currentSpent)}.';
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
        _pendingExceededEvent = PlannerExceededEvent(
          planId: current.id,
          message: message,
          planLabel: plannerAlertPlanLabel(current),
          budgetAmount: _currency.formatAmount(current.total),
          spentAmount: _currency.formatAmount(currentSpent),
          overAmount: _currency.formatAmount(over),
        );
        notifyListeners();
      } else {
        if (notificationsEnabled) {
          await _notifications.showPlannerExceeded(
            planId: current.id,
            message: message,
          );
        }
      }
    } finally {
      _checkingAlert = false;
      if (_alertCheckPending) {
        _alertCheckPending = false;
        _queueAlertCheck();
      }
    }
  }

  @override
  void dispose() {
    _budget.removeListener(_onBudgetChanged);
    _notificationPrefs.removeListener(_onNotificationPrefsChanged);
    _subscription?.cancel();
    super.dispose();
  }
}
