import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import '../providers/budget_provider.dart';
import '../providers/planner_provider.dart';
import '../providers/thirteenth_month_provider.dart';
import 'notification_service.dart';
import 'wallet_repository.dart';

Future<void> clearUserSession(BuildContext context) async {
  context.read<AppLockProvider>().clearUser();
  await Future.wait<void>([
    context.read<BudgetProvider>().reset(),
    context.read<PlannerProvider>().clear(),
    context.read<ThirteenthMonthProvider>().clear(),
    context.read<WalletRepository>().clear(),
  ]);
  await NotificationService.instance.cancelAllReminders();
}
