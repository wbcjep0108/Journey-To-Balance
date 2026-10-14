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
    this.isRefund = false,
    this.iconAsset,
    this.fundingSourceId,
    this.fundingSourceLabel,
  });

  final String id;
  final String title;
  final double amount;
  final DateTime createdAt;

  /// True when this row is a refund credit (money returned to the category).
  final bool isRefund;

  /// Optional Flutter asset path for the quick-select category icon.
  final String? iconAsset;

  /// Wallet/card account used for a savings-goal contribution.
  final String? fundingSourceId;
  final String? fundingSourceLabel;

  FinancialEntry copyWith({
    String? title,
    double? amount,
    DateTime? createdAt,
    bool? isRefund,
    String? iconAsset,
    bool clearIconAsset = false,
    String? fundingSourceId,
    String? fundingSourceLabel,
  }) {
    return FinancialEntry(
      id: id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      createdAt: createdAt ?? this.createdAt,
      isRefund: isRefund ?? this.isRefund,
      iconAsset: clearIconAsset ? null : (iconAsset ?? this.iconAsset),
      fundingSourceId: fundingSourceId ?? this.fundingSourceId,
      fundingSourceLabel: fundingSourceLabel ?? this.fundingSourceLabel,
    );
  }

  Map<String, Object?> toFirestore() {
    return {
      'title': title,
      'amount': amount,
      'createdAt': Timestamp.fromDate(createdAt),
      'isRefund': isRefund,
      if (iconAsset != null && iconAsset!.isNotEmpty) 'iconAsset': iconAsset,
      if (fundingSourceId != null && fundingSourceId!.isNotEmpty)
        'fundingSourceId': fundingSourceId,
      if (fundingSourceLabel != null && fundingSourceLabel!.isNotEmpty)
        'fundingSourceLabel': fundingSourceLabel,
    };
  }

  factory FinancialEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final createdAt = data['createdAt'];
    final rawIcon = data['iconAsset'];
    final rawFundingSourceId = data['fundingSourceId'];
    final rawFundingSourceLabel = data['fundingSourceLabel'];

    return FinancialEntry(
      id: document.id,
      title: data['title'] as String? ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      isRefund: data['isRefund'] == true,
      iconAsset: rawIcon is String && rawIcon.trim().isNotEmpty
          ? rawIcon.trim()
          : null,
      fundingSourceId:
          rawFundingSourceId is String && rawFundingSourceId.trim().isNotEmpty
              ? rawFundingSourceId.trim()
              : null,
      fundingSourceLabel: rawFundingSourceLabel is String &&
              rawFundingSourceLabel.trim().isNotEmpty
          ? rawFundingSourceLabel.trim()
          : null,
    );
  }
}
