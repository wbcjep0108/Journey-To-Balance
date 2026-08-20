import 'package:flutter/material.dart';

import '../screens/home/daily_spending_page.dart';
import '../screens/loans/total_loan_page.dart';
import 'notification_service.dart';

/// Routes notification taps after the navigator is ready.
class NotificationRouter {
  static final navigatorKey = GlobalKey<NavigatorState>();
  static String? pendingPayload;
  static void Function(int index)? selectTab;

  static void handle(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final nav = navigatorKey.currentState;
    if (nav == null) {
      pendingPayload = payload;
      return;
    }
    _open(nav, payload);
  }

  static void consumePending() {
    final payload = pendingPayload;
    if (payload == null) return;
    pendingPayload = null;
    handle(payload);
  }

  static void _open(NavigatorState nav, String payload) {
    if (payload == NotificationPayloads.dailyMorning) {
      selectTab?.call(0);
      return;
    }
    if (payload == NotificationPayloads.dailyEvening) {
      selectTab?.call(0);
      final now = DateTime.now();
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => DailySpendingPage(
            day: DateTime(now.year, now.month, now.day),
          ),
        ),
      );
      return;
    }
    if (payload == NotificationPayloads.loan) {
      nav.push(
        MaterialPageRoute<void>(builder: (_) => const TotalLoanPage()),
      );
    }
  }
}
