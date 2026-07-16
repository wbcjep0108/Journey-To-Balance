import 'package:flutter/material.dart';

class BudgetProvider extends ChangeNotifier {
  double income = 0;

  double billsPercentage = 50;
  double savingsPercentage = 20;
  double personalPercentage = 30;

  double billsAmount = 0;
  double savingsAmount = 0;
  double personalAmount = 0;
  double remainingAmount = 0;

  void updateBudget({
    required double income,
    required double billsPercentage,
    required double savingsPercentage,
    required double personalPercentage,
  }) {
    this.income = income;
    this.billsPercentage = billsPercentage;
    this.savingsPercentage = savingsPercentage;
    this.personalPercentage = personalPercentage;

    final total =
        billsPercentage + savingsPercentage + personalPercentage;

    if (total != 100) return;

    billsAmount = income * (billsPercentage / 100);
    savingsAmount = income * (savingsPercentage / 100);
    personalAmount = income * (personalPercentage / 100);

    remainingAmount =
        income - billsAmount - savingsAmount - personalAmount;

    notifyListeners();
  }
}