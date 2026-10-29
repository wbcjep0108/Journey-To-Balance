import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/services/legal_acceptance_service.dart';

class _FakeLegalAcceptanceStore implements LegalAcceptanceStore {
  bool existsValue = false;
  int existsCalls = 0;
  int createCalls = 0;
  int failuresRemaining = 0;
  String? createdDocumentId;
  String? createdTermsVersion;
  String? createdPrivacyVersion;

  @override
  Future<void> create({
    required String userId,
    required String documentId,
    required String termsVersion,
    required String privacyVersion,
  }) async {
    createCalls++;
    createdDocumentId = documentId;
    createdTermsVersion = termsVersion;
    createdPrivacyVersion = privacyVersion;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('offline');
    }
    existsValue = true;
  }

  @override
  Future<bool> exists({
    required String userId,
    required String documentId,
  }) async {
    existsCalls++;
    return existsValue;
  }
}

void main() {
  test('creates a current acceptance document once', () async {
    final store = _FakeLegalAcceptanceStore();
    final service = LegalAcceptanceService(store: store);

    expect(await service.acceptCurrentVersion('user-id'), isTrue);
    expect(store.createCalls, 1);
    expect(store.existsCalls, 1);
    expect(service.documentId, 'acceptance_$currentLegalVersion');
    expect(store.createdDocumentId, 'acceptance_$currentLegalVersion');
    expect(store.createdTermsVersion, currentLegalVersion);
    expect(store.createdPrivacyVersion, currentLegalVersion);
    expect(currentLegalVersion, '2026-10-29-v2');
    expect(legalVersionDateLabel(), 'October 29, 2026');
    expect(service.documentId, matches(r'^acceptance_.+$'));
    expect(currentLegalVersion.length, lessThanOrEqualTo(32));
  });

  test('skips creation when the current acceptance already exists', () async {
    final store = _FakeLegalAcceptanceStore()..existsValue = true;
    final service = LegalAcceptanceService(store: store);

    expect(await service.acceptCurrentVersion('user-id'), isTrue);
    expect(store.createCalls, 0);
  });

  test(
    'retries a failed write once and does not throw into authentication',
    () async {
      final store = _FakeLegalAcceptanceStore()..failuresRemaining = 1;
      final service = LegalAcceptanceService(store: store);

      expect(await service.acceptCurrentVersion('user-id'), isTrue);
      expect(store.createCalls, 2);
      expect(store.existsCalls, 2);
    },
  );

  test('returns false after two write failures instead of throwing', () async {
    final store = _FakeLegalAcceptanceStore()..failuresRemaining = 2;
    final service = LegalAcceptanceService(store: store);

    expect(await service.acceptCurrentVersion('user-id'), isFalse);
    expect(store.createCalls, 2);
  });
}
