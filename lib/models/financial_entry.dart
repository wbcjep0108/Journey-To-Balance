import 'package:cloud_firestore/cloud_firestore.dart';

enum FinancialCategory {
  bills('bills'),
  savings('savings'),
  personal('personal');

  const FinancialCategory(this.collection);

  final String collection;
}

class FinancialEntry {
  const FinancialEntry({
    required this.id,
    required this.title,
    required this.amount,
    required this.createdAt,
  });

  final String id;
  final String title;
  final double amount;
  final DateTime createdAt;

  FinancialEntry copyWith({
    String? title,
    double? amount,
    DateTime? createdAt,
  }) {
    return FinancialEntry(
      id: id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object> toFirestore() {
    return {
      'title': title,
      'amount': amount,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory FinancialEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final createdAt = data['createdAt'];

    return FinancialEntry(
      id: document.id,
      title: data['title'] as String? ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
