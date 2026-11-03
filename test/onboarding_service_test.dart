import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/onboarding_state.dart';
import 'package:just_budget/services/onboarding_service.dart';

class _FakePersistence implements OnboardingPersistence {
  OnboardingRecord? record;
  int createCalls = 0;
  int failuresRemaining = 0;

  @override
  Future<bool> createPendingIfAbsent(String uid) async {
    createCalls++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('offline');
    }
    if (record != null) return false;
    record = const OnboardingRecord(status: OnboardingStatus.pending);
    return true;
  }

  @override
  Future<OnboardingRecord?> loadRecord(String uid) async => record;

  @override
  Future<void> writeStatus(
    String uid,
    OnboardingStatus status, {
    required int step,
  }) async {
    record = OnboardingRecord(status: status, step: step);
  }
}

class _FakeRetryStore implements OnboardingRetryStore {
  bool pending = false;

  @override
  Future<bool> hasPendingRetry(String uid) async => pending;

  @override
  Future<void> setPendingRetry(String uid, bool value) async {
    pending = value;
  }
}

void main() {
  group('pending onboarding marker', () {
    test('new email account gets a pending record', () async {
      final persistence = _FakePersistence();
      final service = OnboardingService(
        persistence: persistence,
        retryStore: _FakeRetryStore(),
      );

      if (shouldCreatePendingOnboarding(emailAccountCreated: true)) {
        await service.markNewUser('email-user');
      }

      expect(persistence.record?.status, OnboardingStatus.pending);
      expect(isOnboardingEligible(record: persistence.record), isTrue);
    });

    test(
      'new Google account is marked and existing Google account is not',
      () async {
        final persistence = _FakePersistence();
        final service = OnboardingService(
          persistence: persistence,
          retryStore: _FakeRetryStore(),
        );

        Future<void> handleGoogleResult({required bool isNewUser}) async {
          if (shouldCreatePendingOnboarding(
            emailAccountCreated: false,
            googleIsNewUser: isNewUser,
          )) {
            await service.markNewUser('google-user');
          }
        }

        await handleGoogleResult(isNewUser: false);
        expect(persistence.createCalls, 0);

        await handleGoogleResult(isNewUser: true);
        expect(persistence.createCalls, 1);
        expect(persistence.record?.status, OnboardingStatus.pending);
      },
    );

    test('a failed write retries once', () async {
      final persistence = _FakePersistence()..failuresRemaining = 1;
      final service = OnboardingService(
        persistence: persistence,
        retryStore: _FakeRetryStore(),
      );

      await service.markNewUser('retry-user');

      expect(persistence.createCalls, 2);
      expect(persistence.record?.status, OnboardingStatus.pending);
    });

    test('a failed write retries on next start within 24 hours', () async {
      final persistence = _FakePersistence()..failuresRemaining = 2;
      final retryStore = _FakeRetryStore();
      final service = OnboardingService(
        persistence: persistence,
        retryStore: retryStore,
      );
      final now = DateTime.utc(2026, 11, 3, 12);

      await service.markNewUser('restart-user');
      expect(retryStore.pending, isTrue);
      expect(persistence.record, isNull);

      await service.retryPendingForRecentUser(
        'restart-user',
        now.subtract(const Duration(hours: 23)),
        now: now,
      );

      expect(persistence.record?.status, OnboardingStatus.pending);
      expect(retryStore.pending, isFalse);
    });

    test(
      'create-only marker never overwrites completed or dismissed',
      () async {
        for (final status in [
          OnboardingStatus.completed,
          OnboardingStatus.dismissed,
        ]) {
          final persistence = _FakePersistence()
            ..record = OnboardingRecord(status: status, step: 7);
          final service = OnboardingService(
            persistence: persistence,
            retryStore: _FakeRetryStore(),
          );

          await service.markNewUser('existing-user');

          expect(persistence.record?.status, status);
          expect(persistence.record?.step, 7);
        }
      },
    );
  });
}
