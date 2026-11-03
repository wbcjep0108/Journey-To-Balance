import 'dart:convert';

enum OnboardingStatus { pending, completed, dismissed }

class OnboardingRecord {
  const OnboardingRecord({required this.status, this.step});

  final OnboardingStatus status;
  final int? step;
}

bool isOnboardingEligible({required OnboardingRecord? record}) {
  return record?.status == OnboardingStatus.pending;
}

bool shouldRunWalletMigration({
  required bool onboardingReadSucceeded,
  required OnboardingRecord? record,
}) {
  if (!onboardingReadSucceeded) return false;
  return record?.status != OnboardingStatus.pending;
}

bool isValidPercentageSplit({
  required int? bills,
  required int? savings,
  required int? personal,
}) {
  if (bills == null || savings == null || personal == null) return false;
  if (bills < 0 ||
      bills > 100 ||
      savings < 0 ||
      savings > 100 ||
      personal < 0 ||
      personal > 100) {
    return false;
  }
  return bills + savings + personal == 100;
}

class OnboardingDraft {
  OnboardingDraft({
    this.slide = 0,
    this.currencyCode = 'PHP',
    this.monthlyIncome,
    this.noRegularIncome = false,
    this.billsPercentage = 50,
    this.savingsPercentage = 20,
    this.personalPercentage = 30,
    this.walletCash,
    Map<String, double>? cardAmounts,
    Set<String>? selectedCards,
    this.dailyReminder = true,
    this.loanReminders = true,
    this.budgetAlerts = true,
    this.incomeEntered = false,
    this.currencyTouched = false,
    this.splitTouched = false,
    this.cashEntered = false,
    this.cardsTouched = false,
    this.remindersTouched = false,
    Set<String>? completedSaveSteps,
    this.salaryRequestId,
    this.percentagesRequestId,
    this.balanceRequestId,
  }) : cardAmounts = cardAmounts ?? <String, double>{},
       selectedCards = selectedCards ?? <String>{},
       completedSaveSteps = completedSaveSteps ?? <String>{};

  int slide;
  String currencyCode;
  double? monthlyIncome;
  bool noRegularIncome;
  int billsPercentage;
  int savingsPercentage;
  int personalPercentage;
  double? walletCash;
  final Map<String, double> cardAmounts;
  final Set<String> selectedCards;
  bool dailyReminder;
  bool loanReminders;
  bool budgetAlerts;
  bool incomeEntered;
  bool currencyTouched;
  bool splitTouched;
  bool cashEntered;
  bool cardsTouched;
  bool remindersTouched;
  final Set<String> completedSaveSteps;
  String? salaryRequestId;
  String? percentagesRequestId;
  String? balanceRequestId;

  Map<String, dynamic> toJson() => {
    'slide': slide,
    'currencyCode': currencyCode,
    'monthlyIncome': monthlyIncome,
    'noRegularIncome': noRegularIncome,
    'billsPercentage': billsPercentage,
    'savingsPercentage': savingsPercentage,
    'personalPercentage': personalPercentage,
    'walletCash': walletCash,
    'cardAmounts': cardAmounts,
    'selectedCards': selectedCards.toList(),
    'dailyReminder': dailyReminder,
    'loanReminders': loanReminders,
    'budgetAlerts': budgetAlerts,
    'incomeEntered': incomeEntered,
    'currencyTouched': currencyTouched,
    'splitTouched': splitTouched,
    'cashEntered': cashEntered,
    'cardsTouched': cardsTouched,
    'remindersTouched': remindersTouched,
    'completedSaveSteps': completedSaveSteps.toList(),
    'salaryRequestId': salaryRequestId,
    'percentagesRequestId': percentagesRequestId,
    'balanceRequestId': balanceRequestId,
  };

  String encode() => jsonEncode(toJson());

  factory OnboardingDraft.decode(String raw) {
    final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final rawAmounts = json['cardAmounts'];
    final amounts = <String, double>{};
    if (rawAmounts is Map) {
      for (final entry in rawAmounts.entries) {
        if (entry.value is num) {
          amounts[entry.key.toString()] = (entry.value as num).toDouble();
        }
      }
    }
    return OnboardingDraft(
      slide: (json['slide'] as num?)?.toInt() ?? 0,
      currencyCode: json['currencyCode'] as String? ?? 'PHP',
      monthlyIncome: (json['monthlyIncome'] as num?)?.toDouble(),
      noRegularIncome: json['noRegularIncome'] as bool? ?? false,
      billsPercentage: (json['billsPercentage'] as num?)?.toInt() ?? 50,
      savingsPercentage: (json['savingsPercentage'] as num?)?.toInt() ?? 20,
      personalPercentage: (json['personalPercentage'] as num?)?.toInt() ?? 30,
      walletCash: (json['walletCash'] as num?)?.toDouble(),
      cardAmounts: amounts,
      selectedCards: (json['selectedCards'] as List? ?? const [])
          .map((value) => value.toString())
          .toSet(),
      dailyReminder: json['dailyReminder'] as bool? ?? true,
      loanReminders: json['loanReminders'] as bool? ?? true,
      budgetAlerts: json['budgetAlerts'] as bool? ?? true,
      incomeEntered: json['incomeEntered'] as bool? ?? false,
      currencyTouched: json['currencyTouched'] as bool? ?? false,
      splitTouched: json['splitTouched'] as bool? ?? false,
      cashEntered: json['cashEntered'] as bool? ?? false,
      cardsTouched: json['cardsTouched'] as bool? ?? false,
      remindersTouched: json['remindersTouched'] as bool? ?? false,
      completedSaveSteps: (json['completedSaveSteps'] as List? ?? const [])
          .map((value) => value.toString())
          .toSet(),
      salaryRequestId: json['salaryRequestId'] as String?,
      percentagesRequestId: json['percentagesRequestId'] as String?,
      balanceRequestId: json['balanceRequestId'] as String?,
    );
  }
}

({int bills, int savings, int personal}) rebalancePercentages({
  required int changedIndex,
  required int value,
  required int bills,
  required int savings,
  required int personal,
}) {
  final values = [bills, savings, personal];
  final next = value.clamp(0, 100);
  final otherIndexes = [0, 1, 2]..remove(changedIndex);
  final remaining = 100 - next;
  final otherTotal = values[otherIndexes[0]] + values[otherIndexes[1]];

  int first;
  if (otherTotal == 0) {
    first = remaining ~/ 2;
  } else {
    first = (remaining * values[otherIndexes[0]] / otherTotal).round();
  }
  first = first.clamp(0, remaining);
  values[changedIndex] = next;
  values[otherIndexes[0]] = first;
  values[otherIndexes[1]] = remaining - first;
  return (bills: values[0], savings: values[1], personal: values[2]);
}
