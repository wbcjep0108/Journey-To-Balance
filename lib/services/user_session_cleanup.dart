import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import '../providers/budget_provider.dart';
import '../providers/currency_provider.dart';
import '../providers/loan_provider.dart';
import '../providers/planner_provider.dart';
import '../providers/wallet_cards_provider.dart';
import '../providers/wallet_cash_provider.dart';
import 'notification_service.dart';

Future<void> clearUserSession(BuildContext context) async {
  context.read<AppLockProvider>().clearUser();
  await Future.wait<void>([
    context.read<BudgetProvider>().reset(),
    context.read<LoanProvider>().clear(),
    context.read<CurrencyProvider>().clear(),
    context.read<PlannerProvider>().clear(),
    context.read<WalletCashProvider>().clear(),
    context.read<WalletCardsProvider>().clear(),
  ]);
  await NotificationService.instance.cancelAllReminders();
}
