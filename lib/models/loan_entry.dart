import 'dart:convert';

enum LoanStatus { pending, late, paid }

class LoanEntry {
  const LoanEntry({
    required this.id,
    required this.name,
    required this.amount,
    required this.monthlyDueDate,
    required this.finalPaymentDate,
    List<int>? paidInstallmentDueDateMs,
  }) : _paidInstallmentDueDateMs = paidInstallmentDueDateMs;

  final String id;
  final String name;

  /// Monthly installment / payment amount.
  final double amount;
  final DateTime monthlyDueDate;
  final DateTime finalPaymentDate;

  /// May be null after hot reload of older in-memory instances.
  final List<int>? _paidInstallmentDueDateMs;

  /// Due-date timestamps (day-precision) marked as paid.
  List<int> get paidInstallmentDueDateMs =>
      _paidInstallmentDueDateMs ?? const <int>[];

  List<DateTime> get installmentDates {
    final start = DateTime(
      monthlyDueDate.year,
      monthlyDueDate.month,
      monthlyDueDate.day,
    );
    final end = DateTime(
      finalPaymentDate.year,
      finalPaymentDate.month,
      finalPaymentDate.day,
    );
    if (end.isBefore(start)) return [start];

    final dates = <DateTime>[];
    var year = start.year;
    var month = start.month;
    final day = start.day;

    for (var i = 0; i < 600; i++) {
      final due = DateTime(year, month, day);
      if (due.isAfter(end)) break;
      dates.add(due);
      if (due.year == end.year && due.month == end.month) break;
      month += 1;
      if (month > 12) {
        month = 1;
        year += 1;
      }
    }

    if (dates.isEmpty || dates.last.isBefore(end)) {
      final alreadyHasEndMonth = dates.any(
        (d) => d.year == end.year && d.month == end.month,
      );
      if (!alreadyHasEndMonth) {
        dates.add(DateTime(end.year, end.month, day));
      }
    }

    return dates;
  }

  int get unpaidInstallmentCount {
    var count = 0;
    for (final due in installmentDates) {
      if (!isInstallmentPaid(due)) count++;
    }
    return count;
  }

  double get remainingBalance => unpaidInstallmentCount * amount;

  bool get isFullyPaid => unpaidInstallmentCount == 0;

  bool isInstallmentPaid(DateTime due) {
    final key = dayKey(due);
    return paidInstallmentDueDateMs.contains(key);
  }

  LoanStatus installmentStatus(DateTime due) {
    if (isInstallmentPaid(due)) return LoanStatus.paid;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(due.year, due.month, due.day);
    if (day.isBefore(today)) return LoanStatus.late;
    return LoanStatus.pending;
  }

  /// First unpaid installment chronologically (actionable check row).
  DateTime? get nextActionableDue {
    for (final due in installmentDates) {
      if (!isInstallmentPaid(due)) return due;
    }
    return null;
  }

  LoanStatus get status {
    if (isFullyPaid) return LoanStatus.paid;
    final next = nextActionableDue;
    if (next == null) return LoanStatus.paid;
    return installmentStatus(next);
  }

  String get statusLabel => switch (status) {
    LoanStatus.pending => 'PENDING',
    LoanStatus.late => 'LATE',
    LoanStatus.paid => 'PAID',
  };

  LoanEntry copyWith({
    String? name,
    double? amount,
    DateTime? monthlyDueDate,
    DateTime? finalPaymentDate,
    List<int>? paidInstallmentDueDateMs,
  }) {
    return LoanEntry(
      id: id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      monthlyDueDate: monthlyDueDate ?? this.monthlyDueDate,
      finalPaymentDate: finalPaymentDate ?? this.finalPaymentDate,
      paidInstallmentDueDateMs:
          paidInstallmentDueDateMs ?? this.paidInstallmentDueDateMs,
    );
  }

  LoanEntry withInstallmentPaid(DateTime due, {required bool paid}) {
    final key = dayKey(due);
    final next = [...paidInstallmentDueDateMs];
    if (paid) {
      if (!next.contains(key)) next.add(key);
    } else {
      next.remove(key);
    }
    next.sort();
    return copyWith(paidInstallmentDueDateMs: next);
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'monthlyDueDateMs': monthlyDueDate.millisecondsSinceEpoch,
      'finalPaymentDateMs': finalPaymentDate.millisecondsSinceEpoch,
      'paidInstallmentDueDateMs': paidInstallmentDueDateMs,
    };
  }

  factory LoanEntry.fromJson(Map<String, dynamic> json) {
    final legacyDue = (json['dueDateMs'] as num?)?.toInt();
    final monthlyMs =
        (json['monthlyDueDateMs'] as num?)?.toInt() ?? legacyDue ?? 0;
    final finalMs =
        (json['finalPaymentDateMs'] as num?)?.toInt() ?? monthlyMs;
    final legacyTitle = json['title'] as String?;
    final rawPaid = json['paidInstallmentDueDateMs'];
    final paid = <int>[];
    if (rawPaid is List) {
      for (final item in rawPaid) {
        if (item is num) paid.add(item.toInt());
      }
    }
    final legacyWholePaid = json['isPaid'] == true;

    final entry = LoanEntry(
      id: json['id'] as String? ?? '',
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : (legacyTitle?.trim().isNotEmpty == true
                ? legacyTitle!.trim()
                : 'Loan'),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      monthlyDueDate: DateTime.fromMillisecondsSinceEpoch(monthlyMs),
      finalPaymentDate: DateTime.fromMillisecondsSinceEpoch(finalMs),
      paidInstallmentDueDateMs: paid,
    );

    if (legacyWholePaid && paid.isEmpty) {
      return entry.copyWith(
        paidInstallmentDueDateMs: [
          for (final due in entry.installmentDates) dayKey(due),
        ],
      );
    }
    return entry;
  }

  static int dayKey(DateTime due) {
    final day = DateTime(due.year, due.month, due.day);
    return day.millisecondsSinceEpoch;
  }

  static List<LoanEntry> listFromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => LoanEntry.fromJson(Map<String, dynamic>.from(item)))
        .where((loan) => loan.id.isNotEmpty)
        .toList();
  }

  static String listToJsonString(List<LoanEntry> loans) {
    return jsonEncode(loans.map((loan) => loan.toJson()).toList());
  }
}
