import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/app_currency.dart';
import 'package:just_budget/models/financial_entry.dart';
import 'package:just_budget/providers/budget_provider.dart';
import 'package:just_budget/providers/currency_provider.dart';
import 'package:just_budget/providers/wallet_cards_provider.dart';
import 'package:just_budget/providers/wallet_cash_provider.dart';
import 'package:just_budget/screens/savings/savings_goal_page.dart';
import 'package:provider/provider.dart';

class _FakeCurrencyProvider extends ChangeNotifier implements CurrencyProvider {
  @override
  AppCurrency get currency => AppCurrency.php;

  @override
  String get symbol => 'PHP';

  @override
  String formatAmount(double amount, {String pattern = '#,##0.##'}) =>
      'PHP ${amount.toStringAsFixed(2)}';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBudgetProvider extends ChangeNotifier implements BudgetProvider {
  @override
  String savingsGoalTitle = 'Emergency Fund';

  @override
  double savingsGoalCurrent = 1000;

  @override
  double savingsGoalTarget = 10000;

  @override
  double remainingFor(FinancialCategory category) => 20000;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWalletCashProvider extends ChangeNotifier
    implements WalletCashProvider {
  _FakeWalletCashProvider(this.value);

  final double value;

  @override
  double get amount => value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWalletCardsProvider extends ChangeNotifier
    implements WalletCardsProvider {
  _FakeWalletCardsProvider(this.value);

  final List<WalletCardModel> value;

  @override
  List<WalletCardModel> get cards => value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WalletCardModel testCard(int index, {double amount = 5000}) => WalletCardModel(
  id: 'card-$index',
  iconAsset: 'assets/images/bank/bdo.png',
  amount: amount,
);

Future<void> _pumpContributionModal(
  WidgetTester tester, {
  required int cardCount,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<CurrencyProvider>.value(
          value: _FakeCurrencyProvider(),
        ),
        ChangeNotifierProvider<BudgetProvider>.value(
          value: _FakeBudgetProvider(),
        ),
        ChangeNotifierProvider<WalletCashProvider>.value(
          value: _FakeWalletCashProvider(10000),
        ),
        ChangeNotifierProvider<WalletCardsProvider>.value(
          value: _FakeWalletCardsProvider(List.generate(cardCount, testCard)),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SavingsContributionModal(category: FinancialCategory.bills),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

SavingsTransferPart walletPart(double amount) => SavingsTransferPart(
  locationType: 'wallet',
  cardName: 'Wallet',
  amount: amount,
);

SavingsTransferPart cardPart(String id, String name, double amount) =>
    SavingsTransferPart(
      locationType: 'card',
      cardId: id,
      cardName: name,
      amount: amount,
    );

void main() {
  test('centavo split handles even and uneven amounts exactly', () {
    expect(splitSavingsAmount(100, 2), [50, 50]);
    expect(splitSavingsAmount(100, 3), [33.34, 33.33, 33.33]);
    expect(
      splitSavingsAmount(100, 3).map(moneyToCents).reduce((a, b) => a + b),
      10000,
    );
  });

  test('single source and destination is valid', () {
    final validation = validateSavingsTransfer(
      total: 50,
      sources: [walletPart(50)],
      destinations: [cardPart('gcash', 'GCash', 50)],
      balancesByLocationId: {'wallet': 100, 'gcash': 0},
    );
    expect(validation.canConfirm, isTrue);
  });

  test('confirm stays disabled for missing, mismatched, or excessive FROM', () {
    final nothing = validateSavingsTransfer(
      total: 50,
      sources: const [],
      destinations: const [],
      balancesByLocationId: const {},
    );
    final mismatch = validateSavingsTransfer(
      total: 50,
      sources: [walletPart(40)],
      destinations: [cardPart('gcash', 'GCash', 50)],
      balancesByLocationId: {'wallet': 100, 'gcash': 0},
    );
    final exceeds = validateSavingsTransfer(
      total: 50,
      sources: [walletPart(50)],
      destinations: [cardPart('gcash', 'GCash', 50)],
      balancesByLocationId: {'wallet': 49, 'gcash': 0},
    );
    expect(nothing.canConfirm, isFalse);
    expect(mismatch.canConfirm, isFalse);
    expect(exceeds.canConfirm, isFalse);
  });

  test('same location on both sides is valid and reported as overlap', () {
    final validation = validateSavingsTransfer(
      total: 25,
      sources: [walletPart(25)],
      destinations: [walletPart(25)],
      balancesByLocationId: {'wallet': 25},
    );
    expect(validation.canConfirm, isTrue);
    expect(validation.overlappingLocationIds, {'wallet'});
  });

  test(
    'new transfer record stores both lists and legacy record stores neither',
    () {
      final entry = FinancialEntry(
        id: 'entry-1',
        title: 'Savings Goal',
        amount: 100,
        createdAt: DateTime(2026),
        savingsSources: [walletPart(100)],
        savingsDestinations: [cardPart('bpi', 'BPI', 100)],
      );
      final stored = entry.toFirestore();
      expect(stored['savingsSources'], isA<List>());
      expect(stored['savingsDestinations'], isA<List>());

      final legacy = FinancialEntry(
        id: 'legacy',
        title: 'Savings Goal',
        amount: 100,
        createdAt: DateTime(2025),
        fundingSourceId: 'wallet',
        fundingSourceLabel: 'Wallet',
      ).toFirestore();
      expect(legacy.containsKey('savingsSources'), isFalse);
      expect(legacy.containsKey('savingsDestinations'), isFalse);
    },
  );

  testWidgets('one section supports multiple cards and editable amounts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.reset);

    final walletController = TextEditingController(text: '33.34');
    final gcashController = TextEditingController(text: '66.66');
    addTearDown(walletController.dispose);
    addTearDown(gcashController.dispose);
    var selected = <String>{'wallet', 'gcash-card'};

    await tester.pumpWidget(
      ChangeNotifierProvider<CurrencyProvider>.value(
        value: _FakeCurrencyProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: SavingsTransferSection(
                  title: 'FROM',
                  selectedIds: selected,
                  controllers: {
                    'wallet': walletController,
                    'gcash-card': gcashController,
                  },
                  walletAmount: 100,
                  cards: [
                    WalletCardModel(
                      id: 'gcash-card',
                      iconAsset: 'assets/images/bank/gcash.png',
                      amount: 200,
                    ),
                  ],
                  enabled: true,
                  assignedAmount: 100,
                  totalAmount: 100,
                  sumMatches: true,
                  showBalances: true,
                  onToggle: (id, value) => setState(() {
                    value ? selected.add(id) : selected.remove(id);
                  }),
                  onAmountChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('source-status-matched')), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).last, '60.00');
    expect(gcashController.text, '60.00');
    expect(tester.takeException(), isNull);
  });

  testWidgets('TO section shows automatic amounts without editable fields', (
    tester,
  ) async {
    final walletController = TextEditingController(text: '33.34');
    final gcashController = TextEditingController(text: '66.66');
    addTearDown(walletController.dispose);
    addTearDown(gcashController.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<CurrencyProvider>.value(
        value: _FakeCurrencyProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: SavingsTransferSection(
              title: 'TO',
              selectedIds: const {'wallet', 'gcash-card'},
              controllers: {
                'wallet': walletController,
                'gcash-card': gcashController,
              },
              walletAmount: 100,
              cards: [
                WalletCardModel(
                  id: 'gcash-card',
                  iconAsset: 'assets/images/bank/gcash.png',
                  amount: 200,
                ),
              ],
              enabled: true,
              assignedAmount: 100,
              totalAmount: 100,
              sumMatches: true,
              showBalances: false,
              amountEditable: false,
              onToggle: (_, _) {},
              onAmountChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsNothing);
    expect(find.text('PHP 33.34'), findsOneWidget);
    expect(find.text('PHP 66.66'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Take from header shows empty, partial, matched, and over states',
    (tester) async {
      Future<void> pumpStatus(double assigned, double total) async {
        await tester.pumpWidget(
          ChangeNotifierProvider<CurrencyProvider>.value(
            value: _FakeCurrencyProvider(),
            child: MaterialApp(
              home: Scaffold(
                body: SavingsTransferSection(
                  title: 'Take from',
                  selectedIds: const {},
                  controllers: const {},
                  walletAmount: 100,
                  cards: const [],
                  enabled: true,
                  assignedAmount: assigned,
                  totalAmount: total,
                  sumMatches: assigned == total,
                  showBalances: true,
                  onToggle: (_, _) {},
                  onAmountChanged: (_) {},
                ),
              ),
            ),
          ),
        );
      }

      await pumpStatus(0, 100);
      expect(find.byKey(const ValueKey('source-status-empty')), findsOneWidget);
      await pumpStatus(40, 100);
      expect(
        find.byKey(const ValueKey('source-status-partial')),
        findsOneWidget,
      );
      expect(find.text('PHP 60.00 left'), findsOneWidget);
      await pumpStatus(100, 100);
      expect(
        find.byKey(const ValueKey('source-status-matched')),
        findsOneWidget,
      );
      await pumpStatus(120, 100);
      expect(find.byKey(const ValueKey('source-status-over')), findsOneWidget);
      expect(find.text('PHP 20.00 over'), findsOneWidget);
    },
  );

  testWidgets('same location is disabled on the opposite side', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<CurrencyProvider>.value(
        value: _FakeCurrencyProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: SavingsTransferSection(
              title: 'Save into',
              selectedIds: const {},
              oppositeSelectedIds: const {'wallet'},
              controllers: const {},
              walletAmount: 100,
              cards: const [],
              enabled: true,
              assignedAmount: 0,
              totalAmount: 100,
              sumMatches: false,
              showBalances: false,
              amountEditable: false,
              onToggle: (_, _) {},
              onAmountChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final checkbox = tester.widget<Checkbox>(
      find.byKey(const ValueKey('transfer-checkbox-Save into-wallet')),
    );
    expect(checkbox.onChanged, isNull);
    expect(find.text('Used as source'), findsOneWidget);
  });

  testWidgets('insufficient source is dimmed and identified in the row', (
    tester,
  ) async {
    final controller = TextEditingController(text: '150.00');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<CurrencyProvider>.value(
        value: _FakeCurrencyProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: SavingsTransferSection(
              title: 'Take from',
              selectedIds: const {'wallet'},
              controllers: {'wallet': controller},
              walletAmount: 100,
              cards: const [],
              enabled: true,
              assignedAmount: 150,
              totalAmount: 150,
              sumMatches: true,
              showBalances: true,
              onToggle: (_, _) {},
              onAmountChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('insufficient-wallet')), findsOneWidget);
    expect(find.textContaining('Insufficient'), findsOneWidget);
  });

  testWidgets('Show all expands a section with more than four locations', (
    tester,
  ) async {
    final cards = List.generate(4, testCard);
    await tester.pumpWidget(
      ChangeNotifierProvider<CurrencyProvider>.value(
        value: _FakeCurrencyProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: SavingsTransferSection(
              title: 'Save into',
              selectedIds: const {},
              controllers: const {},
              walletAmount: 100,
              cards: cards,
              enabled: true,
              assignedAmount: 0,
              totalAmount: 100,
              sumMatches: false,
              showBalances: false,
              amountEditable: false,
              onToggle: (_, _) {},
              onAmountChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Show all (5)'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('transfer-row-Save into-card-3')),
      findsNothing,
    );
    await tester.tap(find.text('Show all (5)'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('transfer-row-Save into-card-3')),
      findsOneWidget,
    );
  });

  testWidgets('disabled Confirm shows a one-line reason', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    addTearDown(tester.view.reset);
    await _pumpContributionModal(tester, cardCount: 4);

    expect(find.text('Enter a contribution amount'), findsOneWidget);
    final gesture = tester.widget<GestureDetector>(
      find.descendant(
        of: find.byKey(const ValueKey('contribution-confirm')),
        matching: find.byType(GestureDetector),
      ),
    );
    expect(gesture.onTapUp, isNull);
  });

  for (final width in [320.0, 360.0, 430.0]) {
    testWidgets('modal has no overflow at ${width.toInt()}x740', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 740);
      addTearDown(tester.view.reset);
      await _pumpContributionModal(tester, cardCount: 4);

      expect(find.byKey(const ValueKey('pinned-confirm-bar')), findsOneWidget);
      expect(find.text('Show all (5)'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      final modal = tester.getSize(find.byType(SavingsContributionModal));
      expect(modal.height, lessThanOrEqualTo(740));
      expect(modal.width, lessThanOrEqualTo(width));
    });
  }

  group('savingsBalanceEffectSummary', () {
    final currency = _FakeCurrencyProvider();

    SavingsTransferPart wallet(double amount) => SavingsTransferPart(
      locationType: 'wallet',
      cardName: 'Wallet',
      amount: amount,
    );
    SavingsTransferPart card(String id, String name, double amount) =>
        SavingsTransferPart(
          locationType: 'card',
          cardId: id,
          cardName: name,
          amount: amount,
        );

    test('shows signed per-location effect wallet to card', () {
      final effect = savingsBalanceEffectSummary(
        currency: currency,
        sources: [wallet(1000)],
        destinations: [card('bdo', 'BDO', 1000)],
      );
      expect(effect, 'Wallet -PHP 1000.00, BDO +PHP 1000.00');
    });

    test('splits across multiple destinations', () {
      final effect = savingsBalanceEffectSummary(
        currency: currency,
        sources: [wallet(1000), card('bdo', 'BDO', 2000)],
        destinations: [card('gcash', 'GCash', 3000)],
      );
      expect(
        effect,
        'Wallet -PHP 1000.00, BDO -PHP 2000.00, GCash +PHP 3000.00',
      );
    });

    test('nets out a location used on both sides', () {
      final effect = savingsBalanceEffectSummary(
        currency: currency,
        sources: [wallet(100)],
        destinations: [wallet(100)],
      );
      expect(effect, '');
    });

    test('two cards of the same bank are handled separately', () {
      final effect = savingsBalanceEffectSummary(
        currency: currency,
        sources: [card('mari-1', "My MariBank", 500)],
        destinations: [card('mari-2', "Wife's MariBank", 500)],
      );
      expect(effect, "My MariBank -PHP 500.00, Wife's MariBank +PHP 500.00");
    });
  });
}
