import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/onboarding_state.dart';
import 'package:just_budget/providers/notification_prefs_provider.dart';

void main() {
  group('onboarding eligibility', () {
    final cutoff = DateTime.parse(ONBOARDING_RELEASE_CUTOFF);

    test('shows for a new empty account on the cutoff', () {
      expect(
        isOnboardingEligible(
          record: null,
          creationTime: cutoff,
          releaseCutoff: cutoff,
          monthlySalary: 0,
          hasCards: false,
          walletCash: 0,
          hasTransactions: false,
        ),
        isTrue,
      );
    });

    test('account created just before the cutoff is not eligible', () {
      expect(
        isOnboardingEligible(
          record: null,
          creationTime: cutoff.subtract(const Duration(seconds: 1)),
          releaseCutoff: cutoff,
          monthlySalary: 0,
          hasCards: false,
          walletCash: 0,
          hasTransactions: false,
        ),
        isFalse,
      );
    });

    test('account created just after the cutoff is eligible', () {
      expect(
        isOnboardingEligible(
          record: null,
          creationTime: cutoff.add(const Duration(milliseconds: 1)),
          releaseCutoff: cutoff,
          monthlySalary: 0,
          hasCards: false,
          walletCash: 0,
          hasTransactions: false,
        ),
        isTrue,
      );
    });

    test('never shows with any account data', () {
      for (final state in [
        (salary: 1.0, cards: false, cash: 0.0, transactions: false),
        (salary: 0.0, cards: true, cash: 0.0, transactions: false),
        (salary: 0.0, cards: false, cash: 1.0, transactions: false),
        (salary: 0.0, cards: false, cash: 0.0, transactions: true),
      ]) {
        expect(
          isOnboardingEligible(
            record: null,
            creationTime: cutoff,
            releaseCutoff: cutoff,
            monthlySalary: state.salary,
            hasCards: state.cards,
            walletCash: state.cash,
            hasTransactions: state.transactions,
          ),
          isFalse,
        );
      }
    });

    test('never shows for completed or dismissed records', () {
      for (final status in OnboardingStatus.values) {
        expect(
          isOnboardingEligible(
            record: OnboardingRecord(status: status),
            creationTime: cutoff,
            releaseCutoff: cutoff,
            monthlySalary: 0,
            hasCards: false,
            walletCash: 0,
            hasTransactions: false,
          ),
          isFalse,
        );
      }
    });
  });

  group('percentage rebalancing', () {
    test('always totals 100 after moving each slider', () {
      var values = (bills: 50, savings: 20, personal: 30);
      for (var index = 0; index < 3; index++) {
        final next = rebalancePercentages(
          changedIndex: index,
          value: 73,
          bills: values.bills,
          savings: values.savings,
          personal: values.personal,
        );
        expect(next.bills + next.savings + next.personal, 100);
        expect([next.bills, next.savings, next.personal][index], 73);
        values = next;
      }
    });

    test('handles zero and one hundred edge cases without negatives', () {
      final allBills = rebalancePercentages(
        changedIndex: 0,
        value: 100,
        bills: 50,
        savings: 20,
        personal: 30,
      );
      expect(allBills, (bills: 100, savings: 0, personal: 0));

      final noBills = rebalancePercentages(
        changedIndex: 0,
        value: 0,
        bills: 100,
        savings: 0,
        personal: 0,
      );
      expect(noBills.bills + noBills.savings + noBills.personal, 100);
      expect(noBills.savings, greaterThanOrEqualTo(0));
      expect(noBills.personal, greaterThanOrEqualTo(0));
    });

    test('default reset values total 100', () {
      const defaults = (bills: 50, savings: 20, personal: 30);
      expect(defaults.bills + defaults.savings + defaults.personal, 100);
    });

    test('typed percentages must be valid and total exactly 100', () {
      expect(
        isValidPercentageSplit(bills: 50, savings: 20, personal: 30),
        isTrue,
      );
      expect(
        isValidPercentageSplit(bills: 50, savings: 20, personal: 20),
        isFalse,
      );
      expect(
        isValidPercentageSplit(bills: 101, savings: 0, personal: 0),
        isFalse,
      );
      expect(
        isValidPercentageSplit(bills: null, savings: 20, personal: 30),
        isFalse,
      );
    });
  });

  test(
    'draft round trip restores slide, values, and completed save stages',
    () {
      final draft =
          OnboardingDraft(
              slide: 4,
              currencyCode: 'USD',
              monthlyIncome: 2500,
              billsPercentage: 45,
              savingsPercentage: 25,
              personalPercentage: 30,
              walletCash: 125,
              selectedCards: {'assets/images/bank/bpi.png'},
              cardAmounts: {'assets/images/bank/bpi.png': 375},
              completedSaveSteps: {'currency', 'budget'},
              salaryRequestId: 'salary-attempt-1',
              percentagesRequestId: 'percentages-attempt-1',
            )
            ..incomeEntered = true
            ..splitTouched = true
            ..cashEntered = true;

      final restored = OnboardingDraft.decode(draft.encode());

      expect(restored.slide, 4);
      expect(restored.currencyCode, 'USD');
      expect(restored.monthlyIncome, 2500);
      expect(restored.billsPercentage, 45);
      expect(restored.walletCash, 125);
      expect(restored.cardAmounts['assets/images/bank/bpi.png'], 375);
      expect(restored.completedSaveSteps, containsAll(['currency', 'budget']));
      expect(restored.salaryRequestId, 'salary-attempt-1');
      expect(restored.percentagesRequestId, 'percentages-attempt-1');
    },
  );

  test('notification permission is requested only when a switch turns on', () {
    expect(
      shouldRequestOnboardingNotificationPermission(
        previousValue: false,
        nextValue: true,
      ),
      isTrue,
    );
    expect(
      shouldRequestOnboardingNotificationPermission(
        previousValue: true,
        nextValue: false,
      ),
      isFalse,
    );
    expect(
      shouldRequestOnboardingNotificationPermission(
        previousValue: true,
        nextValue: true,
      ),
      isFalse,
    );
  });

  test(
    'completion prompts when reminders are on and permission is undetermined',
    () async {
      var requests = 0;
      NotificationPermissionDecision? saved;

      final prompted = await requestOnboardingCompletionPermissionIfNeeded(
        anyReminderEnabled: true,
        decision: NotificationPermissionDecision.undetermined,
        requestPermission: () async {
          requests++;
          return true;
        },
        saveDecision: (decision) async => saved = decision,
      );

      expect(prompted, isTrue);
      expect(requests, 1);
      expect(saved, NotificationPermissionDecision.granted);
    },
  );

  test('completion does not prompt when all reminders are off', () async {
    var requests = 0;

    final prompted = await requestOnboardingCompletionPermissionIfNeeded(
      anyReminderEnabled: false,
      decision: NotificationPermissionDecision.undetermined,
      requestPermission: () async {
        requests++;
        return true;
      },
      saveDecision: (_) async {},
    );

    expect(prompted, isFalse);
    expect(requests, 0);
  });

  test('completion does not re-prompt an already denied user', () async {
    var requests = 0;

    final prompted = await requestOnboardingCompletionPermissionIfNeeded(
      anyReminderEnabled: true,
      decision: NotificationPermissionDecision.denied,
      requestPermission: () async {
        requests++;
        return true;
      },
      saveDecision: (_) async {},
    );

    expect(prompted, isFalse);
    expect(requests, 0);
  });
}
