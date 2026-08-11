/// User-facing presentation of a Worker finance rate-limit (HTTP 429).
class RateLimitInfo {
  const RateLimitInfo({
    required this.code,
    this.statusCode = 429,
    this.retryAfterSeconds,
    this.bucket,
    this.actionLabel,
  });

  final String code;
  final int statusCode;
  final int? retryAfterSeconds;
  final String? bucket;

  /// Preferred short name for the dialog title, e.g. `Add Money`, `Bills`.
  final String? actionLabel;

  String get dialogTitle {
    final label = actionLabel?.trim();
    if (label != null && label.isNotEmpty) {
      return '$label Limit Reached';
    }
    final fromBucket = labelForBucket(bucket);
    if (fromBucket != null) {
      return '$fromBucket Limit Reached';
    }
    return 'Too Many Requests';
  }

  String get dialogMessage {
    final seconds = retryAfterSeconds;
    if (seconds != null && seconds > 0) {
      return 'You\'ve reached the request limit for this action. '
          'Please try again in $seconds seconds.';
    }
    return 'You\'ve reached the request limit for this action. '
        'Please try again shortly.';
  }

  /// Fallback label derived from the Worker `X-RateLimit-Bucket` value.
  static String? labelForBucket(String? bucket) {
    switch (bucket) {
      case 'addMoney':
        return 'Add Money';
      case 'receiveSalary':
        return 'Receive Salary';
      case 'updateAvailableBalance':
        return 'Available Balance';
      case 'updatePercentages':
        return 'Budget Percentages';
      case 'updateMonthlySalary':
        return 'Monthly Salary';
      case 'addTransaction':
      case 'updateTransaction':
      case 'deleteTransaction':
        return 'Transaction';
      case 'contributeToSavingsGoal':
      case 'updateSavingsGoalSettings':
        return 'Savings Goal';
      case 'migrateBudgetSchema':
        return 'Budget Migration';
      default:
        return null;
    }
  }
}
