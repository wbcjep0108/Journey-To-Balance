import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/financial_entry.dart';

void main() {
  test('financial entry copy preserves identity and creation time', () {
    final createdAt = DateTime(2026, 7, 28);
    final entry = FinancialEntry(
      id: 'entry-id',
      title: 'Electricity',
      amount: 500,
      createdAt: createdAt,
    );

    final updated = entry.copyWith(
      title: 'Water',
      amount: 250,
      iconAsset: 'assets/images/icons_bills/water.png',
    );

    expect(updated.id, entry.id);
    expect(updated.createdAt, createdAt);
    expect(updated.title, 'Water');
    expect(updated.amount, 250);
    expect(updated.iconAsset, 'assets/images/icons_bills/water.png');
  });
}
