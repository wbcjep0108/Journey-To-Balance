import 'package:cloud_firestore/cloud_firestore.dart';

enum FinancialCategory {
  bills('bills'),
  savings('savings'),
  personal('personal');

  const FinancialCategory(this.collection);

  final String collection;
}

/// One wallet/card amount on either side of a savings transfer.
class SavingsTransferPart {
  const SavingsTransferPart({
    required this.locationType,
    required this.cardName,
    required this.amount,
    this.cardId,
  });

  /// Either `wallet` or `card`.
  final String locationType;
  final String? cardId;
  final String cardName;
  final double amount;

  bool get isWallet => locationType == 'wallet';
  String get locationId => isWallet ? 'wallet' : cardId!;
  String get displayName => isWallet ? 'Wallet' : cardName;

  Map<String, Object?> toMap() => {
    'locationType': locationType,
    if (cardId != null) 'cardId': cardId,
    'cardName': cardName,
    'amount': amount,
  };

  static SavingsTransferPart? fromMap(Object? value) {
    if (value is! Map) return null;
    final locationType = value['locationType'];
    final cardId = value['cardId'];
    final cardName = value['cardName'];
    final amount = value['amount'];
    if (locationType is! String ||
        (locationType != 'wallet' && locationType != 'card') ||
        cardName is! String ||
        cardName.trim().isEmpty ||
        amount is! num) {
      return null;
    }
    if (locationType == 'card' &&
        (cardId is! String || cardId.trim().isEmpty)) {
      return null;
    }
    return SavingsTransferPart(
      locationType: locationType,
      cardId: cardId is String ? cardId.trim() : null,
      cardName: cardName.trim(),
      amount: amount.toDouble(),
    );
  }
}

int moneyToCents(double amount) => (amount * 100).round();

double centsToMoney(int cents) => cents / 100;

/// Evenly splits centavos and assigns any remainder to the earliest parts.
List<double> splitSavingsAmount(double amount, int partCount) {
  if (amount <= 0 || partCount <= 0) return const [];
  final totalCents = moneyToCents(amount);
  final base = totalCents ~/ partCount;
  final remainder = totalCents % partCount;
  return [
    for (var index = 0; index < partCount; index++)
      centsToMoney(base + (index < remainder ? 1 : 0)),
  ];
}

int savingsPartsTotalCents(Iterable<SavingsTransferPart> parts) {
  var total = 0;
  for (final part in parts) {
    total += moneyToCents(part.amount);
  }
  return total;
}

class SavingsTransferValidation {
  const SavingsTransferValidation({
    required this.totalCents,
    required this.sourceCents,
    required this.destinationCents,
    required this.sourcesWithinBalance,
    required this.hasPositiveParts,
    required this.overlappingLocationIds,
  });

  final int totalCents;
  final int sourceCents;
  final int destinationCents;
  final bool sourcesWithinBalance;
  final bool hasPositiveParts;
  final Set<String> overlappingLocationIds;

  bool get sourcesMatch => totalCents > 0 && sourceCents == totalCents;
  bool get destinationsMatch =>
      totalCents > 0 && destinationCents == totalCents;
  bool get canConfirm =>
      sourcesMatch &&
      destinationsMatch &&
      sourcesWithinBalance &&
      hasPositiveParts;
}

SavingsTransferValidation validateSavingsTransfer({
  required double total,
  required List<SavingsTransferPart> sources,
  required List<SavingsTransferPart> destinations,
  required Map<String, double> balancesByLocationId,
}) {
  final totalCents = moneyToCents(total);
  final sourceIds = sources.map((part) => part.locationId).toSet();
  final destinationIds = destinations.map((part) => part.locationId).toSet();
  final hasPositiveParts =
      sources.isNotEmpty &&
      destinations.isNotEmpty &&
      sources.every((part) => moneyToCents(part.amount) > 0) &&
      destinations.every((part) => moneyToCents(part.amount) > 0);
  final sourcesWithinBalance = sources.every((part) {
    final balance = balancesByLocationId[part.locationId];
    return balance != null &&
        moneyToCents(part.amount) <= moneyToCents(balance);
  });
  return SavingsTransferValidation(
    totalCents: totalCents,
    sourceCents: savingsPartsTotalCents(sources),
    destinationCents: savingsPartsTotalCents(destinations),
    sourcesWithinBalance: sourcesWithinBalance,
    hasPositiveParts: hasPositiveParts,
    overlappingLocationIds: sourceIds.intersection(destinationIds),
  );
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
    this.savingsSources = const [],
    this.savingsDestinations = const [],
  });

  final String id;
  final String title;
  final double amount;
  final DateTime createdAt;

  /// True when this row is a refund credit (money returned to the category).
  final bool isRefund;

  /// Optional Flutter asset path for the quick-select category icon.
  final String? iconAsset;

  /// Wallet/card account used to fund this transaction.
  ///
  /// These fields are also used by savings-goal contributions so every
  /// transaction can explain where its money came from.
  final String? fundingSourceId;
  final String? fundingSourceLabel;

  /// Transfer details for new savings contributions. Both lists are empty for
  /// legacy contributions and ordinary transactions.
  final List<SavingsTransferPart> savingsSources;
  final List<SavingsTransferPart> savingsDestinations;

  FinancialEntry copyWith({
    String? title,
    double? amount,
    DateTime? createdAt,
    bool? isRefund,
    String? iconAsset,
    bool clearIconAsset = false,
    String? fundingSourceId,
    String? fundingSourceLabel,
    List<SavingsTransferPart>? savingsSources,
    List<SavingsTransferPart>? savingsDestinations,
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
      savingsSources: savingsSources ?? this.savingsSources,
      savingsDestinations: savingsDestinations ?? this.savingsDestinations,
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
      if (savingsSources.isNotEmpty)
        'savingsSources': savingsSources.map((part) => part.toMap()).toList(),
      if (savingsDestinations.isNotEmpty)
        'savingsDestinations': savingsDestinations
            .map((part) => part.toMap())
            .toList(),
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
    List<SavingsTransferPart> parseParts(Object? raw) {
      final parts = <SavingsTransferPart>[];
      if (raw is List) {
        for (final item in raw) {
          final part = SavingsTransferPart.fromMap(item);
          if (part != null) parts.add(part);
        }
      }
      return parts;
    }

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
      fundingSourceLabel:
          rawFundingSourceLabel is String &&
              rawFundingSourceLabel.trim().isNotEmpty
          ? rawFundingSourceLabel.trim()
          : null,
      savingsSources: parseParts(data['savingsSources']),
      savingsDestinations: parseParts(data['savingsDestinations']),
    );
  }
}
